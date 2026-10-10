//! # ts-logging
//!
//! The one place that installs a process-wide `tracing` subscriber.
//!
//! Every crate in the workspace already emits `tracing` events. Without a
//! subscriber those events are **discarded**, which is how a failure could
//! reach the user as a snack bar and leave nothing behind to read afterwards —
//! the snack bar disappears after a few seconds and takes the only copy of the
//! evidence with it. This crate decides where the events actually go.
//!
//! Two properties matter more than the rest:
//!
//! * **Writing is non-blocking and lossy.** Some records are emitted from the
//!   cpal audio callback (`ts-audio`'s "capture is ahead of the engine" is
//!   one). Blocking that thread on a disk write is a real-time hazard:
//!   priority inversion, then xruns, which produce *more* log lines. Records
//!   are handed to a writer thread through a bounded channel and dropped when
//!   it is full — losing a line beats dropping audio.
//! * **Nothing here can fail the process.** A log file that cannot be opened
//!   falls back to stderr; an unparseable filter falls back to the default.
//!   Being unable to write a log is a smaller problem than being unable to
//!   start.
//!
//! The directory is a parameter rather than something this crate discovers, so
//! it stays a leaf: it depends on no other crate in the workspace, and any
//! front-end — the Flutter app, the CLI, a future gateway — can reuse it.

use std::path::{Path, PathBuf};
use std::sync::OnceLock;

use tracing_appender::non_blocking::{NonBlockingBuilder, WorkerGuard};
use tracing_subscriber::EnvFilter;
use tracing_subscriber::fmt::Subscriber;

mod local_time;
use local_time::{LocalDailyWriter, LocalTimer};

/// Environment variable holding the filter, e.g. `debug` or
/// `ts_protocol_tsclient=trace`.
pub const FILTER_VAR: &str = "NIGHTCORD_LOG";

/// Environment variable overriding the log directory. Setting it to an empty
/// string means "stderr only, no file".
pub const DIR_VAR: &str = "NIGHTCORD_LOG_DIR";

/// The filter used when the environment says nothing.
///
/// The vendored protocol crates log per packet. `tsclientlib` writes an `info`
/// line for *every* audio packet that arrives while the user is deafened —
/// twenty milliseconds apart — so leaving them at their own default would bury
/// our own lines under a stream of noise. A terminal can be skimmed past that;
/// a file cannot be searched through it.
pub const DEFAULT_FILTER: &str =
    "info,tsclientlib=warn,tsproto=warn,tsproto_packets=warn,ts_bookkeeping=warn";

/// How many daily files to keep before the oldest is removed.
///
/// Bounded on purpose: a log that grows without limit eventually becomes the
/// user's problem, and the useful part of it is always the recent end.
const KEEP_FILES: usize = 7;

/// The file name logs are written under: `nightcord.2026-09-30.log`.
///
/// The date follows the device's timezone, with `.log` kept as the extension
/// so file managers and log viewers recognise the file type.
const FILE_STEM: &str = "nightcord";
/// See [`FILE_STEM`].
const FILE_EXTENSION: &str = "log";

/// Where log records ended up.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Sink {
    /// Rotating files in this directory.
    File(PathBuf),
    /// The standard error stream, because no usable directory was available.
    Stderr,
}

impl Sink {
    /// The directory logs are being written to, if any.
    #[must_use]
    pub fn directory(&self) -> Option<&Path> {
        match self {
            Self::File(dir) => Some(dir),
            Self::Stderr => None,
        }
    }
}

/// The filter to build the subscriber with.
///
/// Precedence is [`FILTER_VAR`], then `RUST_LOG` — the name a Rust developer
/// reaches for first — then [`DEFAULT_FILTER`].
///
/// A malformed value is reported on stderr and then ignored. Falling back is
/// deliberate: `init` is normally called before anything else exists, so
/// refusing to start logging over a typo in an environment variable would
/// leave the user with nothing at all.
#[must_use]
pub fn env_filter() -> EnvFilter {
    env_filter_from(|name| std::env::var(name).ok())
}

/// [`env_filter`] with the environment passed in.
///
/// The lookup is a parameter because tests cannot vary the real environment:
/// `std::env::set_var` is `unsafe` in edition 2024 precisely because it races
/// every other thread that reads the environment, which a parallel test runner
/// has plenty of.
#[must_use]
pub fn env_filter_from(lookup: impl Fn(&str) -> Option<String>) -> EnvFilter {
    for name in [FILTER_VAR, "RUST_LOG"] {
        let Some(value) = lookup(name) else { continue };
        if value.trim().is_empty() {
            continue;
        }
        match EnvFilter::try_new(&value) {
            Ok(filter) => return filter,
            // Nothing is installed yet, so this is the only channel left to
            // say so on. Staying quiet would leave the user staring at a log
            // that is mysteriously less detailed than they asked for.
            Err(error) => eprintln!("nightcord: ignoring {name}={value:?}: {error}"),
        }
    }
    EnvFilter::new(DEFAULT_FILTER)
}

/// Installs the process-wide subscriber, preferring `dir` for the files.
///
/// Returns where records will go. Never fails, and never panics: with no usable
/// directory, or when a subscriber is already installed, it reports what
/// happened and lets the caller carry on.
///
/// **The first call wins.** `tracing` allows exactly one global subscriber per
/// process, so later calls are no-ops that report the existing choice back.
///
/// # The guard, and what is knowingly given up
///
/// The `WorkerGuard` returned by `non_blocking` is parked in a `static` rather
/// than returned to the caller. If it were dropped, the writer thread would stop
/// and everything still queued would be lost — and the caller has no reason to
/// keep such a value alive, so it is not their job.
///
/// The cost is that Rust does not drop `static`s at exit, so the writer thread
/// is never joined and a record still in the queue when the process ends is
/// lost. That is bounded and small: the worker flushes after draining each
/// batch, so the window is one batch wide. The alternative — hanging the guard
/// off a front-end object — would stop logging the moment that object is torn
/// down, which for a subscriber that is global by construction would be worse.
pub fn init(dir: Option<&Path>) -> Sink {
    static GUARD: OnceLock<WorkerGuard> = OnceLock::new();
    static INSTALLED: OnceLock<Sink> = OnceLock::new();

    if let Some(sink) = INSTALLED.get() {
        return sink.clone();
    }

    let file = dir.and_then(|dir| match build_file(dir, env_filter()) {
        Ok((dispatch, guard)) => match tracing::subscriber::set_global_default(dispatch) {
            Ok(()) => {
                let _ = GUARD.set(guard);
                Some(Sink::File(dir.to_path_buf()))
            }
            Err(error) => {
                eprintln!("nightcord: another log subscriber is already installed: {error}");
                None
            }
        },
        Err(error) => {
            eprintln!("nightcord: could not open {}: {error}", dir.display());
            None
        }
    });

    let sink = file.unwrap_or_else(|| {
        let subscriber = tracing_subscriber::fmt()
            .with_env_filter(env_filter())
            .with_timer(LocalTimer)
            .finish();
        // A failure here means something installed a subscriber between the two
        // attempts. That subscriber is logging, which is what was wanted, so
        // the error is not worth reporting.
        let _ = tracing::subscriber::set_global_default(subscriber);
        Sink::Stderr
    });

    // `get_or_init` rather than `set`: two threads racing to be first both get
    // a correct answer, and the loser's subscriber was already rejected by
    // `set_global_default`.
    INSTALLED.get_or_init(|| sink).clone()
}

/// A subscriber ready to install.
///
/// Boxed rather than named: the concrete type carries the writer, the filter
/// and the formatting layers, and nothing here cares what it is — only that it
/// can be installed or scoped over a block of test code.
type BoxedSubscriber = Box<dyn tracing::Subscriber + Send + Sync>;

/// Builds a file-backed subscriber and the guard that keeps it flushing.
///
/// The filter is a parameter rather than read from the environment here so a
/// test can install a known one; `init` passes [`env_filter`].
///
/// The directory is created if it is missing; filesystem errors are returned
/// so the caller can keep logging to stderr.
fn build_file(
    dir: &Path,
    filter: EnvFilter,
) -> Result<(BoxedSubscriber, WorkerGuard), Box<dyn std::error::Error + Send + Sync>> {
    let appender = LocalDailyWriter::new(dir)?;

    // `lossy(true)` is the default, but it is the whole reason this crate can
    // be called from an audio callback, so it is spelled out rather than
    // inherited from a default that could change.
    let (writer, guard) = NonBlockingBuilder::default().lossy(true).finish(appender);

    let subscriber = Subscriber::builder()
        // A file is read on its own, away from a terminal that would render
        // them: escape codes here are noise in whatever opens it.
        .with_ansi(false)
        .with_timer(LocalTimer)
        .with_env_filter(filter)
        .with_writer(writer)
        .finish();

    Ok((Box::new(subscriber), guard))
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::io;

    use tracing::Level;

    use super::*;

    /// A directory that cleans itself up, so tests can run in parallel.
    pub(super) struct TempDir(PathBuf);

    impl TempDir {
        pub(super) fn new(tag: &str) -> Self {
            let unique = format!(
                "nightcord-logging-{tag}-{}-{:?}",
                std::process::id(),
                std::thread::current().id()
            );
            let path = std::env::temp_dir().join(unique.replace(['(', ')', ' '], ""));
            let _ = fs::remove_dir_all(&path);
            fs::create_dir_all(&path).expect("create temp dir");
            Self(path)
        }

        pub(super) fn path(&self) -> &Path {
            &self.0
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    /// A subscriber that writes nowhere, for asking filter questions.
    fn silent(filter: EnvFilter) -> impl tracing::Subscriber + Send + Sync {
        Subscriber::builder()
            .with_env_filter(filter)
            .with_writer(io::sink)
            .finish()
    }

    /// The single file a daily-rotated appender created under `dir`.
    ///
    /// Found by listing rather than by rebuilding the name: the suffix is a
    /// date, and a test that hard-codes today's would fail at midnight.
    fn only_log_file(dir: &Path) -> String {
        let entries: Vec<PathBuf> = fs::read_dir(dir)
            .expect("read the log directory")
            .map(|entry| entry.expect("a directory entry").path())
            .collect();
        assert_eq!(
            entries.len(),
            1,
            "expected exactly one log file: {entries:?}"
        );
        fs::read_to_string(&entries[0]).expect("read the log file")
    }

    #[test]
    fn a_record_reaches_the_log_file() {
        // The point of the whole crate: a `tracing` call lands somewhere that
        // survives the process.
        let dir = TempDir::new("writes");
        let before = time::OffsetDateTime::now_local().expect("device timezone available");
        let (dispatch, guard) =
            build_file(dir.path(), EnvFilter::new("info")).expect("open the log file");

        tracing::subscriber::with_default(dispatch, || {
            tracing::error!(permission = 218, "could not join the channel");
        });

        // Dropping the guard flushes the writer thread, which is what makes
        // this deterministic rather than a race against it.
        drop(guard);

        let written = only_log_file(dir.path());
        let timestamp = time::OffsetDateTime::parse(
            written.split_whitespace().next().expect("a timestamp"),
            &time::format_description::well_known::Rfc3339,
        )
        .expect("timestamp includes the timezone offset");
        let after = time::OffsetDateTime::now_local().expect("device timezone available");
        assert!(timestamp.offset() == before.offset() || timestamp.offset() == after.offset());
        assert!(timestamp >= before && timestamp <= after);
        assert!(
            written.contains("could not join the channel"),
            "got {written}"
        );
        assert!(written.contains("permission=218"), "got {written}");
    }

    #[test]
    fn the_log_file_name_ends_in_log() {
        // Regression: the appender puts the date *after* its prefix, so a
        // prefix of `nightcord.log` produced `nightcord.log.2026-09-30`. The
        // date became the extension and the file was extensionless — which is
        // what a file manager, an "open with" dialog and every log viewer treat
        // as an unknown type.
        let dir = TempDir::new("name");
        let (dispatch, guard) =
            build_file(dir.path(), EnvFilter::new("info")).expect("open the log file");
        drop(dispatch);
        drop(guard);

        let name = fs::read_dir(dir.path())
            .expect("read the log directory")
            .next()
            .expect("one log file")
            .expect("a directory entry")
            .file_name()
            .to_string_lossy()
            .into_owned();

        assert!(name.starts_with("nightcord."), "got {name}");
        assert!(name.ends_with(".log"), "got {name}");
    }

    #[test]
    fn the_log_file_carries_no_terminal_escape_codes() {
        // It is read in a text editor, not on a terminal, so colour would show
        // up as literal noise.
        let dir = TempDir::new("ansi");
        let (dispatch, guard) =
            build_file(dir.path(), EnvFilter::new("info")).expect("open the log file");

        tracing::subscriber::with_default(dispatch, || tracing::info!("plain text"));
        drop(guard);

        let written = only_log_file(dir.path());
        assert!(!written.contains('\u{1b}'), "got escape codes: {written:?}");
    }

    #[test]
    fn a_directory_that_cannot_be_created_is_an_error_not_a_panic() {
        // A file where the directory should be: `create_dir_all` cannot win,
        // and the caller has to be able to fall back rather than crash.
        let dir = TempDir::new("unusable");
        let blocker = dir.path().join("blocker");
        fs::write(&blocker, b"not a directory").unwrap();

        let outcome = build_file(&blocker.join("logs"), EnvFilter::new("info"));
        assert!(outcome.is_err(), "expected an error, got a subscriber");
    }

    #[test]
    fn the_default_filter_silences_the_vendored_protocol_crates() {
        // Per-packet lines from tsclientlib would bury our own records — see
        // the note on `DEFAULT_FILTER`.
        let filter = EnvFilter::new(DEFAULT_FILTER);

        tracing::subscriber::with_default(silent(filter), || {
            assert!(
                tracing::enabled!(target: "ts_protocol_tsclient", Level::INFO),
                "our own crates must be heard at info"
            );
            assert!(
                !tracing::enabled!(target: "tsclientlib", Level::INFO),
                "the vendored crates must stay quiet at info"
            );
            assert!(
                tracing::enabled!(target: "tsclientlib", Level::WARN),
                "but their warnings must still come through"
            );
        });
    }

    #[test]
    fn our_variable_wins_over_rust_log() {
        let filter = env_filter_from(|name| match name {
            FILTER_VAR => Some("warn".to_string()),
            "RUST_LOG" => Some("trace".to_string()),
            _ => None,
        });

        tracing::subscriber::with_default(silent(filter), || {
            assert!(
                !tracing::enabled!(Level::DEBUG),
                "RUST_LOG won, it should not"
            );
            assert!(tracing::enabled!(Level::WARN));
        });
    }

    #[test]
    fn rust_log_applies_when_our_variable_is_absent() {
        let filter = env_filter_from(|name| match name {
            "RUST_LOG" => Some("error".to_string()),
            _ => None,
        });

        tracing::subscriber::with_default(silent(filter), || {
            assert!(!tracing::enabled!(Level::WARN));
            assert!(tracing::enabled!(Level::ERROR));
        });
    }

    #[test]
    fn an_empty_value_is_treated_as_unset() {
        // An unset-but-present variable is common in scripts; it must not be
        // parsed as a filter that matches nothing.
        let filter = env_filter_from(|name| match name {
            FILTER_VAR => Some("   ".to_string()),
            _ => None,
        });

        tracing::subscriber::with_default(silent(filter), || {
            assert!(
                tracing::enabled!(Level::INFO),
                "the default should have applied"
            );
        });
    }

    #[test]
    fn the_default_applies_when_the_environment_says_nothing() {
        let filter = env_filter_from(|_| None);

        tracing::subscriber::with_default(silent(filter), || {
            assert!(tracing::enabled!(Level::INFO));
            assert!(!tracing::enabled!(Level::DEBUG));
        });
    }

    #[test]
    fn a_malformed_filter_falls_back_instead_of_panicking() {
        // The user gets a usable log at the default level rather than no log
        // at all; the complaint goes to stderr.
        let filter = env_filter_from(|_| Some("!!! not a filter !!!".to_string()));

        tracing::subscriber::with_default(silent(filter), || {
            assert!(
                tracing::enabled!(Level::INFO),
                "the default should have applied"
            );
        });
    }

    #[test]
    fn init_is_idempotent() {
        // `tracing` allows one global subscriber, so a second call has to be a
        // no-op that agrees with the first rather than a panic or a replacement.
        let first = init(None);
        let second = init(None);

        assert_eq!(first, second);
        assert_eq!(first, Sink::Stderr, "no directory was offered");
    }
}
