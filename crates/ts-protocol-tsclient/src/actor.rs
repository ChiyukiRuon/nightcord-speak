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

use ts_protocol::{AudioSink, Codec, VoicePacket};
use tsclientlib::audio::AudioHandler;
use tsproto_packets::packets::{AudioData, CodecType, InAudioBuf, OutAudio, OutPacket};

use futures::StreamExt as _;
use tokio::sync::{mpsc, oneshot};
use ts_events::{ClientEvent, EventBus, SessionEvent};
use ts_identity::IdentityStore;
use ts_model::{
    ChannelId, ClientError, ClientId, ConnectionState, Message, MessageId, MessageTarget,
    NetworkError, PermissionError, Permissions, ProtocolError, Server, ServerInfo, ServerState,
    SessionId, VoiceError, VoiceState,
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

/// Runs the connection until it ends.
///
/// `ready` is signalled once the handshake completes, or with an error if the
/// connection ends first — so a caller awaiting it can never hang.
pub(crate) async fn run(
    mut connection: Connection,
    mut commands: mpsc::Receiver<Command>,
    context: Arc<Context>,
    ready: oneshot::Sender<Result<(), ClientError>>,
) {
    let mut ready = Some(ready);
    let mut next_message_id: u64 = 1;
    let mut pending: HashMap<MessageHandle, Reply> = HashMap::new();
    let mut audio = Audio::new();

    context.set_connection(ConnectionState::Connecting);

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
            Outcome::Stream(Some(Ok(item))) => {
                if handle_item(
                    item,
                    &mut connection,
                    &context,
                    &mut next_message_id,
                    &mut pending,
                    &mut ready,
                    &mut audio,
                )
                .is_err()
                {
                    break;
                }
            }
            Outcome::Stream(Some(Err(error))) => {
                tracing::warn!(session = %context.session, %error, "connection failed");
                context.set_connection(ConnectionState::Failed);
                context.publish(ClientEvent::Error(protocol_error(&error)));
                break;
            }
            Outcome::Stream(None) => {
                tracing::info!(session = %context.session, "connection stream ended");
                break;
            }
            Outcome::Command(command) => {
                handle_command(command, &mut connection, &mut pending);
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
                break;
            }
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

/// Applies one stream item.
///
/// Returns `Err` when the connection is finished and the loop should stop.
#[allow(clippy::too_many_arguments)]
fn handle_item(
    item: StreamItem,
    connection: &mut Connection,
    context: &Arc<Context>,
    next_message_id: &mut u64,
    pending: &mut HashMap<MessageHandle, Reply>,
    ready: &mut Option<oneshot::Sender<Result<(), ClientError>>>,
    audio: &mut Audio,
) -> Result<(), ClientError> {
    match item {
        StreamItem::Audio(packet) => {
            // `handle_packet` takes ownership, so the sender is read first.
            let Some(from) = sender_of(&packet) else {
                return Ok(());
            };
            if let Err(error) = audio.handler.handle_packet(from, packet) {
                tracing::debug!(%error, "dropped an incoming voice packet");
                return Ok(());
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

        StreamItem::DisconnectedTemporarily(reason) => {
            // The library reconnects on its own; we only report the gap. The
            // session and its identity survive, which is what §36 requires.
            tracing::warn!(session = %context.session, ?reason, "temporarily disconnected");
            context.set_connection(ConnectionState::Reconnecting);
            if matches!(reason, TemporaryDisconnectReason::Serverstop) {
                tracing::info!(session = %context.session, "the server is restarting");
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

    Ok(())
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

    if let Some(ready) = ready.take() {
        context.set_connection(ConnectionState::Connected);
        context.publish(ClientEvent::Connected {
            server: state.server.clone(),
            info: state.info.clone(),
        });
        // Unblocks `connect()`. This does *not* mean the full tree has
        // arrived: a TeamSpeak server describes itself before it sends its
        // channels and clients, so the first snapshot — and the `Connected`
        // event built from it — can legitimately be near-empty. Everything
        // else follows as further events, and a front-end should render from
        // those rather than assuming `connect()` returning means "complete".
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
