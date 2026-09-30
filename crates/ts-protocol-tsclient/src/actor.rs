//! The background task that owns the protocol connection.
//!
//! `tsclientlib::Connection` is single-owner and does nothing unless its event
//! stream is being polled — its own documentation is explicit that *sending*
//! packets also only happens while polling. So the connection cannot be shared
//! behind a lock: it is moved into this task, and everything else talks to it
//! through a command channel.
//!
//! ```text
//! Ts3Connection ──mpsc──▶ actor ──▶ tsclientlib::Connection
//!       ▲                    │
//!       └──oneshot reply─────┘        └──▶ EventBus ──▶ front-ends
//! ```
//!
//! The select loop re-creates the event stream each iteration and drops it
//! before touching the connection again. That is not incidental: the stream
//! borrows the connection mutably, so the borrow must end before a command can
//! be sent. It is safe to drop because the stream yields one item per poll.

use std::borrow::Cow;
use std::collections::HashMap;
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::Duration;

use ts_protocol::{AudioSink, Codec, ConnectionConfig, VoicePacket};
use tsclientlib::audio::AudioHandler;
use tsproto_packets::packets::{AudioData, CodecType, InAudioBuf, OutAudio, OutPacket};

use futures::StreamExt as _;
use tokio::sync::{mpsc, oneshot};
use ts_events::{ClientEvent, EventBus, SessionEvent};
use ts_identity::IdentityStore;
use ts_model::{
    ChannelId, ClientError, ClientId, ConnectionState, Message, MessageId, MessageTarget,
    NetworkError, PermissionError, Permissions, ProtocolError, ReconnectPolicy, Server, ServerInfo,
    ServerState, SessionId, VoiceError, VoiceState,
};

use tsclientlib::events::Event as BookEvent;
use tsclientlib::messages::c2s::{
    OutClientMovePart, OutClientPokeRequestPart, OutSendTextMessagePart,
};
use tsclientlib::prelude::M2BClientUpdateExt as _;
use tsclientlib::{
    CommandError, Connection, DisconnectOptions, MessageHandle, OutCommandExt, StreamItem,
    TemporaryDisconnectReason, TextMessageTargetMode,
};

use crate::{convert, diff};

/// Samples in one frame of decoded stereo audio: 20 ms at 48 kHz.
///
/// `tsclientlib`'s decoder always produces stereo, while what we *send* is
/// mono — see `ts-audio`'s `format` module, which owns the matching constants
/// for the capture side.
const AUDIO_FRAME_SAMPLES: usize = 1920;

/// Where a command's outcome is delivered.
pub(crate) type Reply = oneshot::Sender<Result<(), ClientError>>;

/// Per-connection audio state.
///
/// The jitter buffer, packet-loss handling and Opus decoding live in
/// `tsclientlib`'s handler rather than being reimplemented: they are tightly
/// coupled to how that library sequences packets, and duplicating them would
/// mean duplicating a lot of carefully-tuned behaviour (§77).
struct Audio {
    handler: AudioHandler<tsclientlib::ClientId>,
    /// Scratch for one frame of mixed output, reused every frame.
    mix: Vec<f32>,
}

impl Audio {
    fn new() -> Self {
        Self {
            handler: AudioHandler::new(),
            mix: vec![0.0; AUDIO_FRAME_SAMPLES],
        }
    }
}

/// Work the actor performs against the connection.
pub(crate) enum Command {
    /// Move ourselves into a channel.
    JoinChannel { channel_id: ChannelId, reply: Reply },
    /// Send a chat message.
    SendText {
        target: MessageTarget,
        text: String,
        reply: Reply,
    },
    /// Move another client.
    MoveClient {
        client_id: ClientId,
        channel_id: ChannelId,
        reply: Reply,
    },
    /// Send one encoded voice frame.
    SendVoice { packet: VoicePacket, reply: Reply },
    /// Tell the server whether we are muted.
    SetVoiceState { state: VoiceState, reply: Reply },
    /// Poke another client.
    Poke {
        client_id: ClientId,
        message: String,
        reply: Reply,
    },
    /// Close the connection.
    Disconnect { reply: Reply },
}

impl Command {
    /// Takes the reply channel out, for answering without touching a connection.
    ///
    /// Every variant carries one, so this is exhaustive by construction: a new
    /// command cannot be added without deciding what happens to its caller.
    fn into_reply(self) -> Reply {
        match self {
            Self::JoinChannel { reply, .. }
            | Self::SendText { reply, .. }
            | Self::MoveClient { reply, .. }
            | Self::SendVoice { reply, .. }
            | Self::SetVoiceState { reply, .. }
            | Self::Poke { reply, .. }
            | Self::Disconnect { reply } => reply,
        }
    }
}

impl std::fmt::Debug for Command {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // Deliberately omits message bodies: chat is user content and does not
        // belong in a trace by default (§44).
        match self {
            Self::JoinChannel { channel_id, .. } => f
                .debug_struct("JoinChannel")
                .field("channel_id", channel_id)
                .finish(),
            Self::SendText { target, .. } => f
                .debug_struct("SendText")
                .field("target", target)
                .finish_non_exhaustive(),
            Self::MoveClient {
                client_id,
                channel_id,
                ..
            } => f
                .debug_struct("MoveClient")
                .field("client_id", client_id)
                .field("channel_id", channel_id)
                .finish(),
            Self::Poke { client_id, .. } => f
                .debug_struct("Poke")
                .field("client_id", client_id)
                .finish_non_exhaustive(),
            Self::SendVoice { packet, .. } => f
                .debug_struct("SendVoice")
                .field("sequence", &packet.sequence)
                .field("bytes", &packet.payload.len())
                .finish(),
            Self::SetVoiceState { state, .. } => f
                .debug_struct("SetVoiceState")
                .field("state", state)
                .finish(),
            Self::Disconnect { .. } => f.write_str("Disconnect"),
        }
    }
}

/// State the rest of the backend reads without going through the actor.
#[derive(Debug)]
pub(crate) struct SharedState {
    connection: ConnectionState,
    server_info: Option<ServerInfo>,
    permissions: Permissions,
    snapshot: Option<ServerState>,
}

impl Default for SharedState {
    fn default() -> Self {
        Self {
            connection: ConnectionState::Disconnected,
            server_info: None,
            permissions: Permissions::none(),
            snapshot: None,
        }
    }
}

/// Everything the actor needs besides the connection itself.
pub(crate) struct Context {
    /// Which session these events belong to.
    pub session: SessionId,
    /// The server this connection was opened to.
    ///
    /// Mutable because the server names itself during the handshake, and the
    /// configured label is only a guess until then.
    server: Mutex<Server>,
    /// Where events are published.
    pub events: EventBus,
    /// Where an upgraded identity is written back.
    pub identity_store: Option<(IdentityStore, String)>,
    /// Where decoded incoming audio goes.
    ///
    /// Settable at any time, and absent by default: a client that only wants
    /// chat should not have to open speakers to receive nothing.
    audio_sink: Mutex<Option<Arc<dyn AudioSink>>>,
    state: Mutex<SharedState>,
}

impl Context {
    /// Builds a context for one connection.
    #[must_use]
    pub fn new(
        session: SessionId,
        server: Server,
        events: EventBus,
        identity_store: Option<(IdentityStore, String)>,
    ) -> Self {
        Self {
            session,
            server: Mutex::new(server),
            events,
            identity_store,
            audio_sink: Mutex::new(None),
            state: Mutex::new(SharedState::default()),
        }
    }

    /// Points decoded audio at `sink`.
    pub fn set_audio_sink(&self, sink: Arc<dyn AudioSink>) {
        *self
            .audio_sink
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(sink);
    }

    /// The installed sink, if any.
    fn audio_sink(&self) -> Option<Arc<dyn AudioSink>> {
        self.audio_sink
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }

    /// The server, with whatever name it has reported so far.
    pub fn server(&self) -> Server {
        self.server
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }

    /// Adopts the name the server reports for itself.
    fn adopt_server_name(&self, name: &str) {
        if !name.is_empty() {
            self.server
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .name = name.to_string();
        }
    }

    fn lock(&self) -> MutexGuard<'_, SharedState> {
        // A poisoned lock means another thread panicked mid-update. Recovering
        // the data is better than propagating the panic into the network loop.
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }

    /// The connection state, as of the last update.
    pub fn connection_state(&self) -> ConnectionState {
        self.lock().connection
    }

    /// The last known server metadata.
    pub fn server_info(&self) -> Option<ServerInfo> {
        self.lock().server_info.clone()
    }

    /// The last known permission snapshot.
    pub fn permissions(&self) -> Permissions {
        self.lock().permissions
    }

    /// The last known full server state.
    pub fn snapshot(&self) -> Option<ServerState> {
        self.lock().snapshot.clone()
    }

    /// Moves the session to `state` and tells subscribers.
    ///
    /// Every transition goes through here. Setting the state without publishing
    /// it is how a front-end ends up believing a live session is offline — the
    /// reason the server switcher labelled every connected server 「未连接」.
    fn set_connection(&self, state: ConnectionState) {
        self.lock().connection = state;
        self.publish(ClientEvent::ConnectionStateChanged(state));
    }

    fn publish(&self, event: ClientEvent) {
        self.events.publish(SessionEvent::new(self.session, event));
    }
}

impl std::fmt::Debug for Context {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Context")
            .field("session", &self.session)
            .field("server", &self.server().name)
            .finish_non_exhaustive()
    }
}

/// What the select loop chose to do this iteration.
enum Outcome {
    Stream(Option<Result<StreamItem, tsclientlib::Error>>),
    Command(Command),
    /// The command channel closed, which means every handle was dropped.
    Closed,
}

/// Why one connection stopped.
enum Ended {
    /// Nothing more to do: every command handle was dropped, or the session was
    /// closed from this side. Neither is a failure, and neither is worth retrying.
    Done,
    /// The connection dropped. `None` when the library reported a drop without
    /// producing an error — the ordinary shape of a network blip, and always
    /// worth another attempt.
    Dropped(Option<ClientError>),
}

/// Decides whether — and how long — to wait before rebuilding a dropped connection.
///
/// Deliberately apart from the loop it drives, so §35's schedule can be pinned
/// down by tests that need neither a server, a socket, nor a clock.
struct ReconnectSchedule {
    policy: ReconnectPolicy,
    /// Retries scheduled so far. Reported as `attempt`, so it is 1 for the first.
    attempts: u32,
}

impl ReconnectSchedule {
    fn new(policy: ReconnectPolicy) -> Self {
        Self {
            policy,
            attempts: 0,
        }
    }

    /// The connection came back, so the next drop starts from the first delay
    /// again — a blip that resolved should not cost the following drop its
    /// patience.
    fn reset(&mut self) {
        self.attempts = 0;
    }

    /// How many retries have been scheduled.
    fn attempts(&self) -> u32 {
        self.attempts
    }

    /// The delay before the next attempt, or `None` when there should not be one.
    fn next(&mut self, error: Option<&ClientError>) -> Option<u64> {
        // No error means the library *reported a drop* rather than a refusal,
        // and that is always worth retrying. An error is only worth retrying if
        // it is the kind that passes: a rejected password does not become
        // correct by waiting, and retrying a kick is how a client gets banned.
        if !error.is_none_or(ClientError::is_retryable) {
            return None;
        }
        if !self.policy.should_retry(self.attempts) {
            return None;
        }

        let delay = self.policy.delay_for_attempt(self.attempts);
        self.attempts += 1;
        Some(delay)
    }
}

/// What a reconnect needs: the recipe, and how patient to be.
pub(crate) struct Reconnect {
    /// Everything needed to present the same client again (§36).
    config: ConnectionConfig,
    schedule: ReconnectSchedule,
}

impl Reconnect {
    /// Reconnects on the schedule the config carries.
    ///
    /// The schedule itself is §35's; what the user decides is whether retrying
    /// happens at all and for how long. Everything needed for a rebuild —
    /// including that policy — travels together in the config, so a rebuild
    /// cannot end up using a different one than the first attempt did.
    pub(crate) fn new(config: ConnectionConfig) -> Self {
        let schedule = ReconnectSchedule::new(config.reconnect);
        Self { config, schedule }
    }
}

/// Runs the connection, rebuilding it after a drop, until the session is over.
///
/// `ready` is signalled once the handshake completes, or with an error if the
/// connection ends first — so a caller awaiting it can never hang.
pub(crate) async fn run(
    mut connection: Connection,
    mut commands: mpsc::Receiver<Command>,
    context: Arc<Context>,
    ready: oneshot::Sender<Result<(), ClientError>>,
    reconnect: Reconnect,
) {
    let Reconnect {
        config,
        mut schedule,
    } = reconnect;

    let mut ready = Some(ready);
    let mut next_message_id: u64 = 1;
    let mut pending: HashMap<MessageHandle, Reply> = HashMap::new();
    let mut audio = Audio::new();

    context.set_connection(ConnectionState::Connecting);

    loop {
        let ended = serve(
            &mut connection,
            &mut commands,
            &context,
            &mut ready,
            &mut next_message_id,
            &mut pending,
            &mut audio,
        )
        .await;

        // Neither survives a connection: the parked replies belong to the
        // connection that would have carried them, and the jitter buffers are
        // keyed by client ids the next connection will not reuse.
        pending.clear();
        audio = Audio::new();

        let error = match ended {
            Ended::Done => break,
            Ended::Dropped(error) => error,
        };

        // A connection that never finished its handshake belongs to the caller
        // waiting on it: `open()` returns this error directly, and publishing an
        // event for it as well would put the same failure on screen twice — once
        // as a banner, once as the result of the connect that was asked for.
        //
        // It is also what keeps "wrong password" and "the server is not up yet"
        // apart, and stops someone waiting on a handshake from waiting out a
        // backoff schedule they never asked for.
        if ready.is_some() {
            break;
        }

        match rebuild(&mut commands, &context, &config, &mut schedule, error).await {
            Some(fresh) => connection = fresh,
            None => break,
        }
    }

    // Dropping the replies fails every caller still waiting, instead of leaving
    // them parked on a channel that will never fire.
    pending.clear();

    context.set_connection(ConnectionState::Disconnected);
    if let Some(ready) = ready {
        let _ = ready.send(Err(ClientError::Network(NetworkError::new(
            "the connection closed before the handshake finished",
        ))));
    }
    context.publish(ClientEvent::Disconnected);
}

/// Runs one connection until it ends.
///
/// Borrows everything that has to outlive a reconnect, so the caller can hand it
/// a freshly built connection and call it again.
#[allow(clippy::too_many_arguments)]
async fn serve(
    connection: &mut Connection,
    commands: &mut mpsc::Receiver<Command>,
    context: &Arc<Context>,
    ready: &mut Option<oneshot::Sender<Result<(), ClientError>>>,
    next_message_id: &mut u64,
    pending: &mut HashMap<MessageHandle, Reply>,
    audio: &mut Audio,
) -> Ended {
    // Whether the library said the connection dropped. With
    // `ReconnectMode::External` the stream ends immediately afterwards, and
    // without this the ending would be indistinguishable from a clean close.
    let mut dropped = false;

    loop {
        let mut stream = connection.events();
        let outcome = tokio::select! {
            item = stream.next() => Outcome::Stream(item),
            command = commands.recv() => match command {
                Some(command) => Outcome::Command(command),
                None => Outcome::Closed,
            },
        };
        drop(stream);

        match outcome {
            Outcome::Stream(Some(Ok(StreamItem::DisconnectedTemporarily(reason)))) => {
                // Handled here rather than in `handle_item`, because it decides
                // what the *end* of the stream means. The session and its
                // identity survive, which is what §36 requires; putting the
                // connection back together is the caller's job now.
                tracing::warn!(session = %context.session, ?reason, "temporarily disconnected");
                context.set_connection(ConnectionState::Reconnecting);
                if matches!(reason, TemporaryDisconnectReason::Serverstop) {
                    tracing::info!(session = %context.session, "the server is restarting");
                }
                dropped = true;
            }
            Outcome::Stream(Some(Ok(item))) => {
                handle_item(
                    item,
                    connection,
                    context,
                    next_message_id,
                    pending,
                    ready,
                    audio,
                );
            }
            Outcome::Stream(Some(Err(error))) => {
                tracing::warn!(session = %context.session, %error, "connection failed");
                // Not published here: whether this is worth telling anyone
                // depends on whether a caller is still waiting for the
                // handshake, which the caller of this function knows and this
                // one does not.
                return Ended::Dropped(Some(protocol_error(&error)));
            }
            Outcome::Stream(None) => {
                tracing::info!(session = %context.session, "connection stream ended");
                return if dropped {
                    Ended::Dropped(None)
                } else {
                    Ended::Done
                };
            }
            Outcome::Command(command) => {
                handle_command(command, connection, pending);
            }
            Outcome::Closed => {
                tracing::info!(session = %context.session, "no handles left; closing connection");
                let _ = connection.disconnect(DisconnectOptions::new());
                // Keep draining so the disconnect actually reaches the wire.
                while let Some(item) = connection.events().next().await {
                    if item.is_err() {
                        break;
                    }
                }
                return Ended::Done;
            }
        }
    }
}

/// Waits out the backoff, then rebuilds the connection — for as long as the
/// schedule allows.
///
/// Returns the new connection, or `None` when the session should end.
async fn rebuild(
    commands: &mut mpsc::Receiver<Command>,
    context: &Arc<Context>,
    config: &ConnectionConfig,
    schedule: &mut ReconnectSchedule,
    mut error: Option<ClientError>,
) -> Option<Connection> {
    loop {
        let Some(delay_ms) = schedule.next(error.as_ref()) else {
            // Out of patience, or out of hope. Either way this is the end of the
            // session, so the user is told — and told *why*, which is the last
            // thing that went wrong rather than the fact that we stopped.
            if let Some(error) = error {
                context.set_connection(ConnectionState::Failed);
                context.publish(ClientEvent::Error(error));
            }
            return None;
        };

        let attempt = schedule.attempts();
        context.set_connection(ConnectionState::Reconnecting);
        context.publish(ClientEvent::ReconnectScheduled { attempt, delay_ms });

        // Logged rather than published: a server down for an hour would
        // otherwise put an error on screen every thirty seconds and fill the log
        // with the same sentence. `ReconnectScheduled` is what the UI needs, and
        // this is what someone reading the log afterwards needs.
        tracing::warn!(session = %context.session, attempt, delay_ms, "reconnecting");

        match wait_or_stop(Duration::from_millis(delay_ms), commands, context).await {
            Wait::Elapsed => {}
            // The user closed the session. The caller tears it down on the way
            // out, so nothing is published here.
            Wait::Stop => return None,
        }

        match crate::open_connection(config) {
            // The state stays `Reconnecting` until the handshake completes: the
            // session really is still recovering, and `refresh` publishes
            // `Connected` when it is not.
            Ok(connection) => {
                schedule.reset();
                return Some(connection);
            }
            Err(next) => error = Some(next),
        }
    }
}

/// What interrupted a backoff wait.
enum Wait {
    /// The delay passed; time to try again.
    Elapsed,
    /// A command arrived that ends the session.
    Stop,
}

/// Waits out a backoff delay, still answering commands.
///
/// Interruptible on purpose: someone who asks to disconnect during a thirty
/// second backoff should not be made to sit through it. Commands that need a
/// connection are refused rather than parked, because there is not one.
async fn wait_or_stop(
    delay: Duration,
    commands: &mut mpsc::Receiver<Command>,
    context: &Arc<Context>,
) -> Wait {
    let deadline = tokio::time::sleep(delay);
    tokio::pin!(deadline);

    loop {
        tokio::select! {
            () = &mut deadline => return Wait::Elapsed,
            command = commands.recv() => match command {
                // Every handle was dropped, or the session was closed.
                None => return Wait::Stop,
                Some(Command::Disconnect { reply }) => {
                    // Idempotent by contract: disconnecting something that is
                    // already disconnected is a success, not a failure.
                    let _ = reply.send(Ok(()));
                    return Wait::Stop;
                }
                Some(command) => {
                    // No connection to carry it, and none coming before the
                    // backoff is up. Answering now beats making the caller wait
                    // for an answer that is already known.
                    tracing::debug!(
                        session = %context.session,
                        ?command,
                        "refusing a command while reconnecting"
                    );
                    let _ = command.into_reply().send(Err(crate::not_connected()));
                }
            },
        }
    }
}

/// Applies one stream item.
///
/// Items that end the connection are not handled here — they decide what the end
/// *means*, which is the caller's business. See [`serve`].
#[allow(clippy::too_many_arguments)]
fn handle_item(
    item: StreamItem,
    connection: &mut Connection,
    context: &Arc<Context>,
    next_message_id: &mut u64,
    pending: &mut HashMap<MessageHandle, Reply>,
    ready: &mut Option<oneshot::Sender<Result<(), ClientError>>>,
    audio: &mut Audio,
) {
    match item {
        StreamItem::Audio(packet) => {
            // `handle_packet` takes ownership, so the sender is read first.
            let Some(from) = sender_of(&packet) else {
                return;
            };
            if let Err(error) = audio.handler.handle_packet(from, packet) {
                tracing::debug!(%error, "dropped an incoming voice packet");
                return;
            }
            pump_audio(audio, context);
        }

        StreamItem::BookEvents(events) => {
            refresh(context, connection, ready);
            for event in &events {
                publish_book_event(event, context, next_message_id);
            }
        }

        StreamItem::MessageResult(handle, result) => {
            // The server has answered: this is the point a send is confirmed or
            // refused, not when the packet was queued.
            if let Some(reply) = pending.remove(&handle) {
                let _ = reply.send(result.map_err(|error| command_error(&error)));
            }
        }

        StreamItem::IdentityLevelIncreasing(level) => {
            tracing::info!(session = %context.session, level, "increasing identity level");
        }

        StreamItem::IdentityLevelIncreased => {
            // The library upgraded the key pair's proof of work. Persist it, or
            // the next run presents the weaker identity and redoes the work.
            persist_identity(connection, context);
        }

        // Everything else — file transfer, network statistics, audio — belongs
        // to phases this milestone does not reach.
        _ => {}
    }
}

/// Which client sent an incoming voice packet.
fn sender_of(packet: &InAudioBuf) -> Option<tsclientlib::ClientId> {
    match packet.data().data() {
        AudioData::S2C { from, .. } | AudioData::S2CWhisper { from, .. } => {
            Some(tsclientlib::ClientId(*from))
        }
        // Anything client-to-server has no business arriving here.
        _ => None,
    }
}

/// Mixes whatever is buffered and hands it to the sink.
///
/// Called once per received packet, which is the natural frame rate: one packet
/// carries one 20 ms frame, so mixing once per packet keeps the mixer in step
/// with the audio it is consuming.
fn pump_audio(audio: &mut Audio, context: &Arc<Context>) {
    let Some(sink) = context.audio_sink() else {
        return;
    };

    // Skip the work entirely when the sink is full: nobody would hear the
    // result, and the handler keeps its own buffer.
    if sink.space() < AUDIO_FRAME_SAMPLES {
        return;
    }

    // `fill_buffer` *adds* into the buffer, so it has to start at silence.
    audio.mix.fill(0.0);
    let stopped = audio.handler.fill_buffer(&mut audio.mix);
    sink.push(&audio.mix);

    for client in stopped {
        tracing::trace!(client = %client.0, "client stopped talking");
    }
}

/// Builds the outgoing packet for one encoded frame.
///
/// `OutAudio::new` copies the payload into an owned `OutPacket`, so the result
/// does not borrow the frame it came from.
fn out_audio(packet: &VoicePacket) -> Result<OutPacket, ClientError> {
    let codec = match packet.codec {
        Codec::Opus => CodecType::OpusVoice,
        other => {
            tracing::debug!(?other, "refusing to send a frame in an unencodable codec");
            return Err(ClientError::Voice(VoiceError::UnsupportedCodec));
        }
    };

    Ok(OutAudio::new(&AudioData::C2S {
        id: packet.sequence as u16,
        codec,
        data: &packet.payload,
    }))
}

/// Rebuilds the snapshot and publishes whatever changed.
fn refresh(
    context: &Arc<Context>,
    connection: &Connection,
    ready: &mut Option<oneshot::Sender<Result<(), ClientError>>>,
) {
    let Ok(book) = connection.get_state() else {
        // Called before the handshake finished, or after the connection ended.
        return;
    };

    let mut state = convert::snapshot(book, context.server());
    // The server's own name wins over the label the user configured.
    if !state.info.name.is_empty() {
        context.adopt_server_name(&state.info.name);
        state.server.name = state.info.name.clone();
    }

    let previous = context.lock().snapshot.take();
    let events = diff::between(previous.as_ref(), &state);

    // The transition belongs to *every* successful handshake, not just the
    // first. Rebuilding a dropped connection runs this again, and gating it on
    // `ready` — a one-shot signal that was spent the first time — left a session
    // that was live again still reporting `Reconnecting`: the channel tree,
    // permissions and diffs all updated while the front-end greyed the server
    // out and refused to send anything.
    if context.connection_state() != ConnectionState::Connected {
        context.set_connection(ConnectionState::Connected);
        context.publish(ClientEvent::Connected {
            server: state.server.clone(),
            info: state.info.clone(),
        });
    }

    // Unblocks `connect()`. This does *not* mean the full tree has arrived: a
    // TeamSpeak server describes itself before it sends its channels and
    // clients, so the first snapshot — and the `Connected` event built from it —
    // can legitimately be near-empty. Everything else follows as further events,
    // and a front-end should render from those rather than assuming `connect()`
    // returning means "complete".
    if let Some(ready) = ready.take() {
        let _ = ready.send(Ok(()));
    }

    for event in events {
        context.publish(event);
    }

    let mut shared = context.lock();
    shared.server_info = Some(state.info.clone());
    shared.permissions = state.permissions;
    shared.snapshot = Some(state);
}

/// Translates a message or poke out of a book event.
fn publish_book_event(event: &BookEvent, context: &Arc<Context>, next_message_id: &mut u64) {
    let BookEvent::Message {
        target,
        invoker,
        message,
    } = event
    else {
        // Property edits are handled by re-snapshotting, not per-variant.
        return;
    };

    let sender = ClientId::new(invoker.id.0);

    match target {
        tsclientlib::MessageTarget::Poke(_) => {
            context.publish(ClientEvent::Poked {
                client_id: sender,
                sender_name: invoker.name.clone(),
                message: message.clone(),
            });
        }
        _ => {
            // A channel message carries no channel id: it arrived in the channel
            // we are in, which the snapshot already knows.
            let target = match target {
                tsclientlib::MessageTarget::Server => MessageTarget::Server,
                tsclientlib::MessageTarget::Client(id) => {
                    MessageTarget::Client(ClientId::new(id.0))
                }
                tsclientlib::MessageTarget::Channel | tsclientlib::MessageTarget::Poke(_) => {
                    match context
                        .lock()
                        .snapshot
                        .as_ref()
                        .and_then(|s| s.own_channel_id)
                    {
                        Some(channel_id) => MessageTarget::Channel(channel_id),
                        // Should not happen: a channel message implies we are in
                        // one. Falling back to the server target loses the
                        // scope, so say so rather than guessing a channel.
                        None => {
                            tracing::warn!(
                                session = %context.session,
                                "channel message received with no known channel"
                            );
                            MessageTarget::Server
                        }
                    }
                }
            };

            let id = MessageId::new(*next_message_id);
            *next_message_id += 1;

            context.publish(ClientEvent::MessageReceived(Message {
                id,
                sender: Some(sender),
                sender_name: invoker.name.clone(),
                target,
                content: message.clone(),
                timestamp: now_millis(),
            }));
        }
    }
}

/// Writes back an identity the library has strengthened.
fn persist_identity(connection: &Connection, context: &Arc<Context>) {
    let Some((store, profile)) = &context.identity_store else {
        return;
    };
    let Some(identity) = connection.get_options().get_identity() else {
        return;
    };

    match crate::identity::encode(identity) {
        Ok(stored) => {
            if let Err(error) = store.save(profile, &stored) {
                // Not fatal: the connection works, the next run just starts from
                // the weaker proof of work.
                tracing::warn!(session = %context.session, %error, "could not persist identity");
            }
        }
        Err(error) => {
            tracing::warn!(session = %context.session, %error, "could not encode identity");
        }
    }
}

/// Runs one command against the connection.
fn handle_command(
    command: Command,
    connection: &mut Connection,
    pending: &mut HashMap<MessageHandle, Reply>,
) {
    match command {
        Command::SendText {
            target,
            text,
            reply,
        } => {
            let (mode, target_client_id) = match target {
                MessageTarget::Server => (TextMessageTargetMode::Server, None),
                // The channel is whichever one we are in; the server resolves it.
                MessageTarget::Channel(_) => (TextMessageTargetMode::Channel, None),
                MessageTarget::Client(id) => (
                    TextMessageTargetMode::Client,
                    Some(tsclientlib::ClientId(id.get())),
                ),
            };

            let part = OutSendTextMessagePart {
                target: mode,
                target_client_id,
                message: Cow::Borrowed(text.as_str()),
            };
            settle(part.send_with_result(connection), reply, pending);
        }

        Command::JoinChannel { channel_id, reply } => {
            let part = match own_move_part(connection, channel_id) {
                Ok(part) => part,
                Err(error) => {
                    let _ = reply.send(Err(error));
                    return;
                }
            };
            settle(part.send_with_result(connection), reply, pending);
        }

        Command::MoveClient {
            client_id,
            channel_id,
            reply,
        } => {
            let part = OutClientMovePart {
                client_id: tsclientlib::ClientId(client_id.get()),
                channel_id: tsclientlib::ChannelId(channel_id.get()),
                // Always send an explicit password. Some server builds reject a
                // move that omits `cpw` entirely rather than treating it as
                // empty.
                channel_password: Some(Cow::Borrowed("")),
            };
            settle(part.send_with_result(connection), reply, pending);
        }

        Command::Poke {
            client_id,
            message,
            reply,
        } => {
            let part = OutClientPokeRequestPart {
                client_id: tsclientlib::ClientId(client_id.get()),
                message: Cow::Borrowed(message.as_str()),
            };
            settle(part.send_with_result(connection), reply, pending);
        }

        Command::SendVoice { packet, reply } => {
            // The library decides whether the server would accept audio at all
            // — muted, away, or without talk power all count as no.
            if !connection.can_send_audio() {
                let _ = reply.send(Err(ClientError::Voice(VoiceError::NotConnected)));
                return;
            }

            let outcome = out_audio(&packet)
                .and_then(|audio| connection.send_audio(audio).map_err(|e| protocol_error(&e)));
            let _ = reply.send(outcome);
        }

        Command::SetVoiceState { state, reply } => {
            // Told to the server, not just kept locally: it is what lets other
            // clients grey out the speaker instead of receiving silence.
            let part = {
                let Ok(book) = connection.get_state() else {
                    let _ = reply.send(Err(not_connected()));
                    return;
                };
                book.client_update()
                    .set_input_muted(state.input_muted)
                    .set_output_muted(state.output_muted)
            };
            settle(part.send_with_result(connection), reply, pending);
        }

        Command::Disconnect { reply } => {
            let outcome = connection
                .disconnect(DisconnectOptions::new())
                .map_err(|e| protocol_error(&e));
            let _ = reply.send(outcome);
        }
    }
}

/// Builds the self-move that entering a channel is expressed as.
///
/// The concrete type is named rather than returned as `impl Trait`: in edition
/// 2024 an opaque return type captures the input lifetime, which would keep the
/// connection borrowed and block the `&mut` send that follows.
fn own_move_part(
    connection: &Connection,
    channel_id: ChannelId,
) -> Result<OutClientMovePart<'static>, ClientError> {
    let book = connection
        .get_state()
        .map_err(|_| ClientError::Network(NetworkError::new("not connected to a server")))?;
    let own = book.clients.get(&book.own_client).ok_or_else(|| {
        ClientError::Protocol(ProtocolError::new(
            "the server has not told us which client is ours",
        ))
    })?;

    let mut part = own.client_move(tsclientlib::ChannelId(channel_id.get()));
    part.channel_password = Some(Cow::Borrowed(""));
    Ok(part)
}

/// Records a send so its server response can settle the caller's future.
fn settle(
    send: Result<MessageHandle, tsclientlib::Error>,
    reply: Reply,
    pending: &mut HashMap<MessageHandle, Reply>,
) {
    match send {
        // Not resolved yet: the server's answer arrives as a `MessageResult`.
        Ok(handle) => {
            pending.insert(handle, reply);
        }
        Err(error) => {
            let _ = reply.send(Err(protocol_error(&error)));
        }
    }
}

fn protocol_error(error: &tsclientlib::Error) -> ClientError {
    ClientError::Protocol(ProtocolError::new(error.to_string()))
}

fn not_connected() -> ClientError {
    ClientError::Network(NetworkError::new("not connected to a server"))
}

fn command_error(error: &CommandError) -> ClientError {
    // A refusal that names the missing permission is a permission problem, not
    // a protocol one: the UI should hide the action, not report a failure.
    if let Some(permission) = &error.missing_permission {
        // `Permission` is a bare numeric id with no display form; report the id
        // rather than inventing a name for it.
        return ClientError::Permission(PermissionError::MissingPermission {
            permission: permission.0,
        });
    }
    ClientError::Protocol(ProtocolError::new(error.error.to_string()))
}

fn now_millis() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|elapsed| elapsed.as_millis() as i64)
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A schedule with §35's numbers, whatever the default may later become.
    fn schedule() -> ReconnectSchedule {
        ReconnectSchedule::new(ReconnectPolicy::exponential())
    }

    /// The library reported a drop without producing an error.
    const DROPPED: Option<&ClientError> = None;

    /// An error, as a reference so it can go straight to `next`.
    fn refused(error: &ClientError) -> Option<&ClientError> {
        Some(error)
    }

    #[test]
    fn a_reported_drop_is_retried_on_the_documented_schedule() {
        // §35: 1s, 2s, 4s, 8s, 16s, then the 30s ceiling forever after.
        let mut schedule = schedule();
        let delays: Vec<u64> = (0..7).filter_map(|_| schedule.next(DROPPED)).collect();

        assert_eq!(
            delays,
            vec![1_000, 2_000, 4_000, 8_000, 16_000, 30_000, 30_000]
        );
        assert_eq!(schedule.attempts(), 7);
    }

    #[test]
    fn the_attempt_number_is_one_for_the_first_retry() {
        // `ReconnectScheduled` documents `attempt` as 1 for the first retry, and
        // the UI counts from it.
        let mut schedule = schedule();
        assert_eq!(schedule.attempts(), 0);

        schedule.next(DROPPED);
        assert_eq!(schedule.attempts(), 1);
    }

    #[test]
    fn an_unretryable_error_ends_the_session_instead_of_looping() {
        // A rejected password does not become correct by waiting, and retrying a
        // kick is how a client gets banned. `is_retryable` decides, and this is
        // the only caller of it.
        let mut schedule = schedule();

        for error in [
            ClientError::Authentication(ts_model::AuthError::InvalidIdentity),
            ClientError::Permission(PermissionError::Denied),
            ClientError::Unsupported("whisper".into()),
        ] {
            assert_eq!(schedule.next(refused(&error)), None, "{error:?}");
        }
        assert_eq!(
            schedule.attempts(),
            0,
            "a refusal must not consume the retry budget"
        );
    }

    #[test]
    fn a_network_error_is_retried_even_though_it_carries_a_reason() {
        // The other half of the rule: an established connection that fails with
        // a transport error gets the same patience as a drop with no error at
        // all, because that is exactly the "server is not up yet" case.
        let mut schedule = schedule();

        for error in [
            ClientError::Network(NetworkError::new("connection refused")),
            ClientError::Timeout,
        ] {
            assert!(schedule.next(refused(&error)).is_some(), "{error:?}");
        }
        assert_eq!(schedule.attempts(), 2);
    }

    #[test]
    fn a_recovered_connection_starts_the_schedule_over() {
        // A blip that resolved must not cost the next drop its patience: an
        // hour-old session that flickers should still be retried after a second.
        let mut schedule = schedule();
        for _ in 0..4 {
            schedule.next(DROPPED);
        }
        assert_eq!(schedule.attempts(), 4);

        schedule.reset();
        assert_eq!(schedule.attempts(), 0);
        assert_eq!(schedule.next(DROPPED), Some(1_000));
    }

    #[test]
    fn the_policy_comes_from_the_config_rather_than_a_constant() {
        // The seam the settings reach the reconnect through. "Turn automatic
        // reconnect off" is `max_attempts: Some(0)`, and a schedule built from
        // that config must refuse the very first retry.
        let mut config = ConnectionConfig::new(
            ts_model::ConnectionTarget::new("example.com", ts_model::DEFAULT_PORT),
            "Tester",
            ts_identity::Identity::new("uid=", vec![1, 2, 3]),
        );
        config.reconnect.max_attempts = Some(0);

        let mut reconnect = Reconnect::new(config);
        assert_eq!(reconnect.schedule.next(DROPPED), None);
    }

    #[test]
    fn a_config_carrying_no_policy_still_retries() {
        // The other half: a config built without touching the field — which is
        // what every caller that predates settings does — behaves as before.
        let config = ConnectionConfig::new(
            ts_model::ConnectionTarget::new("example.com", ts_model::DEFAULT_PORT),
            "Tester",
            ts_identity::Identity::new("uid=", vec![1, 2, 3]),
        );

        let mut reconnect = Reconnect::new(config);
        assert_eq!(reconnect.schedule.next(DROPPED), Some(1_000));
    }

    #[test]
    fn a_budget_is_honoured_when_one_is_set() {
        // The default retries forever — §35 gives no ceiling — but the policy
        // supports one, and the loop has to respect it.
        let mut policy = ReconnectPolicy::exponential();
        policy.max_attempts = Some(3);
        let mut schedule = ReconnectSchedule::new(policy);

        assert!(schedule.next(DROPPED).is_some());
        assert!(schedule.next(DROPPED).is_some());
        assert!(schedule.next(DROPPED).is_some());
        assert_eq!(schedule.next(DROPPED), None, "the budget was exceeded");
    }
}
