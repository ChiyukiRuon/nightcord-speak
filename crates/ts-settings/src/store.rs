//! Reading and writing one JSON document, atomically.
//!
//! Shared by both stores in this crate rather than written twice: the write path
//! is the part that loses user data when it is wrong, and two copies of it drift
//! in exactly the situation nobody tests — a save interrupted halfway.

use std::path::Path;
use std::{fs, io};

use serde::Serialize;
use serde::de::DeserializeOwned;
use ts_model::SettingsError;

/// Reads a document, or `None` when there is no file yet.
///
/// Absence is returned rather than an error because only the caller knows what
/// it means: for settings it is the first run and the defaults apply, for saved
/// servers it is an empty address book.
///
/// # Errors
///
/// Returns [`SettingsError::Malformed`] if the file exists but cannot be parsed.
/// It is deliberately *not* reported as absence — a caller that wants to fall
/// back can still do so, but it can also say what happened.
pub(crate) fn read_json<T: DeserializeOwned>(path: &Path) -> Result<Option<T>, SettingsError> {
    let bytes = match fs::read(path) {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(io_error(error)),
    };

    serde_json::from_slice(&bytes)
        .map(Some)
        .map_err(|error| SettingsError::Malformed {
            message: format!("{}: {error}", path.display()),
        })
}

/// Writes a document, replacing whatever was there.
///
/// Written beside the target and renamed, so an interrupted save cannot leave a
/// truncated file where a working one used to be. Both files here are read back
/// on the next start, so that would otherwise be a silent reset to defaults — or
/// a lost address book.
///
/// # Errors
///
/// Returns [`SettingsError::Io`] if the directory cannot be created or the file
/// cannot be written.
pub(crate) fn write_json<T: Serialize>(path: &Path, value: &T) -> Result<(), SettingsError> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(io_error)?;
    }

    let json = serde_json::to_vec_pretty(value).map_err(|error| SettingsError::Malformed {
        message: format!("{}: {error}", path.display()),
    })?;

    let temp = path.with_extension("json.tmp");
    fs::write(&temp, &json).map_err(io_error)?;
    restrict_permissions(&temp)?;
    fs::rename(&temp, path).map_err(io_error)?;

    Ok(())
}

pub(crate) fn io_error(source: io::Error) -> SettingsError {
    SettingsError::Io {
        message: source.to_string(),
    }
}

/// Restricts a file to its owner.
///
/// `servers.json` holds server passwords, so this one matters; `settings.json`
/// holds nothing secret but is treated the same way, because the two sit beside
/// a private key and loosening the habit later is how the key ends up readable.
#[cfg(unix)]
fn restrict_permissions(path: &Path) -> Result<(), SettingsError> {
    use std::os::unix::fs::PermissionsExt as _;
    fs::set_permissions(path, fs::Permissions::from_mode(0o600)).map_err(io_error)
}

/// No-op on Windows, where files inherit the profile's user-only ACL.
#[cfg(not(unix))]
fn restrict_permissions(_path: &Path) -> Result<(), SettingsError> {
    Ok(())
}
