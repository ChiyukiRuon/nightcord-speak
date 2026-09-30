//! The table of live sessions (§16, §47).

use std::collections::HashMap;

use ts_events::EventBus;
use ts_model::{Server, ServerId, SessionId};
use ts_protocol::Backend;

use crate::Session;

/// Owns every live session.
///
/// This is the object the FFI layer keeps behind a handle. Dart receives a
/// [`SessionId`] and nothing else, so no Rust object graph is exposed and no
/// lifetime is shared across the boundary (§47).
///
/// ```text
/// SessionManager
/// ├── Session 1 ── TS3 server
/// ├── Session 2 ── TS6 server
/// └── Session 3 ── TS6 server
/// ```
pub struct SessionManager {
    sessions: HashMap<SessionId, Session>,
    events: EventBus,
    next_session_id: u32,
    next_server_id: u64,
}

impl SessionManager {
    /// A manager that publishes into `events`.
    #[must_use]
    pub fn new(events: EventBus) -> Self {
        Self {
            sessions: HashMap::new(),
            events,
            next_session_id: 1,
            next_server_id: 1,
        }
    }

    /// The bus every session publishes to.
    #[must_use]
    pub fn events(&self) -> &EventBus {
        &self.events
    }

    /// Registers a backend as a new session and returns its handle.
    ///
    /// The session starts disconnected; call [`Session::connect`] to bring it up.
    pub fn create(&mut self, server: Server, backend: Backend) -> SessionId {
        let id = self.reserve_id();
        self.insert(id, server, backend);
        id
    }

    /// Reserves a session id without registering anything.
    ///
    /// Backends stamp every event they emit with their session id, so the id
    /// has to exist *before* the backend is built — hence the two-step
    /// [`SessionManager::reserve_id`] then [`SessionManager::insert`]. Use
    /// [`SessionManager::create`] when you do not care.
    pub fn reserve_id(&mut self) -> SessionId {
        let id = SessionId::new(self.next_session_id);
        self.next_session_id = self.next_session_id.wrapping_add(1);
        id
    }

    /// Registers a backend under an id from [`SessionManager::reserve_id`].
    ///
    /// Replaces any session already using the id.
    pub fn insert(&mut self, id: SessionId, server: Server, backend: Backend) {
        tracing::debug!(
            session = %id,
            server = %server.name,
            protocol = %backend.kind(),
            "session registered"
        );

        self.sessions.insert(id, Session::new(id, server, backend));
    }

    /// Reserves an id for a new address-book entry.
    ///
    /// Server ids are local, so the manager hands them out to keep them unique
    /// within the process.
    pub fn allocate_server_id(&mut self) -> ServerId {
        let id = ServerId::new(self.next_server_id);
        self.next_server_id = self.next_server_id.wrapping_add(1);
        id
    }

    /// Looks up a session.
    #[must_use]
    pub fn get(&self, id: SessionId) -> Option<&Session> {
        self.sessions.get(&id)
    }

    /// Looks up a session for modification.
    pub fn get_mut(&mut self, id: SessionId) -> Option<&mut Session> {
        self.sessions.get_mut(&id)
    }

    /// Whether a session with this handle exists.
    #[must_use]
    pub fn contains(&self, id: SessionId) -> bool {
        self.sessions.contains_key(&id)
    }

    /// Removes a session, returning it so the caller can disconnect it first.
    ///
    /// Dropping the returned session tears the connection down, so callers that
    /// care about a clean shutdown should disconnect before dropping.
    pub fn remove(&mut self, id: SessionId) -> Option<Session> {
        tracing::debug!(session = %id, "session removed");
        self.sessions.remove(&id)
    }

    /// Every session, in unspecified order.
    pub fn iter(&self) -> impl Iterator<Item = &Session> {
        self.sessions.values()
    }

    /// Every session handle, in unspecified order.
    pub fn ids(&self) -> Vec<SessionId> {
        self.sessions.keys().copied().collect()
    }

    /// How many sessions are registered.
    #[must_use]
    pub fn len(&self) -> usize {
        self.sessions.len()
    }

    /// Whether no sessions are registered.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.sessions.is_empty()
    }
}

impl std::fmt::Debug for SessionManager {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SessionManager")
            .field("sessions", &self.sessions.len())
            .field("subscribers", &self.events.subscriber_count())
            .finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ts_model::{ConnectionState, ProtocolKind};
    use ts_protocol::testing::{fake_backend, fake_config, fake_server};

    fn manager() -> SessionManager {
        SessionManager::new(EventBus::with_default_capacity())
    }

    #[test]
    fn reserving_then_inserting_registers_under_that_id() {
        // The path the core takes, because a backend needs its session id at
        // construction time to stamp its events.
        let mut manager = manager();
        let reserved = manager.reserve_id();
        assert!(
            !manager.contains(reserved),
            "reserving must not register anything"
        );

        let (backend, _) = fake_backend(ProtocolKind::Ts3, true);
        manager.insert(reserved, fake_server(1, ProtocolKind::Ts3), backend);

        assert!(manager.contains(reserved));
        assert_eq!(manager.get(reserved).unwrap().id(), reserved);
    }

    #[test]
    fn hands_out_distinct_session_ids() {
        let mut manager = manager();
        let a = manager.create(
            fake_server(1, ProtocolKind::Ts3),
            fake_backend(ProtocolKind::Ts3, true).0,
        );
        let b = manager.create(
            fake_server(2, ProtocolKind::Ts6),
            fake_backend(ProtocolKind::Ts6, true).0,
        );

        assert_ne!(a, b);
        assert_eq!(manager.len(), 2);
        assert!(manager.contains(a));
        assert!(manager.contains(b));
    }

    #[test]
    fn server_ids_are_unique_and_start_at_one() {
        let mut manager = manager();
        assert_eq!(manager.allocate_server_id(), ServerId::new(1));
        assert_eq!(manager.allocate_server_id(), ServerId::new(2));
    }

    #[test]
    fn removing_a_session_frees_its_handle() {
        let mut manager = manager();
        let (backend, _) = fake_backend(ProtocolKind::Ts3, true);
        let id = manager.create(fake_server(1, ProtocolKind::Ts3), backend);

        assert!(manager.remove(id).is_some());
        assert!(!manager.contains(id));
        assert!(manager.get(id).is_none());
        assert!(
            manager.remove(id).is_none(),
            "removing twice should be harmless"
        );
        assert!(manager.is_empty());
    }

    #[tokio::test]
    async fn sessions_are_independent() {
        // §16: several servers at once, each with its own state.
        let mut manager = manager();

        let (ts3_backend, ts3_handle) = fake_backend(ProtocolKind::Ts3, true);
        let (ts6_backend, ts6_handle) = fake_backend(ProtocolKind::Ts6, true);
        let ts3 = manager.create(fake_server(1, ProtocolKind::Ts3), ts3_backend);
        let ts6 = manager.create(fake_server(2, ProtocolKind::Ts6), ts6_backend);

        manager
            .get_mut(ts3)
            .unwrap()
            .connect(fake_config("a.example.com"))
            .await
            .unwrap();

        assert_eq!(
            manager.get(ts3).unwrap().state(),
            ConnectionState::Connected
        );
        assert_eq!(
            manager.get(ts6).unwrap().state(),
            ConnectionState::Disconnected,
            "connecting one session must not affect another"
        );
        assert!(ts3_handle.called("Connection.connect"));
        assert!(!ts6_handle.called("Connection.connect"));
    }

    #[tokio::test]
    async fn session_routes_calls_to_its_own_backend() {
        let mut manager = manager();
        let (backend, handle) = fake_backend(ProtocolKind::Ts3, true);
        let id = manager.create(fake_server(1, ProtocolKind::Ts3), backend);

        let session = manager.get_mut(id).unwrap();
        session
            .join_channel(ts_model::ChannelId::new(5))
            .await
            .unwrap();
        session
            .send_text(ts_model::MessageTarget::Server, "hello")
            .await
            .unwrap();

        assert!(handle.called("ChannelOperations.join_channel"));
        assert!(handle.called("Messaging.send_text"));
    }

    #[test]
    fn protocol_is_read_from_the_backend() {
        // Detection may correct the saved protocol, so the backend wins (§34).
        let mut manager = manager();
        let (backend, _) = fake_backend(ProtocolKind::Ts6, true);
        let mut server = fake_server(1, ProtocolKind::Ts3);
        server.protocol = ProtocolKind::Ts3;

        let id = manager.create(server, backend);
        assert_eq!(manager.get(id).unwrap().protocol(), ProtocolKind::Ts6);
    }

    #[test]
    fn iterate_and_collect_ids_agree() {
        let mut manager = manager();
        for i in 1..=3 {
            let (backend, _) = fake_backend(ProtocolKind::Ts3, true);
            manager.create(fake_server(i, ProtocolKind::Ts3), backend);
        }

        assert_eq!(manager.iter().count(), 3);
        assert_eq!(manager.ids().len(), 3);
    }
}
