//! 左右声道联动的峰值限幅，使用短前瞻与平滑恢复。

use std::collections::VecDeque;

use crate::SAMPLE_RATE;

const LOOKAHEAD: usize = SAMPLE_RATE as usize / 200;
const CEILING: f32 = 0.891_250_9;

/// 延迟 5 ms 保护峰值，并保持左右声道比例；静音也应持续处理，或显式重置。
pub struct PeakLimiter {
    delay: Vec<[f32; 2]>,
    constraints: VecDeque<(u64, f64)>,
    position: u64,
    gain: f64,
    release: f64,
}

impl Default for PeakLimiter {
    fn default() -> Self {
        Self {
            delay: vec![[0.0; 2]; LOOKAHEAD],
            constraints: VecDeque::with_capacity(LOOKAHEAD + 1),
            position: 0,
            gain: 1.0,
            release: (-1.0 / (0.080 * f64::from(SAMPLE_RATE))).exp(),
        }
    }
}

impl PeakLimiter {
    /// 在混音和所有增益之后，处理一组双声道采样。
    pub fn process_sample(&mut self, input: [f32; 2]) -> [f32; 2] {
        let input = input.map(|s| if s.is_finite() { s } else { 0.0 });
        let peak = input[0].abs().max(input[1].abs());
        let oldest = self.position.saturating_sub(LOOKAHEAD as u64);
        while self.constraints.front().is_some_and(|&(at, _)| at < oldest) {
            self.constraints.pop_front();
        }
        let required = if peak > CEILING { CEILING / peak } else { 1.0 };
        // 将未来峰值约束向前展开为斜坡，使用滑动最小值实现平滑提前衰减。
        // 所有斜坡斜率相同，因此队列每个采样只需常数摊销工作量。
        let clock = self.position as f64 / LOOKAHEAD as f64;
        let constraint = f64::from(required) + clock;
        while self
            .constraints
            .back()
            .is_some_and(|&(_, value)| value >= constraint)
        {
            self.constraints.pop_back();
        }
        self.constraints.push_back((self.position, constraint));
        let target = (self.constraints.front().unwrap().1 - clock + 1.0).clamp(0.0, 1.0);
        self.gain = target.min(1.0 - (1.0 - self.gain) * self.release);
        let slot = (self.position % LOOKAHEAD as u64) as usize;
        let delayed = self.delay[slot];
        self.delay[slot] = input;
        self.position += 1;
        delayed.map(|s| (s * self.gain as f32).clamp(-CEILING, CEILING))
    }

    /// 对单/双声道交错 PCM 应用增益和限幅，声道数必须为 1 或 2。
    pub fn process(&mut self, samples: &mut [f32], channels: u16, gain: f32) {
        if gain == 0.0 {
            self.reset();
            samples.fill(0.0);
            return;
        }
        for frame in samples.chunks_exact_mut(channels as usize) {
            let left = frame[0] * gain;
            let right = if channels == 2 { frame[1] * gain } else { left };
            let out = self.process_sample([left, right]);
            frame[0] = out[0];
            if channels == 2 {
                frame[1] = out[1];
            }
        }
    }

    /// 设备、会话或隐私门控变化时丢弃延迟音频。
    pub fn reset(&mut self) {
        self.delay.fill([0.0; 2]);
        self.constraints.clear();
        self.position = 0;
        self.gain = 1.0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn future_peak_attenuates_background_with_a_ramp_instead_of_a_gain_step() {
        let mut limiter = PeakLimiter::default();
        for _ in 0..LOOKAHEAD * 2 {
            limiter.process_sample([0.1; 2]);
        }
        let mut previous = 0.1;
        for _ in 0..LOOKAHEAD {
            let out = limiter.process_sample([4.0; 2])[0];
            assert!((out - previous).abs() <= 0.1 / LOOKAHEAD as f32 + 1e-6);
            previous = out;
        }
        assert!(previous < 0.03);
        for _ in 0..LOOKAHEAD {
            assert!(limiter.process_sample([4.0; 2])[0] <= CEILING);
        }
    }

    #[test]
    fn quiet_audio_is_only_delayed_and_chunking_is_irrelevant() {
        let input: Vec<f32> = (0..4800).map(|i| (i as f32 * 0.1).sin() * 0.1).collect();
        let mut whole = input.clone();
        PeakLimiter::default().process(&mut whole, 1, 1.0);
        assert_eq!(&whole[LOOKAHEAD..], &input[..input.len() - LOOKAHEAD]);
        let mut chunked = input;
        let mut limiter = PeakLimiter::default();
        for chunk in chunked.chunks_mut(137) {
            limiter.process(chunk, 1, 1.0);
        }
        assert_eq!(whole, chunked);
    }

    #[test]
    fn boosted_speech_stays_bounded_and_stereo_is_linked() {
        let mut limiter = PeakLimiter::default();
        let mut nonflat = 0;
        for i in 0..4800 {
            let s = (i as f32 * 0.1).sin() * 0.7 * 5.623;
            let out = limiter.process_sample([s, s * 0.25]);
            assert!(out[0].abs() <= CEILING);
            assert!((out[1] - out[0] * 0.25).abs() < 1e-6);
            if out[0].abs() > 0.1 && out[0].abs() < CEILING - 0.01 {
                nonflat += 1;
            }
        }
        assert!(nonflat > 3000, "loud audio must retain its waveform");
        limiter.reset();
        for _ in 0..LOOKAHEAD * 2 {
            assert_eq!(limiter.process_sample([0.0; 2]), [0.0; 2]);
        }
    }
}
