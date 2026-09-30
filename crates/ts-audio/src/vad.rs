//! Voice activation (§29).
//!
//! A gate that opens when the microphone is loud enough and closes when it has
//! been quiet for long enough. The two delays are not cosmetic: opening
//! immediately clips the first consonant, and closing immediately swallows the
//! gaps between words.

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
        if level >= self.settings.sensitivity {
            self.above_ms = self.above_ms.saturating_add(frame_ms);
            self.below_ms = 0;
            if self.open || self.above_ms >= self.settings.attack_ms {
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

impl Default for VoiceGate {
    fn default() -> Self {
        Self::new(VoiceActivationSettings::default())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Settings with obvious numbers, so the tests read as arithmetic.
    fn settings() -> VoiceActivationSettings {
        VoiceActivationSettings {
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
