use serde::{Deserialize, Serialize};

/// Voice codecs the client can carry.
///
/// TeamSpeak 3 negotiates Opus, and TS6 continues to; the others are listed so
/// that an unexpected negotiation fails with a clear error instead of being
/// misread as Opus.
///
/// Opus appears twice because TeamSpeak puts it on the wire twice: "Opus Voice"
/// and "Opus Music" are two values of the codec byte, not one value with a
/// bitrate knob. They differ in channel count (mono against stereo) and in which
/// libopus application the sender used, and a receiver takes the byte as the
/// answer to both. [`Codec::Opus`] is the voice profile, as the name it had
/// before this client could send music.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Codec {
    /// Opus, 48 kHz, mono, tuned for speech (§28).
    Opus,
    /// Opus, 48 kHz, stereo, tuned for music.
    OpusMusic,
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
        matches!(self, Self::Opus | Self::OpusMusic)
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
    /// A voice-profile packet for `payload` at `sequence`.
    #[must_use]
    pub fn opus(payload: Vec<u8>, sequence: u32) -> Self {
        Self::with_codec(Codec::Opus, payload, sequence)
    }

    /// A music-profile packet, which the receiver will decode as stereo.
    #[must_use]
    pub fn opus_music(payload: Vec<u8>, sequence: u32) -> Self {
        Self::with_codec(Codec::OpusMusic, payload, sequence)
    }

    fn with_codec(codec: Codec, payload: Vec<u8>, sequence: u32) -> Self {
        Self {
            codec,
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
    fn only_the_two_opus_profiles_are_encodable() {
        assert!(Codec::Opus.can_encode());
        assert!(Codec::OpusMusic.can_encode());
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

    #[test]
    fn the_music_profile_is_a_different_codec_not_a_flag() {
        // The receiver reads the codec byte, so a stereo frame labelled
        // `Opus` would be decoded as mono and lose a channel.
        let music = VoicePacket::opus_music(vec![1, 2, 3], 4);
        assert_eq!(music.codec, Codec::OpusMusic);
        assert_eq!(music.sequence, 4);
        assert_ne!(music.codec, Codec::Opus);
    }

    #[test]
    fn the_codec_wire_names_are_stable() {
        assert_eq!(serde_json::to_string(&Codec::Opus).unwrap(), "\"opus\"");
        assert_eq!(
            serde_json::to_string(&Codec::OpusMusic).unwrap(),
            "\"opus_music\""
        );
    }
}
