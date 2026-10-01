//! The facade a front-end drives.

use ts_events::{EventBus, SessionEvent};
use ts_identity::IdentityStore;
use ts_model::{ClientError, ConnectionState, ConnectionTarget, ProtocolKind, Server, SessionId};
use ts_protocol::{Backend, ConnectionConfig};
use ts_session::SessionManager;
use ts_settings::{Bookmark, BookmarkList, BookmarkStore, NewBookmark, Settings, SettingsStore};

use crate::request::ConnectRequest;

/// The Rust client core.
///
/// ```text
/// Flutter / CLI / Web gateway
///            │
///            ▼
///        Client  ──▶ SessionManager ──▶ Backend ──▶ server
/// ```
///
/// It owns the session table and the identity store, and it is the only thing
/// that knows how to turn a protocol name into a backend. Everything above it
/// works in terms of [`SessionId`]s.
pub struct Client {
    sessions: SessionManager,
    identities: IdentityStore,
    /// Where preferences are written when they change.
    settings_store: SettingsStore,
    /// The preferences in force, so a connect does not re-read the file.
    settings: Settings,
    /// Where the address book is written when it changes.
    bookmarks_store: BookmarkStore,
    /// The saved servers in force. See [`Client::bookmarks`].
    bookmarks: BookmarkList,
}

impl Client {
    /// A client that persists identities under `identities`, preferences under
    /// `settings` and saved servers under `bookmarks`.
    #[must_use]
    pub fn new(
        identities: IdentityStore,
        settings_store: SettingsStore,
        bookmarks_store: BookmarkStore,
    ) -> Self {
        // Unreadable files are not a reason to refuse to start. The defaults —
        // and an empty address book — are perfectly usable and the user's next
        // change overwrites whatever is wrong; the file is left alone so it can
        // be looked at. The identity store makes the opposite choice, and
        // `docs/settings.md` says why.
        let settings = settings_store.load().unwrap_or_else(|error| {
            tracing::warn!(%error, path = %settings_store.path().display(), "using default settings");
            Settings::default()
        });
        let bookmarks = bookmarks_store.load().unwrap_or_else(|error| {
            tracing::warn!(%error, path = %bookmarks_store.path().display(), "starting with an empty address book");
            BookmarkList::default()
        });

        Self {
            sessions: SessionManager::new(EventBus::with_default_capacity()),
            identities,
            settings_store,
            settings,
            bookmarks_store,
            bookmarks,
        }
    }

    /// A client using this platform's application data directory (§32).
    ///
    /// # Errors
    ///
    /// Returns [`ClientError::Identity`] or [`ClientError::Settings`] where the
    /// platform gives no data directory — Android and iOS, which must supply
    /// their sandbox path via [`Client::new`] instead.
    pub fn with_platform_store() -> Result<Self, ClientError> {
        let identities = IdentityStore::platform_default().map_err(ClientError::Identity)?;
        let settings = SettingsStore::platform_default().map_err(ClientError::Settings)?;
        let bookmarks = BookmarkStore::platform_default().map_err(ClientError::Settings)?;
        Ok(Self::new(identities, settings, bookmarks))
    }

    /// The preferences in force.
    #[must_use]
    pub fn settings(&self) -> &Settings {
        &self.settings
    }

    /// Replaces the preferences and writes them down.
    ///
    /// Saved before it is adopted, so a write that fails leaves the client
    /// running on the values it actually persisted rather than on ones it only
    /// believes it did.
    ///
    /// # Errors
    ///
    /// Returns [`ClientError::Settings`] if the file cannot be written.
    pub fn update_settings(&mut self, settings: Settings) -> Result<(), ClientError> {
        self.settings_store
            .save(&settings)
            .map_err(ClientError::Settings)?;
        self.settings = settings;
        Ok(())
    }

    /// The saved servers (§40).
    #[must_use]
    pub fn bookmarks(&self) -> &BookmarkList {
        &self.bookmarks
    }

    /// Replaces the address book and writes it down.
    ///
    /// Saved before it is adopted, for the same reason as
    /// [`Client::update_settings`]: a failed write must not leave the client
    /// believing in an address book that is not on disk.
    ///
    /// # Errors
    ///
    /// Returns [`ClientError::Settings`] if the file cannot be written.
    pub fn update_bookmarks(&mut self, bookmarks: BookmarkList) -> Result<(), ClientError> {
        self.bookmarks_store
            .save(&bookmarks)
            .map_err(ClientError::Settings)?;
        self.bookmarks = bookmarks;
        Ok(())
    }

    /// Adds a saved server, or replaces the one at the same address.
    ///
    /// The address is parsed here rather than by the caller, so every front-end
    /// gets the same normalisation and the same error.
    ///
    /// Returns the list as it now stands, so a caller does not have to ask
    /// again — and cannot show a list that does not include what it just saved.
    ///
    /// # Errors
    ///
    /// Returns [`ClientError::InvalidAddress`] if the address cannot be parsed,
    /// or [`ClientError::Settings`] if the file cannot be written.
    pub fn add_bookmark(&mut self, new: NewBookmark) -> Result<BookmarkList, ClientError> {
        // The address being replaced goes through the same parser, so an edit
        // finds the old row whatever spelling it was saved under.
        let replaces = match new.replaces.as_deref() {
            Some(address) => {
                Some(ConnectionTarget::parse(address).map_err(ClientError::InvalidAddress)?)
            }
            None => None,
        };
        let bookmark = Bookmark::from_new(new).map_err(ClientError::InvalidAddress)?;

        let mut next = self.bookmarks.clone();
        if let Some(old) = replaces
            && (old.host != bookmark.host || old.port != bookmark.port)
        {
            // Only when it really is a different entry. Keeping the address is
            // an ordinary save, and `upsert` already covers that — and this must
            // not run for it, or the entry would be removed and re-added at the
            // end of the list.
            next.bookmarks
                .retain(|saved| saved.host != old.host || saved.port != old.port);
        }
        next.upsert(bookmark);
        self.update_bookmarks(next)?;

        Ok(self.bookmarks.clone())
    }

    /// The bus every session publishes to.
    #[must_use]
    pub fn events(&self) -> &EventBus {
        self.sessions.events()
    }

    /// Subscribes to every event from now on.
    ///
    /// A UI should subscribe before connecting, so it cannot miss the handshake.
    #[must_use]
    pub fn subscribe(&self) -> tokio::sync::broadcast::Receiver<SessionEvent> {
        self.events().subscribe()
    }

    /// The session table.
    #[must_use]
    pub fn sessions(&self) -> &SessionManager {
        &self.sessions
    }

    /// The session table, for driving a session directly.
    pub fn sessions_mut(&mut self) -> &mut SessionManager {
        &mut self.sessions
    }

    /// The identity store, so a front-end can list or forget profiles.
    #[must_use]
    pub fn identities(&self) -> &IdentityStore {
        &self.identities
    }

    /// Opens a connection and registers it as a session.
    ///
    /// Returns the handle to address it by. On failure nothing is left behind:
    /// the session is removed rather than surviving in a half-connected state.
    ///
    /// # Errors
    ///
    /// - [`ClientError::InvalidAddress`] if the address cannot be parsed.
    /// - [`ClientError::Identity`] if the stored identity is unreadable.
    /// - [`ClientError::Unsupported`] for a protocol with no backend yet.
    /// - Whatever the backend reports for the connection itself.
    pub async fn connect(&mut self, request: &ConnectRequest) -> Result<SessionId, ClientError> {
        let target = ConnectionTarget::parse(&request.address)?;
        let profile = request.profile().to_string();

        let server = Server {
            id: self.sessions.allocate_server_id(),
            // A placeholder: the server names itself during the handshake, and
            // the backend adopts that name.
            name: target.host.clone(),
            address: target.to_string(),
            protocol: request.protocol,
        };

        // The backend stamps its events with the session id, so the id has to
        // exist before the backend does.
        let session_id = self.sessions.reserve_id();

        // Built before the identity is loaded, and before anything is
        // registered: asking for a protocol with no backend must not mint an
        // identity or write to disk on its way to failing.
        let backend = make_backend(
            request.protocol,
            self.events().clone(),
            session_id,
            server.clone(),
            Some((self.identities.clone(), profile.clone())),
        )?;

        // A failure here leaves nothing behind, because nothing is registered
        // until the line below.
        let identity = self
            .identities
            .load_or_create(&profile, ts_protocol_ts3::generate_identity)
            .map_err(ClientError::Identity)?;

        let config = ConnectionConfig {
            target,
            nickname: request.nickname.clone(),
            identity,
            server_password: request.server_password.clone(),
            channel_password: request.channel_password.clone(),
            privilege_key: request.privilege_key.clone(),
            default_channel: request.default_channel.clone(),
            dialect: request.dialect,
            // Not on `ConnectRequest`: how hard to retry is a preference, not a
            // decision made once per connection, and the front-end has no
            // business restating it on every connect.
            reconnect: self.settings.connection.reconnect_policy(),
        };

        self.sessions.insert(session_id, server, backend);

        let session = self
            .sessions
            .get_mut(session_id)
            .expect("the session was inserted immediately above");

        if let Err(error) = session.connect(config).await {
            // Leave nothing behind for the UI to clean up.
            self.sessions.remove(session_id);
            return Err(error);
        }

        tracing::info!(session = %session_id, endpoint = %request.address, "connected");
        Ok(session_id)
    }

    /// Closes a session and forgets it.
    ///
    /// # Errors
    ///
    /// Propagates whatever the backend reports while shutting down. The session
    /// is removed either way — a failed shutdown still ends the session.
    pub async fn disconnect(&mut self, session: SessionId) -> Result<(), ClientError> {
        let Some(mut session) = self.sessions.remove(session) else {
            // Disconnecting something that is not there is a no-op, not a bug:
            // a UI may race a server-side drop.
            return Ok(());
        };
        session.disconnect().await
    }

    /// Closes every session.
    ///
    /// Returns the first error, after attempting all of them: one server
    /// refusing to close must not strand the others.
    pub async fn disconnect_all(&mut self) -> Result<(), ClientError> {
        let ids = self.sessions.ids();
        let mut first_error = None;

        for id in ids {
            if let Err(error) = self.disconnect(id).await {
                first_error.get_or_insert(error);
            }
        }

        match first_error {
            Some(error) => Err(error),
            None => Ok(()),
        }
    }

    /// The connection state of one session.
    #[must_use]
    pub fn state(&self, session: SessionId) -> Option<ConnectionState> {
        self.sessions.get(session).map(ts_session::Session::state)
    }
}

impl std::fmt::Debug for Client {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Client")
            .field("sessions", &self.sessions)
            .field("identity_root", &self.identities.root())
            .finish()
    }
}

/// Picks the backend for a protocol.
///
/// The one place that maps a [`ProtocolKind`] onto a concrete implementation.
/// Adding TS6 means adding a variant here and nothing else.
fn make_backend(
    protocol: ProtocolKind,
    events: EventBus,
    session: SessionId,
    server: Server,
    identity: Option<(IdentityStore, String)>,
) -> Result<Backend, ClientError> {
    match protocol {
        ProtocolKind::Ts3 => Ok(ts_protocol_ts3::backend(events, session, server, identity)),
        // Not a stub any more: TS6 shares the base protocol with TS3, so a
        // TS6 session is a real connection today — channel tree, chat and
        // voice all work against a `6.0.0-beta13.1` server. What it does not
        // have yet is the `stream` family, which is why it reports itself
        // through its own crate rather than being folded into TS3's.
        ProtocolKind::Ts6 => Ok(ts_protocol_ts6::backend(events, session, server, identity)),
    }
}
