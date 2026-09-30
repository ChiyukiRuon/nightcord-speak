//! Sample-rate conversion towards the codec's 48 kHz.
//!
//! Capture devices are not obliged to run at 48 kHz — 44.1 kHz is common on
//! desktop, and phones pick whatever the platform gives them — while Opus at
//! this frame size only accepts 48 kHz. Something has to convert, and it has to
//! be here rather than in the caller.

use crate::format::SAMPLE_RATE;

/// Converts mono `f32` audio from an arbitrary rate to [`SAMPLE_RATE`].
///
/// Linear interpolation, deliberately: a windowed-sinc filter would be more
/// faithful, but the input is speech that is about to be lossily compressed at
/// 24 kbps, and interpolation error is far below the codec's own noise floor.
///
/// State is carried between calls, so a stream can be resampled frame by frame
/// without a click at every boundary.
#[derive(Debug, Clone)]
pub struct Resampler {
    /// Input samples consumed per output sample.
    step: f64,
    /// Read position inside the current chunk, as an offset into a virtual
    /// buffer of `[previous, input...]`.
    position: f64,
    /// Last sample of the previous chunk, for interpolating across the seam.
    previous: f32,
    primed: bool,
    passthrough: bool,
}

impl Resampler {
    /// A resampler converting from `from` Hz.
    #[must_use]
    pub fn new(from: u32) -> Self {
        let passthrough = from == SAMPLE_RATE || from == 0;
        Self {
            step: if from == 0 {
                1.0
            } else {
                f64::from(from) / f64::from(SAMPLE_RATE)
            },
            position: 0.0,
            previous: 0.0,
            primed: false,
            passthrough,
        }
    }

    /// Whether the input already matches the output rate.
    ///
    /// Worth checking, because it lets the caller skip the copy entirely.
    #[must_use]
    pub const fn is_passthrough(&self) -> bool {
        self.passthrough
    }

    /// The rate this resampler was built for.
    #[must_use]
    pub fn input_rate(&self) -> u32 {
        if self.passthrough {
            SAMPLE_RATE
        } else {
            (self.step * f64::from(SAMPLE_RATE)).round() as u32
        }
    }

    /// Appends the resampled form of `input` to `output`.
    ///
    /// `output` is appended to rather than cleared, so a caller can accumulate
    /// several chunks into one frame.
    pub fn process(&mut self, input: &[f32], output: &mut Vec<f32>) {
        if input.is_empty() {
            return;
        }
        if self.passthrough {
            output.extend_from_slice(input);
            return;
        }

        if !self.primed {
            // Nothing precedes the first sample, so start on it rather than
            // fading in from zero.
            self.previous = input[0];
            self.primed = true;
        }

        // The chunk behaves as if `previous` sat in front of it, so the read
        // position can interpolate across the boundary between chunks. Index 0
        // is `previous`; index i is `input[i - 1]`.
        let virtual_len = input.len() + 1;

        while (self.position as usize) + 1 < virtual_len {
            let index = self.position as usize;
            let fraction = (self.position - index as f64) as f32;

            let a = if index == 0 {
                self.previous
            } else {
                input[index - 1]
            };
            let b = input[index];

            output.push(a + (b - a) * fraction);
            self.position += self.step;
        }

        // Re-express the position against the next chunk, whose virtual index 0
        // is this chunk's last sample.
        self.position -= input.len() as f64;
        self.previous = *input.last().expect("checked non-empty above");
    }

    /// Forgets the carried state, as after switching devices.
    pub fn reset(&mut self) {
        self.position = 0.0;
        self.previous = 0.0;
        self.primed = false;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

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
