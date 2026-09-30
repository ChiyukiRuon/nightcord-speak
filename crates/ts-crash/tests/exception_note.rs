// The exception path, driven through `simulate_exception`.
//
// A real SEH exception would kill the test process, and `simulate_exception`
// exists precisely to avoid that: it synthesises the exception record, invokes
// the attached handler, and returns the handler's answer. One test per process:
// attaching is once per process.

#![cfg(windows)]

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
fn a_simulated_exception_writes_a_note() {
    let dir = temp_dir("exception");
    let store = CrashStore::new(&dir);
    store.begin_run().expect("write the run marker");

    let note_dir = dir.clone();
    // SAFETY: the closure keeps to a string build and a file write, and does
    // not unwind — the same contract `install_handlers` upholds.
    let event = unsafe {
        crash_handler::make_crash_event(move |context| {
            ts_crash::write_exception_note(&CrashStore::new(&note_dir), context);
            crash_handler::CrashEventResult::Handled(false)
        })
    };
    let handler = crash_handler::CrashHandler::attach(event).expect("attach the handler");

    handler.simulate_exception(None);

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
    assert!(note.contains("kind: exception"), "{note}");
    assert!(note.contains("exception_code: 0x"), "{note}");
    assert!(
        !note.contains("exception_address: <unknown>"),
        "the address comes from the exception record: {note}"
    );

    handler.detach();
    let _ = fs::remove_dir_all(&dir);
}
