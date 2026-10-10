//! Local notification playback, independent of voice muting and sessions.

use std::io::{Cursor, Read as _};
use std::path::{Path, PathBuf};
use std::sync::{OnceLock, mpsc};
use std::time::{Duration, Instant};

use symphonia::core::{audio::SampleBuffer, errors::Error, io::MediaSourceStream, probe::Hint};

use crate::{Playback, Resampler, SAMPLE_RATE};

const MAX_BYTES: u64 = 20 * 1024 * 1024;
const MAX_SECONDS: usize = 30;

struct Request {
    path: PathBuf,
    output: Option<String>,
    volume: f32,
}

/// Queues bounded work; file I/O, decoding and opening devices stay off the UI thread.
pub fn enqueue(path: PathBuf, output: Option<String>, volume: f32) -> bool {
    static QUEUE: OnceLock<Option<mpsc::SyncSender<Request>>> = OnceLock::new();
    let queue = QUEUE.get_or_init(|| {
        let (sender, receiver) = mpsc::sync_channel::<Request>(8);
        std::thread::Builder::new()
            .name("notification-sounds".into())
            .spawn(move || {
                for request in receiver {
                    if let Err(error) = play(&request) {
                        // Do not include user-controlled file contents or paths.
                        tracing::warn!(%error, "notification sound playback failed");
                    }
                }
            })
            .ok()
            .map(|_| sender)
    });
    queue.as_ref().is_some_and(|queue| {
        queue
            .try_send(Request {
                path,
                output,
                volume,
            })
            .is_ok()
    })
}

fn decode(path: &Path) -> Result<Vec<f32>, String> {
    let file = std::fs::File::open(path).map_err(|_| "cannot open sound file")?;
    let mut bytes = Vec::new();
    file.take(MAX_BYTES + 1)
        .read_to_end(&mut bytes)
        .map_err(|_| "cannot read sound file")?;
    if bytes.len() as u64 > MAX_BYTES {
        return Err("sound file exceeds 20 MiB".into());
    }
    decode_bytes(bytes)
}

fn decode_bytes(bytes: Vec<u8>) -> Result<Vec<f32>, String> {
    let source = MediaSourceStream::new(Box::new(Cursor::new(bytes)), Default::default());
    let mut format = symphonia::default::get_probe()
        .format(
            &Hint::new(),
            source,
            &Default::default(),
            &Default::default(),
        )
        .map_err(|_| "unsupported or damaged sound file")?
        .format;
    let track = format
        .default_track()
        .ok_or("sound file has no audio track")?;
    let id = track.id;
    let mut decoder = symphonia::default::get_codecs()
        .make(&track.codec_params, &Default::default())
        .map_err(|_| "unsupported audio codec")?;
    let mut channels = [Vec::new(), Vec::new()];
    let mut rate = None;
    loop {
        let packet = match format.next_packet() {
            Ok(packet) => packet,
            Err(Error::IoError(error)) if error.kind() == std::io::ErrorKind::UnexpectedEof => {
                break;
            }
            Err(_) => return Err("damaged sound container".into()),
        };
        if packet.track_id() != id {
            continue;
        }
        let decoded = decoder.decode(&packet).map_err(|_| "damaged audio data")?;
        let spec = *decoded.spec();
        let count = spec.channels.count();
        if spec.rate == 0 || !(1..=2).contains(&count) || rate.is_some_and(|rate| rate != spec.rate)
        {
            return Err("sound must have a constant sample rate and one or two channels".into());
        }
        rate = Some(spec.rate);
        let mut buffer = SampleBuffer::<f32>::new(decoded.capacity() as u64, spec);
        buffer.copy_interleaved_ref(decoded);
        for frame in buffer.samples().chunks_exact(count) {
            if frame.iter().any(|sample| !sample.is_finite()) {
                return Err("invalid audio sample".into());
            }
            channels[0].push(frame[0]);
            channels[1].push(frame[count - 1]);
        }
        if channels[0].len() > spec.rate as usize * MAX_SECONDS {
            return Err("sound exceeds 30 seconds".into());
        }
    }
    let rate = rate.ok_or("sound file is empty")?;
    let mut stereo = [Vec::new(), Vec::new()];
    for index in 0..2 {
        Resampler::new(rate).process(&channels[index], &mut stereo[index]);
    }
    Ok(stereo[0]
        .iter()
        .zip(&stereo[1])
        .flat_map(|(&left, &right)| [left, right])
        .collect())
}

fn play(request: &Request) -> Result<(), String> {
    let samples = decode(&request.path)?;
    let playback = Playback::open_with_volume(request.output.as_deref(), request.volume)
        .map_err(|_| "cannot open notification output device")?;
    let deadline = Instant::now() + Duration::from_secs(MAX_SECONDS as u64 + 5);
    let mut offset = 0;
    while offset < samples.len() {
        if Instant::now() > deadline {
            return Err("notification output timed out".into());
        }
        offset += playback.write(&samples[offset..]);
        std::thread::sleep(Duration::from_millis(10));
    }
    std::thread::sleep(
        Duration::from_secs_f64(
            samples.len().min(SAMPLE_RATE as usize * 2) as f64 / (f64::from(SAMPLE_RATE) * 2.0),
        ) + Duration::from_millis(100),
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn supported_formats_decode_to_finite_stereo_samples() {
        // Tiny generated tones exercise the actual codec registrations, not extensions.
        for bytes in [
            include_bytes!("../tests/fixtures/tone.wav").as_slice(),
            include_bytes!("../tests/fixtures/tone.mp3").as_slice(),
            include_bytes!("../tests/fixtures/tone.flac").as_slice(),
        ] {
            let decoded = decode_bytes(bytes.to_vec()).unwrap();
            assert!(decoded.len() >= 4_000);
            assert_eq!(decoded.len() % 2, 0);
            assert!(decoded.iter().all(|sample| sample.is_finite()));
            assert!(decoded.iter().any(|sample| sample.abs() > 0.01));
        }
    }

    #[test]
    fn malformed_audio_is_an_error() {
        assert!(decode_bytes(b"not audio".to_vec()).is_err());
    }

    #[test]
    fn mono_wav_is_resampled_to_stereo() {
        let mut bytes = b"RIFF".to_vec();
        bytes.extend_from_slice(&40_u32.to_le_bytes());
        bytes.extend_from_slice(b"WAVEfmt ");
        bytes.extend_from_slice(&16_u32.to_le_bytes());
        for value in [1_u16, 1] {
            bytes.extend_from_slice(&value.to_le_bytes());
        }
        bytes.extend_from_slice(&24_000_u32.to_le_bytes());
        bytes.extend_from_slice(&48_000_u32.to_le_bytes());
        for value in [2_u16, 16] {
            bytes.extend_from_slice(&value.to_le_bytes());
        }
        bytes.extend_from_slice(b"data");
        bytes.extend_from_slice(&4_u32.to_le_bytes());
        for value in [16_384_i16, -16_384] {
            bytes.extend_from_slice(&value.to_le_bytes());
        }
        let samples = decode_bytes(bytes).unwrap();
        assert!(!samples.is_empty());
        assert!(samples.chunks_exact(2).all(|frame| frame[0] == frame[1]));
        assert!((samples[0] - 0.5).abs() < 0.001);
    }
}
