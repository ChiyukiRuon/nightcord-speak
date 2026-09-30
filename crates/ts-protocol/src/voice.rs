use serde::{Deserialize, Serialize};

/// Voice codecs the client can carry.
///
/// TeamSpeak 3 negotiates Opus, and TS6 continues to; the others are listed so
/// that an unexpected negotiation fails with a clear error instead of being
/// misread as Opus.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Codec {
    /// Opus, 48 kHz — the only codec this client encodes (§28).
    Opus,
    /// Speex narrowband.
    SpeexNarrowband,
    /// Speex wideband.
    SpeexWideband,
    /// Speex ultra-wideband.
    SpeexUltraWideband,
    /// CELT mono, 48 kHz.
    CeltMono,
    /// Raw PCM fallback.
    Pcm,
}

impl Codec {
    /// Whether this client can encode the codec.
    #[must_use]
    pub const fn can_encode(self) -> bool {
        matches!(self, Self::Opus)
    }
}

/// One encoded voice frame, ready to send.
///
/// Produced by `ts-audio` and handed to a [`crate::Voice`] backend, which owns
/// framing, encryption and the UDP transport. Keeping the packet opaque here
/// means the audio engine never learns a protocol detail.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct VoicePacket {
    /// Codec the payload is encoded with.
    pub codec: Codec,
    /// Encoded frame.
    pub payload: Vec<u8>,
    /// Monotonic frame counter, used by the receiver to order and to detect loss.
    pub sequence: u32,
    /// Whether the frame is a discontinuous-transmission marker.
    ///
    /// Set on the frame that resumes after a silence, so the far end can tell
    /// "they stopped talking" from "packets were lost".
    pub is_dtx_resume: bool,
}

impl VoicePacket {
    /// A packet for `payload` at `sequence`.
    #[must_use]
    pub fn opus(payload: Vec<u8>, sequence: u32) -> Self {
        Self {
            codec: Codec::Opus,
            payload,
            sequence,
            is_dtx_resume: false,
        }
    }

    /// Whether the payload is empty, which means there is nothing to send.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.payload.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_opus_is_encodable() {
        assert!(Codec::Opus.can_encode());
        for other in [
            Codec::SpeexNarrowband,
            Codec::SpeexWideband,
            Codec::SpeexUltraWideband,
            Codec::CeltMono,
            Codec::Pcm,
        ] {
            assert!(!other.can_encode(), "{other:?} should not be encodable");
        }
    }

    #[test]
    fn opus_constructor_sets_the_codec() {
        let packet = VoicePacket::opus(vec![1, 2, 3], 7);
        assert_eq!(packet.codec, Codec::Opus);
        assert_eq!(packet.sequence, 7);
        assert!(!packet.is_empty());
        assert!(VoicePacket::opus(vec![], 0).is_empty());
    }
}
