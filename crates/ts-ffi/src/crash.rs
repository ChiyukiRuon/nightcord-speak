//! Process-level crash hooks: where the evidence lives, when a run begins and
//! ends, and the answers the front-end asks for.
//!
//! Everything here works **without the core**. That is not a simplification —
//! it is the requirement: the moment the answers matter is the moment the
//! worker is dead or never started, and a command-driven interface would be
//! exactly the one that cannot answer.

use serde_json::json;
use ts_crash::CrashStore;

/// Overrides the crash directory, mirroring `NIGHTCORD_LOG_DIR`: a machine
/// whose profile is not writable, or a test that must not litter the
/// developer's `%APPDATA%`, can redirect the files.
pub(crate) const DIR_VAR: &str = "NIGHTCORD_CRASH_DIR";

/// The store this process reports into, or `None` on platforms without an
/// application data directory (Android, iOS).
///
/// `NIGHTCORD_CRASH_DIR`, when set, **is** the crashes directory — the same
/// arrangement as `NIGHTCORD_LOG_DIR`, which is the logs directory. Without it
/// the crash evidence sits next to `logs/` under the application data root.
/// (The log helper cannot be reused for this: it appends `logs` on the way.)
pub(crate) fn store() -> Option<CrashStore> {
    if let Some(value) = std::env::var_os(DIR_VAR) {
        return if value.is_empty() {
            None
        } else {
            Some(CrashStore::new(value))
        };
    }
    ts_identity::app_data_root().map(|root| CrashStore::new(root.join(ts_crash::DIR_NAME)))
}

/// Begins a run: installs the crash handlers and writes this process's marker.
///
/// Called from `nightcord_create`. A failure is logged but never fatal — a run
/// without a marker simply cannot be reported as abnormal later.
pub(crate) fn begin() {
    let Some(store) = store() else { return };
    store.install_handlers();
    if let Err(error) = store.begin_run() {
        tracing::warn!(%error, "could not write the run marker; crashes will not be reported");
    }
}

/// Removes this run's marker: a clean exit.
pub(crate) fn mark_clean() {
    if let Some(store) = store() {
        store.mark_clean();
    }
}

/// What the last runs left behind, as JSON.
#[must_use]
pub(crate) fn status_json() -> String {
    let Some(store) = store() else {
        return json!({ "available": false }).to_string();
    };
    let status = store.status();
    json!({
        "available": true,
        "abnormal": status.abnormal,
        "notes": status.notes,
        "directory": status.directory.display().to_string(),
    })
    .to_string()
}

/// Builds the report and answers with its path (or the reason it could not be
/// built), as JSON.
#[must_use]
pub(crate) fn report_json() -> String {
    let Some(store) = store() else {
        return json!({ "error": "no crash directory on this platform" }).to_string();
    };
    match store.write_report(crate::logging::desired_dir().as_deref()) {
        Ok(path) => json!({ "path": path.display().to_string() }).to_string(),
        Err(error) => json!({ "error": error.to_string() }).to_string(),
    }
}
