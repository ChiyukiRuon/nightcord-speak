//! The binary's contract with whoever starts it.
//!
//! Nothing here touches a TeamSpeak server or a real profile: the gateway is
//! started on an ephemeral loopback port with a scratch data directory, and
//! only its stdout is read. What is under test is the hand-off — the few
//! lines a person has to act on before a browser can connect at all.

use std::io::{BufRead, BufReader};
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};

/// A scratch data directory, cleaned up on drop.
struct TempDir(PathBuf);

impl TempDir {
    fn new(tag: &str) -> Self {
        let unique = format!("nightcord-gateway-cli-{tag}-{}", std::process::id());
        let path = std::env::temp_dir().join(unique);
        let _ = std::fs::remove_dir_all(&path);
        std::fs::create_dir_all(&path).expect("create temp dir");
        Self(path)
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

/// Kills the gateway however the test ends: one left running would hold the
/// scratch directory and, worse, answer on a port the next run might want.
struct Killer(Child);

impl Drop for Killer {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

#[test]
fn the_default_gateway_starts_without_generating_or_printing_a_token() {
    // The gateway used to force a random credential on every local launch.
    // Optional authentication must not silently re-enable that behavior.
    let dir = TempDir::new("no-token");
    let child = Command::new(env!("CARGO_BIN_EXE_nightcord-gateway"))
        .args(["--bind", "127.0.0.1:0", "--data-dir"])
        .arg(&dir.0)
        .env_remove("NIGHTCORD_GATEWAY_TOKEN")
        .stdout(Stdio::piped())
        .spawn()
        .expect("the gateway binary runs");
    let mut child = Killer(child);
    let stdout = child.0.stdout.take().expect("stdout was piped");
    let mut listening = false;
    for line in BufReader::new(stdout).lines() {
        let line = line.expect("stdout is readable");
        assert!(!line.starts_with("token:"), "default startup has no token");
        listening |= line.starts_with("nightcord-gateway listening");
        if line.starts_with("open http://") {
            break;
        }
    }
    assert!(listening, "startup announces the bound address");
}
