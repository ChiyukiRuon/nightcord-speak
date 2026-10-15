//! 桌面采集与网页网关共用的有界语音字头缓冲。

use std::collections::VecDeque;

use ts_model::{VadAlgorithm, VoiceActivationMode};

use crate::{TransmitPolicy, limiter::PeakLimiter};

/// 保留激活前最多 160 ms，开启时按时间顺序补发；PTT 不缓存按键前的声音。
/// 策略重置会使历史失效，防止跨越静音或模式切换重放。
#[derive(Default)]
pub struct VoiceSendBuffer {
    history: VecDeque<Vec<f32>>,
    generation: u64,
    limiter: PeakLimiter,
}

impl VoiceSendBuffer {
    /// 返回待编码帧，统一应用增益与限幅；调用方仅将首包标记为恢复发送。
    pub fn prepare(
        &mut self,
        frame: Vec<f32>,
        policy: &TransmitPolicy,
        channels: u16,
        gain: f32,
    ) -> Vec<Vec<f32>> {
        if self.generation != policy.generation() {
            self.reset();
            self.generation = policy.generation();
        }
        let may_buffer = policy.mode() == VoiceActivationMode::VoiceActivation
            && policy.settings().algorithm != VadAlgorithm::Disabled
            && !policy.input_muted()
            && !policy.output_muted()
            && !policy.away();
        if !policy.transmitted_last() {
            if may_buffer {
                if self.history.len() == 8 {
                    self.history.pop_front();
                }
                self.history.push_back(frame);
            } else {
                self.reset();
            }
            return Vec::new();
        }
        let mut frames: Vec<_> = self.history.drain(..).collect();
        frames.push(frame);
        for frame in &mut frames {
            self.limiter.process(frame, channels, gain);
        }
        frames
    }

    /// 设备或会话中断时清空历史及限幅延迟。
    pub fn reset(&mut self) {
        self.history.clear();
        self.limiter.reset();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::FRAME_SAMPLES;
    use ts_model::VoiceActivationSettings;

    #[test]
    fn activation_replays_the_onset_once_in_order() {
        let mut policy = TransmitPolicy::new(
            VoiceActivationMode::VoiceActivation,
            VoiceActivationSettings {
                algorithm: VadAlgorithm::Level,
                sensitivity: 0.1,
                attack_ms: 60,
                ..VoiceActivationSettings::default()
            },
        );
        let mut buffer = VoiceSendBuffer::default();
        for (i, level) in [0.11, 0.12, 0.13].into_iter().enumerate() {
            policy.should_transmit_frame(&vec![level; FRAME_SAMPLES], 20);
            let frames = buffer.prepare(vec![level; FRAME_SAMPLES], &policy, 1, 1.0);
            if i < 2 {
                assert!(frames.is_empty());
            } else {
                assert_eq!(frames.len(), 3);
                for (frame, expected) in frames.iter().zip([0.11, 0.12, 0.13]) {
                    assert!((frame[FRAME_SAMPLES - 1] - expected).abs() < 1e-6);
                }
            }
        }
        policy.should_transmit_frame(&vec![0.2; FRAME_SAMPLES], 20);
        assert_eq!(
            buffer
                .prepare(vec![0.2; FRAME_SAMPLES], &policy, 1, 1.0)
                .len(),
            1
        );
    }

    #[test]
    fn mute_and_ptt_never_replay_private_history() {
        let mut policy = TransmitPolicy::new(
            VoiceActivationMode::VoiceActivation,
            VoiceActivationSettings {
                algorithm: VadAlgorithm::Level,
                sensitivity: 0.1,
                attack_ms: 60,
                ..VoiceActivationSettings::default()
            },
        );
        let mut buffer = VoiceSendBuffer::default();
        policy.should_transmit_frame(&vec![0.12; FRAME_SAMPLES], 20);
        assert!(
            buffer
                .prepare(vec![0.12; FRAME_SAMPLES], &policy, 1, 1.0)
                .is_empty()
        );
        policy.set_input_muted(true);
        policy.set_input_muted(false);
        policy.set_mode(VoiceActivationMode::PushToTalk);
        policy.set_push_to_talk(true);
        policy.should_transmit_frame(&vec![0.2; FRAME_SAMPLES], 20);
        let frames = buffer.prepare(vec![0.2; FRAME_SAMPLES], &policy, 1, 1.0);
        assert_eq!(frames.len(), 1);
        assert!(frames[0].iter().all(|&s| s == 0.0 || s == 0.2));
    }
}
