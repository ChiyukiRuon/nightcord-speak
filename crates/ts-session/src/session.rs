//! One connection to one server (§17).

use ts_model::{
    BanDuration, Capabilities, ChannelId, ClientError, ClientId, ConnectionState, KickScope,
    MessageTarget, Permissions, ProtocolKind, Server, ServerInfo, SessionId, VoiceState,
};
use ts_protocol::{Backend, ConnectionConfig, VoicePacket};

/// One connection to one server.
///
/// A session is the unit everything above this layer addresses. The UI holds a
/// [`SessionId`], the manager resolves it, and no protocol object ever crosses
/// that boundary (§47) — which is what makes several servers connected at once
/// tractable (§16).
pub struct Session {
    id: SessionId,
    server: Server,
    backend: Backend,
}

impl Session {
    /// Wraps a backend as a session.
    ///
    /// Creating a session does not connect it: [`Session::connect`] does, and
    /// keeping those separate is what lets the UI show a configured-but-offline
    /// server tab.
    #[must_use]
    pub fn new(id: SessionId, server: Server, backend: Backend) -> Self {
        Self {
            id,
            server,
            backend,
        }
    }

    /// This session's handle.
    #[must_use]
    pub fn id(&self) -> SessionId {
        self.id
    }

    /// The server this session was created for.
    #[must_use]
    pub fn server(&self) -> &Server {
        &self.server
    }

    /// Which protocol is actually in use.
    ///
    /// Read from the backend rather than from [`Session::server`]: protocol
    /// detection may correct the saved value during the handshake (§34), and the
    /// backend is the one that knows.
    #[must_use]
    pub fn protocol(&self) -> ProtocolKind {
        self.backend.kind()
    }

    /// Where the session is in its lifecycle.
    #[must_use]
    pub fn state(&self) -> ConnectionState {
        self.backend.state()
    }

    /// What the server can do.
    #[must_use]
    pub fn capabilities(&self) -> Capabilities {
        self.backend.capabilities()
    }

    /// What we are allowed to do.
    #[must_use]
    pub fn permissions(&self) -> Permissions {
        self.backend.permissions().permissions()
    }

    /// Server metadata, once connected.
    #[must_use]
    pub fn server_info(&self) -> Option<ServerInfo> {
        self.backend.connection_ref().server_info()
    }

    /// Establishes the connection.
    ///
    /// # Errors
    ///
    /// Propagates whatever the backend reports. The config's identity is used
    /// as given, so a reconnect presents the same client to the server (§36).
    pub async fn connect(&mut self, config: ConnectionConfig) -> Result<(), ClientError> {
        tracing::info!(
            session = %self.id,
            protocol = %self.protocol(),
            endpoint = %config.endpoint(),
            "connecting"
        );
        self.backend.connection().connect(config).await
    }

    /// Tears the connection down. Idempotent.
    ///
    /// # Errors
    ///
    /// Propagates backend failures; a session that was already disconnected
    /// reports success, not an error.
    pub async fn disconnect(&mut self) -> Result<(), ClientError> {
        tracing::info!(session = %self.id, "disconnecting");
        self.backend.connection().disconnect().await
    }

    /// Sends a chat message.
    ///
    /// # Errors
    ///
    /// Returns [`ClientError::Unsupported`] if the server cannot carry chat.
    pub async fn send_text(
        &mut self,
        target: MessageTarget,
        text: &str,
    ) -> Result<(), ClientError> {
        self.backend.messaging().send_text(target, text).await
    }

    /// Enters a channel.
    ///
    /// # Errors
    ///
    /// Propagates backend failures, including permission denial.
    pub async fn join_channel(&mut self, channel_id: ChannelId) -> Result<(), ClientError> {
        self.backend.channels().join_channel(channel_id).await
    }

    /// Leaves the current channel for the server's default.
    ///
    /// # Errors
    ///
    /// Propagates backend failures.
    pub async fn leave_channel(&mut self) -> Result<(), ClientError> {
        self.backend.channels().leave_channel().await
    }

    /// Moves another client into a channel.
    ///
    /// # Errors
    ///
    /// Propagates backend failures, including permission denial.
    pub async fn move_client(
        &mut self,
        client_id: ClientId,
        channel_id: ChannelId,
    ) -> Result<(), ClientError> {
        self.backend
            .clients()
            .move_client(client_id, channel_id)
            .await
    }

    /// Pokes another client.
    ///
    /// # Errors
    ///
    /// Propagates backend failures, including permission denial.
    pub async fn poke(&mut self, client_id: ClientId, message: &str) -> Result<(), ClientError> {
        self.backend.clients().poke(client_id, message).await
    }

    /// Removes another client from a channel or from the server.
    ///
    /// # Errors
    ///
    /// Propagates backend failures, including permission denial — which is the
    /// interesting one here, and arrives naming the permission that was missing.
    pub async fn kick(
        &mut self,
        client_id: ClientId,
        scope: KickScope,
        message: Option<&str>,
    ) -> Result<(), ClientError> {
        self.backend.clients().kick(client_id, scope, message).await
    }

    /// Bans another client.
    ///
    /// # Errors
    ///
    /// Propagates backend failures, including permission denial.
    pub async fn ban(
        &mut self,
        client_id: ClientId,
        duration: BanDuration,
        message: Option<&str>,
    ) -> Result<(), ClientError> {
        self.backend
            .clients()
            .ban(client_id, duration, message)
            .await
    }

    /// Sends one encoded voice frame.
    ///
    /// # Errors
    ///
    /// Returns [`ClientError::Unsupported`] on a backend without voice.
    pub async fn send_voice(&mut self, packet: VoicePacket) -> Result<(), ClientError> {
        self.backend.voice().send_voice(packet).await
    }

    /// Scales one client's audio within the mix.
    ///
    /// # Errors
    ///
    /// Returns [`ClientError::Unsupported`] on a backend without voice.
    pub async fn set_client_volume(
        &mut self,
        client_id: ClientId,
        volume: f32,
    ) -> Result<(), ClientError> {
        self.backend
            .voice()
            .set_client_volume(client_id, volume)
            .await
    }

    /// Applies a local voice-state change.
    ///
    /// # Errors
    ///
    /// Returns [`ClientError::Unsupported`] on a backend without voice.
    pub async fn set_voice_state(&mut self, state: VoiceState) -> Result<(), ClientError> {
        self.backend.voice().set_voice_state(state).await
    }

    /// Points decoded incoming audio at `sink`.
    ///
    /// Synchronous and infallible: a backend that has not been given a sink
    /// discards incoming audio, so there is nothing here that can fail. It may
    /// be called before connecting.
    pub fn set_audio_sink(&mut self, sink: std::sync::Arc<dyn ts_protocol::AudioSink>) {
        self.backend.voice().set_audio_sink(sink);
    }

    /// The underlying backend.
    ///
    /// For layers that must drive a capability this type does not wrap. Kept
    /// out of the FFI surface on purpose.
    pub fn backend_mut(&mut self) -> &mut Backend {
        &mut self.backend
    }
}

impl std::fmt::Debug for Session {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Session")
            .field("id", &self.id)
            .field("server", &self.server.name)
            .field("protocol", &self.protocol())
            .field("state", &self.state())
            .finish()
    }
}
