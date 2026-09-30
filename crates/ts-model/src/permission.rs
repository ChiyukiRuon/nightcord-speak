use serde::{Deserialize, Serialize};

/// A flattened snapshot of what the connected user may do.
///
/// The UI asks these questions instead of inspecting server groups or raw
/// permission ids, which keeps TS3's and TS6's very different permission models
/// behind one struct (§38).
///
/// This is a *snapshot*: the server can change any of it at any time, so the
/// backend re-emits it whenever it learns of a change.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Permissions {
    /// May enter channels that are not the current one.
    pub can_join_channel: bool,
    /// May move other clients between channels.
    pub can_move_clients: bool,
    /// May post in the current channel.
    pub can_send_channel_message: bool,
    /// May send direct messages.
    pub can_send_private_message: bool,
    /// May disconnect other clients.
    pub can_kick: bool,
    /// May ban clients.
    pub can_ban: bool,
}

impl Permissions {
    /// The conservative default assumed before the server has told us
    /// otherwise. Denying everything by default means a slow permission lookup
    /// hides a button rather than offering an action that will fail.
    #[must_use]
    pub const fn none() -> Self {
        Self {
            can_join_channel: false,
            can_move_clients: false,
            can_send_channel_message: false,
            can_send_private_message: false,
            can_kick: false,
            can_ban: false,
        }
    }

    /// Everything granted. Useful for tests and for permission-free protocols.
    #[must_use]
    pub const fn all() -> Self {
        Self {
            can_join_channel: true,
            can_move_clients: true,
            can_send_channel_message: true,
            can_send_private_message: true,
            can_kick: true,
            can_ban: true,
        }
    }

    /// Whether any destructive moderation right is held.
    #[must_use]
    pub const fn is_moderator(self) -> bool {
        self.can_kick || self.can_ban
    }
}
