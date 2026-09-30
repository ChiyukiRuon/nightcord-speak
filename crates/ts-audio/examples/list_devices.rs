//! Lists the audio devices this machine offers.
//!
//! Useful both as a smoke test for the audio backend and as a way to find the
//! device id to put in a settings file.
//!
//! ```text
//! cargo run -p ts-audio --example list_devices
//! ```

use ts_audio::{AudioBackend, Direction, SystemAudio};

fn main() {
    let backend = SystemAudio::new();

    for direction in [Direction::Input, Direction::Output] {
        match backend.devices(direction) {
            Ok(devices) if devices.is_empty() => {
                println!("{}: (none found)", direction.label());
            }
            Ok(devices) => {
                println!("{} ({}):", direction.label(), devices.len());
                for device in devices {
                    let default = if device.is_default { " [default]" } else { "" };
                    let format = match (device.sample_rate, device.channels) {
                        (Some(rate), Some(channels)) => format!(" — {rate} Hz, {channels} ch"),
                        _ => String::new(),
                    };
                    println!("  {}{}{}", device.display_name(), default, format);
                    println!("    id: {}", device.id());
                }
            }
            Err(error) => println!("{}: failed — {error}", direction.label()),
        }
    }
}
