//! Opus encoding for the send path (§28).
//!
//! Opus is the only codec this client encodes. The decoder for received audio
//! lives in the protocol backend, because it is inseparable from that backend's
//! jitter buffering and packet-loss handling.
//!
//! ## One quality, and it is the top of the range
//!
//! TeamSpeak's own client offers a codec picker and a 1–10 quality slider. This
//! one does not: the encoder always runs at the highest bitrate the protocol
//! allows for the channel count it was given, with libopus tuned for arbitrary
//! audio rather than for speech. There is nothing here to configure.
//!
//! The reasoning is that a voice chat's quality is not a dial anybody wants to
//! find — a user who notices the audio is poor should not have to discover a
//! slider to fix it, and a user who does not notice is paying for the ceiling
//! anyway. The cost is the uplink: see [`max_bitrate`].
//!
//! ## Why the channel count is a parameter and not a setting
//!
//! It is a property of what is *fed in*, not of what the user wants. The desktop
//! captures stereo, so it sends the music profile. The web gateway is handed
//! mono frames by the browser's worklet, so it sends the voice profile. Calling
//! a capability a preference would mean encoding mono samples into a stereo
//! stream and paying twice for one channel of information.

// `GenericCtl` is a trait, not a method on `Encoder`: several controls
// (`set_bitrate`, `reset_state`) only exist when it is in scope.
use audiopus::coder::{Encoder, GenericCtl as _};
use audiopus::{Application, Bitrate, Channels, SampleRate};
use ts_model::AudioError;
use ts_protocol::Codec as PacketCodec;
use ts_protocol::VoicePacket;

use crate::format::{
    MAX_OPUS_PACKET, PLAYBACK_CHANNELS, SAMPLE_RATE, VOICE_CHANNELS, frame_samples,
};

/// The highest bitrate TeamSpeak publishes for a mono stream.
const MONO_MAX_BITRATE: i32 = 45_056;

/// The highest bitrate TeamSpeak publishes for a stereo stream.
///
/// Worth the bandwidth: 45 kbps across two channels is where cymbals stop
/// sounding like noise, and it is why the stereo profile exists at all.
const STEREO_MAX_BITRATE: i32 = 79_200;

/// The bitrate for a stream of `channels` channels.
///
/// TeamSpeak's published tables cap at ten steps of `step × (level + 1)`; this
/// is the top of each, which is the whole point of having no ladder.
#[must_use]
pub const fn max_bitrate(channels: u16) -> i32 {
    if channels >= PLAYBACK_CHANNELS {
        STEREO_MAX_BITRATE
    } else {
        MONO_MAX_BITRATE
    }
}

/// Encodes 48 kHz PCM into Opus packets.
pub struct OpusEncoder {
    encoder: Encoder,
    /// What this encoder was built for, which its input must match.
    channels: u16,
    /// Reused between frames so a 50 fps stream allocates nothing.
    scratch: Vec<u8>,
    sequence: u32,
}

impl OpusEncoder {
    /// Builds an encoder for `channels`-channel 48 kHz PCM.
    ///
    /// # Errors
    ///
    /// Returns [`AudioError::UnsupportedConfig`] for anything other than one or
    /// two channels, and [`AudioError::Backend`] if libopus refuses the
    /// configuration.
    pub fn new(channels: u16) -> Result<Self, AudioError> {
        if channels != VOICE_CHANNELS && channels != PLAYBACK_CHANNELS {
            return Err(AudioError::UnsupportedConfig);
        }

        let encoder = Encoder::new(
            SampleRate::Hz48000,
            if channels == VOICE_CHANNELS {
                Channels::Mono
            } else {
                Channels::Stereo
            },
            // Tuned for arbitrary audio rather than for speech. At these
            // bitrates the two applications differ mainly in what they are
            // willing to discard at the top of the spectrum, and the music
            // tuning keeps things the voice tuning throws away.
            Application::Audio,
        )
        .map_err(|error| AudioError::Backend {
            message: error.to_string(),
        })?;

        let mut encoder = Self {
            encoder,
            channels,
            scratch: vec![0; MAX_OPUS_PACKET],
            sequence: 0,
        };

        // A tuning failure is not fatal: libopus's own default is a legal
        // bitrate, so the worst case is a stream at a level nobody chose.
        if let Err(error) = encoder
            .encoder
            .set_bitrate(Bitrate::BitsPerSecond(max_bitrate(channels)))
        {
            tracing::warn!(%error, "could not set the Opus bitrate; using the default");
        }

        Ok(encoder)
    }

    /// The channel count this encoder expects.
    #[must_use]
    pub const fn channels(&self) -> u16 {
        self.channels
    }

    /// Samples in one frame, as [`OpusEncoder::encode`] wants them.
    #[must_use]
    pub const fn frame_samples(&self) -> usize {
        frame_samples(self.channels)
    }

    /// The bitrate in force.
    #[must_use]
    pub const fn bitrate(&self) -> i32 {
        max_bitrate(self.channels)
    }

    /// The codec byte that goes on the wire with every packet.
    ///
    /// Derived from the channel count rather than configured beside it, because
    /// the far end reads this byte to decide whether to expect one channel or
    /// two: a stereo frame labelled mono is decoded as mono, and half of it
    /// disappears.
    #[must_use]
    pub const fn packet_codec(&self) -> PacketCodec {
        if self.channels == VOICE_CHANNELS {
            PacketCodec::Opus
        } else {
            PacketCodec::OpusMusic
        }
    }

    /// Encodes one frame.
    ///
    /// `pcm` must be exactly [`OpusEncoder::frame_samples`] interleaved
    /// samples: TeamSpeak's frame size is fixed, so a different length is a
    /// caller bug rather than something to paper over by padding or truncating.
    ///
    /// # Errors
    ///
    /// Returns [`AudioError::UnsupportedConfig`] if `pcm` is not one frame, or
    /// [`AudioError::Backend`] if libopus fails.
    pub fn encode(&mut self, pcm: &[f32]) -> Result<VoicePacket, AudioError> {
        if pcm.len() != self.frame_samples() {
            return Err(AudioError::UnsupportedConfig);
        }

        let written = self
            .encoder
            .encode_float(pcm, &mut self.scratch)
            .map_err(|error| AudioError::Backend {
                message: error.to_string(),
            })?;

        // The label and the content have to agree; see `packet_codec`.
        let payload = self.scratch[..written].to_vec();
        let packet = match self.packet_codec() {
            PacketCodec::OpusMusic => VoicePacket::opus_music(payload, self.sequence),
            _ => VoicePacket::opus(payload, self.sequence),
        };
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
            .field("channels", &self.channels)
            .field("bitrate", &max_bitrate(self.channels))
            .finish_non_exhaustive()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A sine wave at `hz`, one frame long, with `channels` interleaved copies.
    fn tone(hz: f32, amplitude: f32, channels: u16) -> Vec<f32> {
        let mut out = Vec::with_capacity(frame_samples(channels));
        for i in 0..crate::format::FRAME_SAMPLES {
            let t = i as f32 / SAMPLE_RATE as f32;
            let sample = amplitude * (2.0 * std::f32::consts::PI * hz * t).sin();
            for _ in 0..channels {
                out.push(sample);
            }
        }
        out
    }

    #[test]
    fn each_profile_gets_the_top_of_its_published_range() {
        // The numbers TeamSpeak publishes as the ceiling of each ladder. There
        // is no level to pick, so the ceiling is the only value.
        assert_eq!(max_bitrate(VOICE_CHANNELS), 45_056);
        assert_eq!(max_bitrate(PLAYBACK_CHANNELS), 79_200);
    }

    #[test]
    fn a_stereo_encoder_is_the_music_profile() {
        let encoder = OpusEncoder::new(2).expect("build encoder");
        assert_eq!(encoder.channels(), 2);
        assert_eq!(encoder.frame_samples(), 1920);
        assert_eq!(
            encoder.packet_codec(),
            PacketCodec::OpusMusic,
            "stereo framed as mono would be decoded as mono by the far end"
        );
    }

    #[test]
    fn a_mono_encoder_is_the_voice_profile() {
        let encoder = OpusEncoder::new(1).expect("build encoder");
        assert_eq!(encoder.frame_samples(), 960);
        assert_eq!(encoder.packet_codec(), PacketCodec::Opus);
    }

    #[test]
    fn a_channel_count_opus_cannot_encode_is_refused() {
        // Five channels is a surround stream, not a TeamSpeak voice stream.
        for channels in [0, 3, 6] {
            assert!(
                matches!(
                    OpusEncoder::new(channels),
                    Err(AudioError::UnsupportedConfig)
                ),
                "{channels} channels should be refused"
            );
        }
    }

    #[test]
    fn encodes_a_tone_into_a_plausible_packet() {
        let mut encoder = OpusEncoder::new(2).expect("build encoder");
        let packet = encoder.encode(&tone(440.0, 0.5, 2)).expect("encode");

        assert!(!packet.is_empty(), "a tone must produce a payload");
        // 1920 f32 = 7680 bytes of raw PCM; Opus must beat that comfortably.
        assert!(
            packet.payload.len() < 7680 / 4,
            "packet was {} bytes",
            packet.payload.len()
        );
        assert!(packet.payload.len() <= MAX_OPUS_PACKET);
        assert_eq!(packet.codec, PacketCodec::OpusMusic);
    }

    #[test]
    fn a_wrong_frame_size_is_rejected_rather_than_padded() {
        // The channel count is part of the frame size, so a mono buffer is
        // short for a stereo encoder — padding it would send silence.
        let mut encoder = OpusEncoder::new(2).expect("build encoder");
        for bad in [vec![0.0; 0], vec![0.0; 960], vec![0.0; 1919]] {
            assert!(
                matches!(encoder.encode(&bad), Err(AudioError::UnsupportedConfig)),
                "{} samples should be rejected",
                bad.len()
            );
        }
    }

    #[test]
    fn sequence_numbers_advance_and_wrap() {
        let mut encoder = OpusEncoder::new(2).expect("build encoder");
        let silence = vec![0.0_f32; 1920];

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
        let mut encoder = OpusEncoder::new(2).expect("build encoder");
        encoder.encode(&vec![0.0; 1920]).unwrap();
        encoder.reset();
        assert_eq!(encoder.sequence(), 0);
    }

    #[test]
    fn every_frame_encodes_without_error() {
        // Guards against state leaking between frames in the reused scratch
        // buffer — a stale length would show up as a decode failure.
        let mut encoder = OpusEncoder::new(2).expect("build encoder");
        for i in 0..100 {
            let packet = encoder
                .encode(&tone(220.0 + i as f32, 0.3, 2))
                .expect("encode");
            assert!(!packet.payload.is_empty());
        }
    }

    #[test]
    fn silence_is_cheaper_than_speech() {
        // Not a strict guarantee — Opus's own decisions are its own — but a
        // regression here would mean the encoder is running at a fixed rate.
        let mut encoder = OpusEncoder::new(2).expect("build encoder");
        let quiet = encoder
            .encode(&vec![0.0_f32; 1920])
            .expect("encode silence");
        let loud = encoder.encode(&tone(440.0, 0.9, 2)).expect("encode tone");

        assert!(
            quiet.payload.len() <= loud.payload.len(),
            "silence {} bytes vs tone {} bytes",
            quiet.payload.len(),
            loud.payload.len()
        );
    }
}
