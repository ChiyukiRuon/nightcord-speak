//! The gateway against a real socket and a real client.
//!
//! Everything here is loopback — no TeamSpeak server is involved: the
//! commands exercised (`settings`, `bookmarks`) live entirely in the core's
//! stores, which the tests point at a temporary directory.
//!
//! The client is `tokio-tungstenite`'s, i.e. the code under test is spoken to
//! the way a browser would speak to it: handshake, `hello`, token, frames.

use std::net::SocketAddr;
use std::path::PathBuf;
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use tokio::net::TcpStream;
use tokio::sync::oneshot;
use tokio::time::timeout;
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::{MaybeTlsStream, WebSocketStream};
use ts_gateway::{Gateway, GatewayConfig};

const TOKEN: &str = "test-token-0123456789abcdef";

type Client = WebSocketStream<MaybeTlsStream<TcpStream>>;

/// A temporary data directory, cleaned up on drop.
struct TempDir(PathBuf);

impl TempDir {
    fn new(tag: &str) -> Self {
        let unique = format!(
            "nightcord-gateway-{tag}-{}-{:?}",
            std::process::id(),
            std::thread::current().id()
        );
        let path = std::env::temp_dir().join(unique.replace(['(', ')', ' '], ""));
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

/// Starts a gateway on an ephemeral loopback port.
///
/// The [`TempDir`] comes back with it: it must outlive the gateway, or the
/// stores would be deleted out from under a running test.
async fn start(tag: &str) -> (SocketAddr, oneshot::Sender<()>, TempDir) {
    start_with_token(tag, TOKEN).await
}

async fn start_with_token(tag: &str, token: &str) -> (SocketAddr, oneshot::Sender<()>, TempDir) {
    let dir = TempDir::new(tag);
    let mut config = GatewayConfig::new(vec!["127.0.0.1:0".parse().expect("a literal address")]);
    config.token = token.to_string();
    config.data_dir = Some(dir.0.clone());

    let bound = Gateway::new(config).bind().await.expect("bind the gateway");
    let addr = bound.local_addrs().expect("local addresses")[0];

    let (shutdown, shutdown_rx) = oneshot::channel();
    tokio::spawn(bound.serve(async move {
        let _ = shutdown_rx.await;
    }));

    (addr, shutdown, dir)
}

/// Connects, expects `hello`, sends the token, expects `welcome`.
async fn connect_authed(addr: SocketAddr, token: &str) -> Client {
    connect_device(addr, Some(token), None).await.0
}

async fn connect_device(
    addr: SocketAddr,
    token: Option<&str>,
    device: Option<&str>,
) -> (Client, String) {
    let (mut client, _) = tokio_tungstenite::connect_async(format!("ws://{addr}/ws"))
        .await
        .expect("the handshake");
    let hello = next_json(&mut client).await;
    assert_eq!(hello["kind"], "hello");
    assert_eq!(hello["device"], "required");
    let frame = if let Some(token) = token {
        serde_json::json!({"kind":"auth", "token":token, "device":device})
    } else {
        serde_json::json!({"kind":"attach", "device":device})
    };
    client
        .send(Message::text(frame.to_string()))
        .await
        .expect("attach device");
    let welcome = next_json(&mut client).await;
    assert_eq!(welcome["kind"], "welcome", "{welcome}");
    (
        client,
        welcome["device"]
            .as_str()
            .expect("device credential")
            .to_owned(),
    )
}

/// The next text frame as JSON, skipping binary frames.
async fn next_json(client: &mut Client) -> serde_json::Value {
    loop {
        let message = timeout(Duration::from_secs(10), client.next())
            .await
            .expect("a frame within ten seconds")
            .expect("the socket is open")
            .expect("a valid frame");
        if let Message::Text(text) = message {
            return serde_json::from_str(&text).expect("a JSON frame");
        }
    }
}

/// Waits for a command result with `command`, skipping domain events.
async fn next_result(client: &mut Client, command: &str) -> serde_json::Value {
    loop {
        let frame = next_json(client).await;
        if frame["kind"] == "command_result" && frame["command"] == command {
            return frame;
        }
    }
}

#[tokio::test]
async fn a_browser_authenticates_and_reads_the_settings() {
    let (addr, _shutdown, _dir) = start("settings").await;
    let mut client = connect_authed(addr, TOKEN).await;

    client
        .send(Message::text(r#"{"command":"settings"}"#))
        .await
        .unwrap();

    let result = next_result(&mut client, "settings").await;
    assert_eq!(result["outcome"]["status"], "ok", "{result}");
    // Fresh temp directory: the defaults, read through the whole stack.
    assert_eq!(result["data"]["version"], 1, "{result}");
    assert_eq!(
        result["data"]["connection"]["profile"], "default",
        "{result}"
    );
}

#[tokio::test]
async fn settings_changes_survive_a_round_trip_through_the_gateway() {
    let (addr, _shutdown, _dir) = start("roundtrip").await;
    let mut client = connect_authed(addr, TOKEN).await;

    // Read, edit, write — the same sequence the page performs.
    client
        .send(Message::text(r#"{"command":"settings"}"#))
        .await
        .unwrap();
    let mut settings = next_result(&mut client, "settings").await["data"].clone();
    settings["connection"]["nickname"] = serde_json::json!("Gateway Tester");

    client
        .send(Message::text(
            serde_json::json!({ "command": "settings_update", "payload": settings }).to_string(),
        ))
        .await
        .unwrap();
    let update = next_result(&mut client, "settings_update").await;
    assert_eq!(update["outcome"]["status"], "ok", "{update}");

    client
        .send(Message::text(r#"{"command":"settings"}"#))
        .await
        .unwrap();
    let back = next_result(&mut client, "settings").await;
    assert_eq!(back["data"]["connection"]["nickname"], "Gateway Tester");
}

#[tokio::test]
async fn tabs_of_the_same_device_share_results() {
    // No request ids in v1; the documented consequence is that a result is
    // broadcast. This pins that behaviour deliberately rather than by
    // accident.
    let (addr, _shutdown, _dir) = start("fanout").await;
    let (mut first, device) = connect_device(addr, Some(TOKEN), None).await;
    let (mut second, _) = connect_device(addr, Some(TOKEN), Some(&device)).await;

    first
        .send(Message::text(r#"{"command":"settings"}"#))
        .await
        .unwrap();

    let seen_by_second = next_result(&mut second, "settings").await;
    assert_eq!(seen_by_second["outcome"]["status"], "ok");

    let seen_by_first = next_result(&mut first, "settings").await;
    assert_eq!(seen_by_first["outcome"]["status"], "ok");
}

#[tokio::test]
async fn the_wrong_token_is_refused_and_the_socket_closes() {
    let (addr, _shutdown, _dir) = start("badtoken").await;
    let (mut client, _) = tokio_tungstenite::connect_async(format!("ws://{addr}/ws"))
        .await
        .unwrap();
    let hello = next_json(&mut client).await;
    assert_eq!(hello["kind"], "hello");

    client
        .send(Message::text(
            serde_json::json!({ "kind": "auth", "token": "not-the-token" }).to_string(),
        ))
        .await
        .unwrap();

    let answer = next_json(&mut client).await;
    assert_eq!(answer["kind"], "error", "{answer}");
    assert_eq!(answer["message"], "bad token", "{answer}");

    // And the socket goes away rather than staying open for a second guess.
    let end = timeout(Duration::from_secs(10), client.next()).await;
    match end {
        Ok(None) | Ok(Some(Ok(Message::Close(_)))) | Ok(Some(Err(_))) => {}
        other => panic!("expected the socket to close, got {other:?}"),
    }
}

#[tokio::test]
async fn a_command_before_auth_is_refused() {
    let (addr, _shutdown, _dir) = start("preauth").await;
    let (mut client, _) = tokio_tungstenite::connect_async(format!("ws://{addr}/ws"))
        .await
        .unwrap();
    let hello = next_json(&mut client).await;
    assert_eq!(hello["kind"], "hello");

    client
        .send(Message::text(r#"{"command":"settings"}"#))
        .await
        .unwrap();

    let answer = next_json(&mut client).await;
    assert_eq!(answer["kind"], "error", "{answer}");
    assert!(
        answer["message"].as_str().unwrap().contains("auth"),
        "{answer}"
    );
}

#[tokio::test]
async fn a_disallowed_origin_is_refused_at_the_handshake() {
    let (addr, _shutdown, _dir) = start("origin").await;

    use tokio_tungstenite::tungstenite::client::IntoClientRequest;
    let mut request = format!("ws://{addr}/ws").into_client_request().unwrap();
    request
        .headers_mut()
        .insert("origin", "https://evil.example".parse().unwrap());

    let attempt = tokio_tungstenite::connect_async(request).await;
    assert!(attempt.is_err(), "the handshake must not complete");
}

#[tokio::test]
async fn malformed_binary_frames_are_answered_with_a_readable_error() {
    let (addr, _shutdown, _dir) = start("binary").await;
    let mut client = connect_authed(addr, TOKEN).await;

    // Wrong length: the page and the gateway disagree about the protocol.
    client.send(Message::binary(vec![1u8; 64])).await.unwrap();
    let answer = next_json(&mut client).await;
    assert_eq!(answer["kind"], "error", "{answer}");

    // The connection is still healthy afterwards: one bad frame is not a
    // reason to drop a session.
    client
        .send(Message::text(r#"{"command":"settings"}"#))
        .await
        .unwrap();
    let result = next_result(&mut client, "settings").await;
    assert_eq!(result["outcome"]["status"], "ok");
}

#[tokio::test]
async fn unit_variants_tolerate_an_empty_payload() {
    // `{"payload": {}}` is what a client that always includes the key sends.
    // Serde's adjacent tagging rejects it for unit variants — the page hit
    // this with `voice_stop` during the first end-to-end run — so the gateway
    // normalises an empty payload away before parsing.
    let (addr, _shutdown, _dir) = start("payload").await;
    let mut client = connect_authed(addr, TOKEN).await;

    client
        .send(Message::text(r#"{"command":"voice_stop","payload":{}}"#))
        .await
        .unwrap();

    let result = next_result(&mut client, "voice_stop").await;
    assert_eq!(result["outcome"]["status"], "ok", "{result}");
}

#[tokio::test]
async fn the_page_is_served_on_the_same_port() {
    let (addr, _shutdown, _dir) = start("page").await;

    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    let mut stream = TcpStream::connect(addr).await.unwrap();
    stream
        .write_all(b"GET / HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
        .await
        .unwrap();
    let mut response = String::new();
    timeout(
        Duration::from_secs(10),
        stream.read_to_string(&mut response),
    )
    .await
    .expect("a response")
    .expect("readable");

    assert!(response.starts_with("HTTP/1.1 200 OK"), "{response}");
    assert!(response.contains("Nightcord Speak"), "the page is served");
    assert!(response.contains("/ws"), "and it knows where the socket is");
}

#[tokio::test]
async fn an_unconfigured_gateway_accepts_commands_without_an_auth_frame() {
    let (addr, shutdown, _dir) = start_with_token("no-token", "").await;
    let (mut client, _) = tokio_tungstenite::connect_async(format!("ws://{addr}/ws"))
        .await
        .expect("handshake");
    let hello = next_json(&mut client).await;
    assert_eq!(hello["auth"], "none");
    client
        .send(Message::text(r#"{"kind":"attach"}"#))
        .await
        .unwrap();
    assert_eq!(next_json(&mut client).await["kind"], "welcome");
    client
        .send(Message::text(r#"{"command":"settings"}"#))
        .await
        .expect("send command");
    let result = next_json(&mut client).await;
    assert_eq!(result["command"], "settings");
    assert_eq!(result["outcome"]["status"], "ok");
    let _ = shutdown.send(());
}

#[tokio::test]
async fn different_devices_cannot_read_settings_or_receive_each_others_results() {
    let (addr, shutdown, _dir) = start("isolated").await;
    let (mut first, first_device) = connect_device(addr, Some(TOKEN), None).await;
    let (mut second, second_device) = connect_device(addr, Some(TOKEN), None).await;
    assert_ne!(first_device, second_device);
    first
        .send(Message::text(r#"{"command":"settings"}"#))
        .await
        .unwrap();
    let mut settings = next_result(&mut first, "settings").await["data"].clone();
    assert!(
        timeout(Duration::from_millis(80), second.next())
            .await
            .is_err()
    );
    settings["connection"]["nickname"] = serde_json::json!("Only Device A");
    first
        .send(Message::text(
            serde_json::json!({"command":"settings_update","payload":settings}).to_string(),
        ))
        .await
        .unwrap();
    next_result(&mut first, "settings_update").await;
    second
        .send(Message::text(r#"{"command":"settings"}"#))
        .await
        .unwrap();
    assert_ne!(
        next_result(&mut second, "settings").await["data"]["connection"]["nickname"],
        "Only Device A"
    );
    first.close(None).await.unwrap();
    let (mut resumed, same_device) = connect_device(addr, Some(TOKEN), Some(&first_device)).await;
    assert_eq!(same_device, first_device);
    resumed
        .send(Message::text(r#"{"command":"settings"}"#))
        .await
        .unwrap();
    assert_eq!(
        next_result(&mut resumed, "settings").await["data"]["connection"]["nickname"],
        "Only Device A"
    );
    let _ = shutdown.send(());
}

#[tokio::test]
async fn knowing_a_device_id_without_its_secret_does_not_grant_access() {
    let (addr, shutdown, _dir) = start("device-secret").await;
    let (_, credential) = connect_device(addr, Some(TOKEN), None).await;
    let (id, _) = credential.split_once('.').unwrap();
    let forged = format!("{id}.{}", "0".repeat(32));
    let (mut attacker, _) = tokio_tungstenite::connect_async(format!("ws://{addr}/ws"))
        .await
        .unwrap();
    next_json(&mut attacker).await;
    attacker
        .send(Message::text(
            serde_json::json!({"kind":"auth","token":TOKEN,"device":forged}).to_string(),
        ))
        .await
        .unwrap();
    assert_eq!(
        next_json(&mut attacker).await["message"],
        "invalid device credential"
    );
    let _ = shutdown.send(());
}
