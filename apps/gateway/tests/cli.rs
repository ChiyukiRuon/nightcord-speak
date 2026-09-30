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
fn a_generated_token_is_the_one_that_gets_printed() {
    // Regression: `main` printed `args.token.unwrap_or("…")`, and the branch
    // that prints at all is exactly the branch where `args.token` is `None`.
    // So a gateway started without `--token` — the normal way — announced the
    // literal `…` and the operator had no way to learn the token the gateway
    // was actually enforcing. The one secret they have to carry to the
    // browser was unreachable, and the browser could only answer "refused".
    let dir = TempDir::new("token");
    let child = Command::new(env!("CARGO_BIN_EXE_nightcord-gateway"))
        .args(["--bind", "127.0.0.1:0", "--data-dir"])
        .arg(&dir.0)
        .stdout(Stdio::piped())
        .spawn()
        .expect("the gateway binary runs");
    let mut child = Killer(child);

    let stdout = child.0.stdout.take().expect("stdout was piped");
    let mut announced = None;
    for line in BufReader::new(stdout).lines() {
        let line = line.expect("stdout is readable");
        if let Some(token) = line.strip_prefix("token: ") {
            announced = Some(token.to_string());
            break;
        }
    }

    let token = announced.expect("a generated token is announced");
    assert_ne!(token, "…", "a placeholder is not a token");
    assert_eq!(
        token.len(),
        32,
        "16 bytes of hex, as `generate_token` writes them: {token}"
    );
    assert!(
        token.chars().all(|c| c.is_ascii_hexdigit()),
        "hex digits only: {token}"
    );
}
