//! Speaker playback (§25).
//!
//! ```text
//! engine ─▶ ring ─▶ device callback ─▶ up/downmix ─▶ speakers
//! ```
//!
//! The engine writes stereo 48 kHz samples into a lock-free ring; the device
//! callback drains it. Nothing here ever blocks — see [`crate::ring`] for why.

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::time::Duration;

use cpal::traits::{DeviceTrait as _, StreamTrait as _};
use cpal::{SampleFormat, StreamConfig};
use ts_model::AudioError;

use crate::device::{self, Direction};
use crate::format::{PLAYBACK_CHANNELS, SAMPLE_RATE};
use crate::ring::{SampleConsumer, SampleProducer, SampleRing};

/// How long to wait for the audio backend to start the stream.
const START_TIMEOUT: Duration = Duration::from_secs(5);

/// Around a second of stereo audio, so a scheduling hiccup does not starve the
/// device but latency stays reasonable.
const RING_SAMPLES: usize = SAMPLE_RATE as usize * PLAYBACK_CHANNELS as usize;

/// The format a playback stream ended up using.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PlaybackFormat {
    /// The device's channel count.
    pub device_channels: u16,
    /// The device's sample rate. Always [`SAMPLE_RATE`].
    pub device_rate: u32,
}

/// An open set of speakers.
///
/// Dropping this stops playback.
pub struct Playback {
    /// Held only to keep the stream running: `cpal` stops playback when the
    /// value is dropped, so it is deliberately never read.
    _stream: cpal::Stream,
    /// Which device this actually is, so a front-end can say so.
    device: device::Resolved,
    producer: SampleProducer,
    format: PlaybackFormat,
    /// Cleared by the error callback when the device fails or is unplugged.
    running: Arc<AtomicBool>,
    /// Per-frame gain the callback multiplies by, shared with it.
    ///
    /// An atomic rather than a parameter to the stream callback because the
    /// callback is built once and must never block: writing a new gain has to be
    /// a store, not a rebuild of the stream.
    volume: Arc<AtomicU32>,
}

impl Playback {
    /// Opens `device_id`, or the system default when it is `None` or gone.
    ///
    /// # Errors
    ///
    /// Returns [`AudioError::NoOutputDevice`] when the machine has no speakers,
    /// [`AudioError::UnsupportedConfig`] when the device cannot run at 48 kHz,
    /// or [`AudioError::Backend`] for anything the host reports.
    pub fn open(device_id: Option<&str>) -> Result<Self, AudioError> {
        Self::open_with_volume(device_id, 1.0)
    }

    /// Opens a device, playing at `volume` from the very first sample.
    ///
    /// The gain is handed to the callback rather than applied afterwards
    /// because the alternative is audible: a stream that starts at unity and is
    /// corrected a few milliseconds later plays the beginning of whatever was
    /// queued too loudly.
    ///
    /// # Errors
    ///
    /// See [`Playback::open`].
    pub fn open_with_volume(device_id: Option<&str>, volume: f32) -> Result<Self, AudioError> {
        let resolved = device::resolve(Direction::Output, device_id)?;
        let (config, sample_format) = pick_config(&resolved.device)?;
        let device = &resolved.device;

        let device_channels = config.channels;
        let device_rate = config.sample_rate;

        let (producer, consumer) = SampleRing::channel(RING_SAMPLES);
        let volume = Arc::new(AtomicU32::new(clamp_gain(volume).to_bits()));
        let running = Arc::new(AtomicBool::new(true));

        let stream = match sample_format {
            SampleFormat::F32 => build::<f32>(
                device,
                &config,
                consumer,
                Arc::clone(&volume),
                Arc::clone(&running),
            ),
            SampleFormat::I16 => build::<i16>(
                device,
                &config,
                consumer,
                Arc::clone(&volume),
                Arc::clone(&running),
            ),
            SampleFormat::U16 => build::<u16>(
                device,
                &config,
                consumer,
                Arc::clone(&volume),
                Arc::clone(&running),
            ),
            other => {
                tracing::warn!(?other, "speakers offer no sample format we can convert");
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
            "speakers opened"
        );

        Ok(Self {
            _stream: stream,
            device: resolved,
            producer,
            running,
            volume,
            format: PlaybackFormat {
                device_channels,
                device_rate,
            },
        })
    }

    /// Queues stereo interleaved samples, returning how many were accepted.
    ///
    /// A short write means the ring is full — the engine is generating audio
    /// faster than the device consumes it — and the caller should drop the
    /// remainder rather than retry in a loop.
    pub fn write(&self, samples: &[f32]) -> usize {
        self.producer.write(samples)
    }

    /// Sets the playback gain, `0.0..=1.0`.
    ///
    /// Takes effect on the next device callback — one relaxed store, so this is
    /// safe to call from anywhere and never blocks or allocates the audio
    /// thread.
    ///
    /// Not the same as muting: muting drops incoming audio before it is queued
    /// (so unmuting does not replay a backlog) while this scales what is
    /// already playing. A gain of zero is a faded-out stream, not a stopped one.
    pub fn set_volume(&self, gain: f32) {
        self.volume
            .store(clamp_gain(gain).to_bits(), Ordering::Relaxed);
    }

    /// The gain the callback is currently applying.
    #[must_use]
    pub fn volume(&self) -> f32 {
        f32::from_bits(self.volume.load(Ordering::Relaxed))
    }

    /// How many samples are queued but not yet played.
    #[must_use]
    pub fn buffered(&self) -> usize {
        self.producer.buffered()
    }

    /// How many samples can be accepted before the queue overflows.
    #[must_use]
    pub fn space(&self) -> usize {
        self.producer.space()
    }

    /// The format the device settled on.
    #[must_use]
    pub const fn format(&self) -> PlaybackFormat {
        self.format
    }

    /// Discards queued audio, as after a device switch.
    pub fn clear(&self) {
        self.producer.clear();
    }

    /// The device that was actually opened, and whether it is the one that was
    /// asked for. See [`Capture::device`].
    ///
    /// [`Capture::device`]: crate::capture::Capture::device
    #[must_use]
    pub fn device(&self) -> &device::Resolved {
        &self.device
    }

    /// Whether the stream is still running.
    ///
    /// Goes false when the host reports an error — speakers unplugged mid-call,
    /// which the UI should surface rather than silently dropping incoming audio.
    #[must_use]
    pub fn is_running(&self) -> bool {
        self.running.load(Ordering::Relaxed)
    }
}

impl std::fmt::Debug for Playback {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Playback")
            .field("format", &self.format)
            .finish_non_exhaustive()
    }
}

/// Picks a stream configuration we can feed.
///
/// Playback has no resampler — resampling inside the device callback would mean
/// allocating there — so the device has to run at [`SAMPLE_RATE`]. Most do; a
/// device that cannot is reported rather than played at the wrong pitch.
fn pick_config(device: &cpal::Device) -> Result<(StreamConfig, SampleFormat), AudioError> {
    let default = device
        .default_output_config()
        .map_err(|error| AudioError::Backend {
            message: error.to_string(),
        })?;

    if default.sample_rate() == SAMPLE_RATE {
        let format = default.sample_format();
        let mut config: StreamConfig = default.into();
        config.channels = config.channels.max(1);
        return Ok((config, format));
    }

    // The default was a different rate; look for one that is not.
    if let Ok(ranges) = device.supported_output_configs() {
        for range in ranges {
            let supports_rate =
                range.min_sample_rate() <= SAMPLE_RATE && range.max_sample_rate() >= SAMPLE_RATE;
            if supports_rate && range.channels() > 0 {
                let format = range.sample_format();
                let config = StreamConfig {
                    channels: range.channels(),
                    sample_rate: SAMPLE_RATE,
                    buffer_size: cpal::BufferSize::Default,
                };
                tracing::info!(
                    channels = range.channels(),
                    ?format,
                    "using a non-default output config"
                );
                return Ok((config, format));
            }
        }
    }

    tracing::warn!(
        device_rate = default.sample_rate(),
        "output device cannot run at {SAMPLE_RATE} Hz"
    );
    Err(AudioError::UnsupportedConfig)
}

/// Builds the output stream for one concrete sample type.
fn build<T>(
    device: &cpal::Device,
    config: &StreamConfig,
    consumer: SampleConsumer,
    volume: Arc<AtomicU32>,
    running: Arc<AtomicBool>,
) -> Result<cpal::Stream, AudioError>
where
    T: cpal::SizedSample + FromF32,
{
    let channels = config.channels;
    let mut scratch: Vec<f32> = Vec::new();

    device
        .build_output_stream(
            *config,
            move |data: &mut [T], _info| {
                let gain = f32::from_bits(volume.load(Ordering::Relaxed));
                // Reused across callbacks, so after the first this does not
                // allocate. `clear` keeps the capacity.
                scratch.clear();
                scratch.resize(data.len(), 0.0);

                // Whatever the ring cannot supply stays at zero, which the host
                // has already prefilled as silence — an underrun is a gap, not
                // a stale repeat.
                let played = consumer.read(&mut scratch);
                let interleaved = &scratch[..played];

                write_output(data, interleaved, channels, gain);
            },
            move |error| {
                // Only a device that is actually gone ends the stream; an xrun
                // is a glitch the host recovers from on its own.
                if device::is_fatal(&error) {
                    running.store(false, Ordering::Relaxed);
                    tracing::warn!(%error, "playback device is no longer available");
                } else {
                    tracing::debug!(%error, "playback stream glitch");
                }
            },
            Some(START_TIMEOUT),
        )
        .map_err(|error| AudioError::Backend {
            message: error.to_string(),
        })
}

/// Pulls a requested gain into the range the callback can use.
///
/// Anything outside `0.0..=1.0` is a bug or a hand-edited settings file, and
/// both have the same useful answer: the nearest legal gain. Non-finite values
/// become unity, because multiplying a buffer by `NaN` produces silence
/// indistinguishable from a broken device.
fn clamp_gain(gain: f32) -> f32 {
    if gain.is_finite() {
        gain.clamp(0.0, 1.0)
    } else {
        1.0
    }
}

/// Maps stereo interleaved `f32` into the device's buffer.
///
/// Split out so the channel mapping and gain can be tested without a device —
/// the callback itself cannot be.
pub(crate) fn write_output<T: FromF32>(
    data: &mut [T],
    interleaved: &[f32],
    channels: u16,
    gain: f32,
) {
    if channels == 0 {
        return;
    }
    let channels = channels as usize;

    for (index, sample) in data.iter_mut().enumerate() {
        let frame = index / channels;
        let channel = index % channels;

        let source = match channels {
            1 => {
                // Downmix: averaging the pair keeps a centred signal at the
                // same level rather than halving it.
                let left = interleaved.get(frame * 2).copied().unwrap_or(0.0);
                let right = interleaved.get(frame * 2 + 1).copied().unwrap_or(0.0);
                (left + right) * 0.5
            }
            2 => interleaved.get(frame * 2 + channel).copied().unwrap_or(0.0),
            // Surround: the first two channels carry the stereo image and the
            // rest stay silent rather than duplicating it.
            _ => {
                if channel < PLAYBACK_CHANNELS as usize {
                    interleaved.get(frame * 2 + channel).copied().unwrap_or(0.0)
                } else {
                    0.0
                }
            }
        };

        *sample = T::from_f32((source * gain).clamp(-1.0, 1.0));
    }
}

/// Converts `f32` to a device sample type.
///
/// Clamping happens before this, so the scaling below is the only thing that
/// differs between formats.
pub(crate) trait FromF32 {
    /// This value as the device's sample type.
    fn from_f32(value: f32) -> Self;
}

impl FromF32 for f32 {
    fn from_f32(value: f32) -> Self {
        value
    }
}

impl FromF32 for i16 {
    fn from_f32(value: f32) -> Self {
        // Scale by the negative extreme so +1.0 lands inside the type's range.
        (value * 32_767.0).round() as Self
    }
}

impl FromF32 for u16 {
    fn from_f32(value: f32) -> Self {
        (value * 32_767.0 + 32_768.0).round().clamp(0.0, 65_535.0) as Self
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn f32_conversion_is_identity() {
        assert_eq!(f32::from_f32(0.25), 0.25);
        assert_eq!(f32::from_f32(-1.0), -1.0);
    }

    #[test]
    fn integer_conversions_span_the_full_range_without_wrapping() {
        assert_eq!(i16::from_f32(1.0), 32_767);
        assert_eq!(i16::from_f32(-1.0), -32_767);
        assert_eq!(i16::from_f32(0.0), 0);

        assert_eq!(u16::from_f32(0.0), 32_768);
        assert!(u16::from_f32(1.0) >= 65_534);
        assert_eq!(u16::from_f32(-1.0), 1);
    }

    #[test]
    fn stereo_passes_straight_through() {
        let interleaved = [0.25_f32, -0.25, 0.5, -0.5];
        let mut out = [0.0_f32; 4];
        write_output(&mut out, &interleaved, 2, 1.0);
        assert_eq!(out, interleaved);
    }

    #[test]
    fn mono_is_downmixed_without_halving_a_centred_signal() {
        // A signal present in both channels must come out at its own level, not
        // at half of it.
        let interleaved = [0.5_f32, 0.5, 0.5, 0.5];
        let mut out = [0.0_f32; 2];
        write_output(&mut out, &interleaved, 1, 1.0);
        assert_eq!(out, [0.5, 0.5]);
    }

    #[test]
    fn surround_channels_beyond_stereo_are_silent() {
        // Duplicating the front pair into the surrounds would sound wrong.
        let interleaved = [0.5_f32, -0.5];
        let mut out = [1.0_f32; 6];
        write_output(&mut out, &interleaved, 6, 1.0);

        assert_eq!(out[0], 0.5);
        assert_eq!(out[1], -0.5);
        assert_eq!(&out[2..], &[0.0; 4]);
    }

    #[test]
    fn gain_scales_the_output() {
        let interleaved = [1.0_f32, -1.0];
        let mut out = [0.0_f32; 2];
        write_output(&mut out, &interleaved, 2, 0.5);
        assert_eq!(out, [0.5, -0.5]);
    }

    #[test]
    fn a_hot_signal_is_clamped_rather_than_wrapping() {
        // Several talkers mixed together can exceed full scale; on an integer
        // device that would wrap to the opposite extreme and sound like a crack.
        let interleaved = [4.0_f32, -4.0];
        let mut out = [0.0_f32; 2];
        write_output(&mut out, &interleaved, 2, 2.0);
        assert_eq!(out, [1.0, -1.0]);

        let mut ints = [0_i16; 2];
        write_output(&mut ints, &[4.0, -4.0], 2, 2.0);
        assert_eq!(ints, [32_767, -32_767]);
    }

    #[test]
    fn a_starved_ring_leaves_the_remaining_buffer_untouched() {
        // The host prefills the buffer with silence, so leaving the tail alone
        // is what makes an underrun a gap rather than a repeat.
        let interleaved = [0.5_f32];
        let mut out = [9.0_f32; 4];
        write_output(&mut out, &interleaved, 2, 1.0);
        assert_eq!(out[0], 0.5);
    }

    #[test]
    fn zero_channels_does_not_panic() {
        let mut out = [0.0_f32; 0];
        write_output(&mut out, &[], 0, 1.0);
    }
}
