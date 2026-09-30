//! Opus encoding for the send path (§28).
//!
//! Opus is the only codec this client encodes. The decoder for received audio
//! lives in the protocol backend, because it is inseparable from that backend's
//! jitter buffering and packet-loss handling.

// `GenericCtl` is a trait, not a method on `Encoder`: several controls
// (`set_bitrate`, `reset_state`) only exist when it is in scope.
use audiopus::coder::{Encoder, GenericCtl as _};
use audiopus::{Application, Bitrate, Channels, SampleRate};
use ts_model::AudioError;
use ts_protocol::VoicePacket;

use crate::format::{FRAME_SAMPLES, MAX_OPUS_PACKET, SAMPLE_RATE};

/// Target bitrate for voice, in bits per second.
///
/// TeamSpeak's own client sits in the 20–32 kbps range. This is high enough to
/// stay intelligible under packet loss and low enough not to dominate a slow
/// uplink when several clients transmit at once.
const VOICE_BITRATE: i32 = 24_000;

/// Encodes mono 48 kHz PCM into Opus packets.
pub struct OpusEncoder {
    encoder: Encoder,
    /// Reused between frames so a 50 fps stream allocates nothing.
    scratch: Vec<u8>,
    sequence: u32,
}

impl OpusEncoder {
    /// Builds an encoder configured for voice.
    ///
    /// Uses [`Application::Voip`] rather than `Audio`: it optimises for speech
    /// intelligibility and enables discontinuous transmission, which is what
    /// keeps a mostly-silent microphone cheap.
    ///
    /// # Errors
    ///
    /// Returns [`AudioError::Backend`] if libopus refuses the configuration.
    pub fn new() -> Result<Self, AudioError> {
        let encoder = Encoder::new(
            SampleRate::Hz48000,
            // Voice is mono on the wire; `tsclientlib` decodes to stereo for
            // playback, but nothing we send is stereo.
            Channels::Mono,
            Application::Voip,
        )
        .map_err(|error| AudioError::Backend {
            message: error.to_string(),
        })?;

        let mut encoder = Self {
            encoder,
            scratch: vec![0; MAX_OPUS_PACKET],
            sequence: 0,
        };

        // A tuning failure is not fatal: the defaults Opus picks are within
        // range, so fall back to them rather than refusing to start.
        if let Err(error) = encoder
            .encoder
            .set_bitrate(Bitrate::BitsPerSecond(VOICE_BITRATE))
        {
            tracing::warn!(%error, "could not set the Opus bitrate; using the default");
        }

        Ok(encoder)
    }

    /// Encodes one frame.
    ///
    /// `pcm` must be exactly [`FRAME_SAMPLES`] samples: TeamSpeak's frame size
    /// is fixed, so a different length is a caller bug rather than something to
    /// paper over by padding or truncating.
    ///
    /// # Errors
    ///
    /// Returns [`AudioError::UnsupportedConfig`] if `pcm` is not one frame, or
    /// [`AudioError::Backend`] if libopus fails.
    pub fn encode(&mut self, pcm: &[f32]) -> Result<VoicePacket, AudioError> {
        if pcm.len() != FRAME_SAMPLES {
            return Err(AudioError::UnsupportedConfig);
        }

        let written = self
            .encoder
            .encode_float(pcm, &mut self.scratch)
            .map_err(|error| AudioError::Backend {
                message: error.to_string(),
            })?;

        let packet = VoicePacket::opus(self.scratch[..written].to_vec(), self.sequence);
        self.sequence = self.sequence.wrapping_add(1);
        Ok(packet)
    }

    /// The sequence number the next packet will carry.
    ///
    /// Wraps at `u16::MAX`, matching the wire field's width.
    #[must_use]
    pub fn sequence(&self) -> u16 {
        self.sequence as u16
    }

    /// Clears encoder state, as after a reconnect.
    pub fn reset(&mut self) {
        self.sequence = 0;
        if let Err(error) = self.encoder.reset_state() {
            tracing::warn!(%error, "could not reset the Opus encoder");
        }
    }

    /// The sample rate this encoder expects.
    #[must_use]
    pub const fn sample_rate(&self) -> u32 {
        SAMPLE_RATE
    }
}

impl std::fmt::Debug for OpusEncoder {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("OpusEncoder")
            .field("sequence", &self.sequence)
            .field("bitrate", &VOICE_BITRATE)
            .finish_non_exhaustive()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A sine wave at `hz`, one frame long.
    fn tone(hz: f32, amplitude: f32) -> Vec<f32> {
        (0..FRAME_SAMPLES)
            .map(|i| {
                let t = i as f32 / SAMPLE_RATE as f32;
                amplitude * (2.0 * std::f32::consts::PI * hz * t).sin()
            })
            .collect()
    }

    #[test]
    fn encodes_a_tone_into_a_plausible_packet() {
        let mut encoder = OpusEncoder::new().expect("build encoder");
        let packet = encoder.encode(&tone(440.0, 0.5)).expect("encode");

        assert!(!packet.is_empty(), "a tone must produce a payload");
        // 960 f32 = 3840 bytes of raw PCM; Opus must beat that comfortably.
        assert!(
            packet.payload.len() < 3840 / 4,
            "packet was {} bytes",
            packet.payload.len()
        );
        assert!(packet.payload.len() <= MAX_OPUS_PACKET);
    }

    #[test]
    fn sequence_numbers_advance_and_wrap() {
        let mut encoder = OpusEncoder::new().expect("build encoder");
        let silence = vec![0.0_f32; FRAME_SAMPLES];

        encoder.encode(&silence).unwrap();
        assert_eq!(encoder.sequence(), 1);
        encoder.encode(&silence).unwrap();
        assert_eq!(encoder.sequence(), 2);

        encoder.sequence = u32::from(u16::MAX);
        assert_eq!(encoder.sequence(), u16::MAX);
        encoder.encode(&silence).unwrap();
        assert_eq!(
            encoder.sequence(),
            0,
            "the wire field is 16 bits; it must wrap"
        );
    }

    #[test]
    fn reset_restarts_the_sequence() {
        let mut encoder = OpusEncoder::new().expect("build encoder");
        encoder.encode(&vec![0.0; FRAME_SAMPLES]).unwrap();
        encoder.reset();
        assert_eq!(encoder.sequence(), 0);
    }

    #[test]
    fn a_wrong_frame_size_is_rejected_rather_than_padded() {
        let mut encoder = OpusEncoder::new().expect("build encoder");

        for bad in [vec![0.0; 0], vec![0.0; 480], vec![0.0; 1920]] {
            let result = encoder.encode(&bad);
            assert!(
                matches!(result, Err(AudioError::UnsupportedConfig)),
                "{} samples should be rejected, got {result:?}",
                bad.len()
            );
        }
    }

    #[test]
    fn silence_is_cheaper_than_speech() {
        // Not a strict guarantee — Opus's DTX decisions are its own — but a
        // regression here would mean the encoder is running at a fixed rate.
        let mut encoder = OpusEncoder::new().expect("build encoder");
        let quiet = encoder
            .encode(&vec![0.0_f32; FRAME_SAMPLES])
            .expect("encode silence");
        let loud = encoder.encode(&tone(440.0, 0.9)).expect("encode tone");

        assert!(
            quiet.payload.len() <= loud.payload.len(),
            "silence {} bytes vs tone {} bytes",
            quiet.payload.len(),
            loud.payload.len()
        );
    }

    #[test]
    fn every_frame_encodes_without_error() {
        // Guards against state leaking between frames in the reused scratch
        // buffer — a stale length would show up as a decode failure.
        let mut encoder = OpusEncoder::new().expect("build encoder");
        for i in 0..100 {
            let packet = encoder
                .encode(&tone(220.0 + i as f32, 0.3))
                .expect("encode");
            assert!(!packet.payload.is_empty());
        }
    }
}
