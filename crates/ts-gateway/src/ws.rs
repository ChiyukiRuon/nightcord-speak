//! One browser connection, from upgrade to drop.
//!
//! The protocol has three layers on one socket:
//!
//! - **Control** (text, `{"kind": …}`): `hello` and `welcome` from the server,
//!   `auth` — with the token — from the client, `error` either way.
//! - **Commands** (text, `{"command": …}`): the shared vocabulary from
//!   `ts-wire`, forwarded to the worker. Results come back on the broadcast,
//!   not as replies, so an unauthenticated socket is refused loudly rather
//!   than answered carefully.
//! - **Audio** (binary, a tag byte then PCM): see [`crate::voice`].
//!
//! Auth is the first client message and nothing else happens before it. A
//! browser cannot set headers on a WebSocket, and a token in the URL would
//! leak into access logs and `Referer`s — the first message is the only place
//! left, and it is a better one anyway.

use std::sync::Arc;
use std::sync::atomic::Ordering;
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use serde::Deserialize;
use tokio::net::TcpStream;
use tokio::sync::broadcast::error::RecvError;
use tokio_tungstenite::WebSocketStream;
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::tungstenite::handshake::server::{Request, Response};
use ts_wire::{Command, FfiEvent};

use crate::Outbound;
use crate::config::GatewayConfig;
use crate::worker::GatewayCommand;

/// How long a socket may stay unauthenticated before it is closed.
///
/// A connection that never says anything holds a task and an id; ten seconds
/// is longer than any honest client needs.
const AUTH_DEADLINE: Duration = Duration::from_secs(10);

/// The biggest message either direction may be.
///
/// The largest legitimate one is a 960-sample mono frame (3,841 bytes); the
/// rest is headroom for command JSON. Everything else is a mistake or an
/// attack, and tungstenite enforces the limit before allocating.
pub(crate) const MAX_MESSAGE: usize = 64 * 1024;

/// What a connection task needs from the gateway.
pub(crate) struct ConnectionContext {
    pub(crate) config: Arc<GatewayConfig>,
    pub(crate) outbound: tokio::sync::broadcast::Sender<Outbound>,
    pub(crate) commands: tokio::sync::mpsc::UnboundedSender<GatewayCommand>,
    pub(crate) next_connection: std::sync::atomic::AtomicU64,
}

/// The frames the *client* sends that are not commands.
#[derive(Debug, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
enum ControlFrame {
    /// The token, as the first message.
    Auth { token: String },
}

/// Constant-time-enough token comparison.
///
/// The timing signal over loopback is not a practical attack; the comparison
/// is written this way because the cost is six lines and the habit is free.
fn token_matches(expected: &str, presented: &str) -> bool {
    if expected.len() != presented.len() {
        return false;
    }
    expected
        .bytes()
        .zip(presented.bytes())
        .fold(0u8, |acc, (a, b)| acc | (a ^ b))
        == 0
}

/// Completes the WebSocket handshake, or refuses it.
///
/// The Origin check runs *inside* the handshake callback, before the upgrade
/// is answered: a browser whose page is not allowed here gets a 403 instead of
/// a socket.
#[allow(clippy::result_large_err)] // the callback's error type is tungstenite's
pub(crate) async fn upgrade(
    stream: TcpStream,
    context: &ConnectionContext,
) -> Result<WebSocketStream<TcpStream>, tokio_tungstenite::tungstenite::Error> {
    let config = context.config.clone();
    let callback = move |request: &Request, response: Response| {
        let origin = request
            .headers()
            .get("origin")
            .and_then(|value| value.to_str().ok());
        if config.origin_allowed(origin) {
            Ok(response)
        } else {
            tracing::warn!(?origin, "refused a connection from a disallowed origin");
            let mut refusal = tokio_tungstenite::tungstenite::handshake::server::ErrorResponse::new(
                Some("origin not allowed".to_string()),
            );
            *refusal.status_mut() = tokio_tungstenite::tungstenite::http::StatusCode::FORBIDDEN;
            Err(refusal)
        }
    };

    let mut config = tokio_tungstenite::tungstenite::protocol::WebSocketConfig::default();
    // The builder, not a struct literal: `WebSocketConfig` is
    // `#[non_exhaustive]`, so `..Default::default()` does not compile outside
    // tungstenite.
    config.max_message_size = Some(MAX_MESSAGE);
    config.max_frame_size = Some(MAX_MESSAGE);

    tokio_tungstenite::accept_hdr_async_with_config(stream, callback, Some(config)).await
}

/// Serves one upgraded socket: hello, auth, then the read loop.
pub(crate) async fn serve(socket: WebSocketStream<TcpStream>, context: Arc<ConnectionContext>) {
    let id = context.next_connection.fetch_add(1, Ordering::Relaxed);
    let (mut sink, mut stream) = socket.split();

    let hello = serde_json::json!({
        "kind": "hello",
        "protocol": 1,
        "auth": "required",
    });
    if sink.send(Message::text(hello.to_string())).await.is_err() {
        return;
    }

    // One shot at the token: a second try is a brute-force attempt, and the
    // operator can restart the gateway with a fresh one if a client fumbled.
    let auth = tokio::time::timeout(AUTH_DEADLINE, stream.next()).await;
    let Ok(Some(Ok(Message::Text(text)))) = auth else {
        let _ = sink
            .send(Message::text(
                serde_json::json!({"kind": "error", "message": "expected an auth message"})
                    .to_string(),
            ))
            .await;
        return;
    };

    match serde_json::from_str::<ControlFrame>(&text) {
        Ok(ControlFrame::Auth { token }) if token_matches(&context.config.token, &token) => {}
        Ok(ControlFrame::Auth { .. }) => {
            tracing::warn!(connection = id, "a connection presented the wrong token");
            let _ = sink
                .send(Message::text(
                    serde_json::json!({"kind": "error", "message": "bad token"}).to_string(),
                ))
                .await;
            return;
        }
        Err(_) => {
            // Not an auth frame at all — a command, most likely, sent before
            // the token. Saying exactly that beats "bad token", which would
            // send someone hunting for a token that is actually fine.
            let _ = sink
                .send(Message::text(
                    serde_json::json!({
                        "kind": "error",
                        "message": "expected an auth message first",
                    })
                    .to_string(),
                ))
                .await;
            return;
        }
    }
    tracing::info!(connection = id, "a browser connected");

    let welcome = serde_json::json!({ "kind": "welcome", "protocol": 1 });
    if sink.send(Message::text(welcome.to_string())).await.is_err() {
        return;
    }

    // Subscribed only now: nothing may reach a socket that has not proven
    // itself, and events before auth are not this connection's business.
    let mut outbound = context.outbound.subscribe();
    let writer = tokio::spawn(async move {
        loop {
            match outbound.recv().await {
                Ok(Outbound::Text(text)) => {
                    if sink.send(Message::text(text)).await.is_err() {
                        break;
                    }
                }
                Ok(Outbound::Binary(bytes)) => {
                    if sink.send(Message::binary(bytes)).await.is_err() {
                        break;
                    }
                }
                Err(RecvError::Lagged(missed)) => {
                    // This connection fell behind the fan-out. Told, not
                    // hidden — the same marker the FFI's queue reports.
                    let text = serde_json::to_string(&FfiEvent::lagged(missed))
                        .unwrap_or_else(|_| "{\"kind\":\"lagged\",\"missed\":0}".to_string());
                    if sink.send(Message::text(text)).await.is_err() {
                        break;
                    }
                }
                Err(RecvError::Closed) => break,
            }
        }
    });

    while let Some(Ok(message)) = stream.next().await {
        match message {
            Message::Text(text) => handle_text(&text, id, &context),
            Message::Binary(bytes) => handle_binary(bytes.as_ref(), id, &context),
            Message::Close(_) => break,
            // Ping/pong and the rest are tungstenite's business.
            _ => {}
        }
    }

    // The writer only ends when the broadcast does, and that outlives every
    // connection; abort it rather than leaking a task per visit.
    writer.abort();
    tracing::info!(connection = id, "a browser disconnected");
}

/// Routes one text frame: a control frame, or a command.
fn handle_text(text: &str, id: u64, context: &ConnectionContext) {
    let Ok(mut value) = serde_json::from_str::<serde_json::Value>(text) else {
        send_to(context, error_json("malformed JSON"));
        return;
    };

    // An empty `payload` is normalised to *no* payload. Unit variants (most
    // of the voice controls) take no content, and serde's adjacent-tagged
    // deserialisation rejects `"payload": {}` for them — a trap for any client
    // that always includes the key. An empty map carries no information, so
    // dropping it here is lossless and saves every future client the lesson.
    if value.get("payload").is_some_and(serde_json::Value::is_null)
        || value
            .get("payload")
            .and_then(serde_json::Value::as_object)
            .is_some_and(serde_json::Map::is_empty)
    {
        value.as_object_mut().map(|object| object.remove("payload"));
    }

    if value.get("kind").is_some() {
        // Auth is spent; anything else that claims to be control is a client
        // bug, and saying so beats silence.
        send_to(context, error_json("unknown control frame"));
        return;
    }

    match serde_json::from_value::<Command>(value) {
        Ok(command) => {
            if context
                .commands
                .send(GatewayCommand::Command(Box::new(command)))
                .is_err()
            {
                tracing::warn!(connection = id, "the worker is gone; command dropped");
            }
        }
        Err(error) => send_to(context, error_json(&format!("unknown command: {error}"))),
    }
}

/// Routes one binary frame: captured audio.
fn handle_binary(bytes: &[u8], id: u64, context: &ConnectionContext) {
    match crate::voice::parse_input_frame(bytes) {
        Some(frame) => {
            let _ = context
                .commands
                .send(GatewayCommand::Audio { from: id, frame });
        }
        None => send_to(
            context,
            error_json("a binary frame must be one 960-sample mono input frame"),
        ),
    }
}

/// Queues one error frame for every connection.
///
/// Errors are broadcast like everything else: with no request ids (v1), an
/// error caused by one tab is visible to all of them, and pretending
/// otherwise would need the correlation the protocol does not have.
fn send_to(context: &ConnectionContext, message: String) {
    let _ = context.outbound.send(Outbound::Text(message));
}

fn error_json(message: &str) -> String {
    serde_json::json!({ "kind": "error", "message": message }).to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn token_comparison_is_exact() {
        assert!(token_matches("abc123", "abc123"));
        assert!(!token_matches("abc123", "abc124"));
        assert!(!token_matches("abc123", "abc12"));
        assert!(!token_matches("abc123", ""));
        assert!(!token_matches("", "x"));
        assert!(token_matches("", ""));
    }

    #[test]
    fn the_auth_frame_is_the_only_control_frame() {
        let frame: ControlFrame = serde_json::from_str(r#"{"kind":"auth","token":"t"}"#).unwrap();
        assert!(matches!(frame, ControlFrame::Auth { .. }));

        assert!(serde_json::from_str::<ControlFrame>(r#"{"kind":"ping"}"#).is_err());
        assert!(serde_json::from_str::<ControlFrame>(r#"{"command":"settings"}"#).is_err());
    }
}
