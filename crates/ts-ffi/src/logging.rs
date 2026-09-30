//! Where the log files live.
//!
//! The subscriber itself belongs to `ts-logging`, which knows nothing about
//! this application. What is decided here is the one thing that is ours: which
//! directory under the platform's application data root the files go in.

use std::ffi::OsString;
use std::path::PathBuf;

use ts_identity::app_data_root;

/// Environment variable overriding the log directory.
///
/// Exists so a machine whose profile is not writable — or a test that must not
/// litter the developer's `%APPDATA%` — can redirect the files. Setting it to
/// an **empty** value means "no file at all, stderr only", which is the only
/// way to ask for that.
pub const DIR_VAR: &str = "NIGHTCORD_LOG_DIR";

/// Subdirectory of the application data root holding the log files.
const LOG_DIR: &str = "logs";

/// The directory logs belong in, if this platform has one.
///
/// Returns `None` on Android and iOS, whose sandbox path only the host
/// application knows — the same limitation identity storage has, and it is
/// resolved the same way: the host passes the path in.
#[must_use]
pub fn desired_dir() -> Option<PathBuf> {
    dir_from(std::env::var_os(DIR_VAR), app_data_root())
}

/// [`desired_dir`] with both inputs passed in.
///
/// The environment and the platform root are parameters so that all three cases
/// can be tested. Reading them here instead would leave the tests mutating
/// process-wide state — `std::env::set_var` is `unsafe` for exactly that
/// reason — or silently skipping themselves when the variable happens to be
/// set on the machine running them.
fn dir_from(override_value: Option<OsString>, root: Option<PathBuf>) -> Option<PathBuf> {
    match override_value {
        // Set but empty: an explicit "do not write a file".
        Some(value) if value.is_empty() => None,
        Some(value) => Some(PathBuf::from(value)),
        None => root.map(|root| root.join(LOG_DIR)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn with_nothing_set_the_logs_sit_beside_the_identity_directory() {
        // Both hang off the same application root, which is the whole reason
        // `app_data_root` is exported rather than each caller guessing at the
        // platform's conventions.
        let root = PathBuf::from("/somewhere/nightcord-speak");
        assert_eq!(dir_from(None, Some(root.clone())), Some(root.join(LOG_DIR)));
    }

    #[test]
    fn the_override_wins_over_the_platform_root() {
        assert_eq!(
            dir_from(
                Some(OsString::from("/tmp/logs")),
                Some(PathBuf::from("/root"))
            ),
            Some(PathBuf::from("/tmp/logs"))
        );
    }

    #[test]
    fn an_empty_override_asks_for_no_file() {
        // The only way to say "stderr only" — as distinct from leaving the
        // variable unset, which means "wherever you would normally write".
        assert_eq!(
            dir_from(Some(OsString::new()), Some(PathBuf::from("/root"))),
            None
        );
    }

    #[test]
    fn a_platform_with_no_root_has_nowhere_to_write() {
        // Android and iOS: the host application has to supply the path.
        assert_eq!(dir_from(None, None), None);
    }
}
