use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::path::{Path, PathBuf};

use time::format_description::well_known::Rfc3339;
use time::{Date, OffsetDateTime};
use tracing_subscriber::fmt::{format::Writer, time::FormatTime};

use super::{FILE_EXTENSION, FILE_STEM, KEEP_FILES};

fn now() -> OffsetDateTime {
    // Query on each use: a startup offset would go stale after DST or a device
    // timezone change. An unavailable system offset must not stop logging.
    OffsetDateTime::now_local().unwrap_or_else(|_| OffsetDateTime::now_utc())
}

pub(super) struct LocalTimer;

impl FormatTime for LocalTimer {
    fn format_time(&self, writer: &mut Writer<'_>) -> std::fmt::Result {
        format_timestamp(writer, now())
    }
}

fn format_timestamp(writer: &mut impl std::fmt::Write, time: OffsetDateTime) -> std::fmt::Result {
    let text = time.format(&Rfc3339).map_err(|_| std::fmt::Error)?;
    writer.write_str(&text)
}

/// Runs behind NonBlocking, keeping rollover and cleanup off the audio thread.
pub(super) struct LocalDailyWriter {
    directory: PathBuf,
    date: Date,
    file: File,
}

impl LocalDailyWriter {
    pub(super) fn new(directory: &Path) -> io::Result<Self> {
        Self::at(directory, now())
    }

    fn at(directory: &Path, time: OffsetDateTime) -> io::Result<Self> {
        fs::create_dir_all(directory)?;
        let date = time.date();
        let writer = Self {
            directory: directory.to_path_buf(),
            date,
            file: Self::open(directory, date)?,
        };
        writer.prune();
        Ok(writer)
    }

    fn path(directory: &Path, date: Date) -> PathBuf {
        directory.join(format!("{FILE_STEM}.{date}.{FILE_EXTENSION}"))
    }

    fn open(directory: &Path, date: Date) -> io::Result<File> {
        OpenOptions::new()
            .create(true)
            .append(true)
            .open(Self::path(directory, date))
    }

    fn write_at(&mut self, time: OffsetDateTime, bytes: &[u8]) -> io::Result<usize> {
        if time.date() != self.date {
            let file = Self::open(&self.directory, time.date())?;
            self.file.flush()?;
            self.file = file;
            self.date = time.date();
            self.prune();
        }
        self.file.write(bytes)
    }

    fn prune(&self) {
        // Only our dated regular files are eligible. Keep the active file even
        // when a timezone change or clock correction moves the date backwards.
        let Ok(entries) = fs::read_dir(&self.directory) else {
            return;
        };
        let current = Self::path(&self.directory, self.date);
        let mut files: Vec<PathBuf> = entries
            .filter_map(Result::ok)
            .filter(|entry| entry.file_type().is_ok_and(|kind| kind.is_file()))
            .filter(|entry| {
                let name = entry.file_name();
                let Some(name) = name.to_str() else {
                    return false;
                };
                let Some(date) = name
                    .strip_prefix("nightcord.")
                    .and_then(|name| name.strip_suffix(".log"))
                else {
                    return false;
                };
                Date::parse(
                    date,
                    time::macros::format_description!("[year]-[month]-[day]"),
                )
                .is_ok()
            })
            .map(|entry| entry.path())
            .filter(|path| path != &current)
            .collect();
        files.sort();
        let excess = files.len().saturating_sub(KEEP_FILES - 1);
        for path in files.into_iter().take(excess) {
            if let Err(error) = fs::remove_file(&path) {
                eprintln!(
                    "nightcord: could not remove old log {}: {error}",
                    path.display()
                );
            }
        }
    }
}

impl Write for LocalDailyWriter {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        self.write_at(now(), bytes)
    }

    fn flush(&mut self) -> io::Result<()> {
        self.file.flush()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tests::TempDir;
    use time::{Duration, UtcOffset};

    fn instant(text: &str) -> OffsetDateTime {
        OffsetDateTime::parse(text, &Rfc3339).unwrap()
    }

    #[test]
    fn timestamps_keep_local_clock_and_offset() {
        // UTC formatting made UTC+8 devices appear eight hours behind.
        for text in ["2026-10-11T00:30:00+08:00", "2026-10-10T23:30:00-07:00"] {
            let mut output = String::new();
            format_timestamp(&mut output, instant(text)).unwrap();
            assert_eq!(output, text);
        }
    }

    #[test]
    fn local_midnight_rotates_even_when_the_utc_date_does_not_change() {
        let dir = TempDir::new("local-midnight");
        let before = instant("2026-10-10T23:59:59+08:00");
        let after = before + Duration::seconds(1);
        assert_eq!(
            before.to_offset(UtcOffset::UTC).date(),
            after.to_offset(UtcOffset::UTC).date()
        );
        let mut writer = LocalDailyWriter::at(dir.path(), before).unwrap();
        writer.write_at(before, b"before\n").unwrap();
        writer.write_at(after, b"after\n").unwrap();
        writer.flush().unwrap();
        assert_eq!(
            fs::read_to_string(dir.path().join("nightcord.2026-10-10.log")).unwrap(),
            "before\n"
        );
        assert_eq!(
            fs::read_to_string(dir.path().join("nightcord.2026-10-11.log")).unwrap(),
            "after\n"
        );
    }

    #[test]
    fn offset_changes_and_reopening_append_to_the_local_date() {
        let dir = TempDir::new("zone-change");
        let east = instant("2026-10-11T00:30:00+08:00");
        let west = east.to_offset(UtcOffset::from_hms(-7, 0, 0).unwrap());
        let mut writer = LocalDailyWriter::at(dir.path(), east).unwrap();
        writer.write_at(east, b"east\n").unwrap();
        writer.write_at(west, b"west\n").unwrap();
        drop(writer);
        let mut reopened = LocalDailyWriter::at(dir.path(), west).unwrap();
        reopened.write_at(west, b"restart\n").unwrap();
        drop(reopened);
        assert_eq!(
            fs::read_to_string(dir.path().join("nightcord.2026-10-10.log")).unwrap(),
            "west\nrestart\n"
        );
    }

    #[test]
    fn daylight_saving_changes_keep_the_same_local_daily_file() {
        let dir = TempDir::new("dst");
        let before = instant("2026-11-01T01:59:59-04:00");
        let after = instant("2026-11-01T01:00:00-05:00");
        assert_eq!(after - before, Duration::seconds(1));
        let mut writer = LocalDailyWriter::at(dir.path(), before).unwrap();
        writer.write_at(before, b"before\n").unwrap();
        writer.write_at(after, b"after\n").unwrap();
        drop(writer);
        assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 1);
        assert_eq!(
            fs::read_to_string(dir.path().join("nightcord.2026-11-01.log")).unwrap(),
            "before\nafter\n"
        );
    }

    #[test]
    fn pruning_keeps_seven_files_and_preserves_unrelated_files() {
        let dir = TempDir::new("local-prune");
        let start = instant("2026-10-01T00:00:00+08:00");
        fs::write(dir.path().join("nightcord.notes.log"), "keep").unwrap();
        fs::write(dir.path().join("other.2026-10-01.log"), "keep").unwrap();
        let mut writer = LocalDailyWriter::at(dir.path(), start).unwrap();
        for day in 0..10 {
            writer
                .write_at(start + Duration::days(day), b"line\n")
                .unwrap();
        }
        assert!(!dir.path().join("nightcord.2026-10-03.log").exists());
        assert!(dir.path().join("nightcord.2026-10-04.log").exists());
        assert_eq!(fs::read_dir(dir.path()).unwrap().count(), KEEP_FILES + 2);
        // A backward date jump must keep its open file while enforcing the cap.
        writer.write_at(start, b"clock reset\n").unwrap();
        assert!(dir.path().join("nightcord.2026-10-01.log").exists());
        assert_eq!(fs::read_dir(dir.path()).unwrap().count(), KEEP_FILES + 2);
    }

    #[test]
    fn the_live_clock_uses_the_device_offset() {
        let local = OffsetDateTime::now_local().expect("device timezone available");
        let actual = now();
        assert_eq!(actual.offset(), local.offset());
        assert!((actual - local).abs() < Duration::seconds(5));
    }
}
