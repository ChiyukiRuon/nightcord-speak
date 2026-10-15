// 原版 C++ WebRTC AudioProcessing 的私有桥接，不暴露给客户端公共 FFI。
#include <new>
#include "api/audio/audio_processing.h"

struct NightcordApm {
    rtc::scoped_refptr<webrtc::AudioProcessing> processor;
    webrtc::StreamConfig stream{48000, 2};

    NightcordApm() : processor(webrtc::AudioProcessingBuilder().Create()) {
        webrtc::AudioProcessing::Config config;
        config.pipeline.multi_channel_capture = true;
        config.noise_suppression.enabled = true;
        config.noise_suppression.level =
            webrtc::AudioProcessing::Config::NoiseSuppression::kModerate;
        // 只开启降噪；尚未接入播放参考，增益由 Rust 统一处理。
        config.echo_canceller.enabled = false;
        config.gain_controller1.enabled = false;
        config.gain_controller2.enabled = false;
        processor->ApplyConfig(config);
    }
};

extern "C" {
void* nightcord_apm_create() noexcept {
    try { return new NightcordApm(); } catch (...) { return nullptr; }
}

void nightcord_apm_destroy(void* state) noexcept {
    delete static_cast<NightcordApm*>(state);
}

int nightcord_apm_process(void* state, float* left, float* right) noexcept {
    auto* apm = static_cast<NightcordApm*>(state);
    const float* input[] = {left, right};
    float* output[] = {left, right};
    try {
        return apm->processor->ProcessStream(input, apm->stream, apm->stream, output);
    } catch (...) { return -1; }
}

int nightcord_apm_reset(void* state) noexcept {
    try {
        return static_cast<NightcordApm*>(state)->processor->Initialize();
    } catch (...) { return -1; }
}
}
