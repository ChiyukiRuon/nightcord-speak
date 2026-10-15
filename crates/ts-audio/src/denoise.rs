//! WebRTC APM 降噪；在音频工作线程运行，不进入设备回调。

use std::{ffi::c_void, ptr::NonNull};

use ts_model::AudioError;

const BLOCK: usize = 480;

unsafe extern "C" {
    fn nightcord_apm_create() -> *mut c_void;
    fn nightcord_apm_destroy(state: *mut c_void);
    fn nightcord_apm_process(state: *mut c_void, left: *mut f32, right: *mut f32) -> i32;
    fn nightcord_apm_reset(state: *mut c_void) -> i32;
}

/// 48 kHz 双声道降噪器，保持跨帧状态，只开启 APM 的 NS。
pub struct NoiseSuppressor {
    state: NonNull<c_void>,
    planes: [[f32; BLOCK]; 2],
}

// SAFETY: APM 实例由本对象独占，所有操作均要求 &mut self；不会并发调用。
unsafe impl Send for NoiseSuppressor {}

impl NoiseSuppressor {
    /// 初始化失败必须返回错误，避免悄悄关闭已启用的降噪。
    pub fn new() -> Result<Self, AudioError> {
        // SAFETY: 创建函数无参数，返回独立实例或空指针。
        let state =
            NonNull::new(unsafe { nightcord_apm_create() }).ok_or_else(|| AudioError::Backend {
                message: "WebRTC APM initialization failed".into(),
            })?;
        Ok(Self {
            state,
            planes: [[0.0; BLOCK]; 2],
        })
    }

    /// 每个 20 ms 双声道帧拆成两个 10 ms APM 帧；输入输出均为 ±1 float。
    pub fn process(&mut self, stereo: &mut [f32]) -> Result<(), AudioError> {
        if stereo.len() != crate::PLAYBACK_SAMPLES {
            return Err(AudioError::UnsupportedConfig);
        }
        for block in stereo.chunks_exact_mut(BLOCK * 2) {
            for (index, sample) in block.chunks_exact(2).enumerate() {
                for (channel, value) in sample.iter().enumerate() {
                    self.planes[channel][index] = if value.is_finite() { *value } else { 0.0 };
                }
            }
            let [left, right] = &mut self.planes;
            // SAFETY: 实例有效，两块独立缓冲区各有 APM 所需的 480 个采样。
            check(unsafe {
                nightcord_apm_process(self.state.as_ptr(), left.as_mut_ptr(), right.as_mut_ptr())
            })?;
            for (index, sample) in block.chunks_exact_mut(2).enumerate() {
                sample[0] = left[index];
                sample[1] = right[index];
            }
        }
        Ok(())
    }

    /// 设备切换和重连时丢弃滤波历史。
    pub fn reset(&mut self) -> Result<(), AudioError> {
        // SAFETY: 实例由本对象独占，重置期间没有其他调用。
        check(unsafe { nightcord_apm_reset(self.state.as_ptr()) })
    }
}

impl Drop for NoiseSuppressor {
    fn drop(&mut self) {
        // SAFETY: 只释放本对象创建的实例，且仅释放一次。
        unsafe { nightcord_apm_destroy(self.state.as_ptr()) };
    }
}

fn check(code: i32) -> Result<(), AudioError> {
    if code == 0 {
        Ok(())
    } else {
        Err(AudioError::Backend {
            message: format!("WebRTC APM processing failed ({code})"),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn upstream_apm_attenuates_stationary_noise_without_cross_channel_leakage() {
        let mut apm = NoiseSuppressor::new().unwrap();
        let mut seed = 42_u32;
        let mut before = 0.0_f64;
        let mut after = 0.0_f64;
        for frame_index in 0..150 {
            let mut frame = vec![0.0; crate::PLAYBACK_SAMPLES];
            for pair in frame.chunks_exact_mut(2) {
                seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
                pair[0] = (seed as f32 / u32::MAX as f32 - 0.5) * 0.06;
            }
            if frame_index >= 100 {
                before += frame.iter().map(|&s| f64::from(s).powi(2)).sum::<f64>();
            }
            apm.process(&mut frame).unwrap();
            assert!(frame.iter().all(|s| s.is_finite()));
            assert!(frame.chunks_exact(2).all(|p| p[1].abs() < 1e-7));
            if frame_index >= 100 {
                after += frame.iter().map(|&s| f64::from(s).powi(2)).sum::<f64>();
            }
        }
        let reduction_db = 10.0 * (before / after).log10();
        eprintln!("APM stationary noise reduction: {reduction_db:.2} dB");
        assert!(
            reduction_db > 5.0,
            "noise reduction was only {reduction_db:.2} dB"
        );
        apm.reset().unwrap();
        let mut silence = vec![0.0; crate::PLAYBACK_SAMPLES];
        apm.process(&mut silence).unwrap();
        assert!(silence.iter().all(|&s| s.abs() < 1e-7));
    }

    #[test]
    fn quiet_speech_survives_denoising_and_still_activates_vad() {
        let wav = include_bytes!("../tests/fixtures/vad-speech.wav");
        let mut offset = 12;
        let speech = loop {
            let length =
                u32::from_le_bytes(wav[offset + 4..offset + 8].try_into().unwrap()) as usize;
            if &wav[offset..offset + 4] == b"data" {
                break wav[offset + 8..offset + 8 + length]
                    .chunks_exact(2)
                    .map(|s| f32::from(i16::from_le_bytes([s[0], s[1]])) / 32768.0 * 0.08)
                    .collect::<Vec<_>>();
            }
            offset += 8 + length + length % 2;
        };
        let mut apm = NoiseSuppressor::new().unwrap();
        let mut vad = crate::vad::SmartVad::default();
        let mut energy_in = 0.0_f64;
        let mut energy_out = 0.0_f64;
        let mut detections = 0;
        for frame in speech.chunks_exact(crate::FRAME_SAMPLES) {
            let mut stereo: Vec<_> = frame.iter().flat_map(|&s| [s, s]).collect();
            energy_in += stereo.iter().map(|&s| f64::from(s).powi(2)).sum::<f64>();
            apm.process(&mut stereo).unwrap();
            energy_out += stereo.iter().map(|&s| f64::from(s).powi(2)).sum::<f64>();
            let mono: Vec<_> = stereo
                .chunks_exact(2)
                .map(|p| (p[0] + p[1]) * 0.5)
                .collect();
            detections += usize::from(vad.speech(&mono));
        }
        eprintln!(
            "APM quiet speech energy ratio: {:.3}, VAD frames: {detections}",
            energy_out / energy_in
        );
        assert!(energy_out > energy_in * 0.1);
        assert!(
            detections >= 10,
            "quiet speech lost VAD activation ({detections})"
        );
    }

    #[test]
    fn denoise_gain_codec_and_output_limiting_preserve_audible_audio() {
        use audiopus::{Channels, MutSignals, SampleRate, coder::Decoder, packet::Packet};
        let mut apm = NoiseSuppressor::new().unwrap();
        let mut input_limiter = crate::limiter::PeakLimiter::default();
        let mut output_limiter = crate::limiter::PeakLimiter::default();
        let mut encoder = crate::OpusEncoder::new(2).unwrap();
        let mut decoder = Decoder::new(SampleRate::Hz48000, Channels::Stereo).unwrap();
        let mut decoded = vec![0.0; crate::PLAYBACK_SAMPLES];
        let mut energy = 0.0_f64;
        let mut clipped_before = 0;
        for frame_index in 0..50 {
            let mut frame: Vec<_> = (0..crate::FRAME_SAMPLES)
                .flat_map(|i| {
                    let s = (2.0
                        * std::f32::consts::PI
                        * 220.0
                        * (frame_index * crate::FRAME_SAMPLES + i) as f32
                        / 48000.0)
                        .sin()
                        * 0.7;
                    [s, s * 0.5]
                })
                .collect();
            clipped_before += frame
                .iter()
                .filter(|&&s| (s * crate::microphone_gain(0.0)).abs() > 1.0)
                .count();
            apm.process(&mut frame).unwrap();
            input_limiter.process(&mut frame, 2, crate::microphone_gain(0.0));
            assert!(frame.iter().all(|s| s.abs() <= 0.891251));
            let packet = encoder.encode(&frame).unwrap();
            let samples = decoder
                .decode_float(
                    Some(Packet::try_from(packet.payload.as_slice()).unwrap()),
                    MutSignals::try_from(decoded.as_mut_slice()).unwrap(),
                    false,
                )
                .unwrap();
            assert_eq!(samples, crate::FRAME_SAMPLES);
            output_limiter.process(&mut decoded, 2, 10_f32.sqrt());
            assert!(decoded.iter().all(|s| s.is_finite() && s.abs() <= 0.891251));
            energy += decoded.iter().map(|&s| f64::from(s).powi(2)).sum::<f64>();
        }
        assert!(clipped_before > 10000, "测试信号应足以触发旧链路的削波");
        assert!(
            energy / (50 * crate::PLAYBACK_SAMPLES) as f64 > 0.005,
            "完整链路不能仅靠输出静音通过峰值检查"
        );
    }
}
