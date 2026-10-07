//! # ts-protocol-tsclient
//!
//! The `tsclientlib` adapter shared by the TeamSpeak 3 and 6 backends.
//!
//! **TS6 runs on the same base protocol as TS3**, which was measured rather
//! than assumed: this adapter connects to a `6.0.0-beta13.1` server and gets
//! the channel tree, client list, chat and two-way voice with no changes.
//! What differs between the two is the capability set and TS6's `stream`
//! family — which is why the shared code lives here rather than in a crate
//! named after one of them.
//!
//! This crate is the only place in the project allowed to know about
//! `tsclientlib` and the wire format. Everything it exposes is expressed in
//! [`ts_model`], so the rest of the client — and, through the FFI layer,
//! Flutter — never sees a protocol concept (§77).
//!
//! ```text
//! ts-protocol       ts-protocol-ts3    ts-protocol-ts6
//!       ▲                  │                  │
//!       └────────── ts-protocol-tsclient ◀───┘
//!                         │
//!        TsClient ──mpsc──▶ actor ──▶ tsclientlib
//!                              │
//!                              └──▶ EventBus
//! ```
//!
//! The two thin crates above decide *which* protocol a server is and own
//! whatever that protocol adds. This one only knows the part they share.
//!
//! The connection lives in a background task rather than behind a lock,
//! because `tsclientlib::Connection` is single-owner and only makes progress
//! while its event stream is polled. See [`actor`] for the details.

mod actor;
mod convert;
mod diff;
pub mod extension;
mod identity;

use std::sync::{Arc, Mutex, MutexGuard};
use std::time::Duration;

use ts_protocol::AudioSink;

use async_trait::async_trait;
use tokio::sync::{mpsc, oneshot};
use ts_events::EventBus;
use ts_identity::IdentityStore;
use ts_model::{
    BanDuration, Capabilities, ChannelId, ClientError, ClientId, ConnectionState, IdentityError,
    KickScope, MessageTarget, NetworkError, Permissions, ProtocolKind, Server, ServerInfo,
    SessionId, VoiceState,
};
use ts_protocol::{
    Backend, ChannelOperations, ClientOperations, Connection, ConnectionConfig, Dialect, Messaging,
    PermissionsReport, Presence, Voice, VoicePacket,
};

use actor::{Command, Context};
use tsclientlib::{ReconnectMode, ServerType};

/// How long to wait for the handshake before giving up.
const CONNECT_TIMEOUT: Duration = Duration::from_secs(20);

/// How long to wait for a graceful shutdown before aborting the task.
const DISCONNECT_TIMEOUT: Duration = Duration::from_secs(5);

/// How many commands may queue before a caller starts waiting.
const COMMAND_BUFFER: usize = 64;

/// Generates a new client identity.
///
/// Hand this straight to [`IdentityStore::load_or_create`] so a fresh identity
/// is only created when no stored one exists (§36).
///
/// # Errors
///
/// Returns [`IdentityError`] if the identity cannot be encoded. The error is
/// already in `ts-identity`'s vocabulary so it drops into `load_or_create`
/// without an adapter.
pub fn generate_identity() -> Result<ts_identity::Identity, IdentityError> {
    identity::generate().map_err(|error| match error {
        ClientError::Identity(inner) => inner,
        // `identity::generate` only ever fails with an identity error; anything
        // else would be a programming mistake, so report it faithfully.
        other => IdentityError::Malformed {
            message: other.to_string(),
        },
    })
}

/// A TeamSpeak 3 backend.
///
/// Cheap to clone: every clone shares the same connection, which is what lets
/// [`Backend`] hand out one handle per capability.
#[derive(Clone)]
pub struct TsClient {
    inner: Arc<Inner>,
    extension: Option<Arc<dyn extension::ScreenExtension>>,
}

struct Inner {
    events: EventBus,
    session: SessionId,
    server: Server,
    /// Where a strengthened identity is persisted, and under which profile.
    identity: Option<(IdentityStore, String)>,
    /// The audio sink, held here as well as on the context so one installed
    /// before connecting is not lost.
    audio_sink: Mutex<Option<Arc<dyn AudioSink>>>,
    running: Mutex<Option<Running>>,
}

/// The live connection, once there is one.
struct Running {
    commands: mpsc::Sender<Command>,
    context: Arc<Context>,
    task: tokio::task::JoinHandle<()>,
}

impl TsClient {
    /// Prepares a backend for `server`.
    ///
    /// Nothing connects until [`TsClient::open`] is called.
    #[must_use]
    pub fn new(
        events: EventBus,
        session: SessionId,
        server: Server,
        identity: Option<(IdentityStore, String)>,
    ) -> Self {
        Self {
            extension: None,
            inner: Arc::new(Inner {
                events,
                session,
                server,
                identity,
                audio_sink: Mutex::new(None),
                running: Mutex::new(None),
            }),
        }
    }

    /// Opens the connection and waits for the handshake to finish.
    ///
    /// # Errors
    ///
    /// - [`ClientError::Identity`] if the stored identity cannot be parsed.
    /// - [`ClientError::Network`] if the transport or handshake fails.
    /// - [`ClientError::Timeout`] if the server does not complete the handshake.
    pub async fn open(&mut self, config: ConnectionConfig) -> Result<(), ClientError> {
        // Reconnecting is just opening again; make sure the old task is gone so
        // its events cannot interleave with the new one.
        self.close().await?;

        let target = config.target.clone();

        // Resolution happens here; the handshake itself happens in the actor.
        let connection = open_connection(&config)?;

        let mut context = Context::new(
            self.inner.session,
            self.inner.server.clone(),
            self.inner.events.clone(),
            self.inner.identity.clone(),
        );
        context.extension = self.extension.clone();
        let context = Arc::new(context);
        // Install a sink that was set before this connect, so audio is routed
        // from the very first frame rather than after the UI gets around to it.
        if let Some(sink) = self.audio_sink() {
            context.set_audio_sink(sink);
        }

        let (commands, command_rx) = mpsc::channel(COMMAND_BUFFER);
        let (ready_tx, ready_rx) = oneshot::channel();
        let task = tokio::spawn(actor::run(
            connection,
            command_rx,
            context.clone(),
            ready_tx,
            // The config is moved rather than dropped: rebuilding a dropped
            // connection needs the same identity, nickname and passwords, and
            // this is the last place that has them all (§36).
            actor::Reconnect::new(config),
        ));

        {
            let mut running = self.running();
            *running = Some(Running {
                commands,
                context,
                task,
            });
        }

        match tokio::time::timeout(CONNECT_TIMEOUT, ready_rx).await {
            Ok(Ok(result)) => result,
            // The actor ended before signalling, so it has already published
            // the reason; report the outcome of the attempt itself.
            Ok(Err(_)) => Err(target_error(
                &target,
                NetworkError::new("the connection closed before the handshake finished"),
            )),
            Err(_) => {
                self.close().await.ok();
                Err(ClientError::Timeout)
            }
        }
    }

    /// Closes the connection and waits for the actor to stop.
    ///
    /// Idempotent: closing when nothing is open succeeds.
    ///
    /// # Errors
    ///
    /// Currently always succeeds; the signature leaves room for a backend that
    /// can report a failed shutdown.
    pub async fn close(&mut self) -> Result<(), ClientError> {
        let running = {
            let mut guard = self.running();
            guard.take()
        };
        let Some(running) = running else {
            return Ok(());
        };

        let (reply_tx, reply_rx) = oneshot::channel();
        if running
            .commands
            .send(Command::Disconnect { reply: reply_tx })
            .await
            .is_ok()
        {
            let _ = tokio::time::timeout(DISCONNECT_TIMEOUT, reply_rx).await;
        }

        // Dropping the last sender lets the actor treat the closed channel as a
        // request to finish, even if the disconnect packet never got through.
        drop(running.commands);

        let mut task = running.task;
        if tokio::time::timeout(DISCONNECT_TIMEOUT, &mut task)
            .await
            .is_err()
        {
            // The server never closed its end. Abort rather than leaking a task
            // that still holds the connection.
            tracing::warn!(
                session = %self.inner.session,
                "connection did not close in time; aborting the connection task"
            );
            task.abort();
        }

        Ok(())
    }

    /// The context of the live connection.
    fn context(&self) -> Result<Arc<Context>, ClientError> {
        self.running()
            .as_ref()
            .map(|running| running.context.clone())
            .ok_or_else(not_connected)
    }

    /// Sends a command and waits for the server's answer.
    async fn call(&self, make: impl FnOnce(actor::Reply) -> Command) -> Result<(), ClientError> {
        let commands = self
            .running()
            .as_ref()
            .map(|running| running.commands.clone())
            .ok_or_else(not_connected)?;

        let (reply_tx, reply_rx) = oneshot::channel();
        commands
            .send(make(reply_tx))
            .await
            .map_err(|_| not_connected())?;

        // A dropped reply means the actor ended: report that rather than
        // hanging on a channel that will never fire.
        reply_rx.await.unwrap_or_else(|_| Err(not_connected()))
    }

    fn audio_sink(&self) -> Option<Arc<dyn AudioSink>> {
        self.inner
            .audio_sink
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }

    fn running(&self) -> MutexGuard<'_, Option<Running>> {
        self.inner
            .running
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }
}

impl std::fmt::Debug for TsClient {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("TsClient")
            .field("session", &self.inner.session)
            .field("server", &self.inner.server.name)
            .field("connected", &self.running().is_some())
            .finish()
    }
}

#[async_trait]
impl Connection for TsClient {
    async fn connect(&mut self, config: ConnectionConfig) -> Result<(), ClientError> {
        self.open(config).await
    }

    async fn disconnect(&mut self) -> Result<(), ClientError> {
        self.close().await
    }

    fn state(&self) -> ConnectionState {
        match self.running().as_ref() {
            Some(running) => running.context.connection_state(),
            None => ConnectionState::Disconnected,
        }
    }

    fn kind(&self) -> ProtocolKind {
        // Whatever the caller registered the server as. This adapter serves the
        // protocol TS3 and TS6 have in common; the two crates above it decide
        // which one a given server is.
        self.inner.server.protocol
    }

    fn server_info(&self) -> Option<ServerInfo> {
        self.running()
            .as_ref()
            .and_then(|running| running.context.server_info())
    }

    fn capabilities(&self) -> Capabilities {
        // The set follows the protocol, since that is what differs between
        // them. Reporting none while disconnected keeps a UI from offering
        // actions with nothing behind them.
        match self.state() {
            ConnectionState::Connected => Capabilities::for_protocol(self.inner.server.protocol),
            _ => Capabilities::NONE,
        }
    }
}

#[async_trait]
impl ChannelOperations for TsClient {
    async fn join_channel(&mut self, channel_id: ChannelId) -> Result<(), ClientError> {
        self.call(|reply| Command::JoinChannel { channel_id, reply })
            .await
    }

    async fn leave_channel(&mut self) -> Result<(), ClientError> {
        let context = self.context()?;
        let snapshot = context.snapshot().ok_or_else(not_connected)?;
        let default = snapshot
            .channels
            .iter()
            .find(|channel| channel.is_default)
            .map(|channel| channel.id)
            .ok_or(ClientError::Unsupported(
                "this server has no default channel to return to".into(),
            ))?;
        self.join_channel(default).await
    }
}

#[async_trait]
impl ClientOperations for TsClient {
    async fn move_client(
        &mut self,
        client_id: ClientId,
        channel_id: ChannelId,
    ) -> Result<(), ClientError> {
        self.call(|reply| Command::MoveClient {
            client_id,
            channel_id,
            reply,
        })
        .await
    }

    async fn poke(&mut self, client_id: ClientId, message: &str) -> Result<(), ClientError> {
        let message = message.to_string();
        self.call(|reply| Command::Poke {
            client_id,
            message,
            reply,
        })
        .await
    }

    async fn kick(
        &mut self,
        client_id: ClientId,
        scope: KickScope,
        message: Option<&str>,
    ) -> Result<(), ClientError> {
        let message = message.map(str::to_string);
        self.call(|reply| Command::Kick {
            client_id,
            scope,
            message,
            reply,
        })
        .await
    }

    async fn ban(
        &mut self,
        client_id: ClientId,
        duration: BanDuration,
        message: Option<&str>,
    ) -> Result<(), ClientError> {
        let message = message.map(str::to_string);
        self.call(|reply| Command::Ban {
            client_id,
            duration,
            message,
            reply,
        })
        .await
    }
}

#[async_trait]
impl Presence for TsClient {
    async fn set_away(&mut self, message: Option<&str>) -> Result<(), ClientError> {
        let message = message.map(str::to_string);
        self.call(|reply| Command::SetAway { message, reply }).await
    }
}

#[async_trait]
impl Messaging for TsClient {
    async fn send_text(&mut self, target: MessageTarget, text: &str) -> Result<(), ClientError> {
        let text = text.to_string();
        self.call(|reply| Command::SendText {
            target,
            text,
            reply,
        })
        .await
    }
}

#[async_trait]
impl Voice for TsClient {
    async fn send_voice(&mut self, packet: VoicePacket) -> Result<(), ClientError> {
        self.call(|reply| Command::SendVoice { packet, reply })
            .await
    }

    async fn set_voice_state(&mut self, state: VoiceState) -> Result<(), ClientError> {
        self.call(|reply| Command::SetVoiceState { state, reply })
            .await
    }

    fn set_audio_sink(&mut self, sink: Arc<dyn AudioSink>) {
        // Stored on the client as well as on the context, so a sink installed
        // before connecting survives into the connection that follows.
        *self
            .inner
            .audio_sink
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(Arc::clone(&sink));

        if let Some(running) = self.running().as_ref() {
            running.context.set_audio_sink(sink);
        }
    }

    async fn set_client_volume(
        &mut self,
        client_id: ClientId,
        volume: f32,
    ) -> Result<(), ClientError> {
        self.call(|reply| Command::SetClientVolume {
            client_id,
            volume,
            reply,
        })
        .await
    }
}

impl PermissionsReport for TsClient {
    fn permissions(&self) -> Permissions {
        self.running()
            .as_ref()
            .map(|running| running.context.permissions())
            .unwrap_or_else(Permissions::none)
    }
}

/// Builds a [`Backend`] for one session.
///
/// The protocol is taken from `server`, which is what lets one adapter serve
/// both TeamSpeak 3 and TeamSpeak 6 — they share a base protocol, and the
/// difference lives in [`Capabilities`] and in what the layers above add.
///
/// The capabilities are separate trait objects over one shared connection, as
/// the design doc asks for (§10): a caller that only sends chat cannot move
/// clients or start voice by accident.
#[must_use]
pub fn backend(
    events: EventBus,
    session: SessionId,
    server: Server,
    identity: Option<(IdentityStore, String)>,
) -> Backend {
    let kind = server.protocol;
    let client = TsClient::new(events, session, server, identity);

    Backend::new(
        kind,
        Box::new(client.clone()),
        Box::new(client.clone()),
        Box::new(client.clone()),
        Box::new(client.clone()),
        Box::new(client.clone()),
        Box::new(client.clone()),
        Box::new(client),
    )
}

/// Installs backend-owned wire vocabulary over the existing connection.
pub fn backend_with_screen(
    events: EventBus,
    session: SessionId,
    server: Server,
    identity: Option<(IdentityStore, String)>,
    extension: Arc<dyn extension::ScreenExtension>,
) -> Backend {
    let kind = server.protocol;
    let mut client = TsClient::new(events, session, server, identity);
    client.extension = Some(extension);
    Backend::new(
        kind,
        Box::new(client.clone()),
        Box::new(client.clone()),
        Box::new(client.clone()),
        Box::new(client.clone()),
        Box::new(client.clone()),
        Box::new(client.clone()),
        Box::new(client.clone()),
    )
    .with_screen(Box::new(client))
}

#[async_trait]
impl ts_protocol::ScreenSharing for TsClient {
    async fn execute(&mut self, command: ts_model::ScreenCommand) -> Result<(), ClientError> {
        let extension = self
            .extension
            .as_ref()
            .ok_or_else(|| ClientError::Unsupported("screen sharing is unavailable".into()))?;
        tokio::time::timeout(Duration::from_secs(15), async {
            let mut attempt = 0;
            loop {
                let packet = extension.encode(command.clone())?;
                match self
                    .call(|reply| Command::Extension { packet, reply })
                    .await
                {
                    Ok(()) => return Ok(()),
                    Err(error) => {
                        let Some(delay) = extension.retry_delay(attempt, &error) else {
                            return Err(error);
                        };
                        tracing::info!(session = %self.inner.session, attempt = attempt + 1,
                                delay_ms = delay.as_millis(),
                                "screen command throttled by server; retrying");
                        tokio::time::sleep(delay).await;
                        attempt += 1;
                    }
                }
            }
        })
        .await
        .map_err(|_| ClientError::Timeout)?
    }
}

fn server_type(dialect: Dialect) -> ServerType {
    match dialect {
        Dialect::Auto => ServerType::Auto,
        Dialect::TeamSpeak => ServerType::Teamspeak,
        Dialect::TeaSpeak => ServerType::Teaspeak,
    }
}

/// Opens a connection from a config, starting nothing else.
///
/// Shared by the first attempt and by every reconnect, so the two cannot drift:
/// a rebuild that forgot the channel password, or the privilege key, would land
/// the user somewhere else without saying so.
///
/// # Errors
///
/// [`ClientError::Identity`] if the stored identity cannot be decoded, plus
/// whatever the transport reports for failing to resolve or open the socket.
pub(crate) fn open_connection(
    config: &ConnectionConfig,
) -> Result<tsclientlib::Connection, ClientError> {
    let identity = identity::decode(&config.identity)?;

    // Fully qualified: `Connection` is also the name of the trait this type
    // implements.
    let mut options = tsclientlib::Connection::build(config.target.to_string())
        .identity(identity)
        .name(config.nickname.clone())
        // Nightcord owns reconnect policy, so the library reports a dropped
        // connection and ends its stream rather than waiting ten seconds and
        // trying again on a schedule of its own. Two backoffs on one connection
        // would fight, and only one of them can show the user what is happening.
        // See [`docs/reconnect.md`](../../../docs/reconnect.md).
        .reconnect_mode(ReconnectMode::External);
    if let Some(password) = &config.server_password {
        options = options.password(password.clone());
    }
    if let Some(password) = &config.channel_password {
        options = options.channel_password(password.clone());
    }
    if let Some(token) = &config.privilege_key {
        options = options.default_token(token.clone());
    }
    if let Some(channel) = &config.default_channel {
        options = options.channel(channel.clone());
    }

    options
        .server_type(server_type(config.dialect))
        .connect()
        // Attached here rather than by each caller, so a reconnect reports the
        // same target the first attempt did.
        .map_err(|error| target_error(&config.target, error))
}

fn not_connected() -> ClientError {
    ClientError::Network(NetworkError::new("not connected to a server"))
}

/// Attaches the address a transport failure happened at.
fn target_error(
    target: &ts_model::ConnectionTarget,
    message: impl std::fmt::Display,
) -> ClientError {
    ClientError::Network(
        NetworkError::new(message.to_string()).with_target(target.host.clone(), target.port),
    )
}

#[cfg(feature = "unstable")]
pub use tsclientlib;

#[cfg(test)]
mod tests {
    use super::*;
    use ts_model::{ProtocolKind, ServerId};

    fn server() -> Server {
        Server {
            id: ServerId::new(1),
            name: "Configured Label".into(),
            address: "example.com:9987".into(),
            protocol: ProtocolKind::Ts3,
        }
    }

    fn client() -> TsClient {
        TsClient::new(
            EventBus::with_default_capacity(),
            SessionId::new(1),
            server(),
            None,
        )
    }

    #[test]
    fn a_fresh_client_reports_disconnected() {
        let client = client();
        assert_eq!(client.state(), ConnectionState::Disconnected);
        assert_eq!(client.kind(), ProtocolKind::Ts3);
        assert!(client.server_info().is_none());
    }

    #[test]
    fn capabilities_are_absent_until_connected() {
        // A UI must not offer voice or chat on a session with no connection.
        assert_eq!(client().capabilities(), Capabilities::NONE);
    }

    #[test]
    fn permissions_default_to_denied() {
        assert_eq!(client().permissions(), Permissions::none());
    }

    #[tokio::test]
    async fn commands_without_a_connection_fail_cleanly() {
        // The important property: no panic and no hang, just an error.
        let mut client = client();
        let result = client.join_channel(ChannelId::new(1)).await;
        assert!(
            matches!(result, Err(ClientError::Network(_))),
            "got {result:?}"
        );
    }

    #[tokio::test]
    async fn voice_without_a_connection_fails_rather_than_dropping_frames() {
        // The property that matters: a caller can never mistake a discarded
        // frame for a delivered one.
        let mut client = client();

        let result = client.send_voice(VoicePacket::opus(vec![1, 2, 3], 0)).await;
        assert!(
            matches!(result, Err(ClientError::Network(_))),
            "got {result:?}"
        );

        let result = client.set_voice_state(VoiceState::default()).await;
        assert!(
            matches!(result, Err(ClientError::Network(_))),
            "got {result:?}"
        );
    }

    #[test]
    fn a_sink_installed_before_connecting_is_kept() {
        // Otherwise a UI that sets up audio first would silently receive
        // nothing until it happened to call this again.
        struct Null;

        impl ts_protocol::AudioSink for Null {
            fn push(&self, _interleaved: &[f32]) {}
        }

        let mut client = client();
        assert!(client.audio_sink().is_none());

        client.set_audio_sink(Arc::new(Null));
        assert!(client.audio_sink().is_some());
    }

    #[tokio::test]
    async fn closing_an_unopened_client_succeeds() {
        let mut client = client();
        assert!(client.close().await.is_ok());
        assert!(client.disconnect().await.is_ok());
    }

    #[test]
    fn the_protocol_follows_the_server() {
        // The reason this adapter is shared rather than duplicated: the same
        // code serves TS6, and it reports whichever protocol it was given.
        let mut ts6 = server();
        ts6.protocol = ProtocolKind::Ts6;
        let client = TsClient::new(
            EventBus::with_default_capacity(),
            SessionId::new(1),
            ts6,
            None,
        );

        assert_eq!(client.kind(), ProtocolKind::Ts6);
    }

    #[tokio::test]
    async fn a_ts6_client_reports_no_capabilities_until_connected() {
        // Same rule as TS3 — the set only appears once there is a server behind
        // it — so a UI cannot offer streaming on a dead session.
        let mut ts6 = server();
        ts6.protocol = ProtocolKind::Ts6;
        let client = TsClient::new(
            EventBus::with_default_capacity(),
            SessionId::new(1),
            ts6,
            None,
        );

        assert_eq!(client.capabilities(), Capabilities::NONE);
    }

    #[test]
    fn dialect_maps_onto_the_library_server_type() {
        assert_eq!(server_type(Dialect::Auto), ServerType::Auto);
        assert_eq!(server_type(Dialect::TeamSpeak), ServerType::Teamspeak);
        assert_eq!(server_type(Dialect::TeaSpeak), ServerType::Teaspeak);
    }

    #[test]
    fn debug_does_not_reveal_secrets() {
        let rendered = format!("{:?}", client());
        assert!(rendered.contains("TsClient"));
    }

    #[test]
    fn backend_exposes_each_capability_separately() {
        let backend = backend(
            EventBus::with_default_capacity(),
            SessionId::new(1),
            server(),
            None,
        );
        assert_eq!(backend.kind(), ProtocolKind::Ts3);
        // Every capability is reachable, and the connection reports the
        // protocol this backend actually speaks.
        assert_eq!(backend.connection_ref().kind(), ProtocolKind::Ts3);
        assert_eq!(backend.permissions().permissions(), Permissions::none());
    }
}
