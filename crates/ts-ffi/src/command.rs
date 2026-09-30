//! The commands the worker task performs.
//!
//! Every C entry point turns into one of these and returns immediately. The
//! worker owns the `ts_core::Client`, so the `&mut self` and `async` shapes of
//! the core never reach the ABI — see `client.rs` for why that matters.

use ts_core::ConnectRequest;
use ts_model::{ChannelId, ClientId, MessageTarget, SessionId};
use ts_settings::{BookmarkList, NewBookmark, Settings};

use crate::audio::AudioDirection;

/// Work the worker task performs.
pub(crate) enum Command {
    /// Open a new connection.
    ///
    /// Boxed because a `ConnectRequest` is an order of magnitude larger than
    /// any other variant, and every `Command` would otherwise be sized for it.
    Connect(Box<ConnectRequest>),

    /// Close a connection.
    Disconnect { session: SessionId },

    /// Move ourselves into a channel.
    JoinChannel {
        session: SessionId,
        channel_id: ChannelId,
    },

    /// Return to the server's default channel.
    LeaveChannel { session: SessionId },

    /// Send a chat message.
    SendMessage {
        session: SessionId,
        target: MessageTarget,
        text: String,
    },

    /// Move another client.
    MoveClient {
        session: SessionId,
        client_id: ClientId,
        channel_id: ChannelId,
    },

    /// Enumerate the machine's audio devices.
    ListDevices { direction: AudioDirection },

    /// Report the audio engine's state: which devices are open, how loud the
    /// microphone is, and whether either side is still alive.
    VoiceStatus,

    /// Play a short tone, so the user can hear whether the speakers work.
    VoiceTestOutput,

    /// Bind the voice engine to a session and open devices.
    VoiceStart {
        session: SessionId,
        input: Option<String>,
        output: Option<String>,
    },

    /// Close the voice engine and unbind it.
    VoiceStop,

    /// Mute or unmute the microphone.
    VoiceSetInputMuted { muted: bool },

    /// Mute or unmute the speakers.
    VoiceSetOutputMuted { muted: bool },

    /// Push-to-talk key down or up.
    VoicePushToTalk { held: bool },

    /// Report the preferences in force.
    SettingsGet,

    /// Replace the preferences, write them down, and apply what can be applied
    /// to a running engine.
    SettingsUpdate(Box<Settings>),

    /// Report the saved servers.
    BookmarksGet,

    /// Replace them, and write them down.
    BookmarksUpdate(Box<BookmarkList>),

    /// Save a server from what the connect screen collected.
    BookmarksAdd(Box<NewBookmark>),

    /// Stop the worker.
    Shutdown,
}

impl Command {
    /// The name reported in `CommandResult`.
    ///
    /// Kept stable and independent of the C function name so the Dart side can
    /// match on it without knowing the ABI's prefix.
    pub(crate) const fn name(&self) -> &'static str {
        match self {
            Self::Connect(_) => "connect",
            Self::Disconnect { .. } => "disconnect",
            Self::JoinChannel { .. } => "join_channel",
            Self::LeaveChannel { .. } => "leave_channel",
            Self::SendMessage { .. } => "send_message",
            Self::MoveClient { .. } => "move_client",
            Self::ListDevices { .. } => "audio_devices",
            Self::VoiceStatus => "voice_status",
            Self::VoiceTestOutput => "voice_test_output",
            Self::VoiceStart { .. } => "voice_start",
            Self::VoiceStop => "voice_stop",
            Self::VoiceSetInputMuted { .. } => "voice_set_input_muted",
            Self::VoiceSetOutputMuted { .. } => "voice_set_output_muted",
            Self::VoicePushToTalk { .. } => "voice_push_to_talk",
            Self::SettingsGet => "settings",
            Self::SettingsUpdate(_) => "settings_update",
            Self::BookmarksGet => "bookmarks",
            Self::BookmarksUpdate(_) => "bookmarks_update",
            Self::BookmarksAdd(_) => "bookmark_add",
            Self::Shutdown => "shutdown",
        }
    }

    /// Whether this command ends the worker loop.
    #[must_use]
    pub(crate) const fn is_shutdown(&self) -> bool {
        matches!(self, Self::Shutdown)
    }
}

impl std::fmt::Debug for Command {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // Message bodies and credentials are never printed: chat is user
        // content and a `ConnectRequest` carries passwords (§44).
        match self {
            Self::Connect(request) => f
                .debug_struct("Connect")
                .field("address", &request.address)
                .field("nickname", &request.nickname)
                .finish_non_exhaustive(),
            Self::SendMessage {
                session, target, ..
            } => f
                .debug_struct("SendMessage")
                .field("session", session)
                .field("target", target)
                .finish_non_exhaustive(),
            other => f.debug_struct(other.name()).finish(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn connect() -> Command {
        Command::Connect(Box::new(ConnectRequest::new("example.com", "Tester")))
    }

    #[test]
    fn names_are_stable_and_unique_per_subject() {
        assert_eq!(connect().name(), "connect");
        assert_eq!(Command::Shutdown.name(), "shutdown");
        assert_eq!(
            Command::VoicePushToTalk { held: true }.name(),
            "voice_push_to_talk"
        );
    }

    #[test]
    fn only_shutdown_ends_the_worker() {
        assert!(Command::Shutdown.is_shutdown());
        assert!(!connect().is_shutdown());
    }

    #[test]
    fn debug_never_prints_credentials_or_message_bodies() {
        let mut request = ConnectRequest::new("example.com", "Tester");
        request.server_password = Some("hunter2".into());
        let command = Command::Connect(Box::new(request));

        let rendered = format!("{command:?}");
        assert!(
            !rendered.contains("hunter2"),
            "debug leaked a password: {rendered}"
        );

        let message = Command::SendMessage {
            session: SessionId::new(1),
            target: MessageTarget::Server,
            text: "a private thought".into(),
        };
        let rendered = format!("{message:?}");
        assert!(
            !rendered.contains("private thought"),
            "debug leaked chat: {rendered}"
        );
    }
}
