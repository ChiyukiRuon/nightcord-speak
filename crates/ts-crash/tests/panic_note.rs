// A panic that is caught still leaves a note.
//
// The hook runs at panic *initiation*, before anything can catch it, which is
// exactly why it can be tested with `catch_unwind` instead of by dying. This
// file holds a single test on purpose: installing the handler is once per
// process, and one test binary per concern keeps that honest.

use std::fs;
use std::path::PathBuf;

use ts_crash::CrashStore;

fn temp_dir(tag: &str) -> PathBuf {
    let unique = format!(
        "nightcord-crash-it-{tag}-{}-{:?}",
        std::process::id(),
        std::thread::current().id()
    );
    let path = std::env::temp_dir().join(unique.replace(['(', ')', ' '], ""));
    let _ = fs::remove_dir_all(&path);
    fs::create_dir_all(&path).expect("create temp dir");
    path
}

#[test]
fn a_caught_panic_writes_a_note_while_the_run_is_live() {
    let dir = temp_dir("panic");
    let store = CrashStore::new(&dir);
    // The marker is the gate: notes are only written while our own run is
    // live, so this doubles as the "a real run, not a test process" fixture.
    store.begin_run().expect("write the run marker");
    store.install_handlers();

    let caught = std::panic::catch_unwind(|| panic!("note-probe-42"));
    assert!(caught.is_err(), "the panic still unwinds");

    let notes: Vec<PathBuf> = fs::read_dir(&dir)
        .unwrap()
        .flatten()
        .map(|entry| entry.path())
        .filter(|path| {
            path.file_name()
                .and_then(|name| name.to_str())
                .is_some_and(|name| name.starts_with("crash-"))
        })
        .collect();
    assert_eq!(notes.len(), 1, "exactly one note: {notes:?}");

    let note = fs::read_to_string(&notes[0]).unwrap();
    assert!(note.contains("kind: panic"), "{note}");
    assert!(note.contains("note-probe-42"), "{note}");
    assert!(note.contains("location:"), "{note}");
    assert!(note.contains("backtrace:"), "{note}");

    let _ = fs::remove_dir_all(&dir);
}
