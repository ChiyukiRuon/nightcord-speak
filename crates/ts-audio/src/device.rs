//! Device discovery and the backend abstraction (§27).
//!
//! The UI needs a list of microphones and speakers, and a way to name one to
//! switch to. That is all this module is: opening streams is
//! [`crate::capture`] and [`crate::playback`].

use std::str::FromStr as _;

use cpal::traits::{DeviceTrait as _, HostTrait as _};
use ts_model::AudioError;

/// Which way audio flows through a device.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Direction {
    /// A microphone.
    Input,
    /// Speakers or headphones.
    Output,
}

impl Direction {
    /// A short label for logs and error messages.
    #[must_use]
    pub const fn label(self) -> &'static str {
        match self {
            Self::Input => "input",
            Self::Output => "output",
        }
    }

    /// The error to report when no device of this direction exists.
    #[must_use]
    const fn missing(self) -> AudioError {
        match self {
            Self::Input => AudioError::NoInputDevice,
            Self::Output => AudioError::NoOutputDevice,
        }
    }
}

/// One selectable audio device.
///
/// `id` is opaque to a front-end: it comes from the audio host and is only
/// meaningful when handed back to [`resolve`]. `cpal` renders these as
/// `"<host>:<device>"` and supports parsing them back, which is what makes a
/// saved device survive a restart.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AudioDevice {
    /// Identifier to pass back when selecting this device.
    pub id: String,
    /// Name to show the user.
    pub name: String,
    /// Whether the host considers this its default for its direction.
    pub is_default: bool,
    /// The device's default sample rate, if the host reports one.
    pub sample_rate: Option<u32>,
    /// The device's default channel count, if the host reports one.
    pub channels: Option<u16>,
}

impl AudioDevice {
    /// The identifier to pass back to select this device.
    #[must_use]
    pub fn id(&self) -> &str {
        &self.id
    }

    /// A name to show, falling back to the id when the host gave no name.
    #[must_use]
    pub fn display_name(&self) -> &str {
        if self.name.is_empty() {
            &self.id
        } else {
            &self.name
        }
    }
}

/// Enumerating a machine's audio devices (§27).
///
/// Split from stream handling so a front-end can populate its device list
/// without the ability to open anything.
pub trait AudioBackend: Send + Sync {
    /// Every microphone, defaults first.
    ///
    /// # Errors
    ///
    /// Returns [`AudioError::Backend`] if the host cannot be queried at all.
    fn input_devices(&self) -> Result<Vec<AudioDevice>, AudioError>;

    /// Every speaker, defaults first.
    ///
    /// # Errors
    ///
    /// Returns [`AudioError::Backend`] if the host cannot be queried at all.
    fn output_devices(&self) -> Result<Vec<AudioDevice>, AudioError>;

    /// Every device for one direction.
    ///
    /// # Errors
    ///
    /// Returns [`AudioError::Backend`] if the host cannot be queried at all.
    fn devices(&self, direction: Direction) -> Result<Vec<AudioDevice>, AudioError> {
        match direction {
            Direction::Input => self.input_devices(),
            Direction::Output => self.output_devices(),
        }
    }
}

/// The operating system's audio, backed by `cpal`.
#[derive(Debug, Default, Clone, Copy)]
pub struct SystemAudio;

impl SystemAudio {
    /// The system audio backend.
    #[must_use]
    pub const fn new() -> Self {
        Self
    }
}

impl AudioBackend for SystemAudio {
    fn input_devices(&self) -> Result<Vec<AudioDevice>, AudioError> {
        collect(Direction::Input)
    }

    fn output_devices(&self) -> Result<Vec<AudioDevice>, AudioError> {
        collect(Direction::Output)
    }
}

/// Lists the devices for one direction, default first.
///
/// Devices that cannot report an id are skipped rather than surfaced
/// unselectable: a list entry the user cannot choose is worse than a shorter
/// list.
fn collect(direction: Direction) -> Result<Vec<AudioDevice>, AudioError> {
    let host = cpal::default_host();

    let default_id = match direction {
        Direction::Input => host.default_input_device(),
        Direction::Output => host.default_output_device(),
    }
    .and_then(|device| device.id().ok())
    .map(|id| id.to_string());

    let devices = match direction {
        Direction::Input => host.input_devices(),
        Direction::Output => host.output_devices(),
    }
    .map_err(|error| AudioError::Backend {
        message: error.to_string(),
    })?;

    let mut collected: Vec<AudioDevice> = devices
        .filter_map(|device| {
            let id = device.id().ok()?.to_string();
            let name = device
                .description()
                .map(|d| d.name().to_string())
                .unwrap_or_default();

            let config = match direction {
                Direction::Input => device.default_input_config().ok(),
                Direction::Output => device.default_output_config().ok(),
            };

            Some(AudioDevice {
                is_default: default_id.as_deref() == Some(id.as_str()),
                id,
                name,
                sample_rate: config
                    .as_ref()
                    .map(cpal::SupportedStreamConfig::sample_rate),
                channels: config.as_ref().map(cpal::SupportedStreamConfig::channels),
            })
        })
        .collect();

    // Defaults first, then alphabetical so the order is stable between runs.
    collected.sort_by(|a, b| {
        b.is_default
            .cmp(&a.is_default)
            .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
    });
    collected.dedup_by(|a, b| a.id == b.id);

    tracing::debug!(
        direction = direction.label(),
        count = collected.len(),
        "enumerated devices"
    );
    Ok(collected)
}

/// Whether a stream error means the stream is finished for good.
///
/// Most errors `cpal` reports are transient. Treating them all as fatal leaves
/// the user with no audio after a single glitch — which is exactly what a live
/// test caught: a WASAPI buffer underrun marked the microphone dead even though
/// it kept delivering frames afterwards.
///
/// `DeviceChanged` is deliberately not fatal: the host has already rerouted the
/// stream and it keeps running.
#[must_use]
pub(crate) fn is_fatal(error: &cpal::Error) -> bool {
    matches!(
        error.kind(),
        cpal::ErrorKind::DeviceNotAvailable
            | cpal::ErrorKind::HostUnavailable
            | cpal::ErrorKind::StreamInvalidated
    )
}

/// A device that was resolved, and whether it is the one that was asked for.
///
/// Public because [`Capture::device`] and [`Playback::device`] hand it out: what
/// a caller needs to know is not just "something opened" but *which*, since a
/// fallback is silent otherwise.
///
/// [`Capture::device`]: crate::capture::Capture::device
/// [`Playback::device`]: crate::playback::Playback::device
pub struct Resolved {
    /// The device to open.
    pub device: cpal::Device,
    /// The id it is known by, so the caller can report *what* it opened rather
    /// than what it was asked for.
    pub id: String,
    /// Its name, as the host reports it.
    pub name: String,
    /// Whether the requested device was not found and this is the fallback.
    pub fell_back: bool,
}

/// Looks up a device by id, or falls back to the host's default.
///
/// A saved device id can stop existing — a USB headset gets unplugged — and
/// failing the entire call for that would leave the user with no audio and no
/// obvious way back. Falling back to the default keeps them audible.
///
/// Returns *which* device it settled on, so the answer can reach the user: a
/// log line nobody reads is not enough for "you think you are on a headset and
/// you are actually on the laptop's microphone".
pub(crate) fn resolve(direction: Direction, id: Option<&str>) -> Result<Resolved, AudioError> {
    let host = cpal::default_host();

    if let Some(wanted) = id {
        match cpal::DeviceId::from_str(wanted) {
            Ok(parsed) => {
                if let Some(device) = host.device_by_id(&parsed) {
                    let described = describe(&device);
                    return Ok(Resolved {
                        device,
                        id: described.0,
                        name: described.1,
                        fell_back: false,
                    });
                }
                tracing::warn!(
                    direction = direction.label(),
                    device = wanted,
                    "saved device is gone; falling back to the system default"
                );
            }
            Err(error) => {
                tracing::warn!(
                    direction = direction.label(),
                    device = wanted,
                    %error,
                    "saved device id is malformed; falling back to the system default"
                );
            }
        }
    }

    let fallback = match direction {
        Direction::Input => host.default_input_device(),
        Direction::Output => host.default_output_device(),
    };

    // Only a *requested* device that could not be opened is a fallback;
    // choosing the system default on purpose is not. Read before `describe`
    // shadows the name.
    let fell_back = id.is_some();

    let device = fallback.ok_or_else(|| direction.missing())?;
    let (id, name) = describe(&device);

    Ok(Resolved {
        device,
        id,
        name,
        fell_back,
    })
}

/// The id and name of a device, with the id's absence reported as an empty
/// string rather than as a failure.
fn describe(device: &cpal::Device) -> (String, String) {
    let id = device.id().map(|id| id.to_string()).unwrap_or_default();
    let name = device
        .description()
        .map(|described| described.name().to_string())
        .unwrap_or_default();
    (id, name)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn direction_labels_are_stable() {
        assert_eq!(Direction::Input.label(), "input");
        assert_eq!(Direction::Output.label(), "output");
    }

    #[test]
    fn a_device_without_a_name_shows_its_id() {
        let device = AudioDevice {
            id: "fallback".into(),
            name: String::new(),
            is_default: false,
            sample_rate: None,
            channels: None,
        };
        assert_eq!(device.display_name(), "fallback");
        assert_eq!(device.id(), "fallback");
    }

    #[test]
    fn a_named_device_shows_its_name() {
        let device = AudioDevice {
            id: "wasapi:speakers".into(),
            name: "Realtek USB Audio".into(),
            is_default: true,
            sample_rate: Some(48_000),
            channels: Some(2),
        };
        assert_eq!(device.display_name(), "Realtek USB Audio");
    }

    #[test]
    fn enumeration_returns_a_default_first_and_sorts_the_rest() {
        // Runs against whatever host the test machine has. It asserts the
        // ordering invariant rather than a device count, because a CI container
        // legitimately has none.
        let backend = SystemAudio::new();
        for direction in [Direction::Input, Direction::Output] {
            let devices = backend
                .devices(direction)
                .unwrap_or_else(|e| panic!("{} enumeration failed: {e}", direction.label()));

            let defaults: Vec<usize> = devices
                .iter()
                .enumerate()
                .filter(|(_, d)| d.is_default)
                .map(|(i, _)| i)
                .collect();
            assert!(
                defaults.len() <= 1,
                "{}: more than one default device",
                direction.label()
            );
            assert!(
                defaults.first().is_none_or(|&i| i == 0),
                "{}: the default must sort first",
                direction.label()
            );

            let mut sorted = devices.clone();
            sorted.sort_by(|a, b| {
                b.is_default
                    .cmp(&a.is_default)
                    .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
            });
            assert_eq!(
                devices,
                sorted,
                "{}: ordering is not stable",
                direction.label()
            );

            let mut ids: Vec<&str> = devices.iter().map(|d| d.id.as_str()).collect();
            ids.sort_unstable();
            ids.dedup();
            assert_eq!(
                ids.len(),
                devices.len(),
                "{}: duplicate ids",
                direction.label()
            );
        }
    }

    #[test]
    fn resolving_an_unknown_device_falls_back_rather_than_failing() {
        // A saved id for an unplugged headset must not leave the user silent.
        // On a machine with no devices at all this correctly reports that
        // instead, which is why both outcomes are accepted here.
        match resolve(
            Direction::Output,
            Some("wasapi:a device that does not exist"),
        ) {
            Ok(_) => {}
            Err(AudioError::NoOutputDevice) => {}
            Err(other) => panic!("unexpected error: {other}"),
        }
    }

    #[test]
    fn an_xrun_is_not_fatal() {
        // The bug a live test caught: a single WASAPI underrun was marking the
        // microphone dead while it was still delivering frames.
        let xrun = cpal::Error::with_message(cpal::ErrorKind::Xrun, "underrun");
        assert!(!is_fatal(&xrun));
    }

    #[test]
    fn transient_and_rerouting_errors_are_not_fatal() {
        for kind in [
            cpal::ErrorKind::DeviceBusy,
            // The host has already rerouted the stream and it keeps running.
            cpal::ErrorKind::DeviceChanged,
            cpal::ErrorKind::RealtimeDenied,
        ] {
            let error = cpal::Error::with_message(kind, "transient");
            assert!(!is_fatal(&error), "{kind:?} should not end the stream");
        }
    }

    #[test]
    fn a_vanished_device_is_fatal() {
        for kind in [
            cpal::ErrorKind::DeviceNotAvailable,
            cpal::ErrorKind::HostUnavailable,
            cpal::ErrorKind::StreamInvalidated,
        ] {
            let error = cpal::Error::with_message(kind, "gone");
            assert!(is_fatal(&error), "{kind:?} should end the stream");
        }
    }

    #[test]
    fn resolving_a_malformed_id_falls_back() {
        // The stored string came from us, but a hand-edited settings file or an
        // older format must not crash the client.
        match resolve(Direction::Output, Some("not a valid device id")) {
            Ok(_) => {}
            Err(AudioError::NoOutputDevice) => {}
            Err(other) => panic!("unexpected error: {other}"),
        }
    }
}
