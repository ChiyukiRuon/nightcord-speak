//! The address book: servers the user has saved (§40).
//!
//! A saved server is not an account. It records where to connect, what to call
//! yourself there, and — since that was a deliberate decision, not an oversight —
//! the server's password. It holds no identity, no channel password and no
//! privilege key, because the connect screen collects none of those and a struct
//! that can express what nothing can set is a place for the two to drift.
//!
//! The list lives in its own file, `bookmarks.json`, rather than inside
//! `settings.json`. Nothing about the two is technically different — both are
//! JSON beside the identity — but this one contains a credential, and the
//! settings file is the one a user is likely to paste into a bug report. Keeping
//! them apart keeps that file safe to share.

use std::path::PathBuf;

use serde::{Deserialize, Serialize};
use ts_identity::app_data_root;
use ts_model::{ConnectionTarget, ProtocolKind, SettingsError};

/// The file's name inside the application data root.
pub const FILE_NAME: &str = "bookmarks.json";

/// On-disk format version, so the layout can change without guesswork.
const FILE_VERSION: u32 = 1;

/// One server the user has saved.
///
/// The [`fmt::Debug`] implementation is hand-written: this holds a password, and
/// a stray `{:?}` must not be able to print it (§44).
#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Bookmark {
    /// What the user calls this entry.
    #[serde(default)]
    pub name: String,

    /// Host, without the port. Normalised on the way in through
    /// [`Bookmark::from_address`], so a pasted `ts3://example.com` does not land
    /// in the file with its scheme still attached.
    #[serde(default)]
    pub host: String,

    /// Port. Defaulted rather than required, so a hand-written entry that omits
    /// it still loads — the alternative is that one missing line makes the whole
    /// address book unreadable.
    #[serde(default = "default_port")]
    pub port: u16,

    /// Nickname to use here, or `None` to take the one from the settings.
    ///
    /// `None` is what makes "I changed my default nickname" affect the servers
    /// you had not overridden, which is what a default is for.
    #[serde(default)]
    pub nickname: Option<String>,

    /// Which backend to use. Kept even though the connect screen cannot choose
    /// it yet: it is what a connection needs, and a hand-edited file or a later
    /// front-end can say so.
    #[serde(default)]
    pub protocol: ProtocolKind,

    /// The server's own password, if it has one. **The only secret here.**
    #[serde(default)]
    pub server_password: Option<String>,
}

impl Bookmark {
    /// A saved server built from what the connect screen collects.
    ///
    /// The address is parsed with the same parser a connection uses, so an
    /// entry that saves is an entry that connects — and the file gets the
    /// normalised form rather than whatever was pasted.
    ///
    /// # Errors
    ///
    /// Returns [`ts_model::AddressError`] if the address cannot be parsed.
    pub fn from_new(new: NewBookmark) -> Result<Self, ts_model::AddressError> {
        let target = ConnectionTarget::parse(&new.address)?;
        Ok(Self {
            name: new.name,
            host: target.host,
            port: target.port,
            nickname: new.nickname,
            protocol: new.protocol,
            server_password: new.server_password,
        })
    }

    /// The address to hand to a connection.
    #[must_use]
    pub fn address(&self) -> String {
        ConnectionTarget::new(&self.host, self.port).to_string()
    }

    /// What to show when the user has not named it.
    #[must_use]
    pub fn display_name(&self) -> &str {
        if self.name.trim().is_empty() {
            &self.host
        } else {
            &self.name
        }
    }
}

impl std::fmt::Debug for Bookmark {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Bookmark")
            .field("name", &self.name)
            .field("host", &self.host)
            .field("port", &self.port)
            .field("nickname", &self.nickname)
            .field("protocol", &self.protocol)
            .field(
                "server_password",
                &if self.server_password.is_some() {
                    "<set>"
                } else {
                    "<unset>"
                },
            )
            .finish()
    }
}

/// What the connect screen collects, before the address is parsed.
///
/// Kept apart from [`Bookmark`] so the parsing happens in one place — the core,
/// which already owns [`ConnectionTarget::parse`] — rather than being written
/// again in every front-end that offers a "save this server" button.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct NewBookmark {
    /// What the user calls it. An empty name falls back to the host.
    #[serde(default)]
    pub name: String,

    /// Whatever the user typed: `host`, `host:port`, `ts3://host`, `[::1]:9987`.
    pub address: String,

    #[serde(default)]
    pub nickname: Option<String>,

    #[serde(default)]
    pub protocol: ProtocolKind,

    #[serde(default)]
    pub server_password: Option<String>,
}

/// The saved servers, as they are stored.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct BookmarkList {
    /// Format version. Defaulted rather than required so a hand-written file
    /// does not have to know about it.
    #[serde(default = "current_version")]
    pub version: u32,

    #[serde(default)]
    pub bookmarks: Vec<Bookmark>,
}

impl BookmarkList {
    /// Adds an entry, or replaces the one with the same host and port.
    ///
    /// Matching on the address rather than on the name: the name is a label the
    /// user is free to change, and two entries pointing at one server is how a
    /// list quietly fills with duplicates.
    pub fn upsert(&mut self, server: Bookmark) {
        match self
            .bookmarks
            .iter_mut()
            .find(|existing| existing.host == server.host && existing.port == server.port)
        {
            Some(existing) => *existing = server,
            None => self.bookmarks.push(server),
        }
    }

    /// Removes the entry at `index`, if there is one.
    ///
    /// By position rather than by address: the caller is a list widget that just
    /// showed the user the row they are deleting, and two entries may legitimately
    /// differ in nothing else.
    pub fn remove(&mut self, index: usize) -> Option<Bookmark> {
        if index >= self.bookmarks.len() {
            return None;
        }
        Some(self.bookmarks.remove(index))
    }
}

/// Reads and writes [`BookmarkList`] in one directory.
#[derive(Debug, Clone)]
pub struct BookmarkStore {
    dir: PathBuf,
}

impl BookmarkStore {
    /// A store rooted at `dir` — the application data directory itself.
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

    /// The file the saved servers live in.
    #[must_use]
    pub fn path(&self) -> PathBuf {
        self.dir.join(FILE_NAME)
    }

    /// Reads the saved servers, or an empty list when there is no file yet.
    ///
    /// # Errors
    ///
    /// Returns [`SettingsError::Malformed`] if the file exists but cannot be
    /// read as a server list — including a version this build does not
    /// understand.
    pub fn load(&self) -> Result<BookmarkList, SettingsError> {
        // An embedded default carries the current version, so a file written by
        // hand without one is accepted.
        let Some(stored) = crate::store::read_json::<BookmarkList>(&self.path())? else {
            return Ok(BookmarkList {
                version: current_version(),
                bookmarks: Vec::new(),
            });
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

    /// Writes the saved servers, replacing whatever was there.
    ///
    /// # Errors
    ///
    /// Returns [`SettingsError::Io`] if the directory cannot be created or the
    /// file cannot be written.
    pub fn save(&self, bookmarks: &BookmarkList) -> Result<(), SettingsError> {
        crate::store::write_json(&self.path(), bookmarks)
    }
}

const fn current_version() -> u32 {
    FILE_VERSION
}

const fn default_port() -> u16 {
    ts_model::DEFAULT_PORT
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
                "nightcord-bookmarks-{tag}-{}-{:?}",
                std::process::id(),
                std::thread::current().id()
            );
            let path = std::env::temp_dir().join(unique.replace(['(', ')', ' '], ""));
            let _ = fs::remove_dir_all(&path);
            fs::create_dir_all(&path).expect("create temp dir");
            Self(path)
        }

        fn store(&self) -> BookmarkStore {
            BookmarkStore::new(&self.0)
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    fn sample() -> Bookmark {
        Bookmark {
            name: "Home".into(),
            host: "192.168.31.128".into(),
            port: 9987,
            nickname: Some("Alice".into()),
            protocol: ProtocolKind::Ts6,
            server_password: Some("hunter2".into()),
        }
    }

    #[test]
    fn a_missing_file_is_an_empty_address_book_not_a_failure() {
        let dir = TempDir::new("missing");
        let loaded = dir.store().load().unwrap();

        assert!(loaded.bookmarks.is_empty());
        assert_eq!(loaded.version, FILE_VERSION);
    }

    #[test]
    fn bookmarks_survive_a_round_trip() {
        let dir = TempDir::new("roundtrip");
        let store = dir.store();

        let list = BookmarkList {
            version: FILE_VERSION,
            bookmarks: vec![sample()],
        };

        store.save(&list).unwrap();
        assert_eq!(store.load().unwrap(), list);
    }

    #[test]
    fn the_password_is_never_printed() {
        // §44. A stray `{:?}` in a log line is not allowed to leak a credential,
        // and this type is the one that carries one.
        let rendered = format!("{:?}", sample());

        assert!(
            !rendered.contains("hunter2"),
            "debug leaked the password: {rendered}"
        );
        assert!(rendered.contains("<set>"), "got {rendered}");
        // Everything else is fine to show, and useful when reading a log.
        assert!(rendered.contains("192.168.31.128"), "got {rendered}");
    }

    #[test]
    fn an_entry_without_a_port_gets_the_default() {
        // A hand-written entry. The struct this replaced had no default on its
        // port, so one missing line made the whole file unreadable.
        let dir = TempDir::new("noport");
        let store = dir.store();
        fs::write(
            store.path(),
            br#"{"version":1,"bookmarks":[{"name":"x","host":"192.168.31.128"}]}"#,
        )
        .unwrap();

        let loaded = store.load().unwrap();
        assert_eq!(loaded.bookmarks.len(), 1);
        assert_eq!(loaded.bookmarks[0].port, 9987);
        assert_eq!(loaded.bookmarks[0].nickname, None);
    }

    #[test]
    fn a_corrupt_file_is_reported_rather_than_read_as_an_empty_book() {
        // Reading damage as absence would silently lose every saved server, and
        // the next save would overwrite the evidence.
        let dir = TempDir::new("corrupt");
        let store = dir.store();
        fs::write(store.path(), b"{ not json").unwrap();

        assert!(matches!(store.load(), Err(SettingsError::Malformed { .. })));
    }

    #[test]
    fn a_version_this_build_does_not_know_is_refused() {
        let dir = TempDir::new("version");
        let store = dir.store();
        fs::write(store.path(), br#"{"version":99}"#).unwrap();

        assert!(matches!(store.load(), Err(SettingsError::Malformed { .. })));
    }

    #[test]
    fn saving_leaves_no_temporary_file_behind() {
        let dir = TempDir::new("atomic");
        let store = dir.store();
        store.save(&BookmarkList::default()).unwrap();

        let leftovers: Vec<String> = fs::read_dir(&dir.0)
            .unwrap()
            .map(|entry| entry.unwrap().file_name().to_string_lossy().into_owned())
            .filter(|name| name.ends_with(".tmp"))
            .collect();

        assert!(leftovers.is_empty(), "left behind: {leftovers:?}");
    }

    #[test]
    fn an_unknown_field_is_ignored_rather_than_fatal() {
        let dir = TempDir::new("unknown");
        let store = dir.store();
        fs::write(
            store.path(),
            br#"{"version":1,"bookmarks":[],"from_the_future":42}"#,
        )
        .unwrap();

        assert!(store.load().is_ok());
    }

    #[test]
    fn an_address_is_normalised_on_the_way_in() {
        // Whatever the user pasted — a scheme, a port, nothing — the file gets
        // the same shape, and what comes out connects.
        let server = Bookmark::from_new(NewBookmark {
            name: "x".into(),
            address: "ts3://example.com:9999".into(),
            ..NewBookmark::default()
        })
        .unwrap();

        assert_eq!(server.host, "example.com");
        assert_eq!(server.port, 9999);
        assert_eq!(server.address(), "example.com:9999");

        let bare = Bookmark::from_new(NewBookmark {
            name: "y".into(),
            address: "example.com".into(),
            ..NewBookmark::default()
        })
        .unwrap();
        assert_eq!(bare.port, ts_model::DEFAULT_PORT);
    }

    #[test]
    fn saving_the_same_address_twice_replaces_rather_than_duplicates() {
        // Otherwise a list quietly fills with the same server because the user
        // saved it again with a different name.
        let mut list = BookmarkList::default();
        list.upsert(sample());

        let mut renamed = sample();
        renamed.name = "Renamed".into();
        list.upsert(renamed);

        assert_eq!(list.bookmarks.len(), 1);
        assert_eq!(list.bookmarks[0].name, "Renamed");
    }

    #[test]
    fn an_unnamed_entry_falls_back_to_its_host() {
        let mut server = sample();
        server.name = "   ".into();
        assert_eq!(server.display_name(), "192.168.31.128");
    }

    #[test]
    fn removing_out_of_range_is_a_no_op() {
        let mut list = BookmarkList::default();
        list.upsert(sample());

        assert!(list.remove(7).is_none());
        assert_eq!(list.bookmarks.len(), 1);
        assert!(list.remove(0).is_some());
        assert!(list.bookmarks.is_empty());
    }
}
