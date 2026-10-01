//! # ts-model
//!
//! The domain model that every Nightcord Speak front-end speaks in terms of.
//!
//! This crate is the contract between the protocol backends and the UI. It
//! knows nothing about TS3, TS6, TCP, UDP or Opus, and it depends on nothing
//! but `serde` — so it can be compiled for any target, including the Web
//! gateway's future host and the Flutter bindings.
//!
//! The layering rule it exists to enforce (DEVELOPMENT.md §53, §80):
//!
//! ```text
//! TS3 backend ─┐
//!              ├─→ ts-model ─→ Flutter / Web
//! TS6 backend ─┘
//! ```
//!
//! A backend converts its wire format into these types on the way out. Nothing
//! protocol-shaped is allowed to reach a front-end, and no front-end concept is
//! allowed to leak down into a backend.

mod capability;
mod channel;
mod client;
mod connection;
mod error;
mod id;
mod message;
mod moderation;
mod permission;
mod protocol;
mod server;
mod target;
mod voice;

pub use capability::Capabilities;
pub use channel::Channel;
pub use client::{Client, ClientFlags, ClientType};
pub use connection::{ConnectionState, ReconnectPolicy};
pub use error::{
    AddressError, AudioError, AuthError, ClientError, IdentityError, NetworkError, PermissionError,
    ProtocolError, SettingsError, VoiceError,
};
pub use id::{ChannelId, ClientId, MessageId, ServerId, SessionId};
pub use message::{Message, MessageTarget};
pub use moderation::{BanDuration, KickScope};
pub use permission::Permissions;
pub use protocol::ProtocolKind;
pub use server::{Server, ServerInfo};
pub use target::{ConnectionTarget, DEFAULT_PORT};
pub use voice::{Speaking, VoiceActivationMode, VoiceActivationSettings, VoiceState};

/// Everything a front-end needs to render one server's state after a change.
///
/// Backends mutate this in place and emit it wholesale, so a front-end never
/// has to replay a delta stream to reconstruct the current view.
// No `Default`: a state without a server to describe is meaningless, and
// synthesising one would let a bug present as "connected to nowhere".
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct ServerState {
    /// Which server this describes.
    pub server: Server,
    /// Server-reported metadata.
    pub info: ServerInfo,
    /// Every channel, flat. The UI nests them by `parent_id`.
    pub channels: Vec<Channel>,
    /// Every connected client.
    pub clients: Vec<Client>,
    /// The id of our own client on this server, once known.
    pub own_client_id: Option<ClientId>,
    /// The channel we are currently in.
    pub own_channel_id: Option<ChannelId>,
    /// What this server lets us do.
    pub permissions: Permissions,
    /// What this server can do at all.
    pub capabilities: Capabilities,
}

impl ServerState {
    /// Looks up a channel by id.
    #[must_use]
    pub fn channel(&self, id: ChannelId) -> Option<&Channel> {
        self.channels.iter().find(|c| c.id == id)
    }

    /// Looks up a client by id.
    #[must_use]
    pub fn client(&self, id: ClientId) -> Option<&Client> {
        self.clients.iter().find(|c| c.id == id)
    }

    /// Every client in `channel_id`.
    pub fn clients_in(&self, channel_id: ChannelId) -> impl Iterator<Item = &Client> {
        self.clients
            .iter()
            .filter(move |c| c.channel_id == channel_id)
    }

    /// Our own client record, if the server has identified us yet.
    #[must_use]
    pub fn own_client(&self) -> Option<&Client> {
        self.own_client_id.and_then(|id| self.client(id))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_state() -> ServerState {
        let server = Server {
            id: ServerId::new(1),
            name: "Test".into(),
            address: "example.com:9987".into(),
            protocol: ProtocolKind::Ts3,
        };
        let lobby = ChannelId::new(1);
        let gaming = ChannelId::new(2);

        let mut alice = Client::new(ClientId::new(10), "Alice", lobby);
        let bob = Client::new(ClientId::new(11), "Bob", gaming);
        alice.is_self = true;

        ServerState {
            server,
            info: ServerInfo::default(),
            channels: vec![
                Channel::new(lobby, "Lobby", None),
                Channel::new(gaming, "Gaming", Some(lobby)),
            ],
            clients: vec![alice, bob],
            own_client_id: Some(ClientId::new(10)),
            own_channel_id: Some(lobby),
            permissions: Permissions::all(),
            capabilities: Capabilities::TS3,
        }
    }

    #[test]
    fn lookups_find_what_was_inserted() {
        let state = sample_state();
        assert_eq!(state.channel(ChannelId::new(1)).unwrap().name, "Lobby");
        assert_eq!(state.client(ClientId::new(11)).unwrap().name, "Bob");
        assert!(state.channel(ChannelId::new(99)).is_none());
        assert!(state.client(ClientId::new(99)).is_none());
    }

    #[test]
    fn clients_in_filters_by_channel() {
        let state = sample_state();
        let names: Vec<&str> = state
            .clients_in(ChannelId::new(1))
            .map(|c| c.name.as_str())
            .collect();
        assert_eq!(names, vec!["Alice"]);
    }

    #[test]
    fn own_client_resolves_through_the_id() {
        let state = sample_state();
        assert_eq!(state.own_client().unwrap().name, "Alice");
    }

    #[test]
    fn parent_chain_detects_descendants() {
        let state = sample_state();
        let lobby = state.channel(ChannelId::new(1)).unwrap();
        // Lobby is its own ancestor, and an ancestor of Gaming.
        assert!(lobby.is_ancestor_of(ChannelId::new(1), &state.channels));
        assert!(lobby.is_ancestor_of(ChannelId::new(2), &state.channels));

        let gaming = state.channel(ChannelId::new(2)).unwrap();
        assert!(!gaming.is_ancestor_of(ChannelId::new(1), &state.channels));
    }
}
