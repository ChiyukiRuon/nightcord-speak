//! # ts-identity
//!
//! Persistent client identity (§31, §32, §36).
//!
//! A TeamSpeak identity is a key pair, and a server uses it to recognise a
//! returning user. Regenerating it makes the server see a brand-new client,
//! which loses the user's permissions — so development doc §36 requires that
//! reconnecting *always* reuses the stored identity, and that is why
//! [`IdentityStore::load_or_create`] only generates when nothing is on disk.
//!
//! This crate owns the *lifecycle and storage* of an identity but not the
//! cryptography: generating a key pair is the protocol backend's job, and it
//! hands the result here. That keeps the storage honest about what it can
//! guarantee, and keeps this crate free of any protocol dependency.

use std::path::{Path, PathBuf};
use std::{fmt, fs, io};

use base64::Engine as _;
use serde::{Deserialize, Serialize};
use ts_model::IdentityError;

/// Directory name for per-user application data on Windows and macOS (§32).
const APP_DIR_DISPLAY_NAME: &str = "Nightcord Speak";
/// Directory name on Linux, where lower-case XDG-style names are the norm.
/// Declared only where it is used, so the other targets do not warn about it.
#[cfg(not(any(
    target_os = "windows",
    target_os = "macos",
    target_os = "android",
    target_os = "ios"
)))]
const APP_DIR_XDG_NAME: &str = "nightcord-speak";
/// Subdirectory holding identity files.
const IDENTITY_DIR: &str = "identity";
/// On-disk format version, so the layout can change without guesswork.
const FILE_VERSION: u32 = 1;
/// Longest accepted profile name.
const MAX_NAME_LEN: usize = 64;

/// A TeamSpeak client identity.
///
/// This holds a private key, so it is deliberately **not** `Serialize` and its
/// [`fmt::Debug`] output is redacted: the blob must never reach a front-end or
/// a log line (§44). Persist it through [`IdentityStore`].
#[derive(Clone, PartialEq, Eq)]
pub struct Identity {
    /// Stable public id derived from the key pair. Safe to display.
    pub unique_id: String,
    /// The serialised private identity. **Secret.**
    pub identity_blob: Vec<u8>,
}

impl Identity {
    /// Wraps an already-generated key pair.
    #[must_use]
    pub fn new(unique_id: impl Into<String>, identity_blob: Vec<u8>) -> Self {
        Self {
            unique_id: unique_id.into(),
            identity_blob,
        }
    }

    /// Whether the blob is empty, which means the caller built this wrong.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.identity_blob.is_empty()
    }
}

impl fmt::Debug for Identity {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        // Redacted on purpose: a stray `tracing::debug!("{identity:?}")` must
        // not be able to leak the private key.
        f.debug_struct("Identity")
            .field("unique_id", &self.unique_id)
            .field(
                "identity_blob",
                &format_args!("<{} bytes redacted>", self.identity_blob.len()),
            )
            .finish()
    }
}

/// On-disk representation. The blob is base64 so the file stays text and can be
/// hand-inspected without a binary editor.
#[derive(Debug, Serialize, Deserialize)]
struct StoredIdentity {
    version: u32,
    unique_id: String,
    identity: String,
}

/// Reads and writes identities under one directory.
///
/// The root is explicit rather than implicit so that mobile hosts — which know
/// their own sandbox path and nothing else — can supply it, and so tests can
/// point at a temporary directory.
#[derive(Debug, Clone)]
pub struct IdentityStore {
    root: PathBuf,
}

impl IdentityStore {
    /// A store rooted at `root`.
    #[must_use]
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    /// The store for the current platform's application data directory (§32).
    ///
    /// # Errors
    ///
    /// Returns [`IdentityError::NoStorageRoot`] on platforms where the host
    /// application must supply the path itself — currently Android and iOS,
    /// where the sandbox location is only known to the app.
    pub fn platform_default() -> Result<Self, IdentityError> {
        Ok(Self::new(
            app_data_root()
                .ok_or(IdentityError::NoStorageRoot)?
                .join(IDENTITY_DIR),
        ))
    }

    /// The directory identities are stored in.
    #[must_use]
    pub fn root(&self) -> &Path {
        &self.root
    }

    /// The file a profile is stored in.
    #[must_use]
    pub fn path_for(&self, name: &str) -> PathBuf {
        self.root.join(format!("{name}.identity"))
    }

    /// Reads a stored identity, or `None` if the profile does not exist yet.
    ///
    /// # Errors
    ///
    /// Returns [`IdentityError::Malformed`] if the file exists but cannot be
    /// parsed. That is deliberately *not* treated as "no identity": reading
    /// damage as absence would silently mint a new client.
    pub fn load(&self, name: &str) -> Result<Option<Identity>, IdentityError> {
        let name = validate_name(name)?;
        let path = self.path_for(name);

        let bytes = match fs::read(&path) {
            Ok(bytes) => bytes,
            Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(None),
            Err(e) => return Err(io_error(e)),
        };

        let stored: StoredIdentity =
            serde_json::from_slice(&bytes).map_err(|e| IdentityError::Malformed {
                message: e.to_string(),
            })?;

        if stored.version != FILE_VERSION {
            return Err(IdentityError::Malformed {
                message: format!(
                    "unsupported identity file version {}, expected {FILE_VERSION}",
                    stored.version
                ),
            });
        }

        let blob = base64::engine::general_purpose::STANDARD
            .decode(stored.identity.as_bytes())
            .map_err(|e| IdentityError::Malformed {
                message: format!("identity is not valid base64: {e}"),
            })?;

        Ok(Some(Identity::new(stored.unique_id, blob)))
    }

    /// Writes an identity, replacing any existing one.
    ///
    /// # Errors
    ///
    /// Returns [`IdentityError::Io`] if the directory cannot be created or the
    /// file cannot be written.
    pub fn save(&self, name: &str, identity: &Identity) -> Result<(), IdentityError> {
        let name = validate_name(name)?;
        fs::create_dir_all(&self.root).map_err(io_error)?;

        let stored = StoredIdentity {
            version: FILE_VERSION,
            unique_id: identity.unique_id.clone(),
            identity: base64::engine::general_purpose::STANDARD.encode(&identity.identity_blob),
        };
        let json = serde_json::to_vec_pretty(&stored).map_err(|e| IdentityError::Malformed {
            message: e.to_string(),
        })?;

        // Write beside the target and rename, so an interrupted save cannot
        // leave a truncated key where a valid one used to be.
        let path = self.path_for(name);
        let temp = path.with_extension("identity.tmp");
        fs::write(&temp, &json).map_err(io_error)?;
        restrict_permissions(&temp)?;
        fs::rename(&temp, &path).map_err(io_error)?;

        tracing::info!(profile = name, "stored client identity");
        Ok(())
    }

    /// Returns the stored identity, generating and saving one only if absent.
    ///
    /// This is the function reconnects must go through (§36).
    ///
    /// # Errors
    ///
    /// Propagates storage failures, and whatever `generate` returns.
    pub fn load_or_create<F>(&self, name: &str, generate: F) -> Result<Identity, IdentityError>
    where
        F: FnOnce() -> Result<Identity, IdentityError>,
    {
        if let Some(existing) = self.load(name)? {
            tracing::debug!(profile = name, "reusing stored client identity");
            return Ok(existing);
        }

        tracing::info!(profile = name, "generating a new client identity");
        let identity = generate()?;
        self.save(name, &identity)?;
        Ok(identity)
    }
}

/// Rejects names that would escape the store or collide with the file suffix.
fn validate_name(name: &str) -> Result<&str, IdentityError> {
    let trimmed = name.trim();
    let acceptable = !trimmed.is_empty()
        && trimmed.len() <= MAX_NAME_LEN
        && trimmed
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_');

    if acceptable {
        Ok(trimmed)
    } else {
        // Rejecting `.`, `/` and `\` keeps `../` out of the path; rejecting
        // everything else non-alphanumeric keeps file handling predictable.
        Err(IdentityError::InvalidName {
            name: name.to_string(),
        })
    }
}

fn io_error(source: io::Error) -> IdentityError {
    IdentityError::Io {
        message: source.to_string(),
    }
}

/// Restricts an identity file to its owner.
#[cfg(unix)]
fn restrict_permissions(path: &Path) -> Result<(), IdentityError> {
    use std::os::unix::fs::PermissionsExt as _;
    fs::set_permissions(path, fs::Permissions::from_mode(0o600)).map_err(io_error)
}

/// No-op on Windows, where files inherit the profile's user-only ACL.
#[cfg(not(unix))]
fn restrict_permissions(_path: &Path) -> Result<(), IdentityError> {
    Ok(())
}

/// The per-user directory this application keeps all of its state in (§32).
///
/// Identity storage was the first tenant and still shapes this function —
/// `identity/` is what [`IdentityStore::platform_default`] appends — but the
/// directory belongs to the *application*, not to identities: logs live beside
/// it, and settings and bookmarks will follow. Exporting it keeps one
/// definition of where that is, so porting to another platform cannot leave a
/// second caller behind.
///
/// Returns `None` where the path is only knowable by the host application:
/// Android and iOS, whose sandboxes the OS hands to the app rather than
/// announcing in the environment.
#[cfg(target_os = "windows")]
#[must_use]
pub fn app_data_root() -> Option<PathBuf> {
    std::env::var_os("APPDATA").map(|base| PathBuf::from(base).join(APP_DIR_DISPLAY_NAME))
}

/// See the Windows definition above.
#[cfg(target_os = "macos")]
#[must_use]
pub fn app_data_root() -> Option<PathBuf> {
    std::env::var_os("HOME").map(|home| {
        PathBuf::from(home)
            .join("Library")
            .join("Application Support")
            .join(APP_DIR_DISPLAY_NAME)
    })
}

/// See the Windows definition above.
#[cfg(not(any(
    target_os = "windows",
    target_os = "macos",
    target_os = "android",
    target_os = "ios"
)))]
#[must_use]
pub fn app_data_root() -> Option<PathBuf> {
    std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".config")))
        .map(|base| base.join(APP_DIR_XDG_NAME))
}

/// Report no root on mobile: the sandbox path is only known to the host app, so
/// it must call [`IdentityStore::new`] with the path it was given.
#[cfg(any(target_os = "android", target_os = "ios"))]
#[must_use]
pub fn app_data_root() -> Option<PathBuf> {
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A directory that cleans itself up, so tests can run in parallel.
    struct TempDir(PathBuf);

    impl TempDir {
        fn new(tag: &str) -> Self {
            let unique = format!(
                "nightcord-identity-{tag}-{}-{:?}",
                std::process::id(),
                std::thread::current().id()
            );
            let path = std::env::temp_dir().join(unique.replace(['(', ')', ' '], ""));
            let _ = fs::remove_dir_all(&path);
            fs::create_dir_all(&path).expect("create temp dir");
            Self(path)
        }

        fn store(&self) -> IdentityStore {
            IdentityStore::new(&self.0)
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    fn sample() -> Identity {
        Identity::new("abcdef0123456789=", vec![1, 2, 3, 4, 5])
    }

    #[test]
    fn saves_and_loads_an_identity() {
        let dir = TempDir::new("roundtrip");
        let store = dir.store();

        store.save("default", &sample()).unwrap();
        let loaded = store.load("default").unwrap().expect("identity present");

        assert_eq!(loaded, sample());
    }

    #[test]
    fn missing_identity_is_absence_not_failure() {
        let dir = TempDir::new("missing");
        assert!(dir.store().load("default").unwrap().is_none());
    }

    #[test]
    fn load_or_create_does_not_regenerate() {
        // §36: a reconnect must reuse the stored identity, or the server sees a
        // different client and the user loses their permissions.
        let dir = TempDir::new("reuse");
        let store = dir.store();

        let first = store
            .load_or_create("default", || Ok(sample()))
            .expect("first call generates");

        let second = store
            .load_or_create("default", || {
                panic!("must not generate a second identity for an existing profile")
            })
            .expect("second call reuses");

        assert_eq!(first, second);
    }

    #[test]
    fn load_or_create_survives_a_reopen() {
        let dir = TempDir::new("reopen");
        let created = dir.store().load_or_create("alt", || Ok(sample())).unwrap();

        // A fresh store, as if the process had restarted.
        let reopened = IdentityStore::new(dir.0.clone())
            .load("alt")
            .unwrap()
            .unwrap();
        assert_eq!(created, reopened);
    }

    #[test]
    fn malformed_file_is_an_error_not_a_new_identity() {
        let dir = TempDir::new("malformed");
        let store = dir.store();
        fs::write(store.path_for("default"), b"not json").unwrap();

        assert!(matches!(
            store.load("default"),
            Err(IdentityError::Malformed { .. })
        ));
    }

    #[test]
    fn unsupported_version_is_rejected() {
        let dir = TempDir::new("version");
        let store = dir.store();
        fs::write(
            store.path_for("default"),
            br#"{"version":99,"unique_id":"x","identity":""}"#,
        )
        .unwrap();

        let err = store.load("default").unwrap_err();
        assert!(
            matches!(err, IdentityError::Malformed { .. }),
            "got {err:?}"
        );
    }

    #[test]
    fn rejects_names_that_escape_the_store() {
        let dir = TempDir::new("traversal");
        let store = dir.store();

        for name in [
            "../escape",
            "a/b",
            "a\\b",
            "",
            "   ",
            "with space",
            "dot.name",
        ] {
            assert!(
                matches!(store.load(name), Err(IdentityError::InvalidName { .. })),
                "`{name}` should be rejected"
            );
        }
    }

    #[test]
    fn debug_output_redacts_the_private_key() {
        let rendered = format!("{:?}", sample());
        assert!(
            rendered.contains("redacted"),
            "debug leaked the blob: {rendered}"
        );
        assert!(
            !rendered.contains("[1, 2, 3"),
            "debug leaked the blob: {rendered}"
        );
        // The public id is safe to show and useful in logs.
        assert!(rendered.contains("abcdef0123456789="));
    }

    #[test]
    fn stored_file_is_base64_not_raw_bytes() {
        let dir = TempDir::new("encoding");
        let store = dir.store();
        store.save("default", &sample()).unwrap();

        let raw = fs::read_to_string(store.path_for("default")).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&raw).unwrap();
        assert_eq!(parsed["identity"], "AQIDBAU=");
        assert_eq!(parsed["version"], FILE_VERSION);
    }
}
