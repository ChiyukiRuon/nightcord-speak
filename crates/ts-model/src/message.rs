use serde::{Deserialize, Serialize};

use crate::{ChannelId, ClientId, MessageId};

/// Who a chat message is addressed to.
///
/// One type covers server, channel and direct messages so the UI has a single
/// code path (§24).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(tag = "kind", content = "id", rename_all = "snake_case")]
pub enum MessageTarget {
    /// Visible to everyone on the server.
    Server,
    /// Visible to everyone in one channel.
    Channel(ChannelId),
    /// A direct message to one client.
    Client(ClientId),
}

impl MessageTarget {
    /// Whether this is a private, one-to-one message.
    #[must_use]
    pub const fn is_private(self) -> bool {
        matches!(self, Self::Client(_))
    }
}

/// A chat message, already normalised into the domain model.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Message {
    /// Session-local id, assigned by the core in arrival order.
    pub id: MessageId,
    /// Sender's client id, or `None` for server-generated notices.
    pub sender: Option<ClientId>,
    /// Sender's nickname, captured at delivery time so the UI can render a
    /// message from a client that has since disconnected.
    pub sender_name: String,
    /// Where it was sent.
    pub target: MessageTarget,
    /// Message body.
    pub content: String,
    /// Arrival time, Unix milliseconds.
    pub timestamp: i64,
}
