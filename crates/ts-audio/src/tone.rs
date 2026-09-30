//! A sine wave, for checking a device without a second person.
//!
//! Lives here rather than in the CLI that first needed it, because the speaker
//! test needs the same wave and two implementations of "a tone" would drift in
//! exactly the way that is hardest to notice — one of them clicking.

use std::f32::consts::TAU;

use crate::format::SAMPLE_RATE;

/// Fills `samples` mono samples of a sine wave at `hz`.
///
/// `phase` is carried by the caller so consecutive frames join without a click:
/// restarting the wave every 20 ms would be heard as a rattle rather than a
/// tone.
#[must_use]
pub fn sine(hz: f32, amplitude: f32, samples: usize, phase: &mut f32) -> Vec<f32> {
    let step = TAU * hz / SAMPLE_RATE as f32;
    (0..samples)
        .map(|_| {
            let value = amplitude * phase.sin();
            *phase = (*phase + step) % TAU;
            value
        })
        .collect()
}

/// Duplicates each mono sample into two channels.
///
/// Playback is interleaved stereo; the transmit path is mono. A test tone goes
/// out through the speakers, so it needs the former.
#[must_use]
pub fn to_stereo(mono: &[f32]) -> Vec<f32> {
    mono.iter().flat_map(|sample| [*sample, *sample]).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_tone_stays_inside_the_amplitude_it_was_given() {
        let mut phase = 0.0;
        let samples = sine(440.0, 0.3, 4800, &mut phase);
        assert!(
            samples.iter().all(|s| s.abs() <= 0.3 + f32::EPSILON),
            "a tone louder than asked for would clip"
        );
    }

    #[test]
    fn consecutive_frames_join_without_a_jump() {
        // The whole reason `phase` is carried: a restart every 20 ms is heard
        // as a rattle, which is the one thing a test tone must not do.
        let mut phase = 0.0;
        let first = sine(440.0, 1.0, 960, &mut phase);
        let second = sine(440.0, 1.0, 960, &mut phase);

        let gap = (second[0] - first[first.len() - 1]).abs();
        let step = TAU * 440.0 / SAMPLE_RATE as f32;
        assert!(gap <= step + 1e-3, "the wave jumped by {gap}");
    }

    #[test]
    fn stereo_interleaves_the_same_signal_in_both_channels() {
        let stereo = to_stereo(&[0.1, 0.2]);
        assert_eq!(stereo, vec![0.1, 0.1, 0.2, 0.2]);
    }
}
