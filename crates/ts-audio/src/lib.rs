//! # ts-audio
//!
//! Everything that touches a PCM sample (§26, §80 principle 4).
//!
//! ```text
//! Microphone ─▶ capture ─▶ resample ─▶ gate ─▶ Opus encode ─▶ VoicePacket
//!
//! mix buffer ◀── backend's jitter/decode ◀── UDP
//!     │
//!     └─▶ playback ─▶ Speakers
//! ```
//!
//! ## What lives here, and what does not
//!
//! This crate owns the send path end to end, plus device handling and playback
//! for the receive path. It does **not** decode received audio: that is
//! inseparable from the protocol backend's jitter buffering and packet-loss
//! handling, and `tsclientlib` already implements it well. The backend exposes
//! the mixed result and this crate plays it.
//!
//! The consequence to keep in mind is that the receive format is stereo
//! interleaved `f32` at 48 kHz ([`format::PLAYBACK_SAMPLES`] samples per frame)
//! while the send format is mono ([`format::FRAME_SAMPLES`]).
//!
//! Nothing here depends on a protocol library, so the audio engine can be
//! driven — and tested — without a server.

pub mod capture;
pub mod device;
pub mod encoder;
pub mod engine;
pub mod format;
pub mod playback;
pub mod resampler;
pub mod ring;
mod tone;
pub mod vad;

pub use capture::{Capture, CaptureFormat};
pub use device::{AudioBackend, AudioDevice, Direction, SystemAudio};
pub use encoder::OpusEncoder;
pub use engine::{OpenDevice, TransmitPolicy, VoiceEngine};
pub use playback::{Playback, PlaybackFormat};
pub use resampler::Resampler;
pub use ring::SampleRing;
pub use tone::{sine, to_stereo};
pub use vad::{VoiceGate, peak, rms};

pub use format::{
    FRAME_MS, FRAME_SAMPLES, MAX_OPUS_PACKET, PLAYBACK_CHANNELS, PLAYBACK_SAMPLES, SAMPLE_RATE,
    VOICE_CHANNELS,
};
