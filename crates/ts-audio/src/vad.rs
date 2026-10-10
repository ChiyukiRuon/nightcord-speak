//! Voice activation (§29).
//!
//! Speech classification by default, with a manual RMS threshold as an option.
//! Attack rejects short transients; release bridges pauses between words.

use ts_model::VoiceActivationSettings;

/// Root-mean-square level of a frame, in `0.0..=1.0`.
///
/// Linear rather than dBFS: the threshold is a user-facing slider, and a linear
/// scale is what makes it feel even across its range.
#[must_use]
pub fn rms(frame: &[f32]) -> f32 {
    if frame.is_empty() {
        return 0.0;
    }
    let sum: f32 = frame.iter().map(|sample| sample * sample).sum();
    (sum / frame.len() as f32).sqrt()
}

/// Peak absolute level of a frame, in `0.0..=1.0`.
///
/// Useful for clipping indicators; the gate uses [`rms`], which tracks
/// perceived loudness far better than a single sample can.
#[must_use]
pub fn peak(frame: &[f32]) -> f32 {
    frame
        .iter()
        .fold(0.0_f32, |max, sample| max.max(sample.abs()))
}

/// An RMS-threshold gate with attack and release.
#[derive(Debug, Clone)]
pub struct VoiceGate {
    settings: VoiceActivationSettings,
    open: bool,
    /// Milliseconds spent continuously above the threshold.
    above_ms: u32,
    /// Milliseconds spent continuously below the threshold.
    below_ms: u32,
}

impl VoiceGate {
    /// A gate closed at start, so connecting does not transmit room noise
    /// before the user has said anything.
    #[must_use]
    pub fn new(settings: VoiceActivationSettings) -> Self {
        Self {
            settings,
            open: false,
            above_ms: 0,
            below_ms: 0,
        }
    }

    /// Feeds one frame's level and returns whether to transmit.
    ///
    /// `frame_ms` is how long the level represents, so the caller's frame size
    /// is what sets the time resolution.
    pub fn update(&mut self, level: f32, frame_ms: u32) -> bool {
        self.update_activity(
            level >= self.settings.sensitivity,
            frame_ms,
            self.settings.attack_ms,
        )
    }

    /// Speech classifiers already reject transients; they need less attack delay.
    pub fn update_activity(&mut self, speech: bool, frame_ms: u32, attack_ms: u32) -> bool {
        if speech {
            self.above_ms = self.above_ms.saturating_add(frame_ms);
            self.below_ms = 0;
            if self.open || self.above_ms >= attack_ms {
                self.open = true;
            }
        } else {
            self.below_ms = self.below_ms.saturating_add(frame_ms);
            self.above_ms = 0;
            if self.open && self.below_ms >= self.settings.release_ms {
                self.open = false;
            }
        }

        self.open
    }

    /// Whether the gate is currently letting audio through.
    #[must_use]
    pub const fn is_open(&self) -> bool {
        self.open
    }

    /// The current tuning.
    #[must_use]
    pub const fn settings(&self) -> &VoiceActivationSettings {
        &self.settings
    }

    /// Retunes the gate.
    ///
    /// Does not change whether it is open: a user dragging the sensitivity
    /// slider mid-sentence should not hear themselves cut out.
    pub fn set_settings(&mut self, settings: VoiceActivationSettings) {
        self.settings = settings;
    }

    /// Closes the gate and forgets its timing.
    pub fn reset(&mut self) {
        self.open = false;
        self.above_ms = 0;
        self.below_ms = 0;
    }
}

/// Converts the shared 48 kHz mono stream into Earshot's 16 kHz / 16 ms frames.
/// Carries both filter history and incomplete frames across packet boundaries.
pub(crate) struct SmartVad {
    detector: earshot::Detector,
    history: [f32; 31],
    taps: [f32; 31],
    phase: usize,
    pending: [f32; 256],
    pending_len: usize,
}

impl Default for SmartVad {
    fn default() -> Self {
        // Windowed sinc low-pass: suppress frequencies above the new Nyquist
        // frequency before decimation instead of aliasing them into speech.
        let mut taps = [0.0; 31];
        for (index, tap) in taps.iter_mut().enumerate() {
            let x = index as f32 - 15.0;
            let cutoff = 7000.0 / 48000.0;
            let sinc = if x == 0.0 {
                2.0 * cutoff
            } else {
                (2.0 * std::f32::consts::PI * cutoff * x).sin() / (std::f32::consts::PI * x)
            };
            *tap = sinc * (0.54 - 0.46 * (2.0 * std::f32::consts::PI * index as f32 / 30.0).cos());
        }
        let sum: f32 = taps.iter().sum();
        for tap in &mut taps {
            *tap /= sum;
        }
        Self {
            detector: earshot::Detector::default(),
            history: [0.0; 31],
            taps,
            phase: 0,
            pending: [0.0; 256],
            pending_len: 0,
        }
    }
}

impl SmartVad {
    pub(crate) fn speech(&mut self, frame: &[f32]) -> bool {
        let mut speech = false;
        for &sample in frame {
            self.history.rotate_right(1);
            self.history[0] = if sample.is_finite() {
                sample.clamp(-1.0, 1.0)
            } else {
                0.0
            };
            self.phase += 1;
            if self.phase != 3 {
                continue;
            }
            self.phase = 0;
            self.pending[self.pending_len] =
                self.history.iter().zip(self.taps).map(|(s, t)| s * t).sum();
            self.pending_len += 1;
            if self.pending_len == 256 {
                let score = self.detector.predict_f32(&self.pending);
                // Broadband static can fool the classifier. Require short-lag
                // structure as well; release smoothing carries unvoiced sounds
                // between voiced syllables rather than chopping each consonant.
                let energy: f32 = self.pending.iter().map(|s| s * s).sum();
                let correlation: f32 = self.pending.windows(2).map(|s| s[0] * s[1]).sum();
                speech |= score >= 0.5 && energy > 1e-8 && correlation / energy > 0.35;
                self.pending_len = 0;
            }
        }
        speech
    }

    pub(crate) fn reset(&mut self) {
        self.detector.reset();
        self.history.fill(0.0);
        self.phase = 0;
        self.pending_len = 0;
    }
}

impl Default for VoiceGate {
    fn default() -> Self {
        Self::new(VoiceActivationSettings::default())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Synthesized locally with Windows Speech; no external recording or user audio.
    pub(crate) fn quiet_speech() -> Vec<f32> {
        let wav = include_bytes!("../tests/fixtures/vad-speech.wav");
        let mut offset = 12;
        while offset + 8 <= wav.len() {
            let length =
                u32::from_le_bytes(wav[offset + 4..offset + 8].try_into().unwrap()) as usize;
            if &wav[offset..offset + 4] == b"data" {
                return wav[offset + 8..offset + 8 + length]
                    .chunks_exact(2)
                    .map(|s| f32::from(i16::from_le_bytes([s[0], s[1]])) / 32768.0 * 0.08)
                    .collect();
            }
            offset += 8 + length + length % 2;
        }
        panic!("speech fixture has no PCM data");
    }

    #[test]
    fn smart_detects_speech_below_the_old_volume_threshold() {
        // Regression: the old 0.05 RMS threshold swallowed quiet speech.
        let mut detector = SmartVad::default();
        let frames = quiet_speech();
        let mut detections = 0;
        for frame in frames.chunks_exact(960) {
            assert!(rms(frame) < 0.05);
            detections += usize::from(detector.speech(frame));
        }
        assert!(
            detections >= 10,
            "quiet speech should be recognized, got {detections}"
        );
    }

    #[test]
    fn smart_rejects_silence_and_stationary_noise() {
        let mut detector = SmartVad::default();
        for _ in 0..100 {
            assert!(!detector.speech(&[0.0; 960]));
        }
        let mut state = 42u32;
        let mut detections = 0;
        for _ in 0..100 {
            let frame: Vec<f32> = (0..960)
                .map(|_| {
                    state = state.wrapping_mul(1664525).wrapping_add(1013904223);
                    (state as f32 / u32::MAX as f32 - 0.5) * 0.2
                })
                .collect();
            detections += usize::from(detector.speech(&frame));
        }
        assert!(
            detections < 5,
            "steady noise must not hold the microphone open: {detections}"
        );
        detector.reset();
        assert_eq!(detector.pending_len, 0);
        assert!(!detector.speech(&[0.0; 960]));
    }

    #[test]
    fn smart_preserves_partial_frames_and_filters_aliasing() {
        let mut detector = SmartVad::default();
        detector.speech(&[0.0; 960]);
        assert_eq!(detector.pending_len, 64);
        detector.speech(&[0.0; 960]);
        assert_eq!(detector.pending_len, 128);
        detector.reset();
        let high_frequency: Vec<f32> = (0..960)
            .map(|i| (2.0 * std::f32::consts::PI * 12000.0 * i as f32 / 48000.0).sin())
            .collect();
        detector.speech(&high_frequency);
        assert!(rms(&detector.pending[..detector.pending_len]) < 0.01);
    }

    /// Settings with obvious numbers, so the tests read as arithmetic.
    fn settings() -> VoiceActivationSettings {
        VoiceActivationSettings {
            algorithm: ts_model::VadAlgorithm::Level,
            sensitivity: 0.1,
            attack_ms: 40,
            release_ms: 100,
        }
    }

    #[test]
    fn silence_has_no_level() {
        assert_eq!(rms(&[]), 0.0);
        assert_eq!(rms(&[0.0; 960]), 0.0);
        assert_eq!(peak(&[0.0, -0.0, 0.0]), 0.0);
    }

    #[test]
    fn rms_of_a_constant_signal_is_its_magnitude() {
        // All samples equal to `a` ⇒ RMS is exactly `a`.
        assert!((rms(&[0.5; 100]) - 0.5).abs() < 1e-6);
    }

    #[test]
    fn rms_of_a_full_scale_square_wave_is_one() {
        let wave: Vec<f32> = (0..100)
            .map(|i| if i % 2 == 0 { 1.0 } else { -1.0 })
            .collect();
        assert!((rms(&wave) - 1.0).abs() < 1e-6);
    }

    #[test]
    fn a_quiet_signal_never_opens_the_gate() {
        let mut gate = VoiceGate::new(settings());
        for _ in 0..50 {
            assert!(
                !gate.update(0.05, 20),
                "level below the threshold must stay closed"
            );
        }
    }

    #[test]
    fn a_loud_signal_opens_only_after_the_attack() {
        let mut gate = VoiceGate::new(settings());

        // 40 ms attack at 20 ms per frame: the second frame opens it.
        assert!(!gate.update(0.5, 20), "must not open on the first frame");
        assert!(gate.update(0.5, 20), "should open once the attack elapsed");
        assert!(gate.is_open());
    }

    #[test]
    fn the_attack_needs_continuous_level() {
        // A single loud frame surrounded by quiet must not open the gate, or a
        // door slam would key the microphone.
        let mut gate = VoiceGate::new(settings());
        assert!(!gate.update(0.5, 20));
        assert!(!gate.update(0.01, 20));
        assert!(!gate.update(0.5, 20));
        assert!(!gate.is_open());
    }

    #[test]
    fn short_gaps_do_not_close_the_gate() {
        let mut gate = VoiceGate::new(settings());
        gate.update(0.5, 20);
        assert!(gate.update(0.5, 20));

        // 60 ms of quiet is less than the 100 ms release; still transmitting.
        assert!(gate.update(0.0, 20));
        assert!(gate.update(0.0, 20));
        assert!(gate.update(0.0, 20));
        assert!(gate.is_open());
    }

    #[test]
    fn a_long_silence_closes_the_gate() {
        let mut gate = VoiceGate::new(settings());
        gate.update(0.5, 20);
        assert!(gate.update(0.5, 20));

        // 120 ms of quiet exceeds the 100 ms release.
        for _ in 0..6 {
            gate.update(0.0, 20);
        }
        assert!(!gate.is_open());
    }

    #[test]
    fn a_gap_shorter_than_the_release_does_not_restart_the_attack() {
        // Once open, speech resumes immediately rather than paying the attack
        // again — that is the whole point of the release window.
        let mut gate = VoiceGate::new(settings());
        gate.update(0.5, 20);
        gate.update(0.5, 20);
        gate.update(0.0, 20);
        assert!(
            gate.update(0.5, 20),
            "resumed speech should transmit at once"
        );
    }

    #[test]
    fn retuning_does_not_disturb_an_open_gate() {
        let mut gate = VoiceGate::new(settings());
        gate.update(0.5, 20);
        gate.update(0.5, 20);
        assert!(gate.is_open());

        gate.set_settings(VoiceActivationSettings {
            sensitivity: 0.9,
            ..settings()
        });
        assert!(
            gate.is_open(),
            "dragging the slider must not cut the user off"
        );
    }

    #[test]
    fn reset_closes_the_gate() {
        let mut gate = VoiceGate::new(settings());
        gate.update(0.5, 20);
        gate.update(0.5, 20);
        assert!(gate.is_open());

        gate.reset();
        assert!(!gate.is_open());
        // And the attack is owed again.
        assert!(!gate.update(0.5, 20));
    }
}
