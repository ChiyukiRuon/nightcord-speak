//! Audio device marshalling.
//!
//! The voice engine itself never crosses the ABI: it lives in the worker task,
//! its sink is wired straight to the session, and Dart only sends control
//! commands. That is what keeps 50 frames a second of Opus payload off the
//! JSON boundary (§80 principle 4).

use serde::Serialize;
use ts_audio::{AudioBackend as _, AudioDevice, Direction, SystemAudio};
use ts_model::AudioError;

/// Which way audio flows, as the FFI spells it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum AudioDirection {
    /// A microphone.
    Input,
    /// Speakers or headphones.
    Output,
}

impl AudioDirection {
    /// Parses the string the C ABI accepts.
    ///
    /// Returns `None` for anything else, which the entry point turns into a
    /// failed `CommandResult` rather than guessing.
    #[must_use]
    pub(crate) fn parse(text: &str) -> Option<Self> {
        match text {
            "input" => Some(Self::Input),
            "output" => Some(Self::Output),
            _ => None,
        }
    }

    /// The spelling the ABI uses.
    #[must_use]
    pub(crate) const fn as_str(self) -> &'static str {
        match self {
            Self::Input => "input",
            Self::Output => "output",
        }
    }

    fn direction(self) -> Direction {
        match self {
            Self::Input => Direction::Input,
            Self::Output => Direction::Output,
        }
    }
}

/// A device as the front-end sees it.
///
/// [`AudioDevice`] is not `Serialize` — it belongs to `ts-audio`, which has no
/// business knowing about a wire format — so it is mirrored here rather than
/// pushing serde down into the audio layer.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub(crate) struct DeviceJson {
    /// Opaque identifier to pass back when selecting this device.
    pub id: String,
    /// Name to show the user.
    pub name: String,
    /// Whether the host considers it the default for its direction.
    pub is_default: bool,
    /// Native sample rate, when the host reports one.
    pub sample_rate: Option<u32>,
    /// Native channel count, when the host reports one.
    pub channels: Option<u16>,
}

impl From<AudioDevice> for DeviceJson {
    fn from(device: AudioDevice) -> Self {
        // Resolved before the struct is built: `display_name` borrows the
        // device, and the id is moved in below.
        let name = device.display_name().to_string();
        Self {
            id: device.id,
            name,
            is_default: device.is_default,
            sample_rate: device.sample_rate,
            channels: device.channels,
        }
    }
}

/// Lists the machine's devices for one direction.
///
/// # Errors
///
/// Returns [`AudioError::Backend`] when the host cannot be queried at all.
pub(crate) fn list(direction: AudioDirection) -> Result<Vec<DeviceJson>, AudioError> {
    let devices = SystemAudio::new().devices(direction.direction())?;
    Ok(devices.into_iter().map(DeviceJson::from).collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn directions_round_trip_through_their_spelling() {
        for direction in [AudioDirection::Input, AudioDirection::Output] {
            assert_eq!(AudioDirection::parse(direction.as_str()), Some(direction));
        }
    }

    #[test]
    fn an_unknown_direction_is_rejected_rather_than_defaulted() {
        // Silently treating "microphone" as input would hide a caller's typo
        // behind a device list that happens to look plausible.
        assert_eq!(AudioDirection::parse("microphone"), None);
        assert_eq!(AudioDirection::parse(""), None);
        assert_eq!(
            AudioDirection::parse("Input"),
            None,
            "the ABI is case-sensitive"
        );
    }

    #[test]
    fn a_device_without_a_name_still_gets_one() {
        // `cpal` occasionally reports an empty name; showing the id beats
        // showing a blank row the user cannot tell apart from another blank row.
        let device = AudioDevice {
            id: "wasapi:speakers".into(),
            name: String::new(),
            is_default: true,
            sample_rate: Some(48_000),
            channels: Some(2),
        };

        let json = DeviceJson::from(device);
        assert_eq!(json.name, "wasapi:speakers");
        assert_eq!(json.id, "wasapi:speakers");
    }

    #[test]
    fn a_named_device_keeps_its_name_and_id_separate() {
        let device = AudioDevice {
            id: "wasapi:{guid}".into(),
            name: "Razer Kraken".into(),
            is_default: false,
            sample_rate: Some(48_000),
            channels: Some(2),
        };

        let json = DeviceJson::from(device);
        assert_eq!(json.name, "Razer Kraken");
        assert_eq!(json.id, "wasapi:{guid}");
    }

    #[test]
    fn the_json_shape_is_what_dart_expects() {
        let json = serde_json::to_value(DeviceJson {
            id: "wasapi:x".into(),
            name: "Speakers".into(),
            is_default: true,
            sample_rate: Some(48_000),
            channels: Some(2),
        })
        .unwrap();

        assert_eq!(json["id"], "wasapi:x");
        assert_eq!(json["name"], "Speakers");
        assert_eq!(json["is_default"], true);
        assert_eq!(json["sample_rate"], 48_000);
        assert_eq!(json["channels"], 2);
    }

    #[test]
    fn enumeration_reports_rather_than_panics() {
        // Runs against whatever host this machine has: a CI container with no
        // audio must still return a list, not abort.
        match list(AudioDirection::Output) {
            Ok(devices) => {
                // Defaults sort first, which is what the UI relies on.
                if let Some(position) = devices.iter().position(|d| d.is_default) {
                    assert_eq!(position, 0, "the default device must sort first");
                }
            }
            Err(error) => panic!("enumeration failed outright: {error}"),
        }
    }
}
