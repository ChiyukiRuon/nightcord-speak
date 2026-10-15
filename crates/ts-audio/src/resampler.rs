//! ???????????????????? 48 kHz?

use crate::format::SAMPLE_RATE;
use std::{f64::consts::PI, sync::Arc};

const TAPS: usize = 64;
const PHASES: usize = 1024;

/// 64 ?? Blackman ? sinc?48 kHz ???????
/// ?????? 31 ?????????????????????
#[derive(Debug, Clone)]
pub struct Resampler {
    from: u32,
    phase: u64,
    history: [f32; TAPS],
    cursor: usize,
    coefficients: Arc<Vec<[f32; TAPS]>>,
    primed: bool,
    passthrough: bool,
}

impl Resampler {
    #[must_use]
    pub fn new(from: u32) -> Self {
        let from = if from == 0 { SAMPLE_RATE } else { from };
        let passthrough = from == SAMPLE_RATE;
        let mut coefficients = Vec::new();
        if !passthrough {
            // ?????? Nyquist ???????????????????
            let cutoff = 0.94 * (f64::from(SAMPLE_RATE) / f64::from(from)).min(1.0);
            for phase in 0..=PHASES {
                let fraction = phase as f64 / PHASES as f64;
                let mut taps = [0.0; TAPS];
                for (index, tap) in taps.iter_mut().enumerate() {
                    let x = index as f64 - 31.0 + fraction;
                    let sinc = if x.abs() < 1e-12 {
                        cutoff
                    } else {
                        (PI * cutoff * x).sin() / (PI * x)
                    };
                    let window = 0.42 - 0.5 * (2.0 * PI * index as f64 / (TAPS - 1) as f64).cos()
                        + 0.08 * (4.0 * PI * index as f64 / (TAPS - 1) as f64).cos();
                    *tap = (sinc * window) as f32;
                }
                let sum: f32 = taps.iter().sum();
                for tap in &mut taps {
                    *tap /= sum;
                }
                coefficients.push(taps);
            }
        }
        Self {
            from,
            phase: 0,
            history: [0.0; TAPS],
            cursor: 0,
            coefficients: Arc::new(coefficients),
            primed: false,
            passthrough,
        }
    }

    #[must_use]
    pub const fn is_passthrough(&self) -> bool {
        self.passthrough
    }

    #[must_use]
    pub const fn input_rate(&self) -> u32 {
        self.from
    }

    /// ??????????????????????????????????
    pub fn process(&mut self, input: &[f32], output: &mut Vec<f32>) {
        if self.passthrough {
            output.extend_from_slice(input);
            return;
        }
        for &sample in input {
            let sample = if sample.is_finite() { sample } else { 0.0 };
            if !self.primed {
                self.history.fill(sample);
                self.primed = true;
            }
            self.history[self.cursor] = sample;
            while self.phase < u64::from(SAMPLE_RATE) {
                let position = self.phase as f64 * PHASES as f64 / f64::from(SAMPLE_RATE);
                let phase = position as usize;
                let fraction = (position - phase as f64) as f32;
                let mut value = 0.0;
                for tap in 0..TAPS {
                    let a = self.coefficients[phase][tap];
                    let b = self.coefficients[phase + 1][tap];
                    value +=
                        self.history[(self.cursor + TAPS - tap) % TAPS] * (a + (b - a) * fraction);
                }
                output.push(value);
                self.phase += u64::from(self.from);
            }
            self.phase -= u64::from(SAMPLE_RATE);
            self.cursor = (self.cursor + 1) % TAPS;
        }
    }

    /// ??????????????????
    pub fn reset(&mut self) {
        self.phase = 0;
        self.cursor = 0;
        self.history.fill(0.0);
        self.primed = false;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sine(rate: u32, hz: f32) -> Vec<f32> {
        (0..rate)
            .map(|i| (2.0 * std::f32::consts::PI * hz * i as f32 / rate as f32).sin() * 0.5)
            .collect()
    }

    #[test]
    fn downsampling_rejects_out_of_band_energy_and_preserves_voice_band() {
        for (hz, minimum, maximum) in [(1000.0, 0.34, 0.36), (30000.0, 0.0, 0.002)] {
            let mut out = Vec::new();
            Resampler::new(96000).process(&sine(96000, hz), &mut out);
            let level = crate::rms(&out[1000..]);
            assert!(
                (minimum..=maximum).contains(&level),
                "{hz} Hz output RMS: {level}"
            );
        }
    }

    #[test]
    fn arbitrary_callback_boundaries_preserve_a_nonconstant_waveform() {
        let input = sine(44100, 5371.0);
        let mut whole = Vec::new();
        Resampler::new(44100).process(&input, &mut whole);
        let mut resampler = Resampler::new(44100);
        let mut chunked = Vec::new();
        for chunk in input.chunks(137) {
            resampler.process(chunk, &mut chunked);
        }
        assert_eq!(whole, chunked);
    }

    /// One second of a constant signal at `rate`.
    fn constant(rate: u32, value: f32) -> Vec<f32> {
        vec![value; rate as usize]
    }

    #[test]
    fn matching_rates_are_passed_through_untouched() {
        let mut resampler = Resampler::new(SAMPLE_RATE);
        assert!(resampler.is_passthrough());

        let mut output = Vec::new();
        let input = constant(SAMPLE_RATE, 0.25);
        resampler.process(&input, &mut output);

        assert_eq!(
            output, input,
            "a passthrough must not alter a single sample"
        );
    }

    #[test]
    fn one_second_in_is_one_second_out() {
        // The property that actually matters: the duration must not drift, or
        // the far end hears the wrong pitch.
        for rate in [8_000, 16_000, 22_050, 44_100, 96_000] {
            let mut resampler = Resampler::new(rate);
            let mut output = Vec::new();
            resampler.process(&constant(rate, 0.1), &mut output);

            let produced = output.len();
            let expected = SAMPLE_RATE as usize;
            // A couple of samples of slack for the interpolation boundary.
            assert!(
                produced.abs_diff(expected) <= 2,
                "{rate} Hz over one second produced {produced} samples, expected ~{expected}"
            );
        }
    }

    #[test]
    fn a_constant_signal_stays_constant() {
        // Interpolating between equal samples must return that sample; an
        // off-by-one in the blend would show up as a ripple.
        let mut resampler = Resampler::new(44_100);
        let mut output = Vec::new();
        resampler.process(&constant(44_100, 0.75), &mut output);

        for (i, sample) in output.iter().enumerate() {
            assert!(
                (sample - 0.75).abs() < 1e-5,
                "sample {i} drifted to {sample}"
            );
        }
    }

    #[test]
    fn chunking_does_not_change_the_result() {
        // A stream arrives in frames; resampling must not depend on where the
        // frame boundaries fell.
        let input = constant(44_100, 0.5);

        let mut whole = Vec::new();
        Resampler::new(44_100).process(&input, &mut whole);

        let mut resampler = Resampler::new(44_100);
        let mut chunked = Vec::new();
        for chunk in input.chunks(441) {
            resampler.process(chunk, &mut chunked);
        }

        assert_eq!(
            whole.len(),
            chunked.len(),
            "chunking changed the sample count"
        );
        for (i, (a, b)) in whole.iter().zip(&chunked).enumerate() {
            assert!((a - b).abs() < 1e-6, "sample {i}: {a} vs {b}");
        }
    }

    #[test]
    fn an_empty_chunk_changes_nothing() {
        let mut resampler = Resampler::new(44_100);
        let mut output = Vec::new();
        resampler.process(&[], &mut output);
        assert!(output.is_empty());
    }

    #[test]
    fn reset_clears_the_seam_state() {
        let mut resampler = Resampler::new(44_100);
        let mut discard = Vec::new();
        resampler.process(&constant(44_100, 1.0), &mut discard);
        assert!(resampler.primed);

        resampler.reset();
        assert!(!resampler.primed);

        // After a reset the first sample is adopted as the seam, so the output
        // starts at the signal rather than fading in from zero.
        let mut output = Vec::new();
        resampler.process(&constant(44_100, 0.5), &mut output);
        assert!(
            (output[0] - 0.5).abs() < 1e-5,
            "started at {} instead of 0.5",
            output[0]
        );
    }

    #[test]
    fn the_input_rate_is_reported_back() {
        assert_eq!(Resampler::new(44_100).input_rate(), 44_100);
        assert_eq!(Resampler::new(SAMPLE_RATE).input_rate(), SAMPLE_RATE);
    }
}
