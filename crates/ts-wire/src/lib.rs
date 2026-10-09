//! The JSON vocabulary every front-end speaks.
//!
//! Two front-ends ask the core for things — the Flutter app through the C ABI,
//! the web through the gateway (`docs/gateway.md`) — and this crate is the one
//! spelling of what they may ask for ([`Command`]) and of what comes back
//! ([`FfiEvent`]). Sharing it is what keeps "the web can do what the desktop
//! can" a property of the code rather than a promise (§52).
//!
//! What lives here is vocabulary only: no queue, no transport, no entry
//! points. `ts-ffi` keeps the C ABI and its polling queue; `ts-gateway` keeps
//! the WebSocket and its fan-out.
//!
//! # Two wire shapes, one vocabulary
//!
//! - `ts-ffi` takes **one JSON argument per C entry point** and builds a
//!   [`Command`] by hand (the Dart side is built against exactly that).
//! - The gateway takes a **tagged envelope** — `{"command": …, "payload": …}` —
//!   deserialised with the derives below. That envelope is new surface defined
//!   for the web; the ABI never uses it.

mod command;
mod event;

pub use command::{AudioDirection, Command};
pub use event::{CommandOutcome, FfiEvent};

/// Decodes a bounded upload before forwarding bytes through the core.
pub fn decode_avatar(image: Option<&str>) -> Result<Option<Vec<u8>>, ts_model::ClientError> {
    use base64::Engine as _;
    let Some(image) = image else {
        return Ok(None);
    };
    if image.len() > 273068 {
        return Err(ts_model::ClientError::Unsupported(
            "avatar exceeds 200 KiB".into(),
        ));
    }
    let bytes = base64::engine::general_purpose::STANDARD
        .decode(image)
        .map_err(|_| ts_model::ClientError::Unsupported("invalid avatar encoding".into()))?;
    if bytes.is_empty() || bytes.len() > 204800 {
        return Err(ts_model::ClientError::Unsupported(
            "avatar must contain 1 to 204800 bytes".into(),
        ));
    }
    Ok(Some(bytes))
}

#[cfg(test)]
mod avatar_tests {
    use super::*;
    #[test]
    fn removal_is_distinct_from_empty_or_malformed_uploads() {
        assert_eq!(decode_avatar(None).unwrap(), None);
        assert!(decode_avatar(Some("")).is_err());
        assert!(decode_avatar(Some("not base64!")).is_err());
        assert!(decode_avatar(Some(&"A".repeat(273069))).is_err());
    }
    #[test]
    fn failed_image_results_still_identify_the_requested_client() {
        let event = FfiEvent::avatar(
            ts_model::SessionId::new(1),
            ts_model::ClientId::new(2),
            Err(ts_model::ClientError::Timeout),
        );
        let json = serde_json::to_value(event).unwrap();
        assert_eq!(json["data"]["client_id"], 2);
        assert_eq!(json["outcome"]["status"], "failed");
    }
}
