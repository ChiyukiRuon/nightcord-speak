use serde::{Deserialize, Serialize};

use crate::{ProtocolKind, ServerId};

/// A server as the UI knows it: where to connect, and what to call it.
///
/// This is the shape of an address-book entry. It carries no credentials and no
/// identity — a bookmark is not an account.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Server {
    /// Local id, assigned when the entry is created.
    pub id: ServerId,
    /// Display name; falls back to the address when the user gave none.
    pub name: String,
    /// `host` or `host:port`. Parsed into a [`crate::ConnectionTarget`] before use.
    pub address: String,
    /// Which backend should be used. May be corrected by [`crate::Dialect::Auto`]
    /// detection during the handshake.
    pub protocol: ProtocolKind,
}

/// What the server says about itself once the handshake completes.
///
/// Every field is optional-by-nature: TS3 and TS6 disagree on which of these
/// they report, and a server is free to omit them.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ServerInfo {
    /// Server name as configured by its owner.
    pub name: String,
    /// Shown to clients on connect.
    pub welcome_message: Option<String>,
    /// Free-text platform string, e.g. `Windows`.
    pub platform: Option<String>,
    /// Server build version, e.g. `3.13.7`.
    pub version: Option<String>,
    /// Configured client slots.
    pub max_clients: u32,
    /// Clients connected right now.
    pub clients_online: u32,
    /// Channels that currently exist.
    pub channels_online: u32,
    /// Seconds since the server process started.
    pub uptime: Option<u64>,
}
