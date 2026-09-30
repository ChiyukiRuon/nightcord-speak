//! The one place the audio format is defined.
//!
//! TeamSpeak voice is Opus at 48 kHz, mono, in 20 ms frames. The decoder that
//! `tsclientlib` runs produces *stereo* interleaved `f32`, because a single
//! client's stream can end up on both channels — so the encode side and the
//! playback side disagree on channel count on purpose, and everything that
//! crosses between them has to go through these constants.

/// Sample rate the voice codec runs at, in Hz.
pub const SAMPLE_RATE: u32 = 48_000;

/// Duration of one voice frame, in milliseconds.
///
/// 20 ms is what TeamSpeak uses; it is not configurable on the wire.
pub const FRAME_MS: u32 = 20;

/// Samples in one mono frame — 960 at 48 kHz.
pub const FRAME_SAMPLES: usize = (SAMPLE_RATE as usize / 1000) * FRAME_MS as usize;

/// Channels on the wire. TeamSpeak voice is mono.
pub const VOICE_CHANNELS: u16 = 1;

/// Channels the mixer produces. `tsclientlib` decodes to stereo.
pub const PLAYBACK_CHANNELS: u16 = 2;

/// Samples in one stereo playback buffer — 1920.
pub const PLAYBACK_SAMPLES: usize = FRAME_SAMPLES * PLAYBACK_CHANNELS as usize;

/// Largest packet Opus can produce, used to size encode buffers.
pub const MAX_OPUS_PACKET: usize = 1275;

/// Bytes per second of raw PCM at this format, for buffer sizing.
pub const PCM_BYTES_PER_SECOND: u32 = SAMPLE_RATE * VOICE_CHANNELS as u32 * 4;

/// Whether `samples` is a frame the encoder will accept.
///
/// TeamSpeak always sends 20 ms, so anything else is a bug upstream of here
/// rather than something to resample around.
#[must_use]
pub const fn is_full_frame(samples: usize) -> bool {
    samples == FRAME_SAMPLES
}

/// Converts a duration to a whole number of frames, rounding up.
#[must_use]
pub const fn frames_for_ms(millis: u32) -> u32 {
    millis.div_ceil(FRAME_MS)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frame_arithmetic_matches_the_wire_format() {
        assert_eq!(FRAME_SAMPLES, 960);
        assert_eq!(PLAYBACK_SAMPLES, 1920);
        assert_eq!(FRAME_MS, 20);
        // 20 ms at 48 kHz is 960 samples; the two definitions must agree.
        assert_eq!(
            SAMPLE_RATE as usize / 1000 * FRAME_MS as usize,
            FRAME_SAMPLES
        );
    }

    #[test]
    fn one_second_is_fifty_frames() {
        assert_eq!(frames_for_ms(1_000), 50);
        assert_eq!(
            (1_000 / FRAME_MS) as usize * FRAME_SAMPLES,
            SAMPLE_RATE as usize
        );
    }

    #[test]
    fn frame_conversion_rounds_up() {
        // A partial frame still needs a whole buffer to live in.
        assert_eq!(frames_for_ms(1), 1);
        assert_eq!(frames_for_ms(21), 2);
        assert_eq!(frames_for_ms(0), 0);
    }

    #[test]
    fn only_full_frames_are_accepted() {
        assert!(is_full_frame(960));
        assert!(!is_full_frame(959));
        assert!(
            !is_full_frame(1920),
            "1920 is a playback buffer, not a mono frame"
        );
        assert!(!is_full_frame(0));
    }
}
