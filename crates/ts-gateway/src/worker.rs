//! The core worker: one per gateway, the same shape as the FFI's and the
//! CLI's.
//!
//! It owns the `ts_core::Client`, so `&mut self` and `async` never reach a
//! connection task; commands arrive through a channel, and everything the
//! front-end should see — domain events and command results — is serialised
//! once and broadcast to every authenticated connection.

use std::collections::HashMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use tokio::sync::broadcast;
use tokio::sync::broadcast::error::RecvError;
use tokio::sync::mpsc;
use ts_audio::FRAME_MS;
use ts_core::Client as CoreClient;
use ts_events::{ClientEvent, SessionEvent};
use ts_model::{ClientError, NetworkError, SessionId, VoiceState};
use ts_protocol::VoicePacket;
use ts_wire::{Command, FfiEvent};

use crate::Outbound;
use crate::voice::{RemoteVoice, WsAudioSink, mix};

/// One message from a connection to the worker.
pub(crate) enum GatewayCommand {
    /// A command somebody asked for. The worker answers on the broadcast, not
    /// to the asker — every connection sees every result (v1's documented
    /// multi-tab behaviour).
    Command(Box<Command>),

    /// One 960-sample mono frame of captured audio from `from`.
    Audio {
        /// Which connection sent it; one accumulator per connection is what
        /// makes the mix work.
        from: u64,
        /// The decoded frame.
        frame: Vec<f32>,
    },

    /// Stop the worker and disconnect everything.
    Shutdown,
}

/// The error for addressing a session that has gone away.
fn no_such_session() -> ClientError {
    ClientError::Network(NetworkError::new("no such session"))
}

/// Runs an action against one session, or fails if it is gone.
///
/// A macro rather than a helper taking an async closure — the same reasoning
/// as `ts-ffi`'s copy of it.
macro_rules! with_session {
    ($core:expr, $session:expr, $session_ref:ident => $body:expr) => {
        match $core.sessions_mut().get_mut($session) {
            Some($session_ref) => $body.await,
            None => Err(no_such_session()),
        }
    };
}

pub(crate) struct Worker {
    core: CoreClient,
    /// The identity profile every connection's `connect` is forced onto.
    ///
    /// A browser does not get to pick: TS3 refuses a second connection from
    /// the same identity, so a page free to choose could collide with the
    /// desktop app — and one gateway is one identity by design.
    profile: String,
    outbound: broadcast::Sender<Outbound>,
    commands: mpsc::UnboundedReceiver<GatewayCommand>,
    voice: Option<RemoteVoice>,
    /// The mute/output-muted side of the engine, held outside `voice` the way
    /// the FFI holds it: the intent has to outlive the engine not existing
    /// yet, and setting mute before starting voice must not be an error.
    voice_intent: VoiceState,
    /// The output gate the sink consults; shared with the running sink.
    output_muted: Arc<AtomicBool>,
    /// The current sink, kept so `voice_status` can report what it received.
    voice_sink: Option<Arc<WsAudioSink>>,
    /// Frames browsers sent since the last tick, one per connection.
    pending_audio: HashMap<u64, Vec<f32>>,
    /// Scratch for the mix, sized once.
    mixed: Vec<f32>,
    /// Whether a voice failure has been reported, so a broken stream says so
    /// once rather than fifty times a second.
    voice_failed: bool,
    /// Whether the first transmitted packet has been logged; see the
    /// once-logging note on `WsAudioSink`.
    voice_sent_logged: bool,
}

impl Worker {
    pub(crate) fn new(
        core: CoreClient,
        profile: String,
        outbound: broadcast::Sender<Outbound>,
        commands: mpsc::UnboundedReceiver<GatewayCommand>,
    ) -> Self {
        let voice_intent = VoiceState {
            mode: core.settings().audio.mode,
            ..VoiceState::default()
        };
        Self {
            core,
            profile,
            outbound,
            commands,
            voice: None,
            voice_intent,
            output_muted: Arc::new(AtomicBool::new(false)),
            voice_sink: None,
            pending_audio: HashMap::new(),
            mixed: vec![0.0; ts_audio::FRAME_SAMPLES],
            voice_failed: false,
            voice_sent_logged: false,
        }
    }

    pub(crate) async fn run(mut self) {
        // Subscribed before anything can be commanded, so the handshake burst
        // is never missed.
        let mut subscription = self.core.subscribe();

        let mut ticker = tokio::time::interval(Duration::from_millis(u64::from(FRAME_MS)));
        ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
        // The first tick fires immediately; consume it so the cadence is a
        // full 20 ms from the first frame.
        ticker.tick().await;

        loop {
            tokio::select! {
                command = self.commands.recv() => match command {
                    Some(GatewayCommand::Command(command)) => {
                        if command.is_shutdown() {
                            break;
                        }
                        let name = command.name();
                        self.handle(name, &command).await;
                    }
                    Some(GatewayCommand::Audio { from, frame }) => {
                        // Replaces any unconsumed frame from the same
                        // connection: a tick consumes what is freshest, and a
                        // late frame is worth less than the next one.
                        self.pending_audio.insert(from, frame);
                    }
                    Some(GatewayCommand::Shutdown) | None => break,
                },

                event = subscription.recv() => match event {
                    Ok(SessionEvent { session, event }) => {
                        self.send(FfiEvent::client(session, event));
                    }
                    Err(RecvError::Lagged(missed)) => {
                        // The worker itself fell behind the core. The same
                        // marker the connections would get, from the other
                        // direction — and FfiEvent::lagged logs it.
                        self.send(FfiEvent::lagged(missed));
                    }
                    Err(RecvError::Closed) => break,
                },

                _ = ticker.tick(), if self.voice.is_some() => {
                    self.pump_voice().await;
                }
            }
        }

        // Sessions are disconnected on the way out, so the server does not
        // keep holding a client for this identity.
        if let Err(error) = self.core.disconnect_all().await {
            // There is nobody left to tell; the log is the only honest place.
            tracing::warn!(%error, "could not disconnect every session cleanly");
        }
        tracing::info!("the gateway worker stopped");
    }

    /// Serialises one event and broadcasts it to every connection.
    fn send(&self, event: FfiEvent) {
        match serde_json::to_string(&event) {
            Ok(json) => {
                let _ = self.outbound.send(Outbound::Text(json));
            }
            Err(error) => tracing::error!(%error, "could not serialise an event"),
        }
    }

    /// One mixed frame through gate and encoder, then onto the session.
    async fn pump_voice(&mut self) {
        let Some(voice) = self.voice.as_mut() else {
            self.pending_audio.clear();
            return;
        };
        let session = voice.session;

        let frames: Vec<Vec<f32>> = self.pending_audio.drain().map(|(_, frame)| frame).collect();
        if !mix(&frames, &mut self.mixed) {
            // Nobody sent anything this tick: sending silence would burn
            // uplink for a room nobody is talking in.
            return;
        }

        let encoded = voice.encode_frame(&self.mixed);
        match encoded {
            Ok(Some(packet)) => {
                let bytes = packet.payload.len();
                let outcome = self.send_packet(session, packet).await;
                if outcome.is_ok() && !self.voice_sent_logged {
                    self.voice_sent_logged = true;
                    tracing::info!(session = %session, bytes, "voice: first packet sent to the session");
                }
                if let Err(error) = outcome {
                    if !self.voice_failed {
                        self.voice_failed = true;
                        self.send(FfiEvent::failed("voice", Some(session), error));
                    }
                } else {
                    self.voice_failed = false;
                }
            }
            Ok(None) => {}
            Err(error) => {
                if !self.voice_failed {
                    self.voice_failed = true;
                    self.send(FfiEvent::failed(
                        "voice",
                        Some(session),
                        ClientError::Audio(error),
                    ));
                }
            }
        }
    }

    async fn send_packet(
        &mut self,
        session: SessionId,
        packet: VoicePacket,
    ) -> Result<(), ClientError> {
        with_session!(self.core, session, s => s.send_voice(packet))
    }

    /// Pushes the outcome of a plain `Result<(), _>` action.
    fn report(&self, name: &str, session: Option<SessionId>, outcome: Result<(), ClientError>) {
        match outcome {
            Ok(()) => self.send(FfiEvent::ok(name, session)),
            Err(error) => self.send(FfiEvent::failed(name, session, error)),
        }
    }

    async fn handle(&mut self, name: &'static str, command: &Command) {
        match command {
            Command::Connect(request) => {
                let mut request = (**request).clone();
                request.profile = self.profile.clone();
                match self.core.connect(&request).await {
                    Ok(session) => self.send(FfiEvent::ok(name, Some(session))),
                    Err(error) => self.send(FfiEvent::failed(name, None, error)),
                }
            }

            Command::Disconnect { session } => {
                // A voice path bound to the leaving session goes with it; the
                // same hygiene the FFI's pump applies when its session ends.
                if self
                    .voice
                    .as_ref()
                    .is_some_and(|voice| voice.session == *session)
                {
                    self.voice = None;
                    tracing::info!(session = %session, "voice: the session left; the remote path is closed");
                }
                let outcome = self.core.disconnect(*session).await;
                self.report(name, Some(*session), outcome);
            }

            Command::JoinChannel {
                session,
                channel_id,
            } => {
                let session = *session;
                let outcome = with_session!(self.core, session, s => s.join_channel(*channel_id));
                self.report(name, Some(session), outcome);
            }

            Command::LeaveChannel { session } => {
                let session = *session;
                let outcome = with_session!(self.core, session, s => s.leave_channel());
                self.report(name, Some(session), outcome);
            }

            Command::SendMessage {
                session,
                target,
                text,
            } => {
                let session = *session;
                let outcome = with_session!(self.core, session, s => s.send_text(*target, text));
                self.report(name, Some(session), outcome);
            }

            Command::MoveClient {
                session,
                client_id,
                channel_id,
            } => {
                let session = *session;
                let outcome = with_session!(
                    self.core, session,
                    s => s.move_client(*client_id, *channel_id)
                );
                self.report(name, Some(session), outcome);
            }

            // The gateway runs no audio engine, and the devices of *this*
            // machine are not the browser's anyway.
            Command::ListDevices { direction } => self.send(FfiEvent::failed(
                name,
                None,
                ClientError::Unsupported(format!(
                    "listing {} devices over the gateway",
                    direction.as_str()
                )),
            )),
            Command::VoiceTestOutput => self.send(FfiEvent::failed(
                name,
                None,
                ClientError::Unsupported("the test tone over the gateway".into()),
            )),

            Command::VoiceStatus => self.send(FfiEvent::with_data(
                name,
                self.voice.as_ref().map(|voice| voice.session),
                self.voice_status_json(),
            )),

            Command::VoiceStart { session, .. } => self.start_voice(*session).await,

            Command::VoiceStop => {
                let was_bound = self.voice.take().map(|voice| voice.session);
                self.voice_sink = None;
                self.send(FfiEvent::ok(name, was_bound));
            }

            Command::VoiceSetInputMuted { muted } => {
                self.set_input_muted(*muted);
                self.publish_voice_state().await;
                self.send(FfiEvent::ok(name, None));
            }

            Command::VoiceSetOutputMuted { muted } => {
                self.voice_intent.output_muted = *muted;
                self.output_muted.store(*muted, Ordering::Relaxed);
                if let Some(voice) = self.voice.as_mut() {
                    voice.set_output_muted(*muted);
                }
                self.publish_voice_state().await;
                self.send(FfiEvent::ok(name, None));
            }

            Command::VoicePushToTalk { held } => {
                if let Some(voice) = self.voice.as_mut() {
                    voice.set_push_to_talk(*held);
                }
                self.send(FfiEvent::ok(name, None));
            }

            Command::SettingsGet => {
                let settings = self.core.settings().clone();
                match serde_json::to_value(settings) {
                    Ok(data) => self.send(FfiEvent::with_data(name, None, data)),
                    Err(error) => self.send(FfiEvent::failed(
                        name,
                        None,
                        ClientError::Protocol(ts_model::ProtocolError::new(error.to_string())),
                    )),
                }
            }

            Command::SettingsUpdate(settings) => {
                // A failed write is reported, not papered over — the same
                // contract as the desktop's settings screen.
                match self.core.update_settings((**settings).clone()) {
                    Ok(()) => {
                        // What can be applied to a running voice path, is.
                        self.voice_intent.mode = settings.audio.mode;
                        if let Some(voice) = self.voice.as_mut() {
                            voice.set_mode(settings.audio.mode);
                            voice.set_settings(settings.audio.activation);
                        }
                        self.send(FfiEvent::ok(name, None));
                    }
                    Err(error) => self.send(FfiEvent::failed(name, None, error)),
                }
            }

            Command::BookmarksGet => self.send_bookmarks(name),

            Command::BookmarksUpdate(bookmarks) => {
                match self.core.update_bookmarks((**bookmarks).clone()) {
                    Ok(()) => self.send(FfiEvent::ok(name, None)),
                    Err(error) => self.send(FfiEvent::failed(name, None, error)),
                }
            }

            Command::BookmarksAdd(bookmark) => {
                // `add_bookmark` answers with the list as it now stands, so
                // there is no second read to race with.
                match self.core.add_bookmark((**bookmark).clone()) {
                    Ok(list) => self.send_list(name, list),
                    Err(error) => self.send(FfiEvent::failed(name, None, error)),
                }
            }

            Command::Shutdown => unreachable!("filtered by the caller"),

            // A test seam with no meaning over the wire; refusing it by name
            // keeps a token holder from killing the worker on purpose.
            Command::TestPanic => self.send(FfiEvent::failed(
                name,
                None,
                ClientError::Unsupported("test_panic over the gateway".into()),
            )),
        }
    }

    /// Starts the remote voice path for `session`.
    ///
    /// A fresh session starts **undeafened and unmuted**. The mute intent
    /// lives in this worker, not in the page, so it survives a page reload —
    /// and a page that reloaded shows "Deafen" while the server still has us
    /// marked deaf, which is why nobody's voice arrives and nothing on screen
    /// says why. Mute is a moment, not a preference (the same rule the desktop
    /// applies to a restart).
    async fn start_voice(&mut self, session: SessionId) {
        // Idempotent: starting an already-started session is exactly what it
        // already is. Without this, a second browser (or a second trigger in
        // one page) replaces the sink mid-flight — the old sink keeps pushing
        // for a moment, the new one is what the worker reports on, and the
        // counters disagree with reality. Two tabs driving one gateway is a
        // documented consequence of having no request ids; it should be
        // harmless, not confusing.
        if self
            .voice
            .as_ref()
            .is_some_and(|voice| voice.session == session)
        {
            self.send(FfiEvent::ok("voice_start", Some(session)));
            return;
        }

        let audio = &self.core.settings().audio;
        let mut voice = match RemoteVoice::new(session, self.voice_intent.mode, audio.activation) {
            Ok(voice) => voice,
            Err(error) => {
                self.send(FfiEvent::failed(
                    "voice_start",
                    Some(session),
                    ClientError::Audio(error),
                ));
                return;
            }
        };
        // A fresh session starts clear: see this method's note on why stale
        // intent is worse than forgetfulness here.
        self.voice_intent.input_muted = false;
        self.voice_intent.output_muted = false;
        self.output_muted.store(false, Ordering::Relaxed);
        voice.set_input_muted(false);
        self.voice = Some(voice);

        // The sink is wired straight to the session, exactly like the
        // desktop's: decoded audio never crosses a message boundary in pieces.
        let sink = Arc::new(WsAudioSink::new(
            self.outbound.clone(),
            self.output_muted.clone(),
        ));
        self.voice_sink = Some(Arc::clone(&sink));
        let bound = self
            .core
            .sessions_mut()
            .get_mut(session)
            .map(|session_ref| {
                session_ref.set_audio_sink(sink);
            });
        match bound {
            Some(()) => {
                self.voice_failed = false;
                self.voice_sent_logged = false;
                tracing::info!(session = %session, "voice: the remote path is open");
                self.send(FfiEvent::ok("voice_start", Some(session)));
                // Deliberately *no* announcement to the server here. An
                // earlier revision sent a `clientupdate` at every voice start
                // and receive went silent right after it — the desktop only
                // ever announces on an actual mute change, and the server
                // state is per connection, so a fresh session needs no
                // correction. The local reset above is the whole fix for a
                // stale mute.
            }
            None => {
                self.voice = None;
                self.send(FfiEvent::failed(
                    "voice_start",
                    Some(session),
                    no_such_session(),
                ));
            }
        }
    }

    fn set_input_muted(&mut self, muted: bool) {
        self.voice_intent.input_muted = muted;
        if let Some(voice) = self.voice.as_mut() {
            voice.set_input_muted(muted);
        }
    }

    /// Tells the front-ends what the local voice state is.
    ///
    /// The same shape the FFI publishes: without it the mute buttons in every
    /// connection would only know what they themselves clicked.
    async fn publish_voice_state(&mut self) {
        let Some(voice) = self.voice.as_ref() else {
            return;
        };
        let state = VoiceState {
            mode: self.voice_intent.mode,
            input_muted: self.voice_intent.input_muted,
            output_muted: self.voice_intent.output_muted,
            transmitting: voice.levels().2,
        };
        let session = voice.session;
        let _ = with_session!(self.core, session, s => s.set_voice_state(state));
        self.send(FfiEvent::client(
            session,
            ClientEvent::VoiceStateChanged(state),
        ));
    }

    /// The `voice_status` payload.
    ///
    /// No devices: a browser is not this machine's microphone, and saying so
    /// with `null` is more honest than naming hardware nobody can use.
    fn voice_status_json(&self) -> serde_json::Value {
        let (level, peak, transmitting) = self
            .voice
            .as_ref()
            .map_or((0.0, 0.0, false), RemoteVoice::levels);
        // The receive side's own numbers, so "did audio arrive and how loud"
        // is answerable from the page instead of from a debugger.
        let (received, received_peak) = self
            .voice_sink
            .as_ref()
            .map_or((0, 0.0), |sink| (sink.frames(), sink.peak()));
        serde_json::json!({
            "input": serde_json::Value::Null,
            "output": serde_json::Value::Null,
            "level": level,
            "peak": peak,
            "transmitting": transmitting,
            "healthy": self.voice.is_some(),
            "received": received,
            "received_peak": received_peak,
            // Null until voice starts: the gateway only ever runs the voice
            // profile, because what a browser sends is mono (see ).
            "codec": self.voice.as_ref().map(|voice| voice.codec()),
            "bitrate_bps": self.voice.as_ref().map(|voice| voice.bitrate()),
        })
    }

    /// Answers a bookmarks request with the list as it now stands.
    fn send_bookmarks(&self, name: &'static str) {
        self.send_list(name, self.core.bookmarks().clone());
    }

    /// Serialises a bookmark list into a result.
    fn send_list(&self, name: &'static str, list: ts_settings::BookmarkList) {
        match serde_json::to_value(list) {
            Ok(data) => self.send(FfiEvent::with_data(name, None, data)),
            Err(error) => self.send(FfiEvent::failed(
                name,
                None,
                ClientError::Protocol(ts_model::ProtocolError::new(error.to_string())),
            )),
        }
    }
}
