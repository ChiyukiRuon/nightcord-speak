//! An in-memory backend for tests.
//!
//! Available behind the `testing` feature so `ts-session`, `ts-core` and
//! `ts-ffi` can exercise their logic without a live server.
//!
//! It doubles as executable documentation of the composition in
//! [`crate::Backend`]: seven narrow capability objects, all sharing one state,
//! no wide interface anywhere.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use crate::AudioSink;

use async_trait::async_trait;
use ts_model::{
    BanDuration, Capabilities, ChannelId, ClientError, ClientId, ConnectionState, KickScope,
    MessageTarget, Permissions, ProtocolKind, ReconnectPolicy, Server, ServerId, ServerInfo,
    VoiceState,
};

use crate::{
    Backend, ChannelOperations, ClientOperations, Connection, ConnectionConfig, Messaging, NoVoice,
    PermissionsReport, Presence, Voice, VoicePacket,
};

/// State shared by every capability of one fake backend.
struct FakeState {
    connection_state: ConnectionState,
    server_info: Option<ServerInfo>,
    capabilities: Capabilities,
    permissions: Permissions,
    /// Every call the backend received, in order, as `"trait.method"`.
    calls: Vec<String>,
    /// Errors to return once for a given call name.
    failures: HashMap<String, ClientError>,
    /// Where decoded audio would go, so tests can drive a sink without a
    /// server.
    audio_sink: Option<Arc<dyn AudioSink>>,
}

impl Default for FakeState {
    fn default() -> Self {
        Self {
            connection_state: ConnectionState::Disconnected,
            server_info: None,
            capabilities: Capabilities::NONE,
            permissions: Permissions::none(),
            calls: Vec::new(),
            failures: HashMap::new(),
            audio_sink: None,
        }
    }
}

impl std::fmt::Debug for FakeState {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // `AudioSink` is not `Debug`, so report whether one is installed
        // rather than deriving.
        f.debug_struct("FakeState")
            .field("connection_state", &self.connection_state)
            .field("server_info", &self.server_info)
            .field("capabilities", &self.capabilities)
            .field("permissions", &self.permissions)
            .field("calls", &self.calls)
            .field("failures", &self.failures)
            .field("audio_sink", &self.audio_sink.is_some())
            .finish()
    }
}

impl FakeState {
    /// Records a call and returns any scripted failure for it.
    ///
    /// A scripted failure is consumed, so the next identical call succeeds —
    /// which is what makes "fail once, then recover" reconnect tests possible.
    fn record(&mut self, call: &str) -> Result<(), ClientError> {
        self.calls.push(call.to_string());
        match self.failures.remove(call) {
            Some(error) => Err(error),
            None => Ok(()),
        }
    }
}

/// Test-side handle for inspecting and steering a fake backend.
#[derive(Debug, Clone)]
pub struct FakeHandle {
    state: Arc<Mutex<FakeState>>,
}

impl FakeHandle {
    /// Every call received so far, in order.
    pub fn calls(&self) -> Vec<String> {
        self.state
            .lock()
            .expect("fake state poisoned")
            .calls
            .clone()
    }

    /// Whether a call named `call` — e.g. `"Messaging.send_text"` — was made.
    pub fn called(&self, call: &str) -> bool {
        self.state
            .lock()
            .expect("fake state poisoned")
            .calls
            .iter()
            .any(|c| c == call)
    }

    /// How many times a call was made.
    pub fn call_count(&self, call: &str) -> usize {
        self.state
            .lock()
            .expect("fake state poisoned")
            .calls
            .iter()
            .filter(|c| *c == call)
            .count()
    }

    /// Makes the next `call` return `error`.
    pub fn fail_next(&self, call: &str, error: ClientError) {
        self.state
            .lock()
            .expect("fake state poisoned")
            .failures
            .insert(call.to_string(), error);
    }

    /// Forces the connection state, as if the transport had changed underneath.
    pub fn set_connection_state(&self, state: ConnectionState) {
        self.state
            .lock()
            .expect("fake state poisoned")
            .connection_state = state;
    }

    /// Sets what [`Connection::server_info`] reports.
    pub fn set_server_info(&self, info: ServerInfo) {
        self.state.lock().expect("fake state poisoned").server_info = Some(info);
    }

    /// Sets what [`Connection::capabilities`] reports.
    pub fn set_capabilities(&self, capabilities: Capabilities) {
        self.state.lock().expect("fake state poisoned").capabilities = capabilities;
    }

    /// Sets what [`PermissionsReport::permissions`] reports.
    pub fn set_permissions(&self, permissions: Permissions) {
        self.state.lock().expect("fake state poisoned").permissions = permissions;
    }

    /// Pushes mixed audio into the sink the backend was given, as if the
    /// server had sent it.
    ///
    /// Returns `false` when no sink has been installed yet.
    pub fn push_audio(&self, interleaved: &[f32]) -> bool {
        let sink = self
            .state
            .lock()
            .expect("fake state poisoned")
            .audio_sink
            .clone();
        match sink {
            Some(sink) => {
                sink.push(interleaved);
                true
            }
            None => false,
        }
    }

    /// How much room the installed sink reports.
    pub fn sink_space(&self) -> Option<usize> {
        let sink = self
            .state
            .lock()
            .expect("fake state poisoned")
            .audio_sink
            .clone();
        sink.map(|sink| sink.space())
    }
}

macro_rules! fake_capability {
    ($name:ident, $state:ident) => {
        struct $name(Arc<Mutex<FakeState>>);
    };
}

fake_capability!(FakeConnection, state);
fake_capability!(FakeChannels, state);
fake_capability!(FakeClients, state);
fake_capability!(FakePresence, state);
fake_capability!(FakeMessaging, state);
fake_capability!(FakeVoice, state);
fake_capability!(FakePermissions, state);

#[async_trait]
impl Connection for FakeConnection {
    async fn connect(&mut self, _config: ConnectionConfig) -> Result<(), ClientError> {
        let mut state = self.0.lock().expect("fake state poisoned");
        state.record("Connection.connect")?;
        state.connection_state = ConnectionState::Connected;
        Ok(())
    }

    async fn disconnect(&mut self) -> Result<(), ClientError> {
        let mut state = self.0.lock().expect("fake state poisoned");
        state.record("Connection.disconnect")?;
        state.connection_state = ConnectionState::Disconnected;
        Ok(())
    }

    fn state(&self) -> ConnectionState {
        self.0.lock().expect("fake state poisoned").connection_state
    }

    fn kind(&self) -> ProtocolKind {
        ProtocolKind::Ts3
    }

    fn server_info(&self) -> Option<ServerInfo> {
        self.0
            .lock()
            .expect("fake state poisoned")
            .server_info
            .clone()
    }

    fn capabilities(&self) -> Capabilities {
        self.0.lock().expect("fake state poisoned").capabilities
    }
}

#[async_trait]
impl ChannelOperations for FakeChannels {
    async fn join_channel(&mut self, _channel_id: ChannelId) -> Result<(), ClientError> {
        self.0
            .lock()
            .expect("fake state poisoned")
            .record("ChannelOperations.join_channel")
    }

    async fn leave_channel(&mut self) -> Result<(), ClientError> {
        self.0
            .lock()
            .expect("fake state poisoned")
            .record("ChannelOperations.leave_channel")
    }
}

#[async_trait]
impl ClientOperations for FakeClients {
    async fn move_client(
        &mut self,
        _client_id: ClientId,
        _channel_id: ChannelId,
    ) -> Result<(), ClientError> {
        self.0
            .lock()
            .expect("fake state poisoned")
            .record("ClientOperations.move_client")
    }

    async fn poke(&mut self, _client_id: ClientId, _message: &str) -> Result<(), ClientError> {
        self.0
            .lock()
            .expect("fake state poisoned")
            .record("ClientOperations.poke")
    }

    async fn kick(
        &mut self,
        _client_id: ClientId,
        scope: KickScope,
        _message: Option<&str>,
    ) -> Result<(), ClientError> {
        // The scope is recorded, not just the call: a front-end that wired the
        // two menu items to the same value would otherwise pass every test.
        let name = match scope {
            KickScope::Channel => "ClientOperations.kick_channel",
            KickScope::Server => "ClientOperations.kick_server",
        };
        self.0.lock().expect("fake state poisoned").record(name)
    }

    async fn ban(
        &mut self,
        _client_id: ClientId,
        duration: BanDuration,
        _message: Option<&str>,
    ) -> Result<(), ClientError> {
        let name = if duration.is_permanent() {
            "ClientOperations.ban_permanent"
        } else {
            "ClientOperations.ban_temporary"
        };
        self.0.lock().expect("fake state poisoned").record(name)
    }
}

#[async_trait]
impl Presence for FakePresence {
    async fn set_away(&mut self, message: Option<&str>) -> Result<(), ClientError> {
        // Away and back are recorded apart, and the message itself is never
        // recorded: it is text the user typed, and a fake that kept it would
        // put user content into every failure message that prints the calls.
        let name = if message.is_some() {
            "Presence.set_away"
        } else {
            "Presence.set_away_cleared"
        };
        self.0.lock().expect("fake state poisoned").record(name)
    }
}

#[async_trait]
impl Messaging for FakeMessaging {
    async fn send_text(&mut self, _target: MessageTarget, _text: &str) -> Result<(), ClientError> {
        self.0
            .lock()
            .expect("fake state poisoned")
            .record("Messaging.send_text")
    }
}

#[async_trait]
impl Voice for FakeVoice {
    async fn send_voice(&mut self, _packet: VoicePacket) -> Result<(), ClientError> {
        self.0
            .lock()
            .expect("fake state poisoned")
            .record("Voice.send_voice")
    }

    async fn set_voice_state(&mut self, _state: VoiceState) -> Result<(), ClientError> {
        self.0
            .lock()
            .expect("fake state poisoned")
            .record("Voice.set_voice_state")
    }

    fn set_audio_sink(&mut self, sink: Arc<dyn AudioSink>) {
        let mut state = self.0.lock().expect("fake state poisoned");
        state.calls.push("Voice.set_audio_sink".to_string());
        state.audio_sink = Some(sink);
    }

    async fn set_client_volume(
        &mut self,
        _client_id: ClientId,
        _volume: f32,
    ) -> Result<(), ClientError> {
        self.0
            .lock()
            .expect("fake state poisoned")
            .record("Voice.set_client_volume")
    }
}

impl PermissionsReport for FakePermissions {
    fn permissions(&self) -> Permissions {
        self.0.lock().expect("fake state poisoned").permissions
    }
}

/// Builds a fake backend and the handle used to steer it.
///
/// `with_voice` decides whether voice is wired to the fake — which accepts
/// packets and records them — or to [`NoVoice`], which reports the capability as
/// unsupported. Testing both proves callers handle a backend that lacks a
/// capability.
#[must_use]
pub fn fake_backend(kind: ProtocolKind, with_voice: bool) -> (Backend, FakeHandle) {
    let state = Arc::new(Mutex::new(FakeState::default()));
    let handle = FakeHandle {
        state: state.clone(),
    };

    let connection = Box::new(FakeConnection(state.clone()));
    let channels = Box::new(FakeChannels(state.clone()));
    let clients = Box::new(FakeClients(state.clone()));
    let presence = Box::new(FakePresence(state.clone()));
    let messaging = Box::new(FakeMessaging(state.clone()));
    let permissions = Box::new(FakePermissions(state.clone()));
    let voice: Box<dyn Voice> = if with_voice {
        Box::new(FakeVoice(state))
    } else {
        Box::new(NoVoice)
    };

    (
        Backend::new(
            kind,
            connection,
            channels,
            clients,
            presence,
            messaging,
            voice,
            permissions,
        ),
        handle,
    )
}

/// A [`Server`] suitable for tests.
#[must_use]
pub fn fake_server(id: u64, protocol: ProtocolKind) -> Server {
    Server {
        id: ServerId::new(id),
        name: format!("Test Server {id}"),
        address: "example.com:9987".into(),
        protocol,
    }
}

/// A [`ConnectionConfig`] suitable for tests.
///
/// Uses a throwaway identity: tests never authenticate against anything.
#[must_use]
pub fn fake_config(target: &str) -> ConnectionConfig {
    ConnectionConfig::new(
        ts_model::ConnectionTarget::parse(target).expect("test target should parse"),
        "Tester",
        ts_identity::Identity::new("test-uid=", vec![0; 8]),
    )
}

/// The default reconnect schedule, re-exported so tests share one definition.
#[must_use]
pub const fn fake_reconnect_policy() -> ReconnectPolicy {
    ReconnectPolicy::exponential()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn fake_records_calls_in_order() {
        let (mut backend, handle) = fake_backend(ProtocolKind::Ts3, true);

        backend
            .channels()
            .join_channel(ChannelId::new(1))
            .await
            .unwrap();
        backend
            .messaging()
            .send_text(MessageTarget::Server, "hi")
            .await
            .unwrap();

        assert_eq!(
            handle.calls(),
            vec!["ChannelOperations.join_channel", "Messaging.send_text"]
        );
        assert!(handle.called("Messaging.send_text"));
        assert_eq!(handle.call_count("Messaging.send_text"), 1);
    }

    #[tokio::test]
    async fn scripted_failure_fires_once_then_recovers() {
        let (mut backend, handle) = fake_backend(ProtocolKind::Ts3, true);
        handle.fail_next("Messaging.send_text", ClientError::Timeout);

        let first = backend
            .messaging()
            .send_text(MessageTarget::Server, "hi")
            .await;
        assert_eq!(first, Err(ClientError::Timeout));

        let second = backend
            .messaging()
            .send_text(MessageTarget::Server, "hi")
            .await;
        assert!(second.is_ok(), "the scripted failure should be consumed");
    }

    #[tokio::test]
    async fn connect_moves_the_state_machine() {
        let (mut backend, handle) = fake_backend(ProtocolKind::Ts3, true);

        assert_eq!(backend.state(), ConnectionState::Disconnected);
        backend
            .connection()
            .connect(fake_config("example.com:9987"))
            .await
            .unwrap();
        assert_eq!(backend.state(), ConnectionState::Connected);
        assert!(handle.called("Connection.connect"));

        backend.connection().disconnect().await.unwrap();
        assert_eq!(backend.state(), ConnectionState::Disconnected);
    }

    #[tokio::test]
    async fn backend_without_voice_reports_unsupported() {
        let (mut backend, _handle) = fake_backend(ProtocolKind::Ts3, false);

        let result = backend
            .voice()
            .send_voice(VoicePacket::opus(vec![1], 0))
            .await;
        assert!(
            matches!(result, Err(ClientError::Unsupported(_))),
            "got {result:?}"
        );
    }

    #[tokio::test]
    async fn backend_with_voice_accepts_packets() {
        let (mut backend, handle) = fake_backend(ProtocolKind::Ts3, true);

        assert!(
            backend
                .voice()
                .send_voice(VoicePacket::opus(vec![1], 0))
                .await
                .is_ok()
        );
        assert!(handle.called("Voice.send_voice"));
    }

    #[tokio::test]
    async fn permissions_come_from_the_backend() {
        let (backend, handle) = fake_backend(ProtocolKind::Ts3, true);
        assert_eq!(backend.permissions().permissions(), Permissions::none());

        handle.set_permissions(Permissions::all());
        assert_eq!(backend.permissions().permissions(), Permissions::all());
    }
}
