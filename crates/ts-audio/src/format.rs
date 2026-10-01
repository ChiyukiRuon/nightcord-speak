//! The one place the audio format is defined.
//!
//! Everything here is Opus at 48 kHz in 20 ms frames. The channel counts differ
//! by direction, and on purpose:
//!
//! | Path | Channels | Why |
//! | --- | --- | --- |
//! | Send, voice profile | 1 | TeamSpeak's "Opus Voice" is mono. |
//! | Send, music profile | 2 | TeamSpeak's "Opus Music" is stereo. |
//! | Capture | 2 | Always, so switching profiles does not reopen the device. |
//! | Playback | 2 | `tsclientlib` decodes to stereo. |
//!
//! Capture being stereo even for the mono voice profile costs one downmix per
//! frame and buys the thing that matters: the microphone is opened once per call
//! rather than once per profile change.

/// Sample rate the voice codec runs at, in Hz.
pub const SAMPLE_RATE: u32 = 48_000;

/// Duration of one voice frame, in milliseconds.
///
/// 20 ms is what TeamSpeak uses; it is not configurable on the wire.
pub const FRAME_MS: u32 = 20;

/// Samples in one mono frame — 960 at 48 kHz.
pub const FRAME_SAMPLES: usize = (SAMPLE_RATE as usize / 1000) * FRAME_MS as usize;

/// Channels in the mono voice profile — what [`crate::format::PCM_BYTES_PER_SECOND`]
/// is computed from, and what `ts-audio`'s own tests name.
pub const VOICE_CHANNELS: u16 = 1;

/// Channels on both sides of the engine that are not the mono voice profile:
/// what capture always produces, and what the mixer always emits.
///
/// The name comes from the playback side, which had it first; capture joined it
/// when the stereo music profile needed a second channel to exist at all.
pub const PLAYBACK_CHANNELS: u16 = 2;

/// Samples in one stereo playback buffer — 1920.
pub const PLAYBACK_SAMPLES: usize = FRAME_SAMPLES * PLAYBACK_CHANNELS as usize;

/// Largest packet Opus can produce, used to size encode buffers.
pub const MAX_OPUS_PACKET: usize = 1275;

/// Bytes per second of raw PCM at this format, for buffer sizing.
pub const PCM_BYTES_PER_SECOND: u32 = SAMPLE_RATE * VOICE_CHANNELS as u32 * 4;

/// Samples in one frame of `channels` interleaved channels.
#[must_use]
pub const fn frame_samples(channels: u16) -> usize {
    FRAME_SAMPLES * channels as usize
}

/// Whether `samples` is a frame the encoder will accept.
///
/// TeamSpeak always sends 20 ms, so anything else is a bug upstream of here
/// rather than something to resample around.
#[must_use]
pub const fn is_full_frame(samples: usize, channels: u16) -> bool {
    samples == frame_samples(channels)
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
        assert!(is_full_frame(960, VOICE_CHANNELS));
        assert!(!is_full_frame(959, VOICE_CHANNELS));
        assert!(
            !is_full_frame(1920, VOICE_CHANNELS),
            "1920 is a stereo frame, not a mono one"
        );
        assert!(!is_full_frame(0, VOICE_CHANNELS));

        // The same length that is wrong for mono is right for stereo, which is
        // the whole reason this takes a channel count.
        assert!(is_full_frame(1920, PLAYBACK_CHANNELS));
        assert!(!is_full_frame(960, PLAYBACK_CHANNELS));
    }

    #[test]
    fn a_frame_scales_with_its_channel_count() {
        assert_eq!(frame_samples(1), 960);
        assert_eq!(frame_samples(2), PLAYBACK_SAMPLES);
    }
}
