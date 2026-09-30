//! Crash evidence, for the classes of failure the log cannot record.
//!
//! `ts-logging` answers "what happened while the process was alive". This crate
//! answers the other question — "what happened when it died" — with three
//! signals:
//!
//! 1. **A run marker** per process (`last-run.<pid>`), written at start and
//!    removed on a clean exit. A marker whose process is no longer alive is the
//!    evidence that the last run did not exit cleanly. One file per pid rather
//!    than one shared file, so two instances cannot overwrite each other's
//!    evidence or clear each other's marker.
//! 2. **A note** written synchronously from the panic hook and from the
//!    `crash-handler` exception callback. Neither can use the logging queue: it
//!    is bounded and asynchronous, and the records worth most are the ones that
//!    never make it out. Notes are only written while *our own* run marker
//!    exists, so a panicking test process does not litter a user's directory.
//! 3. **A report**, built on demand, that bundles the notes, the markers and
//!    the tail of the log into one text file a user can send. Nothing leaves
//!    the machine by itself (§74: no cloud).
//!
//! What this crate deliberately is *not*: a minidump producer. A minidump needs
//! an out-of-process writer (`minidumper` and a sidecar binary), which is an
//! upgrade path recorded in `docs/crash.md`, not a v1 feature.

use std::fs;
use std::io;
use std::panic::{self, PanicHookInfo};
use std::path::{Path, PathBuf};
use std::sync::OnceLock;
use std::time::{SystemTime, UNIX_EPOCH};

/// The directory's name inside the application data root.
pub const DIR_NAME: &str = "crashes";

/// The prefix of one process's run marker; the rest is its pid.
const RUN_MARKER_PREFIX: &str = "last-run.";

/// The prefix of a crash note file.
const NOTE_PREFIX: &str = "crash-";

/// The prefix of a generated report.
const REPORT_PREFIX: &str = "nightcord-report-";

/// How many notes and reports to keep. Mirrors `ts-logging`'s `KEEP_FILES`, and
/// for the same reason: enough to cover a bad day, few enough not to grow.
const KEEP_FILES: usize = 10;

/// How long a marker of a process that is gone keeps being reported before it
/// is pruned. Long on purpose: the banner should survive until the user has
/// dealt with it, not disappear overnight.
const MARKER_MAX_AGE_DAYS: u64 = 30;

/// How much of the log the report carries. Enough for the minutes around a
/// crash at the default level; the file is text, so a bigger cap costs little
/// but a wall of log buries the crash notes above it.
const LOG_TAIL_LIMIT: u64 = 256 * 1024;

/// Reads and writes the crash evidence in one directory.
///
/// The directory is explicit — the FFI layer computes it from the application
/// data root, exactly as it does for the log directory — so tests point at a
/// temporary directory and this crate stays platform-agnostic.
#[derive(Debug, Clone)]
pub struct CrashStore {
    dir: PathBuf,
}

/// What the last runs left behind.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CrashStatus {
    /// A run marker whose process is no longer alive: the last run did not
    /// exit cleanly.
    pub abnormal: bool,

    /// How many crash notes are waiting to be looked at.
    pub notes: usize,

    /// Where the evidence lives, so the UI can offer to open it.
    pub directory: PathBuf,
}

impl CrashStore {
    /// A store rooted at `dir` — the `crashes` directory itself, not the data
    /// root: the caller knows where the latter is, this crate does not.
    #[must_use]
    pub fn new(dir: impl Into<PathBuf>) -> Self {
        Self { dir: dir.into() }
    }

    /// The directory the evidence lives in.
    #[must_use]
    pub fn path(&self) -> &Path {
        &self.dir
    }

    /// Installs the panic hook and the exception handler, at most once per
    /// process.
    ///
    /// Called from the FFI entry point rather than from client construction, so
    /// that Rust tests — which build clients directly — neither install a
    /// process-wide hook nor write into a user's directory.
    pub fn install_handlers(&self) {
        static PANIC_HOOK: OnceLock<()> = OnceLock::new();
        // Dropping the `CrashHandler` detaches the exception handler, so it has
        // to live as long as the process does.
        static EXCEPTION_HANDLER: OnceLock<crash_handler::CrashHandler> = OnceLock::new();

        PANIC_HOOK.get_or_init(|| {
            let dir = self.dir.clone();
            // The original hook is captured once and chained to, both so the
            // default report on stderr survives and so repeated installations
            // could not grow an unbounded chain.
            let previous = panic::take_hook();
            panic::set_hook(Box::new(move |info| {
                write_panic_note(&dir, info);
                previous(info);
            }));
        });

        if EXCEPTION_HANDLER.get().is_none() {
            let dir = self.dir.clone();
            // SAFETY: the closure runs in a compromised context; it does as
            // little as possible — build a string, write a file — and never
            // unwinds. See the crate-level docs of `crash-handler` for the
            // caveats that come with that context.
            let event = unsafe {
                crash_handler::make_crash_event(move |context| {
                    write_exception_note(&CrashStore::new(&dir), context);
                    crash_handler::CrashEventResult::Handled(false)
                })
            };
            // `attach` fails if a handler is already installed, which in this
            // process only means someone else called first; either way the
            // behaviour is "install once".
            if let Ok(handler) = crash_handler::CrashHandler::attach(event) {
                let _ = EXCEPTION_HANDLER.set(handler);
            }
        }
    }

    /// Begins a run: writes this process's marker and prunes old evidence.
    ///
    /// Does **not** remove old markers — those are the evidence; the caller
    /// reads them through [`CrashStore::status`].
    ///
    /// # Errors
    ///
    /// Returns the I/O error when the directory cannot be created or the marker
    /// cannot be written. Callers may continue: a run without a marker simply
    /// cannot be reported as abnormal later.
    pub fn begin_run(&self) -> io::Result<()> {
        fs::create_dir_all(&self.dir)?;
        let marker = self
            .dir
            .join(format!("{RUN_MARKER_PREFIX}{}", std::process::id()));
        fs::write(&marker, self.marker_contents())?;
        self.prune();
        Ok(())
    }

    /// Removes this process's marker: the run ended cleanly.
    ///
    /// Best effort — a failure here means the next start reports this run as
    /// abnormal, which is the safe direction to err in.
    pub fn mark_clean(&self) {
        let marker = self
            .dir
            .join(format!("{RUN_MARKER_PREFIX}{}", std::process::id()));
        let _ = fs::remove_file(marker);
    }

    /// Reads what the previous runs left behind.
    #[must_use]
    pub fn status(&self) -> CrashStatus {
        let mut abnormal = false;
        let mut notes = 0;

        if let Ok(entries) = fs::read_dir(&self.dir) {
            for entry in entries.flatten() {
                let name = entry.file_name();
                let Some(name) = name.to_str() else { continue };

                if let Some(pid) = name.strip_prefix(RUN_MARKER_PREFIX) {
                    // A marker whose process is gone is the evidence. Our own
                    // live marker is not, and neither is another instance's.
                    if pid.parse::<u32>().is_ok_and(|pid| !is_pid_alive(pid)) {
                        abnormal = true;
                    }
                } else if name.starts_with(NOTE_PREFIX) && name.ends_with(".txt") {
                    notes += 1;
                }
            }
        }

        CrashStatus {
            abnormal,
            notes,
            directory: self.dir.clone(),
        }
    }

    /// Builds the report a user can send, and returns its path.
    ///
    /// `logs_dir` is where the log files live; pass `None` when there are none
    /// on this platform. Markers of dead runs are *consumed* by a successful
    /// report — their contents are inside it now — so generating the report is
    /// what settles the "last run did not exit cleanly" notice.
    ///
    /// # Errors
    ///
    /// Returns the I/O error when the report cannot be written.
    pub fn write_report(&self, logs_dir: Option<&Path>) -> io::Result<PathBuf> {
        let mut report = String::new();
        write_header(&mut report, &self.dir);
        write_notes_section(&mut report, &self.dir);
        write_markers_section(&mut report, &self.dir);
        write_log_section(&mut report, logs_dir);
        report.push_str(PRIVACY_NOTE);

        fs::create_dir_all(&self.dir)?;
        let path = self.dir.join(format!("{REPORT_PREFIX}{}.txt", unix_secs()));
        fs::write(&path, report)?;

        // The dead markers are in the report now; a live one stays, it belongs
        // to a running process.
        if let Ok(entries) = fs::read_dir(&self.dir) {
            for entry in entries.flatten() {
                let name = entry.file_name();
                let Some(name) = name.to_str() else { continue };
                if let Some(pid) = name.strip_prefix(RUN_MARKER_PREFIX) {
                    if pid.parse::<u32>().is_ok_and(|pid| !is_pid_alive(pid)) {
                        let _ = fs::remove_file(entry.path());
                    }
                }
            }
        }

        self.prune();
        Ok(path)
    }

    /// The content of this run's marker, kept short and human-readable — it
    /// ends up inside reports.
    fn marker_contents(&self) -> String {
        format!(
            "version={}\npid={}\nstarted={}\n",
            env!("CARGO_PKG_VERSION"),
            std::process::id(),
            unix_secs(),
        )
    }

    /// Keeps the newest [`KEEP_FILES`] notes and reports, and drops markers of
    /// processes that have been gone for longer than [`MARKER_MAX_AGE_DAYS`].
    fn prune(&self) {
        let mut notes = Vec::new();
        let mut reports = Vec::new();
        let mut markers = Vec::new();

        let Ok(entries) = fs::read_dir(&self.dir) else {
            return;
        };
        for entry in entries.flatten() {
            let name = entry.file_name();
            let Some(name) = name.to_str() else { continue };
            if name.starts_with(NOTE_PREFIX) && name.ends_with(".txt") {
                notes.push(entry);
            } else if name.starts_with(REPORT_PREFIX) && name.ends_with(".txt") {
                reports.push(entry);
            } else if name.starts_with(RUN_MARKER_PREFIX) {
                markers.push(entry);
            }
        }

        // Timestamps lead the names, so a lexical sort is a chronological one.
        prune_newest(&mut notes);
        prune_newest(&mut reports);

        let max_age = std::time::Duration::from_secs(MARKER_MAX_AGE_DAYS * 24 * 60 * 60);
        for marker in markers {
            let own = marker
                .file_name()
                .to_str()
                .is_some_and(|name| name == format!("{RUN_MARKER_PREFIX}{}", std::process::id()));
            if own {
                continue;
            }
            let old = marker
                .metadata()
                .and_then(|meta| meta.modified())
                .map_or(true, |modified| {
                    SystemTime::now()
                        .duration_since(modified)
                        .is_ok_and(|age| age > max_age)
                });
            if old {
                let _ = fs::remove_file(marker.path());
            }
        }
    }
}

/// Keeps the newest [`KEEP_FILES`] entries of a timestamp-prefixed set.
fn prune_newest(entries: &mut Vec<fs::DirEntry>) {
    if entries.len() <= KEEP_FILES {
        return;
    }
    entries.sort_by_key(fs::DirEntry::file_name);
    let remove = entries.len() - KEEP_FILES;
    for entry in entries.drain(..remove) {
        let _ = fs::remove_file(entry.path());
    }
}

/// Whether a panic or exception note may be written at all.
///
/// Only while *our own* run marker exists: that marker is written by the FFI
/// entry point and removed on a clean exit, so it is the one honest answer to
/// "is this a real run or a test process?". Without this check, a failing test
/// suite would write notes into a developer's real crash directory.
fn our_run_is_live(dir: &Path) -> bool {
    dir.join(format!("{RUN_MARKER_PREFIX}{}", std::process::id()))
        .exists()
}

/// Writes the note a panic leaves. Best effort by nature: it runs while the
/// process is coming apart, so every failure is swallowed.
fn write_panic_note(dir: &Path, info: &PanicHookInfo<'_>) {
    if !our_run_is_live(dir) {
        return;
    }

    let message = if let Some(text) = info.payload().downcast_ref::<&str>() {
        (*text).to_string()
    } else if let Some(text) = info.payload().downcast_ref::<String>() {
        text.clone()
    } else {
        "<non-string panic payload>".to_string()
    };
    let location = info
        .location()
        .map_or_else(|| "<unknown>".to_string(), ToString::to_string);
    let thread = std::thread::current()
        .name()
        .unwrap_or("unnamed")
        .to_string();

    write_note(
        dir,
        "panic",
        &format!(
            "message: {message}\nlocation: {location}\nthread: {thread}\n\nbacktrace:\n{}",
            format_backtrace(),
        ),
    );
}

/// The backtrace as text: one frame per line, by instruction pointer.
///
/// Deliberately **unresolved** — no symbol names. Three reasons, each learned
/// the hard way:
///
/// - Addresses are what always survive. A release build ships no symbols, and
///   the machine that crashed does not have the matching PDB; addresses plus
///   the PDB kept in this repository symbolize the report later
///   (`docs/crash.md`).
/// - Without that PDB, a resolver does not fail — it answers *wrongly*, naming
///   whatever export happens to sit nearest. A misleading name is worse than
///   no name.
/// - Symbolization loads dbghelp and allocates. This runs in a panic hook and
///   in an exception handler; on the failing path it came back empty, and it
///   is the wrong kind of work to do while the process is coming apart.
///
/// The `backtrace` crate rather than `std::backtrace`: `frames()` is still
/// unstable in std, and without it there is no way to reach the addresses.
fn format_backtrace() -> String {
    let backtrace = backtrace::Backtrace::new_unresolved();
    let mut text = String::new();
    for (index, frame) in backtrace.frames().iter().enumerate() {
        text.push_str(&format!("  {index:2} {:p}\n", frame.ip()));
    }
    text
}

/// Writes the note an exception leaves.
///
/// Public because the integration test drives it through `crash-handler`'s
/// `simulate_exception`, which is the only way to exercise this path without
/// actually dying.
pub fn write_exception_note(store: &CrashStore, context: &crash_handler::CrashContext) {
    let dir = store.path();
    if !our_run_is_live(dir) {
        return;
    }

    let (code, address) = exception_details(context);
    write_note(
        dir,
        "exception",
        &format!(
            "exception_code: {code}\nexception_address: {address}\nthread: {}\n\nbacktrace (best effort):\n{}",
            std::thread::current().name().unwrap_or("unnamed"),
            format_backtrace(),
        ),
    );
}

/// The exception code and address, to whatever depth this platform exposes.
///
/// Windows carries both (the address via the exception record the context
/// points at); the other platforms' contexts have different shapes, and the
/// note's value there is the backtrace — a fact recorded in `docs/crash.md`
/// rather than papered over.
#[cfg(windows)]
#[allow(unsafe_code)] // Dereferencing the crash context is this function's job.
fn exception_details(context: &crash_handler::CrashContext) -> (String, String) {
    // `as` rather than `cast_unsigned`: the latter is newer than the workspace
    // MSRV, and the bit pattern is all that matters for a display value.
    let code = format!("{:#010x}", context.exception_code as u32);
    // The context points into this same process's crashed memory; the null
    // checks are for the case where the platform handed us nothing.
    let address = unsafe {
        let pointers = context.exception_pointers;
        if pointers.is_null() {
            None
        } else {
            let record = (*pointers).ExceptionRecord;
            if record.is_null() {
                None
            } else {
                Some((*record).ExceptionAddress as usize)
            }
        }
    };
    let address = address.map_or_else(|| "<unknown>".to_string(), |at| format!("{at:#x}"));
    (code, address)
}

/// See the Windows implementation.
#[cfg(not(windows))]
fn exception_details(_context: &crash_handler::CrashContext) -> (String, String) {
    ("<unknown>".to_string(), "<unknown>".to_string())
}

/// The shared tail of both notes: a header, the body, and a write that ignores
/// every error. The directory is created here too — a crash before `begin_run`
/// managed to (or after someone removed it) should still leave evidence.
fn write_note(dir: &Path, kind: &str, body: &str) {
    let _ = fs::create_dir_all(dir);
    let note = format!(
        "kind: {kind}\n\
         time: {}\n\
         process: {}\n\
         version: {}\n\
         \n\
         {body}",
        unix_secs(),
        std::process::id(),
        env!("CARGO_PKG_VERSION"),
    );
    let path = dir.join(format!(
        "{NOTE_PREFIX}{}-{}-{kind}.txt",
        unix_nanos(),
        std::process::id(),
    ));
    let _ = fs::write(path, note);
}

/// One line of context at the top of every report.
fn write_header(report: &mut String, dir: &Path) {
    report.push_str("Nightcord Speak crash report\n");
    report.push_str(&format!("generated: {}\n", unix_secs()));
    report.push_str(&format!("version: {}\n", env!("CARGO_PKG_VERSION")));
    report.push_str(&format!("process: {}\n", std::process::id()));
    report.push_str(&format!("os: {}\n", std::env::consts::OS));
    report.push_str(&format!("arch: {}\n", std::env::consts::ARCH));
    report.push_str(&format!("directory: {}\n", dir.display()));
}

/// Every crash note on disk, newest first.
fn write_notes_section(report: &mut String, dir: &Path) {
    let mut notes = files_with_prefix(dir, NOTE_PREFIX);
    notes.sort();
    notes.reverse();

    report.push_str(&format!("\n===== crash notes ({}) =====\n", notes.len()));
    if notes.is_empty() {
        report.push_str("(none) — this report was generated without a recorded crash.\n");
    }
    for note in notes {
        report.push_str(&format!("\n----- {} -----\n", note.display()));
        append_file_lossy(report, &note);
    }
}

/// Every run marker, with whether its process is still alive.
fn write_markers_section(report: &mut String, dir: &Path) {
    let mut markers = files_with_prefix(dir, RUN_MARKER_PREFIX);

    report.push_str(&format!("\n===== run markers ({}) =====\n", markers.len()));
    if markers.is_empty() {
        report.push_str("(none)\n");
    }
    markers.sort();
    for marker in markers {
        let pid = marker
            .file_name()
            .and_then(|name| name.to_str())
            .and_then(|name| name.strip_prefix(RUN_MARKER_PREFIX))
            .and_then(|pid| pid.parse::<u32>().ok());
        let alive = pid.is_some_and(is_pid_alive);
        report.push_str(&format!(
            "\n----- {} (process alive: {alive}) -----\n",
            marker.display()
        ));
        append_file_lossy(report, &marker);
    }
}

/// The tail of the newest log files, up to [`LOG_TAIL_LIMIT`] bytes.
fn write_log_section(report: &mut String, logs_dir: Option<&Path>) {
    report.push_str("\n===== log tail =====\n");
    let Some(logs_dir) = logs_dir else {
        report.push_str("(no log directory on this platform)\n");
        return;
    };

    let mut files: Vec<PathBuf> = match fs::read_dir(logs_dir) {
        Ok(entries) => entries
            .flatten()
            .map(|entry| entry.path())
            .filter(|path| path.is_file())
            .collect(),
        Err(_) => Vec::new(),
    };
    // Newest first, so the byte budget goes to the records nearest the crash.
    files.sort_by_key(|path| {
        fs::metadata(path)
            .and_then(|meta| meta.modified())
            .unwrap_or(UNIX_EPOCH)
    });
    files.reverse();

    let mut chunks: Vec<String> = Vec::new();
    let mut budget = LOG_TAIL_LIMIT;
    for file in &files {
        if budget == 0 {
            break;
        }
        let Ok(contents) = fs::read(file) else {
            continue;
        };
        let take = usize::try_from(budget.min(contents.len() as u64)).unwrap_or(0);
        // A tail, not a head: the end of an old file is closer to the crash
        // than its beginning.
        let slice = &contents[contents.len() - take..];
        chunks.push(format!(
            "\n----- {} (last {} bytes) -----\n{}\n",
            file.display(),
            take,
            String::from_utf8_lossy(slice),
        ));
        budget -= take as u64;
    }

    if chunks.is_empty() {
        report.push_str("(no log files found)\n");
        return;
    }
    // Collected newest-first; print oldest-first so the section reads forward.
    chunks.reverse();
    for chunk in chunks {
        report.push_str(&chunk);
    }
}

/// All files in `dir` whose name starts with `prefix`.
fn files_with_prefix(dir: &Path, prefix: &str) -> Vec<PathBuf> {
    let Ok(entries) = fs::read_dir(dir) else {
        return Vec::new();
    };
    entries
        .flatten()
        .map(|entry| entry.path())
        .filter(|path| {
            path.file_name()
                .and_then(|name| name.to_str())
                .is_some_and(|name| name.starts_with(prefix))
        })
        .collect()
}

/// Appends a file's contents (best effort, lossy) to the report.
fn append_file_lossy(report: &mut String, path: &Path) {
    match fs::read(path) {
        Ok(bytes) => {
            report.push_str(&String::from_utf8_lossy(&bytes));
            report.push('\n');
        }
        Err(error) => report.push_str(&format!("<could not read: {error}>\n")),
    }
}

/// Whether a process with this pid exists.
///
/// Windows is the shipping target; the fallback errs towards "alive" so a live
/// process is never reported as a crash.
#[cfg(windows)]
fn is_pid_alive(pid: u32) -> bool {
    use windows_sys::Win32::Foundation::{CloseHandle, STILL_ACTIVE};
    use windows_sys::Win32::System::Threading::{
        GetExitCodeProcess, OpenProcess, PROCESS_QUERY_LIMITED_INFORMATION,
    };

    if pid == std::process::id() {
        return true;
    }
    // SAFETY: plain Win32 calls; the handle is closed on every path that opens
    // it, and the out-parameter is a local.
    unsafe {
        let handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid);
        if handle == 0 {
            return false;
        }
        let mut code = 0;
        let ok = GetExitCodeProcess(handle, &mut code);
        CloseHandle(handle);
        ok != 0 && code == STILL_ACTIVE as u32
    }
}

/// See the Windows implementation for the reasoning.
#[cfg(not(windows))]
fn is_pid_alive(pid: u32) -> bool {
    if pid == std::process::id() {
        return true;
    }
    let proc = Path::new("/proc");
    if proc.is_dir() {
        proc.join(pid.to_string()).exists()
    } else {
        true
    }
}

fn unix_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |since| since.as_secs())
}

/// Nanoseconds since the epoch, as the note filename's sort key.
///
/// Nanoseconds rather than milliseconds because one abort produces two panics
/// back to back — the original, then "a function that cannot unwind" — and at
/// millisecond resolution the second note silently replaced the first. The
/// cause is the one worth keeping.
fn unix_nanos() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |since| since.as_nanos())
}

/// The paragraph every report ends with, in the report itself rather than only
/// in the docs: whoever is about to send this file should read it there.
const PRIVACY_NOTE: &str = "\n===== what is in this file =====\n\
This report contains the log tail (which can include server addresses,\n\
nicknames and device names), the crash notes, and the run markers.\n\
It does not contain chat messages, identity keys or passwords.\n\
Review it before sharing it with anyone.\n";

#[cfg(test)]
mod tests {
    use super::*;

    /// A temporary crashes directory, cleaned up on drop. The pattern follows
    /// `ts-logging` and `ts-identity`.
    struct TempDir(PathBuf);

    impl TempDir {
        fn new(tag: &str) -> Self {
            let unique = format!(
                "nightcord-crash-{tag}-{}-{:?}",
                std::process::id(),
                std::thread::current().id()
            );
            let path = std::env::temp_dir().join(unique.replace(['(', ')', ' '], ""));
            let _ = fs::remove_dir_all(&path);
            fs::create_dir_all(&path).expect("create temp dir");
            Self(path)
        }

        fn store(&self) -> CrashStore {
            CrashStore::new(&self.0)
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    /// A pid that (almost certainly) does not exist.
    ///
    /// Windows pids are multiples of 4 below 2^32; `u32::MAX - 3` is one such
    /// value and is far above anything a test machine allocates.
    const DEAD_PID: u32 = u32::MAX - 3;

    #[test]
    fn a_fresh_run_is_not_abnormal() {
        let dir = TempDir::new("fresh");
        let store = dir.store();

        store.begin_run().unwrap();
        let status = store.status();

        assert!(!status.abnormal, "our own live marker is not evidence");
        assert_eq!(status.notes, 0);
        assert_eq!(status.directory, dir.0);
    }

    #[test]
    fn a_marker_left_by_a_dead_process_is_abnormal() {
        // The shape a hard kill leaves behind: the marker outlives its process.
        let dir = TempDir::new("dead");
        let store = dir.store();
        fs::create_dir_all(&dir.0).unwrap();
        fs::write(
            dir.0.join(format!("{RUN_MARKER_PREFIX}{DEAD_PID}")),
            "version=0.1.0\n",
        )
        .unwrap();

        let status = store.status();
        assert!(status.abnormal);
    }

    #[test]
    fn a_clean_exit_removes_the_marker() {
        let dir = TempDir::new("clean");
        let store = dir.store();
        store.begin_run().unwrap();

        store.mark_clean();

        let marker = dir
            .0
            .join(format!("{RUN_MARKER_PREFIX}{}", std::process::id()));
        assert!(!marker.exists());
        // And a new run still sees nothing to report.
        assert!(!store.status().abnormal);
    }

    #[test]
    fn notes_are_counted_and_do_not_make_a_run_abnormal() {
        // A note without a dead marker is possible (a worker panic in a still
        // running process); the count tells the banner there is something to
        // bundle, the marker decides whether this was an abnormal exit.
        let dir = TempDir::new("notes");
        let store = dir.store();
        fs::create_dir_all(&dir.0).unwrap();
        fs::write(
            dir.0.join("crash-0000000000001-1-panic.txt"),
            "kind: panic\n",
        )
        .unwrap();

        let status = store.status();
        assert_eq!(status.notes, 1);
        assert!(!status.abnormal);
    }

    #[test]
    fn a_panic_note_is_only_written_while_our_run_is_live() {
        // Without a marker: a test process (or a panic after a clean exit)
        // writes nothing into the directory it was pointed at.
        let dir = TempDir::new("nomarker");
        let store = dir.store();
        fs::create_dir_all(&dir.0).unwrap();

        let result = panic::catch_unwind(|| panic!("should not be recorded"));
        assert!(result.is_err());
        // install_handlers was never called here, so the note path is driven
        // through the same gate directly.
        assert!(!our_run_is_live(&dir.0));

        store.begin_run().unwrap();
        assert!(our_run_is_live(&dir.0));
        store.mark_clean();
        assert!(!our_run_is_live(&dir.0));
    }

    #[test]
    fn the_report_bundles_notes_markers_and_the_log_tail() {
        let dir = TempDir::new("report");
        let logs = TempDir::new("report-logs");
        let store = dir.store();
        store.begin_run().unwrap();
        fs::write(
            dir.0.join("crash-0000000000001-1-panic.txt"),
            "kind: panic\nmessage: boom\n",
        )
        .unwrap();
        fs::write(
            dir.0.join(format!("{RUN_MARKER_PREFIX}{DEAD_PID}")),
            "version=0.1.0\npid=would-be-dead\n",
        )
        .unwrap();
        fs::write(
            logs.0.join("nightcord.log.2026-09-30"),
            "log line one\nlog line two\n",
        )
        .unwrap();

        let path = store.write_report(Some(&logs.0)).unwrap();
        let report = fs::read_to_string(&path).unwrap();

        assert!(report.contains("Nightcord Speak crash report"), "{report}");
        assert!(report.contains("message: boom"), "{report}");
        assert!(report.contains("process alive: false"), "{report}");
        assert!(report.contains("log line two"), "{report}");
        assert!(
            report.contains("It does not contain chat messages"),
            "{report}"
        );
    }

    #[test]
    fn a_report_consumes_the_dead_markers_but_not_a_live_one() {
        let dir = TempDir::new("consume");
        let store = dir.store();
        store.begin_run().unwrap();
        fs::write(dir.0.join(format!("{RUN_MARKER_PREFIX}{DEAD_PID}")), "x\n").unwrap();

        store.write_report(None).unwrap();

        assert!(
            !dir.0
                .join(format!("{RUN_MARKER_PREFIX}{DEAD_PID}"))
                .exists()
        );
        // Our own marker belongs to this live process and stays.
        assert!(
            dir.0
                .join(format!("{RUN_MARKER_PREFIX}{}", std::process::id()))
                .exists()
        );
        assert!(!store.status().abnormal, "nothing dead is left to report");
    }

    #[test]
    fn the_log_tail_is_capped_and_keeps_the_end() {
        let dir = TempDir::new("captail");
        let logs = TempDir::new("captail-logs");
        let store = dir.store();
        fs::create_dir_all(&dir.0).unwrap();

        // Twice the cap, with a marker at the very end.
        let mut big = "x".repeat(LOG_TAIL_LIMIT as usize * 2);
        big.push_str("\nTHE LAST LINE\n");
        fs::write(logs.0.join("nightcord.log.2026-09-30"), &big).unwrap();

        let path = store.write_report(Some(&logs.0)).unwrap();
        let report = fs::read_to_string(&path).unwrap();

        assert!(report.contains("THE LAST LINE"), "the tail is what matters");
        assert!(
            report.len() < LOG_TAIL_LIMIT as usize + 4096,
            "the cap holds, header notwithstanding: {}",
            report.len()
        );
    }

    #[test]
    fn a_backtrace_carries_addresses_even_without_symbols() {
        // The address is the load-bearing part of a crash note: symbols need a
        // PDB the crashing machine usually lacks. An earlier version printed
        // only names and lost the addresses entirely.
        let text = format_backtrace();
        assert!(text.contains("0x"), "no address in:\n{text}");
        assert!(!text.is_empty());
    }

    #[test]
    fn two_notes_in_the_same_instant_do_not_overwrite_each_other() {
        // One abort produces two panics back to back — the original, then "a
        // function that cannot unwind". With a millisecond-resolution name the
        // second silently replaced the first, and the cause was the one lost.
        let dir = TempDir::new("notecollision");
        let store = dir.store();
        store.begin_run().unwrap();

        write_note(store.path(), "panic", "first");
        write_note(store.path(), "panic", "second");

        let notes = files_with_prefix(store.path(), NOTE_PREFIX);
        assert_eq!(notes.len(), 2, "{notes:?}");
    }

    #[test]
    fn report_markers_are_annotated_with_liveness() {
        let dir = TempDir::new("liveness");
        let store = dir.store();
        store.begin_run().unwrap();

        let path = store.write_report(None).unwrap();
        let report = fs::read_to_string(&path).unwrap();

        assert!(report.contains("process alive: true"), "{report}");
    }
}
