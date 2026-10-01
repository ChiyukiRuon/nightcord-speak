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

    /// Whether the channel-level answers above came from the server.
    ///
    /// TeamSpeak's permission hints are *optional*, and a server that omits them
    /// is not refusing anything — so [`Permissions::can_join_channel`] and
    /// friends read as allowed when nothing arrives. That is the right answer
    /// for gating, where a greyed-out button on a server that simply does not
    /// send hints is worse than one the server will refuse.
    ///
    /// It is the wrong answer for *reporting*: a panel that lists what the user
    /// may do cannot claim a right the server never confirmed. These two flags
    /// are how that difference survives the trip.
    ///
    /// Two of them rather than one because the answers come from two places —
    /// the channel's hints and our own client's — and a server that sends one
    /// without the other would otherwise have its silence reported as consent
    /// for the other group.
    #[serde(default)]
    pub channel_known: bool,

    /// Whether [`Permissions::can_move_clients`] and the three after it came
    /// from the server. See [`Permissions::channel_known`].
    #[serde(default)]
    pub client_known: bool,
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
            channel_known: false,
            client_known: false,
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
            // Granted, not merely defaulted: this is only ever built by a caller
            // that has decided the answers.
            channel_known: true,
            client_known: true,
        }
    }

    /// Whether any destructive moderation right is held.
    #[must_use]
    pub const fn is_moderator(self) -> bool {
        self.can_kick || self.can_ban
    }
}
