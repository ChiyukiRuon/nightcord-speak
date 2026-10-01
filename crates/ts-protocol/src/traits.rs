//! The capability traits a backend implements (§9, §10).
//!
//! These are deliberately split rather than merged into one "TeamSpeak
//! everything" interface. TS6 will grow abilities TS3 never had, and a single
//! wide trait would force every backend to answer questions it has no opinion
//! about — or, worse, leak a TS6-only concept into the TS3 path.
//!
//! A backend exposes them together through [`Backend`], which keeps the split
//! while still giving the session one object to drive.

use std::sync::Arc;

use async_trait::async_trait;
use ts_model::{
    BanDuration, Capabilities, ChannelId, ClientError, ClientId, ConnectionState, KickScope,
    MessageTarget, Permissions, ProtocolKind, ServerInfo, VoiceState,
};

use crate::{ConnectionConfig, VoicePacket};

/// Opening and closing the transport, and reporting what is on the far end.
#[async_trait]
pub trait Connection: Send + Sync {
    /// Establishes the session, running the handshake to completion.
    ///
    /// Must be safe to call again after a failure: that is how reconnect works,
    /// and it must reuse [`ConnectionConfig::identity`] rather than minting a
    /// new one (§36).
    async fn connect(&mut self, config: ConnectionConfig) -> Result<(), ClientError>;

    /// Tears the session down. Idempotent: calling it when already disconnected
    /// is a success, not an error.
    async fn disconnect(&mut self) -> Result<(), ClientError>;

    /// Where the session is in its lifecycle.
    fn state(&self) -> ConnectionState;

    /// Which protocol this backend speaks.
    fn kind(&self) -> ProtocolKind;

    /// Server metadata, available once the handshake has produced it.
    fn server_info(&self) -> Option<ServerInfo>;

    /// What the connected server can do. See [`Capabilities::NONE`] before the
    /// handshake completes.
    fn capabilities(&self) -> Capabilities;
}

/// Moving between channels.
#[async_trait]
pub trait ChannelOperations: Send + Sync {
    /// Enters `channel_id`.
    async fn join_channel(&mut self, channel_id: ChannelId) -> Result<(), ClientError>;

    /// Leaves the current channel for the server's default.
    async fn leave_channel(&mut self) -> Result<(), ClientError>;
}

/// Acting on other clients.
#[async_trait]
pub trait ClientOperations: Send + Sync {
    /// Moves `client_id` into `channel_id`.
    async fn move_client(
        &mut self,
        client_id: ClientId,
        channel_id: ChannelId,
    ) -> Result<(), ClientError>;

    /// Pokes `client_id`, which typically makes their client beep.
    async fn poke(&mut self, client_id: ClientId, message: &str) -> Result<(), ClientError>;

    /// Removes `client_id` from a channel or from the server.
    ///
    /// The server is the authority on whether we may: a refusal arrives as
    /// [`ClientError::Permission`] naming the permission that was missing, which
    /// is more useful than anything the client could work out in advance.
    async fn kick(
        &mut self,
        client_id: ClientId,
        scope: KickScope,
        message: Option<&str>,
    ) -> Result<(), ClientError>;

    /// Bans `client_id`, so they cannot come back until the ban is lifted or
    /// expires.
    async fn ban(
        &mut self,
        client_id: ClientId,
        duration: BanDuration,
        message: Option<&str>,
    ) -> Result<(), ClientError>;
}

/// Saying whether we are at the keyboard.
///
/// Its own capability rather than a method on [`ClientOperations`], which acts
/// on *other* clients, or on [`Voice`], whose state is about sound: being away
/// is a fact about us that everyone else can see, and the server is what
/// carries it.
#[async_trait]
pub trait Presence: Send + Sync {
    /// Marks us away with `message`, or back at the keyboard with `None`.
    ///
    /// `Some("")` is a third state the protocol distinguishes and the UI has a
    /// use for: away, with nothing to say. It is not the same as `None`, which
    /// clears the mark entirely.
    async fn set_away(&mut self, message: Option<&str>) -> Result<(), ClientError>;
}

/// Sending messages.
#[async_trait]
pub trait Messaging: Send + Sync {
    /// Sends `text` to `target`.
    async fn send_text(&mut self, target: MessageTarget, text: &str) -> Result<(), ClientError>;
}

/// Where decoded incoming audio is delivered.
///
/// The receive path is split here rather than being one call: a backend decodes,
/// de-jitters and mixes as packets arrive, and a sink consumes the result at the
/// device's pace. Making the sink a trait keeps `ts-audio` free of any protocol
/// dependency while still letting the backend write straight into the playback
/// ring — a per-frame round trip through the session would add latency for no
/// benefit.
pub trait AudioSink: Send + Sync {
    /// Accepts one frame of interleaved stereo audio at 48 kHz.
    ///
    /// Called from the backend's event loop, never from the audio callback, so
    /// an implementation may allocate. It must still be quick: it runs on the
    /// same task the network does.
    fn push(&self, interleaved: &[f32]);

    /// How many samples the sink can take without dropping.
    ///
    /// Lets a backend skip decoding audio nobody can hear yet, rather than
    /// burning CPU to fill a buffer that is already full.
    fn space(&self) -> usize {
        usize::MAX
    }
}

/// Sending and configuring voice.
#[async_trait]
pub trait Voice: Send + Sync {
    /// Sends one encoded frame.
    async fn send_voice(&mut self, packet: VoicePacket) -> Result<(), ClientError>;

    /// Applies a local voice-state change, such as muting.
    ///
    /// A backend needs this because the server is told about muting, so other
    /// clients can grey out the speaker rather than streaming silence.
    async fn set_voice_state(&mut self, state: VoiceState) -> Result<(), ClientError>;

    /// Points the backend at the sink its decoded audio should go to.
    ///
    /// May be called before or after connecting; a backend that has not been
    /// given a sink simply discards incoming audio.
    fn set_audio_sink(&mut self, sink: Arc<dyn AudioSink>);

    /// Scales one client's audio within the mix.
    ///
    /// Purely local: the server is not told, because nothing about what anyone
    /// else receives changes. Whether the setting survives the client going
    /// quiet and speaking again is the backend's business — it is the backend
    /// that owns the mixing queue — but it is expected to.
    async fn set_client_volume(
        &mut self,
        client_id: ClientId,
        volume: f32,
    ) -> Result<(), ClientError>;
}

/// Reading the current permission snapshot.
pub trait PermissionsReport: Send + Sync {
    /// What the connected user may currently do.
    fn permissions(&self) -> Permissions;
}

/// One backend, with each capability reached through its own trait object.
///
/// A caller that only needs to send chat asks for [`Backend::messaging`] and
/// cannot move clients or start voice by accident. Backends can also leave a
/// capability unimplemented and get a clear [`ClientError::Unsupported`] rather
/// than a silent no-op.
pub struct Backend {
    kind: ProtocolKind,
    connection: Box<dyn Connection>,
    channels: Box<dyn ChannelOperations>,
    clients: Box<dyn ClientOperations>,
    presence: Box<dyn Presence>,
    messaging: Box<dyn Messaging>,
    voice: Box<dyn Voice>,
    permissions: Box<dyn PermissionsReport>,
}

impl Backend {
    /// Assembles a backend from its capability implementations.
    ///
    /// They normally come from one struct — see the `Ts3Client` composition in
    /// the design doc (§10) — sharing whatever connection state they need.
    #[must_use]
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        kind: ProtocolKind,
        connection: Box<dyn Connection>,
        channels: Box<dyn ChannelOperations>,
        clients: Box<dyn ClientOperations>,
        presence: Box<dyn Presence>,
        messaging: Box<dyn Messaging>,
        voice: Box<dyn Voice>,
        permissions: Box<dyn PermissionsReport>,
    ) -> Self {
        Self {
            kind,
            connection,
            channels,
            clients,
            presence,
            messaging,
            voice,
            permissions,
        }
    }

    /// Which protocol this backend speaks.
    #[must_use]
    pub fn kind(&self) -> ProtocolKind {
        self.kind
    }

    /// The lifecycle half of the backend.
    pub fn connection(&mut self) -> &mut dyn Connection {
        self.connection.as_mut()
    }

    /// The lifecycle half, for queries that do not change anything.
    ///
    /// Reading state through `&self` matters: a UI redrawing a window should not
    /// need exclusive access to the connection to ask what the server is called.
    pub fn connection_ref(&self) -> &dyn Connection {
        self.connection.as_ref()
    }

    /// The channel half of the backend.
    pub fn channels(&mut self) -> &mut dyn ChannelOperations {
        self.channels.as_mut()
    }

    /// The client-moderation half of the backend.
    pub fn clients(&mut self) -> &mut dyn ClientOperations {
        self.clients.as_mut()
    }

    /// The presence half of the backend.
    pub fn presence(&mut self) -> &mut dyn Presence {
        self.presence.as_mut()
    }

    /// The messaging half of the backend.
    pub fn messaging(&mut self) -> &mut dyn Messaging {
        self.messaging.as_mut()
    }

    /// The voice half of the backend.
    pub fn voice(&mut self) -> &mut dyn Voice {
        self.voice.as_mut()
    }

    /// The permission half of the backend.
    pub fn permissions(&self) -> &dyn PermissionsReport {
        self.permissions.as_ref()
    }

    /// What this server can do, taken from the connection half.
    pub fn capabilities(&self) -> Capabilities {
        self.connection.capabilities()
    }

    /// Where the session is in its lifecycle.
    pub fn state(&self) -> ConnectionState {
        self.connection.state()
    }
}

impl std::fmt::Debug for Backend {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Backend")
            .field("kind", &self.kind)
            .finish_non_exhaustive()
    }
}

/// A [`Voice`] that reports voice as unsupported.
///
/// Lets a backend that has not grown voice yet — TS3 before Milestone 0.2, TS6
/// for now — satisfy the interface without pretending to accept packets that
/// would be silently dropped.
#[derive(Debug, Default, Clone, Copy)]
pub struct NoVoice;

#[async_trait]
impl Voice for NoVoice {
    async fn send_voice(&mut self, _packet: VoicePacket) -> Result<(), ClientError> {
        Err(ClientError::Unsupported(
            "voice is not implemented for this backend".into(),
        ))
    }

    async fn set_voice_state(&mut self, _state: VoiceState) -> Result<(), ClientError> {
        Err(ClientError::Unsupported(
            "voice is not implemented for this backend".into(),
        ))
    }

    fn set_audio_sink(&mut self, _sink: Arc<dyn AudioSink>) {
        // Nothing is decoded, so there is nowhere to send it.
    }

    async fn set_client_volume(
        &mut self,
        _client_id: ClientId,
        _volume: f32,
    ) -> Result<(), ClientError> {
        Err(ClientError::Unsupported(
            "voice is not implemented for this backend".into(),
        ))
    }
}
