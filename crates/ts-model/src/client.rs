use serde::{Deserialize, Serialize};

use crate::{ChannelId, ClientId};

/// Everything that can be true about a user at once.
///
/// The design doc is explicit that a single status enum is the wrong model:
/// a client can be away *and* muted *and* recording simultaneously (§8). These
/// are the raw flags; anything derived belongs in the UI.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ClientFlags {
    /// Marked themselves away.
    pub away: bool,
    /// Their microphone is disabled — they cannot be heard.
    pub input_muted: bool,
    /// Their speakers are disabled — they cannot hear anyone.
    pub output_muted: bool,
    /// Currently recording locally.
    pub recording: bool,
    /// Has channel-commander rights in its channel.
    pub channel_commander: bool,
}

impl ClientFlags {
    /// Flags with everything off.
    #[must_use]
    pub const fn none() -> Self {
        Self {
            away: false,
            input_muted: false,
            output_muted: false,
            recording: false,
            channel_commander: false,
        }
    }

    /// Whether the client is fully muted — neither heard nor hearing.
    #[must_use]
    pub const fn is_deafened(self) -> bool {
        self.input_muted && self.output_muted
    }
}

/// Whether a connection belongs to a human or to server-side automation.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ClientType {
    /// A normal client, usually a person.
    Voice,
    /// A server-query connection.
    Query,
}

/// A user connected to the server.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Client {
    /// Server-assigned id, valid only for this connection.
    pub id: ClientId,
    /// Nickname shown on the server.
    pub name: String,
    /// Channel the client currently occupies.
    pub channel_id: ChannelId,
    /// Simultaneous status flags.
    pub flags: ClientFlags,
    /// What they said when they went away.
    ///
    /// `None` when they are not away, and also when they are away with nothing
    /// to say: an empty message is not worth rendering. Those two are not the
    /// same state, and telling them apart is [`ClientFlags::away`]'s job —
    /// this field only ever carries something worth reading.
    pub away_message: Option<String>,
    /// Stable per-user id. Survives reconnects and nick changes, unlike
    /// [`Client::id`]. Absent for server-query connections.
    pub unique_id: Option<String>,
    /// Voice or query.
    pub client_type: ClientType,
    /// Whether this client is us. Saves every front-end re-deriving it.
    pub is_self: bool,
}

impl Client {
    /// A minimal voice client in the given channel.
    #[must_use]
    pub fn new(id: ClientId, name: impl Into<String>, channel_id: ChannelId) -> Self {
        Self {
            id,
            name: name.into(),
            channel_id,
            flags: ClientFlags::none(),
            away_message: None,
            unique_id: None,
            client_type: ClientType::Voice,
            is_self: false,
        }
    }

    /// Whether the client can currently be heard.
    ///
    /// This is a *capability* check, not a live speaking indicator — use the
    /// speaking events for that.
    #[must_use]
    pub const fn is_audible(&self) -> bool {
        !self.flags.input_muted
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deafened_requires_both_mutes() {
        let mut flags = ClientFlags::none();
        flags.input_muted = true;
        assert!(!flags.is_deafened());
        flags.output_muted = true;
        assert!(flags.is_deafened());
    }
}
