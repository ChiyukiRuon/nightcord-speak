//! # ts-ffi
//!
//! The C ABI Flutter talks to (§45–§47).
//!
//! ```text
//! Dart ──dart:ffi──▶ these functions ──command channel──▶ worker ──▶ Rust core
//!   ▲                                                       │
//!   └──────────── nightcord_poll_events() ◀─────────────────┘
//! ```
//!
//! Three rules hold across the boundary:
//!
//! * **Handles, never pointers to Rust objects.** `nightcord_create` returns an
//!   opaque `void*`; everything else addresses a `u32` session id, so no Rust
//!   object graph is exposed and nothing is shared by lifetime (§47).
//! * **JSON in, JSON out.** No Rust type is mirrored in C. The shapes are the
//!   same `serde` encodings `ts-model` and `ts-events` already produce, so there
//!   is exactly one definition of each.
//! * **Nothing blocks.** Every command returns immediately; results arrive
//!   through `nightcord_poll_events`. `connect` takes seconds and must not run
//!   on Dart's UI thread.
//!
//! Every `char*` this module returns is heap-allocated and must be handed back
//! to [`nightcord_free_string`]. Every `char*` it accepts is borrowed for the
//! duration of the call only.

mod audio;
mod client;
mod crash;
mod logging;
mod string;

use std::ffi::c_char;

use ts_core::ConnectRequest;
use ts_model::{
    BanDuration, ChannelId, ClientError, ClientId, KickScope, MessageTarget, ProtocolError,
    SessionId,
};
use ts_wire::{AudioDirection, Command};

use crate::client::NightcordClient;
use crate::string::{free_c_string, from_c_str, into_c_string};

/// A development aid, next to `NIGHTCORD_AUTO_CONNECT` (which lives in the
/// Dart layer): `ffi` makes `nightcord_create` panic — the process aborts, the
/// "died on the spot" path — and `worker` makes the worker task panic, the
/// "core half-dead" path. Both are how the crash-reporting smoke tests ask for
/// a crash on purpose (`docs/crash.md`).
pub(crate) const TEST_PANIC_VAR: &str = "NIGHTCORD_TEST_PANIC";

/// Reports a request that could not even be understood.
///
/// Uses the same `CommandResult` shape as a worker failure, so the UI has one
/// error path rather than two.
fn reject(client: &NightcordClient, command: &str, message: impl Into<String>) {
    client.report_failure(command, ClientError::Protocol(ProtocolError::new(message)));
}

/// Parses one JSON argument, or reports why not.
fn parse_json<T: serde::de::DeserializeOwned>(
    client: &NightcordClient,
    command: &str,
    text: &str,
) -> Option<T> {
    match serde_json::from_str(text) {
        Ok(value) => Some(value),
        Err(error) => {
            reject(client, command, format!("malformed request: {error}"));
            None
        }
    }
}

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

/// Starts the client core.
///
/// Returns null if the core cannot start, which in practice means the platform
/// gave no application data directory for identities. The caller must treat
/// null as fatal rather than passing it to anything else.
#[unsafe(no_mangle)]
pub extern "C" fn nightcord_create() -> *mut NightcordClient {
    // Before the core rather than after it. "The core could not start" is the
    // failure a user is most likely to report, and a line about it written
    // after the thing that failed has already given up is a line nobody reads.
    install_logging();

    // The crash hooks and the run marker, before anything that could die. The
    // marker is also what gates note-writing, so a start that never gets this
    // far leaves nothing behind on purpose.
    crash::begin();

    // Read after the hooks are installed, so the note is written before the
    // abort. This panic unwinds out of an `extern "C"` function, which edition
    // 2024 turns into an abort — the real "process died" path.
    if std::env::var(TEST_PANIC_VAR).is_ok_and(|value| value == "ffi") {
        panic!("{TEST_PANIC_VAR}=ffi");
    }

    match NightcordClient::new() {
        Ok(client) => Box::into_raw(Box::new(client)),
        Err(error) => {
            tracing::error!(%error, "could not start the core");
            // A run that never began is not a crash: clear the marker so the
            // start-up-failure screen is not followed by a false "last session
            // ended abnormally" banner on the next start.
            crash::mark_clean();
            std::ptr::null_mut()
        }
    }
}

/// Stops the core and frees it.
///
/// Sessions are disconnected first, so the server does not keep holding a
/// client for this identity.
///
/// # Safety
///
/// `handle` must be null, or a pointer returned by [`nightcord_create`] that
/// has not already been destroyed. Destroying twice, or destroying anything
/// else, is undefined behaviour.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nightcord_destroy(handle: *mut NightcordClient) {
    if handle.is_null() {
        return;
    }
    // Safety: the caller guarantees a live pointer from `nightcord_create`.
    let mut client = unsafe { Box::from_raw(handle) };
    if client.shutdown() {
        crash::mark_clean();
    }
    // Dropping runs `shutdown` again, which is harmless and idempotent.
    drop(client);
}

/// Marks this run as a clean exit, so the next start does not report it.
///
/// The front-end calls this when the user closes the window: that path never
/// destroys the client (the process is about to end), and without this call
/// every normal exit would look like a crash.
///
/// Returns `false` when the worker is already gone — a run whose core died is
/// not a clean one, and its marker is kept so the next start can say so.
///
/// # Safety
///
/// `handle` must be null, or a pointer returned by [`nightcord_create`] that
/// has not already been destroyed. It is only *read* here, so calling this
/// right before `nightcord_destroy` is fine.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nightcord_mark_clean_exit(handle: *mut NightcordClient) -> bool {
    // Safety: null is allowed, anything else is the caller's live pointer.
    match unsafe { handle.as_ref() } {
        Some(client) if !client.worker_alive() => {
            // Keep the marker: the next start must report the dead core even
            // though the user closed the window themselves.
            tracing::error!("the worker is gone; not marking this run as clean");
            false
        }
        _ => {
            crash::mark_clean();
            true
        }
    }
}

// ---------------------------------------------------------------------------
// Crash evidence
// ---------------------------------------------------------------------------

/// What the last runs left behind, as JSON.
///
/// No handle on purpose, like [`nightcord_log_dir`]: the answer must be
/// available when the core is dead or never started — which is exactly when it
/// is asked for — so it must not depend on the worker.
///
/// The returned string must be freed with [`nightcord_free_string`].
#[unsafe(no_mangle)]
pub extern "C" fn nightcord_crash_status() -> *mut c_char {
    into_c_string(crash::status_json())
}

/// Builds the crash report and answers with its path (or why not), as JSON.
///
/// Same no-handle reasoning as [`nightcord_crash_status`]. The returned string
/// must be freed with [`nightcord_free_string`].
#[unsafe(no_mangle)]
pub extern "C" fn nightcord_crash_report() -> *mut c_char {
    into_c_string(crash::report_json())
}

/// The library version, as a static string the caller must **not** free.
///
/// Dart checks this against what it was built against, so a stale DLL next to
/// the executable is reported rather than failing later in a confusing way.
#[unsafe(no_mangle)]
pub extern "C" fn nightcord_version() -> *const c_char {
    // A `'static` literal that already carries its own NUL: no allocation, and
    // no ownership question for the caller.
    concat!("nightcord ", env!("CARGO_PKG_VERSION"), "\0")
        .as_ptr()
        .cast()
}

// ---------------------------------------------------------------------------
// Logging
// ---------------------------------------------------------------------------

/// The `tracing` target every line forwarded from Dart carries.
///
/// Gives a reader one word to search for to separate "what the UI reported"
/// from "what the core did".
const UI_TARGET: &str = "nightcord_ui";

/// Installs the process-wide subscriber, on the first call only.
///
/// Idempotent because `tracing` allows exactly one global subscriber, and
/// because both [`nightcord_create`] and [`nightcord_log_dir`] have to agree on
/// where records go — whichever runs first decides, and the other reads back
/// the same answer.
fn install_logging() -> ts_logging::Sink {
    ts_logging::init(logging::desired_dir().as_deref())
}

/// The directory log files are written to.
///
/// Empty when records only reach stderr: on Android and iOS, whose sandbox path
/// the host application has to pass in, or when `NIGHTCORD_LOG_DIR` asks for no
/// file. The UI reads the empty string as "do not offer to open a folder".
///
/// Takes **no handle** on purpose. The screen that reports a core which failed
/// to start has no handle to pass, and that is exactly when the path is worth
/// showing.
///
/// The caller owns the result and must pass it to [`nightcord_free_string`].
#[unsafe(no_mangle)]
pub extern "C" fn nightcord_log_dir() -> *mut c_char {
    let dir = match install_logging() {
        ts_logging::Sink::File(dir) => dir.to_string_lossy().into_owned(),
        ts_logging::Sink::Stderr => String::new(),
    };
    into_c_string(dir)
}

/// Records a line sent by the front-end.
///
/// The UI owns failures the core cannot see — an exception thrown while
/// building a widget, an event batch it could not parse — and those are exactly
/// the ones a user reports. Forwarding them is what makes one file the whole
/// story rather than half of it.
///
/// `level` is one of `trace`, `debug`, `info`, `warn`, `error`, in any case.
/// Anything else, including null, is recorded as `info` rather than dropped:
/// the caller is our own code, so a mistake in *how* it called should not take
/// the message down with it. A null message is the one thing ignored, because
/// then there is nothing to record.
///
/// # Safety
///
/// Both pointers must be null, or point at NUL-terminated UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nightcord_log(level: *const c_char, message: *const c_char) {
    let Some(message) = (unsafe { from_c_str(message) }) else {
        return;
    };

    // Matched as text rather than through `Level`: the ABI's vocabulary is the
    // contract Dart codes against, so it is defined here where it can be read
    // and tested, not inherited from whatever words `tracing` happens to accept.
    let level = (unsafe { from_c_str(level) })
        .map(|text| text.trim().to_ascii_lowercase())
        .unwrap_or_default();

    match level.as_str() {
        "error" => tracing::error!(target: UI_TARGET, "{}", message),
        "warn" => tracing::warn!(target: UI_TARGET, "{}", message),
        "debug" => tracing::debug!(target: UI_TARGET, "{}", message),
        "trace" => tracing::trace!(target: UI_TARGET, "{}", message),
        _ => tracing::info!(target: UI_TARGET, "{}", message),
    }
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

/// Opens a connection. `request_json` is a serialised `ConnectRequest`.
///
/// The new session's id arrives as a `command_result` whose `session` field is
/// the handle everything else is addressed by.
///
/// # Safety
///
/// `handle` must be live, and `request_json` a NUL-terminated UTF-8 string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nightcord_connect(
    handle: *mut NightcordClient,
    request_json: *const c_char,
) {
    let Some(client) = (unsafe { handle.as_ref() }) else {
        return;
    };
    let Some(text) = (unsafe { from_c_str(request_json) }) else {
        reject(client, "connect", "no request provided");
        return;
    };
    if let Some(request) = parse_json::<ConnectRequest>(client, "connect", &text) {
        client.send(Command::Connect(Box::new(request)));
    }
}

/// Closes a connection.
///
/// # Safety
///
/// `handle` must be live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nightcord_disconnect(handle: *mut NightcordClient, session: u32) {
    let Some(client) = (unsafe { handle.as_ref() }) else {
        return;
    };
    client.send(Command::Disconnect {
        session: SessionId::new(session),
    });
}

/// Moves us into a channel.
///
/// # Safety
///
/// `handle` must be live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nightcord_join_channel(
    handle: *mut NightcordClient,
    session: u32,
    channel_id: u64,
) {
    let Some(client) = (unsafe { handle.as_ref() }) else {
        return;
    };
    client.send(Command::JoinChannel {
        session: SessionId::new(session),
        channel_id: ChannelId::new(channel_id),
    });
}

/// Returns to the server's default channel.
///
/// # Safety
///
/// `handle` must be live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nightcord_leave_channel(handle: *mut NightcordClient, session: u32) {
    let Some(client) = (unsafe { handle.as_ref() }) else {
        return;
    };
    client.send(Command::LeaveChannel {
        session: SessionId::new(session),
    });
}

/// Sends a chat message.
///
/// `target_json` is a serialised `MessageTarget`, e.g. `{"kind":"server"}` or
/// `{"kind":"channel","id":5}`.
///
/// # Safety
///
/// `handle` must be live, and both strings NUL-terminated UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nightcord_send_message(
    handle: *mut NightcordClient,
    session: u32,
    target_json: *const c_char,
    text: *const c_char,
) {
    let Some(client) = (unsafe { handle.as_ref() }) else {
        return;
    };
    let Some(target_text) = (unsafe { from_c_str(target_json) }) else {
        reject(client, "send_message", "no target provided");
        return;
    };
    // A missing body is a legitimate empty message rather than an error.
    let body = (unsafe { from_c_str(text) }).unwrap_or_default();

    if let Some(target) = parse_json::<MessageTarget>(client, "send_message", &target_text) {
        client.send(Command::SendMessage {
            session: SessionId::new(session),
            target,
            text: body,
        });
    }
}

/// Moves another client into a channel.
///
/// # Safety
///
/// `handle` must be live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nightcord_move_client(
    handle: *mut NightcordClient,
    session: u32,
    client_id: u16,
    channel_id: u64,
) {
    let Some(client) = (unsafe { handle.as_ref() }) else {
        return;
    };
    client.send(Command::MoveClient {
        session: SessionId::new(session),
        client_id: ClientId::new(client_id),
        channel_id: ChannelId::new(channel_id),
    });
}

/// Pokes another client, which typically makes their client beep.
///
/// # Safety
///
/// `handle` must be live, and `message` a NUL-terminated UTF-8 string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nightcord_poke(
    handle: *mut NightcordClient,
    session: u32,
    client_id: u16,
    message: *const c_char,
) {
    let Some(client) = (unsafe { handle.as_ref() }) else {
        return;
    };
    // A poke with nothing in it is still a poke; the sound is the point.
    let message = (unsafe { from_c_str(message) }).unwrap_or_default();

    client.send(Command::Poke {
        session: SessionId::new(session),
        client_id: ClientId::new(client_id),
        message,
    });
}

/// Removes another client from a channel or from the server.
///
/// `scope_json` is a serialised `KickScope` — `"\"channel\""` or `"\"server\""`
/// — and `message` may be null for no explanation.
///
/// # Safety
///
/// `handle` must be live, and both strings NUL-terminated UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nightcord_kick(
    handle: *mut NightcordClient,
    session: u32,
    client_id: u16,
    scope_json: *const c_char,
    message: *const c_char,
) {
    let Some(client) = (unsafe { handle.as_ref() }) else {
        return;
    };
    let Some(scope_text) = (unsafe { from_c_str(scope_json) }) else {
        reject(client, "kick", "no scope provided");
        return;
    };
    let message = unsafe { from_c_str(message) }.filter(|text| !text.is_empty());

    if let Some(scope) = parse_json::<KickScope>(client, "kick", &scope_text) {
        client.send(Command::Kick {
            session: SessionId::new(session),
            client_id: ClientId::new(client_id),
            scope,
            message,
        });
    }
}

/// Bans another client.
///
/// `duration_json` is a serialised `BanDuration` — `"\"permanent\""` or
/// `{"seconds":600}` — and `reason` may be null.
///
/// # Safety
///
/// `handle` must be live, and both strings NUL-terminated UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nightcord_ban(
    handle: *mut NightcordClient,
    session: u32,
    client_id: u16,
    duration_json: *const c_char,
    reason: *const c_char,
) {
    let Some(client) = (unsafe { handle.as_ref() }) else {
        return;
    };
    let Some(duration_text) = (unsafe { from_c_str(duration_json) }) else {
        reject(client, "ban", "no duration provided");
        return;
    };
    let reason = unsafe { from_c_str(reason) }.filter(|text| !text.is_empty());

    if let Some(duration) = parse_json::<BanDuration>(client, "ban", &duration_text) {
        client.send(Command::Ban {
            session: SessionId::new(session),
            client_id: ClientId::new(client_id),
            duration,
            reason,
        });
    }
}

/// Marks us away, or back at the keyboard.
///
/// `away` is the switch and `message` is what to say about it; `message` may be
/// null and carries no meaning when `away` is false. Away with no message is
/// its own state on the server — not the same as being back — which is why the
/// two are separate arguments rather than "null means here".
///
/// # Safety
///
/// `handle` must be live, and `message` null or a NUL-terminated UTF-8 string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nightcord_set_away(
    handle: *mut NightcordClient,
    session: u32,
    away: bool,
    message: *const c_char,
) {
    let Some(client) = (unsafe { handle.as_ref() }) else {
        return;
    };
    let message = unsafe { from_c_str(message) }.filter(|text| !text.is_empty());

    client.send(Command::SetAway {
        session: SessionId::new(session),
        away,
        message,
    });
}

/// Scales one client's audio within the mix.
///
/// Local only: nothing is sent to the server, and nothing anyone else receives
/// changes. The gain applies while they are talking and is put back the next
/// time they speak.
///
/// # Safety
///
/// `handle` must be live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nightcord_voice_set_client_volume(
    handle: *mut NightcordClient,
    session: u32,
    client_id: u16,
    volume: f32,
) {
    let Some(client) = (unsafe { handle.as_ref() }) else {
        return;
    };
    client.send(Command::VoiceSetClientVolume {
        session: SessionId::new(session),
        client_id: ClientId::new(client_id),
        volume,
    });
}

/// Asks for the machine's audio devices.
///
/// The list arrives as a `command_result` named `audio_devices`, whose `data`
/// holds `{"direction": "input"|"output", "devices": [...]}`.
///
/// # Safety
///
/// `handle` must be live, and `direction` a NUL-terminated UTF-8 string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nightcord_audio_devices(
    handle: *mut NightcordClient,
    direction: *const c_char,
) {
    let Some(client) = (unsafe { handle.as_ref() }) else {
        return;
    };
    let Some(text) = (unsafe { from_c_str(direction) }) else {
        reject(client, "audio_devices", "no direction provided");
        return;
    };

    match AudioDirection::parse(&text) {
        Some(direction) => {
            client.send(Command::ListDevices { direction });
        }
        None => reject(
            client,
            "audio_devices",
            format!("`{text}` is not a direction; expected `input` or `output`"),
        ),
    }
}

// ---------------------------------------------------------------------------
// Voice
// ---------------------------------------------------------------------------

/// Opens audio devices and binds voice to a session.
///
/// Either device id may be null or empty, which means "whatever is configured";
/// an explicit id overrides it for this run, which is what the CLI's
/// `--input-device` needs. A configured id that no longer exists falls back to
/// the system default rather than failing — an unplugged headset should not
/// leave the user silent.
///
/// The transmission mode and the voice-activation tuning come from the settings
/// too, so this is the point where everything the user chose about audio takes
/// effect at once.
///
/// # Safety
///
/// `handle` must be live; the id strings, when non-null, must be NUL-terminated
/// UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nightcord_voice_start(
    handle: *mut NightcordClient,
    session: u32,
    input_device: *const c_char,
    output_device: *const c_char,
) {
    let Some(client) = (unsafe { handle.as_ref() }) else {
        return;
    };

    let input = (unsafe { from_c_str(input_device) }).filter(|id| !id.is_empty());
    let output = (unsafe { from_c_str(output_device) }).filter(|id| !id.is_empty());

    client.send(Command::VoiceStart {
        session: SessionId::new(session),
        input,
        output,
    });
}

/// Closes the devices and stops transmitting.
///
/// # Safety
///
/// `handle` must be live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nightcord_voice_stop(handle: *mut NightcordClient) {
    let Some(client) = (unsafe { handle.as_ref() }) else {
        return;
    };
    client.send(Command::VoiceStop);
}

/// Mutes or unmutes the microphone.
///
/// # Safety
///
/// `handle` must be live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nightcord_voice_set_input_muted(
    handle: *mut NightcordClient,
    muted: bool,
) {
    let Some(client) = (unsafe { handle.as_ref() }) else {
        return;
    };
    client.send(Command::VoiceSetInputMuted { muted });
}

/// Mutes or unmutes the speakers.
///
/// # Safety
///
/// `handle` must be live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nightcord_voice_set_output_muted(
    handle: *mut NightcordClient,
    muted: bool,
) {
    let Some(client) = (unsafe { handle.as_ref() }) else {
        return;
    };
    client.send(Command::VoiceSetOutputMuted { muted });
}

/// Push-to-talk key down or up (§30).
///
/// Called on every key press, so it produces no `command_result`: only the
/// resulting `VoiceStateChanged` matters.
///
/// # Safety
///
/// `handle` must be live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nightcord_voice_push_to_talk(handle: *mut NightcordClient, held: bool) {
    let Some(client) = (unsafe { handle.as_ref() }) else {
        return;
    };
    client.send(Command::VoicePushToTalk { held });
}

/// Asks what the audio engine is doing.
///
/// The answer arrives as a `command_result` named `voice_status`: which device
/// each side actually opened (and whether it is the one that was asked for),
/// the microphone's current level and peak, whether we are transmitting, and
/// whether either device has since gone away.
///
/// **Pulled rather than pushed.** The engine produces a frame every 20 ms, and
/// a stream of status events at that rate would fill the event queue — the
/// thing `audio.rs` exists to keep Opus payload out of — and give every
/// front-end's event handling a 50 Hz heartbeat to keep up with. The caller
/// decides how often to ask.
///
/// With no engine running the answer is "nothing is open" rather than a
/// failure: that is what "voice has not been started" looks like.
///
/// # Safety
///
/// `handle` must be live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nightcord_voice_status(handle: *mut NightcordClient) {
    let Some(client) = (unsafe { handle.as_ref() }) else {
        return;
    };
    client.send(Command::VoiceStatus);
}

/// Plays a short tone so the user can hear whether the speakers work.
///
/// Goes to the speakers only — it is playback, never captured, so nothing is
/// sent anywhere. Requires voice to be running, because the engine is what owns
/// the output device.
///
/// # Safety
///
/// `handle` must be live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nightcord_voice_test_output(handle: *mut NightcordClient) {
    let Some(client) = (unsafe { handle.as_ref() }) else {
        return;
    };
    client.send(Command::VoiceTestOutput);
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

/// Asks for the preferences in force.
///
/// The answer arrives as a `command_result` named `settings`, whose `data` is
/// the settings object. Asynchronous rather than a return value, so there is one
/// copy of the settings — the core's — instead of a second cache here that could
/// disagree with it.
///
/// # Safety
///
/// `handle` must be live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nightcord_settings(handle: *mut NightcordClient) {
    let Some(client) = (unsafe { handle.as_ref() }) else {
        return;
    };
    client.send(Command::SettingsGet);
}

/// Replaces the preferences.
///
/// `settings_json` is a serialised `Settings`, complete rather than partial: the
/// caller has the current object and edits it. A malformed one is rejected
/// without touching what is stored, so a bad write cannot cost the user the
/// settings they had.
///
/// The outcome arrives as a `command_result` named `settings_update`. On success
/// the file has been written and whatever a running voice engine can adopt —
/// the transmission mode and the voice-activation tuning — has been applied.
///
/// # Safety
///
/// `handle` must be live, and `settings_json` a NUL-terminated UTF-8 string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nightcord_update_settings(
    handle: *mut NightcordClient,
    settings_json: *const c_char,
) {
    let Some(client) = (unsafe { handle.as_ref() }) else {
        return;
    };
    let Some(text) = (unsafe { from_c_str(settings_json) }) else {
        reject(client, "settings_update", "no settings provided");
        return;
    };

    if let Some(settings) = parse_json::<ts_settings::Settings>(client, "settings_update", &text) {
        client.send(Command::SettingsUpdate(Box::new(settings)));
    }
}

/// Asks for the saved servers (§40).
///
/// The answer arrives as a `command_result` named `bookmarks`, whose `data` is
/// `{"version": 1, "servers": [...]}`. Same shape as `settings` and for the same
/// reason: the core owns the file, and a second cache here could disagree with
/// it.
///
/// # Safety
///
/// `handle` must be live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nightcord_bookmarks(handle: *mut NightcordClient) {
    let Some(client) = (unsafe { handle.as_ref() }) else {
        return;
    };
    client.send(Command::BookmarksGet);
}

/// Replaces the saved servers.
///
/// `bookmarks_json` is a serialised `BookmarkList`, complete rather than partial.
/// A malformed one is rejected without touching what is stored, so a bad write
/// cannot cost the user their address book.
///
/// The outcome arrives as a `command_result` named `bookmarks_update`. The entries
/// carry server passwords, so the reply to [`nightcord_bookmarks`] does too —
/// nothing here logs either (§44).
///
/// # Safety
///
/// `handle` must be live, and `bookmarks_json` a NUL-terminated UTF-8 string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nightcord_update_bookmarks(
    handle: *mut NightcordClient,
    bookmarks_json: *const c_char,
) {
    let Some(client) = (unsafe { handle.as_ref() }) else {
        return;
    };
    let Some(text) = (unsafe { from_c_str(bookmarks_json) }) else {
        reject(client, "bookmarks_update", "no bookmarks provided");
        return;
    };

    if let Some(servers) =
        parse_json::<ts_settings::BookmarkList>(client, "bookmarks_update", &text)
    {
        client.send(Command::BookmarksUpdate(Box::new(servers)));
    }
}

/// Saves a server from what the connect screen collected.
///
/// `request_json` is a serialised `NewBookmark`: a name, and the address as the
/// user typed it. The core parses it — the same parser a connection uses, so an
/// entry that saves is an entry that connects — and normalises what it stores.
///
/// The answer arrives as a `command_result` named `bookmark_add` whose `data` is
/// the list as it now stands, so the caller does not have to ask again.
///
/// # Safety
///
/// `handle` must be live, and `request_json` a NUL-terminated UTF-8 string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nightcord_add_bookmark(
    handle: *mut NightcordClient,
    request_json: *const c_char,
) {
    let Some(client) = (unsafe { handle.as_ref() }) else {
        return;
    };
    let Some(text) = (unsafe { from_c_str(request_json) }) else {
        reject(client, "bookmark_add", "no bookmark provided");
        return;
    };

    if let Some(bookmark) = parse_json::<ts_settings::NewBookmark>(client, "bookmark_add", &text) {
        client.send(Command::BookmarksAdd(Box::new(bookmark)));
    }
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

/// Drains queued events as a JSON array.
///
/// The caller **owns** the result and must pass it to
/// [`nightcord_free_string`]. An empty queue yields `[]` rather than null, so
/// the caller never has to special-case "nothing happened".
///
/// # Safety
///
/// `handle` must be live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nightcord_poll_events(handle: *mut NightcordClient) -> *mut c_char {
    match unsafe { handle.as_ref() } {
        Some(client) => into_c_string(client.poll_events()),
        // A null handle gets an empty batch rather than a crash: a UI that has
        // already torn the client down should not have to stop polling first.
        None => into_c_string("[]"),
    }
}

/// Frees a string returned by this library.
///
/// # Safety
///
/// `text` must be null, or a pointer returned by one of this module's
/// `char*`-returning functions that has not already been freed. Passing a
/// static string such as [`nightcord_version`]'s is undefined behaviour.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nightcord_free_string(text: *mut c_char) {
    // Safety: the caller guarantees provenance.
    unsafe { free_c_string(text) };
}

#[cfg(test)]
mod tests {
    use ts_model::VoiceActivationMode;

    use super::*;

    #[test]
    fn the_mode_names_match_the_serialised_form() {
        // The transmission mode now travels inside the settings object rather
        // than as its own command, and Dart parses `VoiceStateChanged` from the
        // same vocabulary — so all three have to agree on these strings.
        for (text, mode) in [
            ("push_to_talk", VoiceActivationMode::PushToTalk),
            ("voice_activation", VoiceActivationMode::VoiceActivation),
            ("continuous", VoiceActivationMode::Continuous),
            ("muted", VoiceActivationMode::Muted),
        ] {
            let json = serde_json::to_value(mode).unwrap();
            assert_eq!(json.as_str(), Some(text), "{mode:?} serialises as {json}");
        }
    }

    #[test]
    fn a_malformed_servers_update_is_refused_rather_than_stored() {
        // The user's address book must survive a caller sending nonsense.
        let client = NightcordClient::new().expect("start the core");
        reject(&client, "bookmarks_update", "malformed request");

        let batch: serde_json::Value =
            serde_json::from_str(&client.poll_events()).expect("valid JSON");

        assert_eq!(batch[0]["command"], "bookmarks_update");
        assert_eq!(batch[0]["outcome"]["status"], "failed");
    }

    #[test]
    fn a_malformed_settings_update_is_refused_rather_than_stored() {
        // The user's existing settings must survive a caller sending nonsense;
        // the entry point rejects before anything reads or writes the file.
        let client = NightcordClient::new().expect("start the core");
        reject(&client, "settings_update", "malformed request");

        let batch: serde_json::Value =
            serde_json::from_str(&client.poll_events()).expect("valid JSON");

        assert_eq!(batch[0]["command"], "settings_update");
        assert_eq!(batch[0]["outcome"]["status"], "failed");
    }

    #[test]
    fn creating_and_destroying_a_client_is_safe() {
        let handle = nightcord_create();
        assert!(
            !handle.is_null(),
            "the core should start on a desktop platform"
        );
        // Safety: `handle` came from `nightcord_create` and is destroyed once.
        unsafe { nightcord_destroy(handle) };
    }

    #[test]
    fn destroying_null_is_harmless() {
        // Safety: null is explicitly allowed.
        unsafe { nightcord_destroy(std::ptr::null_mut()) };
    }

    #[test]
    fn polling_a_null_handle_yields_an_empty_batch() {
        // Safety: a null handle is explicitly allowed here.
        let raw = unsafe { nightcord_poll_events(std::ptr::null_mut()) };
        assert!(!raw.is_null());

        // Safety: `raw` came from `nightcord_poll_events`.
        let text = unsafe { from_c_str(raw) }.expect("a string");
        assert_eq!(text, "[]");

        // Safety: freed exactly once.
        unsafe { nightcord_free_string(raw) };
    }

    #[test]
    fn a_round_trip_through_the_abi_produces_an_event_batch() {
        let handle = nightcord_create();
        assert!(!handle.is_null());

        // Safety: `handle` is live for this block, and the string outlives the
        // call.
        unsafe {
            let raw = nightcord_poll_events(handle);
            let text = from_c_str(raw).expect("a string");
            assert!(
                serde_json::from_str::<serde_json::Value>(&text).is_ok(),
                "not JSON: {text}"
            );
            nightcord_free_string(raw);

            nightcord_destroy(handle);
        }
    }

    #[test]
    fn the_log_directory_can_be_asked_for_without_a_client() {
        // No handle, deliberately: the screen that reports a core which failed
        // to start has none to pass, and that is exactly when the path is worth
        // showing.
        let raw = nightcord_log_dir();
        assert!(!raw.is_null(), "the caller would dereference NULL");

        // Safety: `raw` came from `nightcord_log_dir` and is freed once.
        unsafe {
            let text = from_c_str(raw).expect("a string");

            // Empty is a legitimate answer — mobile has no root, and an empty
            // `NIGHTCORD_LOG_DIR` asks for no file — but it must be empty for
            // exactly those reasons, not because the path was lost.
            assert_eq!(
                text.is_empty(),
                logging::desired_dir().is_none(),
                "reported {text:?} for {:?}",
                logging::desired_dir()
            );

            nightcord_free_string(raw);
        }
    }

    #[test]
    fn a_line_forwarded_from_the_ui_is_recorded_whatever_is_in_it() {
        // This is called from an error handler, so a panic here would turn a
        // reportable failure into a silent one. Null pointers, an unknown
        // level, and bytes that are not UTF-8 all have to be survivable
        // no-ops or best-effort records.
        let not_utf8: &[u8] = b"\xff\xfe not utf-8\0";

        // Safety: every pointer is null or NUL-terminated, and outlives the
        // call.
        unsafe {
            nightcord_log(std::ptr::null(), std::ptr::null());
            nightcord_log(c"error".as_ptr(), std::ptr::null());
            nightcord_log(not_utf8.as_ptr().cast(), c"still recorded".as_ptr());
            nightcord_log(c"LOUD".as_ptr(), c"an unknown level".as_ptr());
            nightcord_log(std::ptr::null(), c"no level at all".as_ptr());
        }
    }

    #[test]
    fn a_malformed_request_is_reported_rather_than_dropped() {
        // The UI must learn that its request was understood badly, not sit
        // waiting for a result that will never come.
        let client = NightcordClient::new().expect("start the core");
        reject(&client, "connect", "malformed request");

        let batch: serde_json::Value =
            serde_json::from_str(&client.poll_events()).expect("valid JSON");
        assert_eq!(batch[0]["kind"], "command_result");
        assert_eq!(batch[0]["command"], "connect");
        assert_eq!(batch[0]["outcome"]["status"], "failed");
    }
}
