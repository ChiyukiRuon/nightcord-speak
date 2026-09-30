//! Bridging a stored identity onto the one `tsclientlib` expects.
//!
//! The key pair itself is `tsclientlib`'s business; `ts-identity` only stores
//! opaque bytes and the public id. This module is the seam between the two, and
//! it is the only place that knows how those bytes are encoded.

use ts_identity::Identity as StoredIdentity;
use ts_model::{ClientError, IdentityError};
use tsclientlib::Identity as WireIdentity;

/// Generates a brand-new identity, ready to be persisted.
///
/// This is expensive on purpose — TeamSpeak identities carry a proof-of-work
/// counter — so it must run only when no identity was found on disk (§36).
///
/// # Errors
///
/// Returns [`ClientError::Identity`] if the identity cannot be encoded.
pub fn generate() -> Result<StoredIdentity, ClientError> {
    encode(&WireIdentity::create())
}

/// Packs a wire identity into the bytes `ts-identity` stores.
///
/// The wire type's own serde form is used rather than a hand-rolled encoding, so
/// the hash-cash counter and its high-water mark survive a round trip. Encoding
/// only the key would silently reset the counter and make every reconnect
/// recompute the proof of work.
///
/// # Errors
///
/// Returns [`ClientError::Identity`] if serialisation fails.
pub fn encode(identity: &WireIdentity) -> Result<StoredIdentity, ClientError> {
    let unique_id = identity.key().to_pub().get_uid();
    let blob = serde_json::to_vec(identity).map_err(malformed)?;
    Ok(StoredIdentity::new(unique_id, blob))
}

/// Unpacks stored bytes back into the identity `tsclientlib` accepts.
///
/// # Errors
///
/// Returns [`ClientError::Identity`] if the stored bytes cannot be parsed.
/// Callers must surface this rather than falling back to a new identity —
/// doing so would present a different client to the server and lose the user's
/// permissions (§36).
pub fn decode(stored: &StoredIdentity) -> Result<WireIdentity, ClientError> {
    serde_json::from_slice(&stored.identity_blob).map_err(malformed)
}

fn malformed(source: serde_json::Error) -> ClientError {
    ClientError::Identity(IdentityError::Malformed {
        message: source.to_string(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip_preserves_the_public_id() {
        // Generating is deliberately slow (proof of work), so this is the one
        // test that pays for it; everything else reuses the result.
        let wire = WireIdentity::create();
        let stored = encode(&wire).expect("encode");

        let restored = decode(&stored).expect("decode");
        assert_eq!(restored.key().to_pub().get_uid(), stored.unique_id);
        assert_eq!(
            restored.key().to_pub().get_uid(),
            wire.key().to_pub().get_uid()
        );
    }

    #[test]
    fn round_trip_preserves_the_hash_cash_counter() {
        // §36 in miniature: the counter must survive, or every reconnect
        // recomputes the proof of work.
        let wire = WireIdentity::create();
        let stored = encode(&wire).expect("encode");
        let restored = decode(&stored).expect("decode");

        assert_eq!(restored.counter(), wire.counter());
        assert_eq!(restored.max_counter(), wire.max_counter());
        assert_eq!(restored.level(), wire.level());
    }

    #[test]
    fn generate_produces_a_usable_identity() {
        let stored = generate().expect("generate");
        assert!(
            !stored.is_empty(),
            "generated identity must carry key material"
        );
        assert!(
            !stored.unique_id.is_empty(),
            "generated identity must have a public id"
        );
        assert!(decode(&stored).is_ok());
    }

    #[test]
    fn garbage_bytes_are_reported_not_ignored() {
        let broken = StoredIdentity::new("uid=", b"not json".to_vec());
        let err = decode(&broken).unwrap_err();
        assert!(matches!(
            err,
            ClientError::Identity(IdentityError::Malformed { .. })
        ));
    }

    #[test]
    fn debug_output_does_not_leak_the_key() {
        let stored = generate().expect("generate");
        let rendered = format!("{stored:?}");
        assert!(
            rendered.contains("redacted"),
            "identity debug leaked: {rendered}"
        );
    }
}
