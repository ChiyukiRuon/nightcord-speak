//! Voice support for the headless client.
//!
//! Two jobs: a sink that reports what arrives, so a headless run can *prove*
//! audio flowed without anyone listening, and a tone generator that lets one
//! process transmit while another receives — which is the only way to exercise
//! the full path without a second person and two microphones.

use std::sync::Arc;
use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};
use std::time::Duration;

use ts_audio::{FRAME_MS, FRAME_SAMPLES, SAMPLE_RATE, format};
use ts_protocol::AudioSink;

/// A sink that counts what the backend decoded.
///
/// Deliberately does not play anything: on a headless box the point is to show
/// that frames arrived and carried a signal, not to make a sound.
#[derive(Debug, Default)]
pub struct AudioReport {
    /// Frames pushed since the run started.
    frames: AtomicU64,
    /// Total samples pushed.
    samples: AtomicU64,
    /// Loudest sample seen, as `f32` bits.
    peak: AtomicU32,
}

impl AudioReport {
    /// A report with nothing counted yet.
    #[must_use]
    pub fn new() -> Arc<Self> {
        Arc::new(Self::default())
    }

    /// Frames received so far.
    #[must_use]
    pub fn frames(&self) -> u64 {
        self.frames.load(Ordering::Relaxed)
    }

    /// Total samples received so far.
    #[must_use]
    pub fn samples(&self) -> u64 {
        self.samples.load(Ordering::Relaxed)
    }

    /// The loudest sample seen, in `0.0..=1.0`.
    #[must_use]
    pub fn peak(&self) -> f32 {
        f32::from_bits(self.peak.load(Ordering::Relaxed))
    }

    /// How many seconds of audio have arrived.
    #[must_use]
    pub fn seconds(&self) -> f64 {
        self.samples() as f64 / (SAMPLE_RATE as f64 * format::PLAYBACK_CHANNELS as f64)
    }
}

impl AudioSink for AudioReport {
    fn push(&self, interleaved: &[f32]) {
        self.frames.fetch_add(1, Ordering::Relaxed);
        self.samples
            .fetch_add(interleaved.len() as u64, Ordering::Relaxed);

        let peak = interleaved
            .iter()
            .fold(0.0_f32, |max, sample| max.max(sample.abs()));
        // A plain load-then-store race is harmless here: several writers can
        // only ever push the reported peak up, and losing one update just means
        // the next frame reports it.
        if peak > f32::from_bits(self.peak.load(Ordering::Relaxed)) {
            self.peak.store(peak.to_bits(), Ordering::Relaxed);
        }
    }

    fn space(&self) -> usize {
        // Nothing is queued, so there is always room.
        usize::MAX
    }
}

/// Generates one frame of a sine wave.
///
/// A thin wrapper around `ts-audio`'s generator rather than a second
/// implementation: the app's speaker test needs the same wave, and two copies
/// would drift in the way that is hardest to notice — one of them clicking.
pub fn tone_frame(hz: f32, amplitude: f32, phase: &mut f32) -> Vec<f32> {
    ts_audio::sine(hz, amplitude, FRAME_SAMPLES, phase)
}

/// How long to wait between transmitted frames.
///
/// Matches the codec's frame duration, so the tone leaves at real time rather
/// than as fast as the encoder can produce it.
#[must_use]
pub const fn frame_interval() -> Duration {
    Duration::from_millis(FRAME_MS as u64)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_fresh_report_is_empty() {
        let report = AudioReport::new();
        assert_eq!(report.frames(), 0);
        assert_eq!(report.samples(), 0);
        assert_eq!(report.peak(), 0.0);
        // Nothing queued means unlimited room, so the backend keeps pushing.
        assert_eq!(report.space(), usize::MAX);
    }

    #[test]
    fn pushing_audio_is_counted() {
        let report = AudioReport::new();
        report.push(&[0.0; format::PLAYBACK_SAMPLES]);
        report.push(&[0.0; format::PLAYBACK_SAMPLES]);

        assert_eq!(report.frames(), 2);
        assert_eq!(report.samples(), (format::PLAYBACK_SAMPLES * 2) as u64);
        // Two frames is 40 ms.
        assert!((report.seconds() - 0.04).abs() < 1e-9);
    }

    #[test]
    fn the_peak_survives_a_quieter_frame() {
        let report = AudioReport::new();
        report.push(&[0.8, -0.3]);
        report.push(&[0.1, 0.1]);

        assert!(
            (report.peak() - 0.8).abs() < 1e-6,
            "peak was {}",
            report.peak()
        );
    }

    #[test]
    fn a_tone_frame_has_the_right_length_and_level() {
        let mut phase = 0.0;
        let frame = tone_frame(440.0, 0.5, &mut phase);

        assert_eq!(frame.len(), FRAME_SAMPLES);
        let peak = frame.iter().fold(0.0_f32, |m, s| m.max(s.abs()));
        assert!((peak - 0.5).abs() < 0.01, "peak was {peak}");
    }

    #[test]
    fn consecutive_frames_join_without_a_discontinuity() {
        // Carrying the phase is the whole point; restarting it would put a step
        // at every frame boundary.
        let mut phase = 0.0;
        let first = tone_frame(440.0, 0.5, &mut phase);
        let second = tone_frame(440.0, 0.5, &mut phase);

        let jump = (second[0] - first[first.len() - 1]).abs();
        let per_sample = 2.0 * std::f32::consts::PI * 440.0 / SAMPLE_RATE as f32 * 0.5;
        assert!(
            jump < per_sample * 4.0,
            "phase restarted: jump of {jump} between frames"
        );
    }

    #[test]
    fn the_frame_interval_matches_the_codec() {
        assert_eq!(frame_interval(), Duration::from_millis(20));
    }
}
