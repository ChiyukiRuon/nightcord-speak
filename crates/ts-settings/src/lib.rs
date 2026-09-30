//! # ts-settings
//!
//! The user's preferences, persisted.
//!
//! Until this crate existed the application stored exactly one thing — the
//! client identity — and everything a user could choose lived in a front-end's
//! memory: pick a microphone in the settings dialog and it was forgotten the
//! moment the dialog closed. The audio pipeline had been *built* for a saved
//! device ([`ts_audio`]'s device ids are designed to survive a restart, and
//! resolving a stale one already falls back to the default), and the voice
//! activation gate already had a setter for a sensitivity slider. What was
//! missing was somewhere to keep the values.
//!
//! That somewhere is one JSON file beside the identity and the logs:
//!
//! ```text
//! <application data root>/
//! ├── identity/        ← ts-identity
//! ├── logs/            ← ts-logging
//! └── settings.json    ← this crate
//! ```
//!
//! The file is meant to be readable and hand-editable — every field has a
//! default, so deleting a line is how you reset one thing, and an unknown field
//! is ignored rather than fatal.
//!
//! ## The one place this deliberately differs from the identity store
//!
//! A malformed *identity* is an error that must not be papered over: reading
//! damage as absence would quietly mint a new client and lose the user's
//! permissions. A malformed *settings file* is not that. It is reported as
//! [`SettingsError::Malformed`] and the caller carries on with defaults, because
//! refusing to start over a preference file turns a cosmetic problem into a
//! fatal one.

mod bookmarks;
mod store;

pub use bookmarks::{Bookmark, BookmarkList, BookmarkStore, NewBookmark};

use std::path::PathBuf;

use serde::{Deserialize, Serialize};
use ts_identity::app_data_root;
use ts_model::{ReconnectPolicy, SettingsError, VoiceActivationMode, VoiceActivationSettings};

/// The file's name inside the application data root.
pub const FILE_NAME: &str = "settings.json";

/// On-disk format version, so the layout can change without guesswork.
const FILE_VERSION: u32 = 1;

/// What the client remembers between runs.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Settings {
    /// Format version. Defaulted rather than required so a hand-written file
    /// does not have to know about it.
    #[serde(default = "current_version")]
    pub version: u32,

    /// Everything about capturing and playing audio.
    #[serde(default)]
    pub audio: AudioSettings,

    /// Everything about reaching a server.
    #[serde(default)]
    pub connection: ConnectionSettings,

    /// What is worth interrupting the user for.
    #[serde(default)]
    pub notifications: NotificationSettings,

    /// Which keys do what (§42).
    #[serde(default)]
    pub shortcuts: ShortcutSettings,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            version: FILE_VERSION,
            audio: AudioSettings::default(),
            connection: ConnectionSettings::default(),
            notifications: NotificationSettings::default(),
            shortcuts: ShortcutSettings::default(),
        }
    }
}

/// The key combinations that raise the three actions §42 names.
///
/// Each is an `Option` so a binding can be *cleared* as well as changed: an
/// explicitly unbound action and one that was never configured are different
/// things, and only the second should fall back to a default. A file written
/// before this section existed has no keys at all, so the serde defaults supply
/// §42's combinations rather than leaving someone with nothing bound.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ShortcutSettings {
    #[serde(default = "default_mute_shortcut")]
    pub mute: Option<Chord>,

    #[serde(default = "default_deafen_shortcut")]
    pub deafen: Option<Chord>,

    #[serde(default = "default_push_to_talk_shortcut")]
    pub push_to_talk: Option<Chord>,
}

impl Default for ShortcutSettings {
    fn default() -> Self {
        Self {
            mute: default_mute_shortcut(),
            deafen: default_deafen_shortcut(),
            push_to_talk: default_push_to_talk_shortcut(),
        }
    }
}

/// One key combination.
///
/// `key` is Flutter's `PhysicalKeyboardKey.usbHidUsage` — the full value
/// including the 0x0007 usage-page prefix, because that is what
/// `PhysicalKeyboardKey.findKeyByCode` takes and the round trip has to be
/// lossless. A *physical* key rather than a letter: on an AZERTY keyboard the
/// key where QWERTY has M is somewhere else entirely, and a shortcut — push to
/// talk above all — is about where the hand goes, not what letter comes out.
///
/// The cost is that this section of `settings.json` is written for a machine
/// rather than for a person. The settings dialog is the editor.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Chord {
    /// `PhysicalKeyboardKey.usbHidUsage`.
    pub key: u32,

    #[serde(default)]
    pub ctrl: bool,

    #[serde(default)]
    pub shift: bool,

    #[serde(default)]
    pub alt: bool,

    #[serde(default)]
    pub meta: bool,
}

fn default_mute_shortcut() -> Option<Chord> {
    Some(Chord {
        // 0x00070010 — the key labelled M on a US layout.
        key: 0x0007_0010,
        ctrl: true,
        shift: true,
        alt: false,
        meta: false,
    })
}

fn default_deafen_shortcut() -> Option<Chord> {
    Some(Chord {
        // 0x00070007 — the key labelled D on a US layout.
        key: 0x0007_0007,
        ctrl: true,
        shift: true,
        alt: false,
        meta: false,
    })
}

fn default_push_to_talk_shortcut() -> Option<Chord> {
    Some(Chord {
        // 0x00070013 — the key labelled P on a US layout.
        key: 0x0007_0013,
        ctrl: true,
        shift: true,
        alt: false,
        meta: false,
    })
}

/// What raises a notification (§43).
///
/// Everything is on by default, which is why [`Default`] is written out rather
/// than derived: a derived one would turn every switch off, and a client that
/// starts silent looks broken rather than quiet.
///
/// The switches are per *kind* of event rather than per event, because that is
/// the granularity a user actually has an opinion about. Nobody wants to be told
/// about every join but not every leave.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct NotificationSettings {
    /// Someone joined or left.
    #[serde(default = "default_true")]
    pub presence: bool,

    /// Someone poked us.
    #[serde(default = "default_true")]
    pub poke: bool,

    /// A message in a channel, or to the whole server.
    #[serde(default = "default_true")]
    pub channel_message: bool,

    /// A private message.
    #[serde(default = "default_true")]
    pub direct_message: bool,

    /// A connection dropped or came back.
    #[serde(default = "default_true")]
    pub connection: bool,

    /// Whether the above should also reach the operating system's notification
    /// centre when the window is not in front.
    ///
    /// Separate from the switches above because it answers a different
    /// question — *where* rather than *whether* — and because a desktop
    /// notification is far more intrusive than one inside an app the user is
    /// already looking at.
    #[serde(default = "default_true")]
    pub system: bool,
}

impl Default for NotificationSettings {
    fn default() -> Self {
        Self {
            presence: true,
            poke: true,
            channel_message: true,
            direct_message: true,
            connection: true,
            system: true,
        }
    }
}

const fn default_true() -> bool {
    true
}

/// How audio is captured and played.
///
/// Every field's default is the one that was in force before settings existed,
/// so a missing section changes nothing.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct AudioSettings {
    /// Capture device id, in the form `cpal` renders (`"<host>:<device>"`).
    ///
    /// `None` means the system default. A saved id that no longer resolves —
    /// the headset was unplugged — is not an error either; `ts-audio` falls back
    /// to the default and says so.
    #[serde(default)]
    pub input_device: Option<String>,

    /// Playback device id. See [`AudioSettings::input_device`].
    #[serde(default)]
    pub output_device: Option<String>,

    /// How transmission is triggered.
    #[serde(default)]
    pub mode: VoiceActivationMode,

    /// Voice-activation tuning: the sensitivity slider, and the two smoothing
    /// constants behind it (§29).
    #[serde(default)]
    pub activation: VoiceActivationSettings,
}

/// How connections to servers are made.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ConnectionSettings {
    /// Nickname offered to servers, and the front-end's starting value for the
    /// field the user can still override per connection.
    #[serde(default = "default_nickname")]
    pub nickname: String,

    /// Which identity profile to present.
    ///
    /// One profile means one client to every server that sees it, which is what
    /// a user expects of "their" identity. TeamSpeak refuses a second live
    /// connection from the same identity, so running two clients side by side
    /// means giving one of them its own profile.
    #[serde(default = "default_profile")]
    pub profile: String,

    /// How many times a dropped connection may be retried.
    ///
    /// * `None` — forever. The default: a server that is down for an hour is
    ///   worth rejoining without being asked, and the backoff caps at 30s.
    /// * `Some(0)` — never. The drop is reported and the session ends.
    /// * `Some(n)` — up to `n` attempts.
    #[serde(default)]
    pub max_reconnect_attempts: Option<u32>,
}

impl Default for ConnectionSettings {
    fn default() -> Self {
        Self {
            nickname: default_nickname(),
            profile: default_profile(),
            max_reconnect_attempts: None,
        }
    }
}

impl ConnectionSettings {
    /// The reconnect policy these settings describe.
    ///
    /// The schedule itself is §35's and is not configurable yet: what a user
    /// actually wants to decide is whether retrying happens at all, and for how
    /// long. `None`/`Some(0)`/`Some(n)` map onto
    /// [`ReconnectPolicy::max_attempts`] exactly — `should_retry(0)` is already
    /// false for `Some(0)`, so "never retry" needs no separate flag.
    #[must_use]
    pub fn reconnect_policy(&self) -> ReconnectPolicy {
        ReconnectPolicy {
            max_attempts: self.max_reconnect_attempts,
            ..ReconnectPolicy::exponential()
        }
    }
}

/// Reads and writes [`Settings`] in one directory.
///
/// The root is explicit so tests can point at a temporary directory and mobile
/// hosts can supply their own sandbox path, exactly as [`ts_identity`] does.
#[derive(Debug, Clone)]
pub struct SettingsStore {
    dir: PathBuf,
}

impl SettingsStore {
    /// A store rooted at `dir` — the application data directory itself, not a
    /// subdirectory of it: there is one settings file, so giving it a directory
    /// of its own would only add a level.
    #[must_use]
    pub fn new(dir: impl Into<PathBuf>) -> Self {
        Self { dir: dir.into() }
    }

    /// The store for this platform's application data directory.
    ///
    /// # Errors
    ///
    /// Returns [`SettingsError::NoStorageRoot`] where the host application has
    /// to supply the path — Android and iOS.
    pub fn platform_default() -> Result<Self, SettingsError> {
        Ok(Self::new(
            app_data_root().ok_or(SettingsError::NoStorageRoot)?,
        ))
    }

    /// The file the settings live in.
    #[must_use]
    pub fn path(&self) -> PathBuf {
        self.dir.join(FILE_NAME)
    }

    /// Reads the settings, or the defaults when there is no file yet.
    ///
    /// # Errors
    ///
    /// Returns [`SettingsError::Malformed`] if the file exists but cannot be
    /// read as settings — including a version this build does not understand.
    /// The caller decides whether to carry on with defaults; this does not
    /// pretend the file was absent, because then nobody could say so.
    pub fn load(&self) -> Result<Settings, SettingsError> {
        // No file is the first run, not a failure.
        let Some(stored) = crate::store::read_json::<Settings>(&self.path())? else {
            return Ok(Settings::default());
        };

        if stored.version != FILE_VERSION {
            return Err(SettingsError::Malformed {
                message: format!(
                    "{}: unsupported version {}, expected {FILE_VERSION}",
                    self.path().display(),
                    stored.version
                ),
            });
        }

        Ok(stored)
    }

    /// Writes the settings, replacing whatever was there.
    ///
    /// # Errors
    ///
    /// Returns [`SettingsError::Io`] if the directory cannot be created or the
    /// file cannot be written.
    pub fn save(&self, settings: &Settings) -> Result<(), SettingsError> {
        crate::store::write_json(&self.path(), settings)
    }
}

const fn current_version() -> u32 {
    FILE_VERSION
}

fn default_nickname() -> String {
    // Matches the front-ends' own fallback, so the first run looks the same as
    // it did before settings existed.
    "Nightcord User".to_string()
}

fn default_profile() -> String {
    "default".to_string()
}

#[cfg(test)]
mod tests {
    use std::fs;

    use super::*;

    /// A directory that cleans itself up, so tests can run in parallel.
    struct TempDir(PathBuf);

    impl TempDir {
        fn new(tag: &str) -> Self {
            let unique = format!(
                "nightcord-settings-{tag}-{}-{:?}",
                std::process::id(),
                std::thread::current().id()
            );
            let path = std::env::temp_dir().join(unique.replace(['(', ')', ' '], ""));
            let _ = fs::remove_dir_all(&path);
            fs::create_dir_all(&path).expect("create temp dir");
            Self(path)
        }

        fn store(&self) -> SettingsStore {
            SettingsStore::new(&self.0)
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn a_missing_file_is_the_defaults_not_a_failure() {
        // The first run has no settings file, and that is not an error to
        // report to anyone.
        let dir = TempDir::new("missing");
        assert_eq!(dir.store().load().unwrap(), Settings::default());
    }

    #[test]
    fn settings_survive_a_round_trip() {
        let dir = TempDir::new("roundtrip");
        let store = dir.store();

        let settings = Settings {
            version: FILE_VERSION,
            audio: AudioSettings {
                input_device: Some("wasapi:Headset".into()),
                output_device: None,
                mode: VoiceActivationMode::PushToTalk,
                activation: VoiceActivationSettings {
                    sensitivity: 0.21,
                    attack_ms: 45,
                    release_ms: 250,
                },
            },
            connection: ConnectionSettings {
                nickname: "Alice".into(),
                profile: "alt".into(),
                max_reconnect_attempts: Some(3),
            },
            notifications: NotificationSettings::default(),
            shortcuts: ShortcutSettings::default(),
        };

        store.save(&settings).unwrap();
        assert_eq!(store.load().unwrap(), settings);
    }

    #[test]
    fn saving_leaves_no_temporary_file_behind() {
        // The write is a temp file plus a rename. A leftover `.tmp` would mean
        // the rename never happened — and, worse, that the real file is the old
        // one while the caller believes it saved.
        let dir = TempDir::new("atomic");
        let store = dir.store();
        store.save(&Settings::default()).unwrap();

        let leftovers: Vec<String> = fs::read_dir(&dir.0)
            .unwrap()
            .map(|entry| entry.unwrap().file_name().to_string_lossy().into_owned())
            .filter(|name| name.ends_with(".tmp"))
            .collect();

        assert!(leftovers.is_empty(), "left behind: {leftovers:?}");
    }

    #[test]
    fn a_corrupt_file_is_reported_rather_than_read_as_absence() {
        // Unlike a missing file. If this returned defaults silently, a user
        // whose preferences vanished would have nothing to go on — and the next
        // save would overwrite the evidence.
        let dir = TempDir::new("corrupt");
        let store = dir.store();
        fs::write(store.path(), b"{ this is not json").unwrap();

        assert!(matches!(store.load(), Err(SettingsError::Malformed { .. })));
    }

    #[test]
    fn a_version_this_build_does_not_know_is_refused() {
        let dir = TempDir::new("version");
        let store = dir.store();
        fs::write(store.path(), br#"{"version":99}"#).unwrap();

        let error = store.load().unwrap_err();
        assert!(
            matches!(error, SettingsError::Malformed { .. }),
            "got {error:?}"
        );
    }

    #[test]
    fn a_partial_file_fills_in_the_defaults() {
        // The file is meant to be hand-edited. Deleting a line resets that one
        // thing; it must not make the rest unreadable.
        let dir = TempDir::new("partial");
        let store = dir.store();
        fs::write(store.path(), br#"{"connection":{"nickname":"Bob"}}"#).unwrap();

        let loaded = store.load().unwrap();
        assert_eq!(loaded.connection.nickname, "Bob");
        assert_eq!(loaded.connection.profile, "default");
        assert_eq!(loaded.connection.max_reconnect_attempts, None);
        assert_eq!(loaded.audio, AudioSettings::default());
    }

    #[test]
    fn notifications_default_to_on() {
        // A client that starts silent looks broken rather than quiet. This is
        // the reason `Default` is written out instead of derived.
        let settings = Settings::default().notifications;
        assert!(settings.presence);
        assert!(settings.poke);
        assert!(settings.channel_message);
        assert!(settings.direct_message);
        assert!(settings.connection);
        assert!(settings.system);
    }

    #[test]
    fn a_file_written_before_notifications_existed_still_loads() {
        // What every existing settings file looks like: no `notifications` key
        // at all. It has to come back with the switches on, not off.
        let dir = TempDir::new("nonotifications");
        let store = dir.store();
        fs::write(
            store.path(),
            br#"{"version":1,"connection":{"nickname":"Bob"}}"#,
        )
        .unwrap();

        let loaded = store.load().unwrap();
        assert_eq!(loaded.connection.nickname, "Bob");
        assert_eq!(loaded.notifications, NotificationSettings::default());
    }

    #[test]
    fn a_single_notification_switch_round_trips() {
        // Turning one thing off must not turn the others off, which is what a
        // hand-written `Default` and per-field serde defaults are for.
        let dir = TempDir::new("oneswitch");
        let store = dir.store();

        let mut settings = Settings::default();
        settings.notifications.presence = false;
        store.save(&settings).unwrap();

        let loaded = store.load().unwrap();
        assert!(!loaded.notifications.presence);
        assert!(loaded.notifications.direct_message);
    }

    #[test]
    fn shortcuts_default_to_the_combinations_the_design_doc_names() {
        // §42. A file written before this section existed comes back with these
        // rather than with nothing bound — a client whose shortcuts silently
        // stopped working is worse than one that never had them.
        let shortcuts = Settings::default().shortcuts;

        for (chord, label) in [
            (shortcuts.mute, "mute"),
            (shortcuts.deafen, "deafen"),
            (shortcuts.push_to_talk, "push to talk"),
        ] {
            let chord = chord.unwrap_or_else(|| panic!("{label} has no default"));
            assert!(chord.ctrl && chord.shift, "{label} should be Ctrl+Shift");
            // Not the letter: the *physical* key, USB HID usage and all.
            assert!(
                chord.key > 0x0007_0000,
                "{label} lost the usage-page prefix"
            );
        }
    }

    #[test]
    fn a_bound_shortcut_can_be_cleared_without_being_reset() {
        // An explicitly unbound action and one that was never configured are
        // different, and only the second should fall back to a default.
        let dir = TempDir::new("unbound");
        let store = dir.store();

        let mut settings = Settings::default();
        settings.shortcuts.mute = None;
        store.save(&settings).unwrap();

        let loaded = store.load().unwrap();
        assert_eq!(loaded.shortcuts.mute, None, "cleared stays cleared");
        assert!(
            loaded.shortcuts.deafen.is_some(),
            "clearing one must not clear the others"
        );
    }

    #[test]
    fn a_file_written_before_shortcuts_existed_still_gets_them() {
        let dir = TempDir::new("noshortcuts");
        let store = dir.store();
        fs::write(
            store.path(),
            br#"{"version":1,"connection":{"nickname":"Bob"}}"#,
        )
        .unwrap();

        let loaded = store.load().unwrap();
        assert_eq!(loaded.shortcuts, ShortcutSettings::default());
    }

    #[test]
    fn an_unknown_field_is_ignored_rather_than_fatal() {
        // What an older build meeting a newer file looks like. Refusing to read
        // it would make downgrading impossible for no benefit.
        let dir = TempDir::new("unknown");
        let store = dir.store();
        fs::write(
            store.path(),
            br#"{"version":1,"something_from_the_future":true}"#,
        )
        .unwrap();

        assert!(store.load().is_ok());
    }

    #[test]
    fn a_saved_file_is_readable_text() {
        // The whole point of JSON here is that a person can look at it and fix
        // a device id that no longer exists.
        let dir = TempDir::new("text");
        let store = dir.store();
        store.save(&Settings::default()).unwrap();

        let raw = fs::read_to_string(store.path()).unwrap();
        assert!(raw.contains("\"nickname\""), "got {raw}");
        assert!(raw.contains('\n'), "expected pretty-printed JSON: {raw}");
    }

    #[test]
    fn never_retrying_is_expressible() {
        // `max_attempts: Some(0)` is "off" — `should_retry(0)` is already false
        // for it, so the policy needs no separate flag.
        let settings = ConnectionSettings {
            max_reconnect_attempts: Some(0),
            ..ConnectionSettings::default()
        };

        let policy = settings.reconnect_policy();
        assert!(!policy.should_retry(0));
        assert_eq!(policy.delay_for_attempt(0), 1_000, "the schedule is §35's");
    }

    #[test]
    fn the_default_policy_retries_forever() {
        let policy = ConnectionSettings::default().reconnect_policy();
        assert!(policy.should_retry(10_000));
        assert_eq!(policy.delay_for_attempt(5), 30_000);
    }
}
