//! The commands a front-end may ask the core to perform.
//!
//! Each host turns its own transport into one of these: the C entry points
//! build them by hand from per-argument JSON, the gateway deserialises them
//! from its envelope. The worker — whichever host's — owns the `ts_core::Client`
//! and performs them, so the core's `&mut self` and `async` shapes never reach
//! either boundary.

use serde::{Deserialize, Serialize};
use ts_core::ConnectRequest;
use ts_model::{BanDuration, ChannelId, ClientId, KickScope, MessageTarget, SessionId};
use ts_settings::{BookmarkList, NewBookmark, Settings};

/// Which way audio flows, as the wire spells it.
///
/// Lives here rather than in a host so both spellings — the ABI's bare string
/// and the gateway's JSON — come from one type. `ts-audio`'s own `Direction`
/// stays the audio layer's business; the hosts map at the call site.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AudioDirection {
    /// A microphone.
    Input,
    /// Speakers or headphones.
    Output,
}

impl AudioDirection {
    /// Parses the string the C ABI accepts.
    ///
    /// Returns `None` for anything else, which the entry point turns into a
    /// failed `CommandResult` rather than guessing.
    #[must_use]
    pub fn parse(text: &str) -> Option<Self> {
        match text {
            "input" => Some(Self::Input),
            "output" => Some(Self::Output),
            _ => None,
        }
    }

    /// The spelling the ABI uses.
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Input => "input",
            Self::Output => "output",
        }
    }
}

/// Work the worker task performs.
///
/// The gateway's envelope is the adjacent-tagged form of this enum:
/// `{"command": "connect", "payload": {…}}`. The derives exist for that;
/// `ts-ffi` builds the variants by hand and never serialises a `Command`.
#[derive(Clone, Serialize, Deserialize)]
#[serde(tag = "command", content = "payload", rename_all = "snake_case")]
pub enum Command {
    SetNickname {
        session: SessionId,
        nickname: String,
    },
    /// Fetch a visible client's picture; the response includes its image revision.
    GetAvatar {
        session: SessionId,
        client_id: ClientId,
    },
    /// Base64-encoded PNG/JPEG, or `None` to remove our server picture.
    SetAvatar {
        session: SessionId,
        image: Option<String>,
        #[serde(default)]
        edit: Option<ts_model::AvatarEdit>,
    },
    /// Screen control; media travels directly between peers.
    Screen {
        session: SessionId,
        command: ts_model::ScreenCommand,
    },
    /// Open a new connection.
    ///
    /// Boxed because a `ConnectRequest` is an order of magnitude larger than
    /// any other variant, and every `Command` would otherwise be sized for it.
    Connect(Box<ConnectRequest>),

    /// Close a connection.
    Disconnect {
        /// Which session to close.
        session: SessionId,
    },

    /// Move ourselves into a channel.
    JoinChannel {
        /// Which session to act on.
        session: SessionId,
        /// Where to go.
        channel_id: ChannelId,
    },

    /// Return to the server's default channel.
    LeaveChannel {
        /// Which session to act on.
        session: SessionId,
    },

    /// Send a chat message.
    SendMessage {
        /// Which session to act on.
        session: SessionId,
        /// Where the message goes.
        target: MessageTarget,
        /// What to say.
        text: String,
    },

    /// Move another client.
    MoveClient {
        /// Which session to act on.
        session: SessionId,
        /// Who to move.
        client_id: ClientId,
        /// Where to move them.
        channel_id: ChannelId,
    },

    /// Poke another client, which typically makes their client beep.
    Poke {
        /// Which session to act on.
        session: SessionId,
        /// Who to poke.
        client_id: ClientId,
        /// What to say with the poke.
        message: String,
    },

    /// Remove another client from a channel or from the server.
    Kick {
        /// Which session to act on.
        session: SessionId,
        /// Who to kick.
        client_id: ClientId,
        /// How far the kick reaches.
        scope: KickScope,
        /// An optional explanation the kicked client is shown.
        message: Option<String>,
    },

    /// Ban another client.
    Ban {
        /// Which session to act on.
        session: SessionId,
        /// Who to ban.
        client_id: ClientId,
        /// How long the ban lasts.
        duration: BanDuration,
        /// An optional reason, recorded on the ban list.
        reason: Option<String>,
    },

    /// Mark ourselves away, or back at the keyboard.
    ///
    /// `away` and `message` are two fields rather than one optional string
    /// because the three states are all real: away with something to say, away
    /// with nothing to say (`away: true`, no message), and here. The collapse
    /// into the protocol's single optional message happens in `ts-session`.
    SetAway {
        /// Which session to act on.
        session: SessionId,
        /// Whether we are away.
        away: bool,
        /// What to say about it, if anything.
        message: Option<String>,
    },

    /// Enumerate the machine's audio devices.
    ///
    /// Renamed to match [`Command::name`]: the request tag and the name
    /// reported in the result are one vocabulary, not two that can drift.
    #[serde(rename = "audio_devices")]
    ListDevices {
        /// Which way to look.
        direction: AudioDirection,
    },

    /// Report the audio engine's state: which devices are open, how loud the
    /// microphone is, and whether either side is still alive.
    VoiceStatus,

    /// Play a short tone, so the user can hear whether the speakers work.
    VoiceTestOutput,

    /// Bind the voice engine to a session and open devices.
    VoiceStart {
        /// Which session the engine feeds.
        session: SessionId,
        /// Input device id, or the system default.
        input: Option<String>,
        /// Output device id, or the system default.
        output: Option<String>,
    },

    /// Close the voice engine and unbind it.
    VoiceStop,

    /// Mute or unmute the microphone.
    VoiceSetInputMuted {
        /// The requested state.
        muted: bool,
    },

    /// Mute or unmute the speakers.
    VoiceSetOutputMuted {
        /// The requested state.
        muted: bool,
    },

    /// Push-to-talk key down or up.
    VoicePushToTalk {
        /// Whether the key is held.
        held: bool,
    },

    /// Scale one client's audio within the mix.
    ///
    /// Local to the client that asked: the server is not told, because nothing
    /// about what anyone else receives changes.
    VoiceSetClientVolume {
        /// Which session to act on.
        session: SessionId,
        /// Whose audio to scale.
        client_id: ClientId,
        /// Playback gain, `0.0..=2.0`.
        volume: f32,
    },

    /// Report the preferences in force.
    ///
    /// Renamed to match [`Command::name`]; see [`Command::ListDevices`].
    #[serde(rename = "settings")]
    SettingsGet,

    /// Replace the preferences, write them down, and apply what can be applied
    /// to a running engine.
    SettingsUpdate(Box<Settings>),

    /// Put one shortcut binding back to the platform's default.
    ///
    /// Not a `SettingsUpdate`: the defaults depend on the platform and live in
    /// the core, so a front-end cannot send them — only ask for one.
    ResetShortcuts { action: ts_settings::ShortcutAction },

    /// Report the saved servers.
    ///
    /// Renamed to match [`Command::name`]; see [`Command::ListDevices`].
    #[serde(rename = "bookmarks")]
    BookmarksGet,

    /// Replace them, and write them down.
    BookmarksUpdate(Box<BookmarkList>),

    /// Save a server from what the connect screen collected.
    ///
    /// Renamed to match [`Command::name`]; see [`Command::ListDevices`].
    #[serde(rename = "bookmark_add")]
    BookmarksAdd(Box<NewBookmark>),

    /// Stop the worker.
    Shutdown,

    /// Panics the worker on purpose, killing the task but not the process.
    ///
    /// A test seam with no production caller: no C entry point constructs it
    /// (the ABI cannot reach it), and the gateway's dispatch refuses it by
    /// name. It lives in the vocabulary rather than behind a feature because
    /// `cfg(test)` is false in dependent crates and a feature would leak
    /// through dev-dependency unification into builds that never asked for it.
    /// Reproducing the "core half-dead" failure is otherwise impossible without
    /// editing code, and it is the failure the crash evidence exists to surface
    /// (`docs/crash.md`).
    TestPanic,
}

impl Command {
    /// The name reported in `CommandResult`.
    ///
    /// Kept stable and independent of the C function name so a front-end can
    /// match on it without knowing the ABI's prefix. Also the serde tag, so
    /// the two spellings of "which command" cannot drift.
    #[must_use]
    pub const fn name(&self) -> &'static str {
        match self {
            Self::GetAvatar { .. } => "get_avatar",
            Self::SetAvatar { .. } => "set_avatar",
            Self::Connect(_) => "connect",
            Self::Screen { .. } => "screen",
            Self::Disconnect { .. } => "disconnect",
            Self::JoinChannel { .. } => "join_channel",
            Self::LeaveChannel { .. } => "leave_channel",
            Self::SendMessage { .. } => "send_message",
            Self::MoveClient { .. } => "move_client",
            Self::Poke { .. } => "poke",
            Self::Kick { .. } => "kick",
            Self::Ban { .. } => "ban",
            Self::SetAway { .. } => "set_away",
            Self::SetNickname { .. } => "set_nickname",
            Self::ListDevices { .. } => "audio_devices",
            Self::VoiceStatus => "voice_status",
            Self::VoiceTestOutput => "voice_test_output",
            Self::VoiceStart { .. } => "voice_start",
            Self::VoiceStop => "voice_stop",
            Self::VoiceSetInputMuted { .. } => "voice_set_input_muted",
            Self::VoiceSetOutputMuted { .. } => "voice_set_output_muted",
            Self::VoicePushToTalk { .. } => "voice_push_to_talk",
            Self::VoiceSetClientVolume { .. } => "voice_set_client_volume",
            Self::SettingsGet => "settings",
            Self::SettingsUpdate(_) => "settings_update",
            Self::ResetShortcuts { .. } => "reset_shortcuts",
            Self::BookmarksGet => "bookmarks",
            Self::BookmarksUpdate(_) => "bookmarks_update",
            Self::BookmarksAdd(_) => "bookmark_add",
            Self::Shutdown => "shutdown",
            Self::TestPanic => "test_panic",
        }
    }

    /// Whether this command ends the worker loop.
    #[must_use]
    pub const fn is_shutdown(&self) -> bool {
        matches!(self, Self::Shutdown)
    }
}

impl std::fmt::Debug for Command {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // Message bodies and credentials are never printed: chat is user
        // content and a `ConnectRequest` carries passwords (§44). This impl
        // has to travel with the enum — leaving it behind would silently
        // restore a leak the day someone logs a command.
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
    fn nickname_command_keeps_its_session_and_name_across_the_wire() {
        let command: Command = serde_json::from_str(
            r#"{"command":"set_nickname","payload":{"session":7,"nickname":"New Name"}}"#,
        )
        .unwrap();
        assert!(
            matches!(&command, Command::SetNickname { session, nickname } if session.get() == 7 && nickname == "New Name")
        );
        assert_eq!(command.name(), "set_nickname");
        assert!(!format!("{command:?}").contains("New Name"));
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

    #[test]
    fn the_web_envelope_round_trips() {
        // The shape the gateway receives and the docs describe. If either the
        // tag or the payload key moves, this is the test that notices.
        let json = serde_json::json!({
            "command": "voice_push_to_talk",
            "payload": { "held": true },
        });
        let command: Command = serde_json::from_value(json).unwrap();
        assert!(matches!(command, Command::VoicePushToTalk { held: true }));
        assert_eq!(command.name(), "voice_push_to_talk");
    }

    #[test]
    fn the_serde_tag_and_the_result_name_agree() {
        // Two spellings of "which command" would be a drift waiting to happen,
        // so pin them equal for a sample of variants.
        for command in [
            connect(),
            Command::Disconnect {
                session: SessionId::new(1),
            },
            Command::SettingsGet,
            Command::VoiceStop,
            Command::Poke {
                session: SessionId::new(1),
                client_id: ClientId::new(2),
                message: "hi".into(),
            },
            Command::Kick {
                session: SessionId::new(1),
                client_id: ClientId::new(2),
                scope: KickScope::Channel,
                message: None,
            },
            Command::Ban {
                session: SessionId::new(1),
                client_id: ClientId::new(2),
                duration: BanDuration::Seconds(600),
                reason: None,
            },
            Command::VoiceSetClientVolume {
                session: SessionId::new(1),
                client_id: ClientId::new(2),
                volume: 0.5,
            },
            Command::SetAway {
                session: SessionId::new(1),
                away: true,
                message: Some("back later".into()),
            },
        ] {
            let json = serde_json::to_value(&command).unwrap();
            assert_eq!(
                json["command"].as_str().unwrap(),
                command.name(),
                "tag and name disagree for {command:?}"
            );
        }
    }

    #[test]
    fn moderation_commands_survive_a_round_trip() {
        // The gateway deserialises these straight off a WebSocket, so the wire
        // shape is a contract with the browser as much as with the desktop.
        for command in [
            Command::Poke {
                session: SessionId::new(3),
                client_id: ClientId::new(11),
                message: "look at this".into(),
            },
            Command::Kick {
                session: SessionId::new(3),
                client_id: ClientId::new(11),
                scope: KickScope::Server,
                message: Some("spamming".into()),
            },
            Command::Ban {
                session: SessionId::new(3),
                client_id: ClientId::new(11),
                duration: BanDuration::Permanent,
                reason: None,
            },
        ] {
            let json = serde_json::to_string(&command).unwrap();
            let back: Command = serde_json::from_str(&json).unwrap();
            assert_eq!(
                serde_json::to_value(&back).unwrap(),
                serde_json::to_value(&command).unwrap(),
                "{json} did not survive the trip"
            );
        }
    }

    #[test]
    fn the_three_presence_states_survive_a_round_trip() {
        // Away-with-a-message, away-with-nothing-to-say, and here are three
        // different things; a front-end that flattened two of them would look
        // correct on the wire and put the wrong status on the server.
        let states = [
            Command::SetAway {
                session: SessionId::new(2),
                away: true,
                message: Some("in a meeting".into()),
            },
            Command::SetAway {
                session: SessionId::new(2),
                away: true,
                message: None,
            },
            Command::SetAway {
                session: SessionId::new(2),
                away: false,
                message: None,
            },
        ];

        let mut seen = Vec::new();
        for command in states {
            let json = serde_json::to_string(&command).unwrap();
            let back: Command = serde_json::from_str(&json).unwrap();
            let value = serde_json::to_value(&back).unwrap();
            assert_eq!(value, serde_json::to_value(&command).unwrap(), "{json}");
            seen.push(value["payload"].to_string());
        }
        seen.dedup();
        assert_eq!(
            seen.len(),
            3,
            "two of the three states look alike: {seen:?}"
        );
    }

    #[test]
    fn a_kick_says_how_far_it_reaches() {
        // The two menu items differ only by this field, so a front-end that
        // wired both to the same value would otherwise look correct.
        let channel = Command::Kick {
            session: SessionId::new(1),
            client_id: ClientId::new(2),
            scope: KickScope::Channel,
            message: None,
        };
        let server = Command::Kick {
            session: SessionId::new(1),
            client_id: ClientId::new(2),
            scope: KickScope::Server,
            message: None,
        };
        assert_ne!(
            serde_json::to_string(&channel).unwrap(),
            serde_json::to_string(&server).unwrap()
        );
    }

    #[test]
    fn audio_direction_spellings_match_the_abi() {
        for direction in [AudioDirection::Input, AudioDirection::Output] {
            assert_eq!(AudioDirection::parse(direction.as_str()), Some(direction));
            let json = serde_json::to_value(direction).unwrap();
            assert_eq!(json.as_str(), Some(direction.as_str()));
        }
        assert_eq!(AudioDirection::parse("microphone"), None);
        assert_eq!(AudioDirection::parse(""), None);
        // The ABI's spelling is case-sensitive; so is the web's.
        assert_eq!(AudioDirection::parse("Input"), None);
    }
}
