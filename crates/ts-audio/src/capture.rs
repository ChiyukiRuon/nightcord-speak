//! Microphone capture (§25).
//!
//! ```text
//! device ─▶ convert to f32 ─▶ downmix to mono ─▶ resample to 48k ─▶ frame ─▶ engine
//! ```
//!
//! Everything happens inside the device callback, so the work per sample is
//! kept to a conversion and an interpolation. The only allocation is the
//! finished frame itself, which is handed to the engine's channel.

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{SyncSender, TrySendError, sync_channel};
use std::time::Duration;

use cpal::traits::{DeviceTrait as _, StreamTrait as _};
use cpal::{SampleFormat, StreamConfig};
use ts_model::AudioError;

use crate::device::{self, Direction};
use crate::format::{FRAME_SAMPLES, SAMPLE_RATE};
use crate::resampler::Resampler;

/// How many finished frames may queue before capture starts dropping them.
///
/// Around half a second. If the engine falls this far behind, the audio is
/// already unusable and dropping is better than growing without bound.
const FRAME_QUEUE: usize = 25;

/// How long to wait for the audio backend to start the stream.
const START_TIMEOUT: Duration = Duration::from_secs(5);

/// The format a capture stream ended up using.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CaptureFormat {
    /// The device's native rate, before resampling.
    pub device_rate: u32,
    /// The device's channel count, before downmixing.
    pub device_channels: u16,
    /// The rate the engine receives. Always [`SAMPLE_RATE`].
    pub output_rate: u32,
}

/// An open microphone, delivering 48 kHz mono frames.
///
/// Dropping this stops capture. The stream is kept alive by this value, which
/// is why the field is not public.
pub struct Capture {
    /// Held only to keep the stream running: `cpal` stops capture when the
    /// value is dropped, so it is deliberately never read.
    _stream: cpal::Stream,
    frames: std::sync::mpsc::Receiver<Vec<f32>>,
    format: CaptureFormat,
    /// Cleared by the error callback when the device fails or is unplugged.
    running: Arc<AtomicBool>,
}

impl Capture {
    /// Opens `device_id`, or the system default when it is `None` or gone.
    ///
    /// # Errors
    ///
    /// Returns [`AudioError::NoInputDevice`] when the machine has no
    /// microphone, [`AudioError::UnsupportedConfig`] when the device offers no
    /// usable sample format, or [`AudioError::Backend`] for anything the host
    /// reports.
    pub fn open(device_id: Option<&str>) -> Result<Self, AudioError> {
        let device = device::resolve(Direction::Input, device_id)?;
        let config = device
            .default_input_config()
            .map_err(|error| AudioError::Backend {
                message: error.to_string(),
            })?;

        let device_rate = config.sample_rate();
        let device_channels = config.channels();
        let sample_format = config.sample_format();
        let stream_config: StreamConfig = config.into();

        let (sender, frames) = sync_channel(FRAME_QUEUE);
        let assembler = FrameAssembler::new(Resampler::new(device_rate), device_channels, sender);
        let running = Arc::new(AtomicBool::new(true));

        // The sample type has to be chosen once here, because `cpal`'s stream
        // builder is generic over it; branching per callback is not possible.
        let stream = match sample_format {
            SampleFormat::F32 => {
                build::<f32>(&device, &stream_config, assembler, Arc::clone(&running))
            }
            SampleFormat::I16 => {
                build::<i16>(&device, &stream_config, assembler, Arc::clone(&running))
            }
            SampleFormat::U16 => {
                build::<u16>(&device, &stream_config, assembler, Arc::clone(&running))
            }
            SampleFormat::I32 => {
                build::<i32>(&device, &stream_config, assembler, Arc::clone(&running))
            }
            SampleFormat::F64 => {
                build::<f64>(&device, &stream_config, assembler, Arc::clone(&running))
            }
            other => {
                tracing::warn!(?other, "microphone offers no sample format we can convert");
                return Err(AudioError::UnsupportedConfig);
            }
        }?;

        stream.play().map_err(|error| AudioError::Backend {
            message: error.to_string(),
        })?;

        tracing::info!(
            device = device_id.unwrap_or("default"),
            rate = device_rate,
            channels = device_channels,
            "microphone opened"
        );

        Ok(Self {
            _stream: stream,
            frames,
            running,
            format: CaptureFormat {
                device_rate,
                device_channels,
                output_rate: SAMPLE_RATE,
            },
        })
    }

    /// Takes the next finished frame, if one is ready.
    ///
    /// Never blocks: this is called from the engine's poll loop, which also has
    /// network work to do.
    pub fn try_recv(&self) -> Option<Vec<f32>> {
        self.frames.try_recv().ok()
    }

    /// The format the device settled on.
    #[must_use]
    pub const fn format(&self) -> CaptureFormat {
        self.format
    }

    /// Whether the stream is still running.
    ///
    /// Goes false when the host reports an error — a microphone unplugged
    /// mid-call, which the UI should surface rather than silently transmit
    /// nothing.
    #[must_use]
    pub fn is_running(&self) -> bool {
        self.running.load(Ordering::Relaxed)
    }
}

impl std::fmt::Debug for Capture {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Capture")
            .field("format", &self.format)
            .finish_non_exhaustive()
    }
}

/// Builds the input stream for one concrete sample type.
///
/// `cpal` is generic over the sample type, so the format has to be dispatched
/// once at open time rather than branched on per callback.
fn build<T>(
    device: &cpal::Device,
    config: &StreamConfig,
    mut assembler: FrameAssembler,
    running: Arc<AtomicBool>,
) -> Result<cpal::Stream, AudioError>
where
    T: cpal::SizedSample + ToF32 + Copy,
{
    device
        .build_input_stream(
            *config,
            move |data: &[T], _info| assembler.push(data),
            move |error| {
                // Only a device that is actually gone ends the stream; an xrun
                // is a glitch the host recovers from on its own.
                if device::is_fatal(&error) {
                    running.store(false, Ordering::Relaxed);
                    tracing::warn!(%error, "capture device is no longer available");
                } else {
                    tracing::debug!(%error, "capture stream glitch");
                }
            },
            Some(START_TIMEOUT),
        )
        .map_err(|error| AudioError::Backend {
            message: error.to_string(),
        })
}

/// Converts a device sample to `f32` in `-1.0..=1.0`.
///
/// Written out rather than using `cpal`'s conversion so the scaling is visible;
/// an integer format divided by the wrong constant sounds subtly wrong rather
/// than obviously broken.
pub(crate) trait ToF32 {
    /// This sample as `f32`.
    fn to_f32(self) -> f32;
}

impl ToF32 for f32 {
    fn to_f32(self) -> f32 {
        self
    }
}

impl ToF32 for f64 {
    fn to_f32(self) -> f32 {
        self as f32
    }
}

impl ToF32 for i16 {
    fn to_f32(self) -> f32 {
        f32::from(self) / 32_768.0
    }
}

impl ToF32 for i32 {
    fn to_f32(self) -> f32 {
        self as f32 / 2_147_483_648.0
    }
}

impl ToF32 for u16 {
    fn to_f32(self) -> f32 {
        (f32::from(self) - 32_768.0) / 32_768.0
    }
}

/// Turns a stream of device callbacks into exactly-sized frames.
///
/// Separated from the stream so the framing, downmixing and resampling can be
/// tested without a microphone.
pub(crate) struct FrameAssembler {
    resampler: Resampler,
    channels: u16,
    sender: SyncSender<Vec<f32>>,
    /// Mono 48 kHz samples that do not yet fill a frame.
    pending: Vec<f32>,
    /// Scratch for the resampler's output, reused so the callback does not
    /// allocate beyond the frames it emits.
    resampled: Vec<f32>,
    /// Set once the first frame has been dropped, so the log line is emitted
    /// once rather than fifty times a second.
    warned_full: bool,
}

impl FrameAssembler {
    pub(crate) fn new(resampler: Resampler, channels: u16, sender: SyncSender<Vec<f32>>) -> Self {
        Self {
            resampler,
            channels,
            sender,
            pending: Vec::with_capacity(FRAME_SAMPLES * 2),
            resampled: Vec::with_capacity(FRAME_SAMPLES * 2),
            warned_full: false,
        }
    }

    /// Accepts one device callback's worth of samples.
    pub(crate) fn push<T: ToF32 + Copy>(&mut self, data: &[T]) {
        if data.is_empty() || self.channels == 0 {
            return;
        }

        self.resampled.clear();

        if self.channels == 1 {
            // Fast path: already mono, so convert straight into the resampler.
            let mono: Vec<f32> = data.iter().map(|s| s.to_f32()).collect();
            self.resampler.process(&mono, &mut self.resampled);
        } else {
            // Downmix by averaging, which is what a mono sum should be — summing
            // without dividing would clip on correlated input.
            let mono: Vec<f32> = data
                .chunks_exact(self.channels as usize)
                .map(|frame| frame.iter().map(|s| s.to_f32()).sum::<f32>() / frame.len() as f32)
                .collect();
            self.resampler.process(&mono, &mut self.resampled);
        }

        self.pending.extend_from_slice(&self.resampled);
        self.emit_full_frames();
    }

    /// Sends every complete frame currently buffered.
    fn emit_full_frames(&mut self) {
        while self.pending.len() >= FRAME_SAMPLES {
            let frame: Vec<f32> = self.pending.drain(..FRAME_SAMPLES).collect();

            match self.sender.try_send(frame) {
                Ok(()) => {}
                Err(TrySendError::Full(_)) => {
                    if !self.warned_full {
                        self.warned_full = true;
                        tracing::warn!("capture is ahead of the engine; dropping audio");
                    }
                }
                // The engine is gone, so capture is over.
                Err(TrySendError::Disconnected(_)) => {
                    self.pending.clear();
                    return;
                }
            }
        }

        // Keep the warning armed so a later stall is reported again.
        if self.pending.len() < FRAME_SAMPLES {
            self.warned_full = false;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn integer_conversions_scale_to_the_full_range() {
        assert!((1.0_f32.to_f32() - 1.0).abs() < f32::EPSILON);
        assert!((f64::from(-0.5f32).to_f32() + 0.5).abs() < 1e-6);

        assert!((i16::MAX.to_f32() - 0.999_97).abs() < 1e-4);
        assert!((i16::MIN.to_f32() + 1.0).abs() < f32::EPSILON);
        assert!(i16::default().to_f32().abs() < f32::EPSILON);

        assert!(
            u16::default().to_f32() < 0.0,
            "u16 is offset, so midpoint is silence"
        );
        assert!(u16::MAX.to_f32() > 0.999);
    }

    /// Collects whatever an assembler emits.
    fn assembler(
        rate: u32,
        channels: u16,
    ) -> (FrameAssembler, std::sync::mpsc::Receiver<Vec<f32>>) {
        let (sender, receiver) = sync_channel(FRAME_QUEUE);
        (
            FrameAssembler::new(Resampler::new(rate), channels, sender),
            receiver,
        )
    }

    #[test]
    fn a_full_frame_of_mono_is_emitted_whole() {
        let (mut assembler, frames) = assembler(SAMPLE_RATE, 1);
        assembler.push(&vec![0.5_f32; FRAME_SAMPLES]);

        let frame = frames.try_recv().expect("one frame");
        assert_eq!(frame.len(), FRAME_SAMPLES);
    }

    #[test]
    fn a_partial_callback_is_buffered_not_emitted() {
        let (mut assembler, frames) = assembler(SAMPLE_RATE, 1);

        assembler.push(&vec![0.5_f32; 100]);
        assert!(frames.try_recv().is_err(), "100 samples is not a frame");

        assembler.push(&vec![0.5_f32; FRAME_SAMPLES - 100]);
        assert!(
            frames.try_recv().is_ok(),
            "the frame completes on the second call"
        );
    }

    #[test]
    fn a_large_callback_emits_several_frames() {
        let (mut assembler, frames) = assembler(SAMPLE_RATE, 1);
        assembler.push(&vec![0.25_f32; FRAME_SAMPLES * 3]);

        for _ in 0..3 {
            let frame = frames.try_recv().expect("frame");
            assert_eq!(frame.len(), FRAME_SAMPLES);
            assert!(frame.iter().all(|s| (s - 0.25).abs() < 1e-6));
        }
        assert!(frames.try_recv().is_err(), "exactly three frames were owed");
    }

    #[test]
    fn a_remainder_is_kept_for_the_next_callback() {
        let (mut assembler, frames) = assembler(SAMPLE_RATE, 1);
        assembler.push(&vec![0.0_f32; FRAME_SAMPLES + 10]);

        assert!(frames.try_recv().is_ok());
        assert!(
            frames.try_recv().is_err(),
            "the 10 leftover samples are not a frame"
        );

        assembler.push(&vec![0.0_f32; FRAME_SAMPLES - 10]);
        assert!(
            frames.try_recv().is_ok(),
            "the leftover completed the next frame"
        );
    }

    #[test]
    fn stereo_is_downmixed_by_averaging() {
        let (mut assembler, frames) = assembler(SAMPLE_RATE, 2);
        // Left is +1, right is -1: the average is silence, not a doubled signal.
        let interleaved: Vec<f32> = (0..FRAME_SAMPLES)
            .flat_map(|_| [1.0_f32, -1.0_f32])
            .collect();
        assembler.push(&interleaved);

        let frame = frames.try_recv().expect("one frame");
        assert!(
            frame.iter().all(|s| s.abs() < 1e-6),
            "opposite channels should cancel, got {:?}",
            &frame[..4]
        );
    }

    #[test]
    fn identical_stereo_channels_survive_the_downmix() {
        let (mut assembler, frames) = assembler(SAMPLE_RATE, 2);
        let interleaved: Vec<f32> = (0..FRAME_SAMPLES)
            .flat_map(|_| [0.5_f32, 0.5_f32])
            .collect();
        assembler.push(&interleaved);

        let frame = frames.try_recv().expect("one frame");
        assert!(frame.iter().all(|s| (s - 0.5).abs() < 1e-6));
    }

    #[test]
    fn a_device_rate_is_resampled_to_the_codec_rate() {
        // One second at 44.1 kHz must produce one second at 48 kHz, whatever
        // the callback size.
        //
        // The receiver has to be drained as we go: a real engine consumes
        // continuously, whereas pushing a whole second into a half-second queue
        // would be dropped by design.
        let (mut assembler, frames) = assembler(44_100, 1);
        let mut produced = 0;

        for _ in 0..(44_100 / 441) {
            assembler.push(&vec![0.1_f32; 441]);
            while let Ok(frame) = frames.try_recv() {
                produced += frame.len();
            }
        }
        while let Ok(frame) = frames.try_recv() {
            produced += frame.len();
        }

        assert!(
            produced.abs_diff(SAMPLE_RATE as usize) <= FRAME_SAMPLES,
            "produced {produced} samples for one second, expected ~{SAMPLE_RATE}"
        );
    }

    #[test]
    fn an_empty_callback_is_ignored() {
        let (mut assembler, frames) = assembler(SAMPLE_RATE, 1);
        assembler.push::<f32>(&[]);
        assert!(frames.try_recv().is_err());
    }

    #[test]
    fn a_zero_channel_config_does_not_panic() {
        // Should not happen, but it divides by the channel count.
        let (mut assembler, frames) = assembler(SAMPLE_RATE, 0);
        assembler.push(&[1.0_f32, 2.0, 3.0]);
        assert!(frames.try_recv().is_err());
    }

    #[test]
    fn a_full_queue_drops_rather_than_blocking() {
        // The engine being behind must never stall the audio callback: a
        // blocked device callback is heard as a dropout.
        let (sender, _receiver) = sync_channel(1);
        let mut assembler = FrameAssembler::new(Resampler::new(SAMPLE_RATE), 1, sender);

        for _ in 0..5 {
            assembler.push(&vec![0.5_f32; FRAME_SAMPLES]);
        }
        // Reaching here at all is the assertion; try_send never waits.
    }

    #[test]
    fn a_disconnected_engine_stops_buffering() {
        let (sender, receiver) = sync_channel(FRAME_QUEUE);
        let mut assembler = FrameAssembler::new(Resampler::new(SAMPLE_RATE), 1, sender);
        drop(receiver);

        assembler.push(&vec![0.5_f32; FRAME_SAMPLES * 4]);
        assert!(
            assembler.pending.len() < FRAME_SAMPLES,
            "pending buffer kept growing"
        );
    }
}
