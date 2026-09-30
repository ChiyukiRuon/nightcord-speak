use serde::{Deserialize, Serialize};

use crate::{ChannelId, ClientId};

/// One node of the channel tree.
///
/// The tree is *not* materialised here. Each channel names its parent and the
/// UI assembles the hierarchy, which keeps ordering and nesting rules out of
/// the core and lets a front-end render a flat list if it prefers.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Channel {
    /// Server-assigned id.
    pub id: ChannelId,
    /// Display name.
    pub name: String,
    /// `None` for a root channel.
    pub parent_id: Option<ChannelId>,
    /// Sort key among siblings. TS3 uses a sparse integer ordering, so gaps are
    /// normal and this must not be treated as an index.
    pub order: i64,
    /// Clients currently in this channel.
    pub clients: Vec<ClientId>,
    /// Channel description, if the server sent one.
    pub description: Option<String>,
    /// Channel topic, if set.
    pub topic: Option<String>,
    /// Whether a password is required to enter.
    pub has_password: bool,
    /// Whether this is the server's default channel.
    pub is_default: bool,
    /// Whether the channel survives a server restart.
    pub is_permanent: bool,
    /// Client limit, or `None` when unlimited.
    pub max_clients: Option<u32>,
}

impl Channel {
    /// A channel with everything but the essentials left at its default.
    #[must_use]
    pub fn new(id: ChannelId, name: impl Into<String>, parent_id: Option<ChannelId>) -> Self {
        Self {
            id,
            name: name.into(),
            parent_id,
            order: 0,
            clients: Vec::new(),
            description: None,
            topic: None,
            has_password: false,
            is_default: false,
            is_permanent: false,
            max_clients: None,
        }
    }

    /// Whether `candidate` is this channel or one of its descendants.
    ///
    /// Walks the parent chain, so it is `O(depth)`. Used to reject moves that
    /// would create a cycle.
    #[must_use]
    pub fn is_ancestor_of(&self, candidate: ChannelId, all: &[Self]) -> bool {
        let mut cursor = Some(candidate);
        while let Some(id) = cursor {
            if id == self.id {
                return true;
            }
            // `all` is small (one entry per channel) and this runs on user
            // actions, not in a hot loop.
            cursor = all.iter().find(|c| c.id == id).and_then(|c| c.parent_id);
        }
        false
    }
}
