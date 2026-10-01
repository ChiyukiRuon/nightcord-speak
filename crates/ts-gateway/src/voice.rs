//! The gateway's voice path: PCM in from browsers, PCM out to them.
//!
//! Opus never leaves Rust (§80 principle 4). The pieces are `ts-audio`'s, used
//! without its engine — the engine is welded to cpal devices, and a gateway has
//! no devices; what it has is a socket. Both halves were chosen because they
//! are exactly the seam:
//!
//! - **Out**: the backend hands decoded stereo `f32` to an
//!   [`AudioSink`](ts_protocol::AudioSink). The gateway's sink forwards each
//!   frame to every connection in one binary message.
//! - **In**: the browser sends 960-sample mono frames (it accumulates to that
//!   size itself, on its true 48 kHz clock — see `web/pcm-worklet.js`);
//!   `TransmitPolicy` gates them by mode, `OpusEncoder` encodes what gets
//!   through, and the worker sends one packet per session.
//!
//! Nothing here decodes: `tsclientlib` already did.

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering};

use tokio::sync::broadcast;
use ts_audio::{FRAME_MS, FRAME_SAMPLES, OpusEncoder, TransmitPolicy, rms};
use ts_model::{AudioError, SessionId, VoiceActivationMode, VoiceActivationSettings};
use ts_protocol::VoicePacket;

use crate::Outbound;

/// The first byte of a binary frame carrying captured audio to the gateway.
pub const FRAME_INPUT: u8 = 1;

/// The first byte of a binary frame carrying playback audio to the browser.
pub const FRAME_OUTPUT: u8 = 2;

/// Decodes one browser audio frame.
///
/// Anything that is not exactly one 960-sample mono frame is rejected rather
/// than trimmed: a frame of the wrong length means the page and the gateway
/// disagree about the protocol, and guessing which side is right would hide
/// that. Explicit little-endian, though every platform the web runs on is
/// little-endian — the one line that removes a class of portability bug.
#[must_use]
pub fn parse_input_frame(bytes: &[u8]) -> Option<Vec<f32>> {
    let (tag, payload) = bytes.split_first()?;
    if *tag != FRAME_INPUT || payload.len() != FRAME_SAMPLES * 4 {
        return None;
    }
    Some(
        payload
            .chunks_exact(4)
            .map(|chunk| f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]))
            .collect(),
    )
}

/// Sums the frames browsers sent since the last tick into one.
///
/// Scaled by `1/n` so two people at full volume cannot clip three; a talker
/// who is silent contributes silence, which is what "nobody spoke this tick"
/// means. Returns `None` when nobody sent anything — the gate is not opened
/// for a room nobody is talking in.
#[must_use]
pub fn mix(frames: &[Vec<f32>], out: &mut [f32]) -> bool {
    if frames.is_empty() {
        return false;
    }
    out.fill(0.0);
    for frame in frames {
        for (sum, sample) in out.iter_mut().zip(frame.iter()) {
            *sum += sample;
        }
    }
    let scale = 1.0 / frames.len() as f32;
    for sample in out.iter_mut() {
        *sample = (*sample * scale).clamp(-1.0, 1.0);
    }
    true
}

/// The session's voice boundary on the gateway side.
pub(crate) struct RemoteVoice {
    /// Which session the encoder feeds.
    pub session: SessionId,
    encoder: OpusEncoder,
    policy: TransmitPolicy,
    /// Microphone gain, as a linear factor — the decibels the user chose in the
    /// same settings file the desktop uses.
    input_gain: f32,
    /// The last mixed frame's loudness, so `voice_status` can answer without
    /// waiting for the next push.
    last_level: f32,
    last_peak: f32,
    last_transmitting: bool,
}

impl RemoteVoice {
    /// Builds the path for `session` from the stored preferences.
    pub(crate) fn new(
        session: SessionId,
        mode: VoiceActivationMode,
        activation: VoiceActivationSettings,
    ) -> Result<Self, AudioError> {
        Ok(Self {
            session,
            // Mono: a browser's worklet sends 960 samples per frame, and a stereo
            // encoder would reject every one of them as half a frame.
            encoder: OpusEncoder::new(ts_audio::VOICE_CHANNELS)?,
            policy: TransmitPolicy::new(mode, activation),
            // Unity until the worker applies the stored preference, which it
            // does in the same breath as building this.
            input_gain: 1.0,
            last_level: 0.0,
            last_peak: 0.0,
            last_transmitting: false,
        })
    }

    /// Gates and encodes one mixed frame; `None` means the gate is closed.
    ///
    /// Takes the frame mutably because the microphone gain is applied to it —
    /// after the gate, never before, so the level the sensitivity threshold is
    /// compared against stays the browser's own. See the desktop's
    /// `VoiceEngine::poll` for the same argument.
    pub(crate) fn encode_frame(
        &mut self,
        mixed: &mut [f32],
    ) -> Result<Option<VoicePacket>, AudioError> {
        // The order matters and mirrors `VoiceEngine::measure`: the level is
        // recorded *before* the policy runs, or the meter lies in the modes
        // that keep the gate shut.
        self.last_level = rms(mixed);
        self.last_peak = ts_audio::peak(mixed);
        let transmitting = self.policy.should_transmit(self.last_level, FRAME_MS);
        self.last_transmitting = transmitting;
        if !transmitting {
            return Ok(None);
        }
        ts_audio::apply_gain(mixed, self.input_gain);
        let mut packet = self.encoder.encode(mixed)?;
        // The first frame after silence is flagged, so the far end can tell
        // "they started talking again" from "packets were lost".
        packet.is_dtx_resume = self.policy.is_resume();
        Ok(Some(packet))
    }

    /// The mode the browser asked for.
    pub(crate) fn set_mode(&mut self, mode: VoiceActivationMode) {
        self.policy.set_mode(mode);
    }

    /// Mute or unmute, through the same policy the desktop uses.
    ///
    /// `input_muted` is a second gate on top of the mode — the desktop's own
    /// semantics, kept rather than reinvented.
    pub(crate) fn set_input_muted(&mut self, muted: bool) {
        self.policy.set_input_muted(muted);
    }

    pub(crate) fn set_push_to_talk(&mut self, held: bool) {
        self.policy.set_push_to_talk(held);
    }

    /// Deafens or undeafens, which closes the transmit gate as well.
    ///
    /// The server refuses voice from a deafened client, so frames sent while
    /// deafened are frames the far end never sees — and each one came back as
    /// `VoiceError::NotConnected`, which the worker reported to every browser.
    pub(crate) fn set_output_muted(&mut self, muted: bool) {
        self.policy.set_output_muted(muted);
    }

    /// Marks the browser's client away or back, which closes the transmit gate.
    ///
    /// The same reason deafening closes it: the server refuses voice from an
    /// away client, so every frame the browser sent while away was a frame
    /// nobody hears — each one answered with `VoiceError::NotConnected` and
    /// broadcast to every connection.
    pub(crate) fn set_away(&mut self, away: bool) {
        self.policy.set_away(away);
    }

    /// Sets the microphone gain in decibels, the way the desktop does.
    ///
    /// It comes from the same settings file, so a browser and a desktop
    /// talking through one core hear each other's voice the same way — and a
    /// user who set their gain on the desktop is not quietly quiet in the
    /// browser.
    pub(crate) fn set_input_gain_db(&mut self, db: f32) {
        self.input_gain = ts_audio::gain_from_db(ts_audio::clamp_gain_db(db));
    }

    pub(crate) fn set_settings(&mut self, settings: VoiceActivationSettings) {
        self.policy.set_settings(settings);
    }

    /// The meter readings, as `voice_status` reports them.
    pub(crate) fn levels(&self) -> (f32, f32, bool) {
        (self.last_level, self.last_peak, self.last_transmitting)
    }

    /// Which profile this end is encoding with, for `voice_status`.
    ///
    /// Always the voice profile: what arrives from a browser is 960 mono
    /// samples per frame, and the stereo profile would reject every frame as
    /// half a frame long.
    pub(crate) fn codec(&self) -> ts_protocol::Codec {
        self.encoder.packet_codec()
    }

    /// The bitrate that profile amounts to, for `voice_status`.
    pub(crate) fn bitrate(&self) -> i32 {
        self.encoder.bitrate()
    }
}

/// Receives decoded audio from the backend and forwards it to every browser.
///
/// `space()` reports unbounded capacity, and that is the honest answer here:
/// the fan-out is a `broadcast`, where a slow consumer *lags and loses*
/// rather than pushing back. The concrete cpal sink's bounded ring exists to
/// keep a real output buffer from overflowing; a gateway has no output buffer,
/// and reporting a bound would make the backend skip decoding for a backlog
/// nobody is actually holding.
pub(crate) struct WsAudioSink {
    outbound: broadcast::Sender<Outbound>,
    /// Deafening is a gate on this side too: the backend keeps decoding (the
    /// jitter buffer must keep draining), but nothing goes to the browsers.
    output_muted: Arc<AtomicBool>,
    /// Whether the first forwarded frame has been logged, so the line appears
    /// once per voice session rather than fifty times a second. "Did any
    /// playback audio arrive at all" was the first question a silent speaker
    /// raised during the first end-to-end test, and nothing could answer it.
    logged_first: AtomicBool,
    /// Frames and peak forwarded so far, so `voice_status` can report what
    /// the *receive* side is doing with the same kind of numbers the CLI's
    /// `AudioReport` prints. The peak is what tells "audio arrived" from
    /// "audio arrived and is a whisper" — a distinction that cost an evening.
    frames: AtomicU64,
    peak_bits: AtomicU32,
}

impl WsAudioSink {
    pub(crate) fn new(
        outbound: broadcast::Sender<Outbound>,
        output_muted: Arc<AtomicBool>,
    ) -> Self {
        Self {
            outbound,
            output_muted,
            logged_first: AtomicBool::new(false),
            frames: AtomicU64::new(0),
            peak_bits: AtomicU32::new(0),
        }
    }

    /// Frames forwarded since this sink was built.
    pub(crate) fn frames(&self) -> u64 {
        self.frames.load(Ordering::Relaxed)
    }

    /// The loudest sample forwarded since this sink was built, in `0.0..=1.0`.
    pub(crate) fn peak(&self) -> f32 {
        f32::from_bits(self.peak_bits.load(Ordering::Relaxed))
    }

    /// Records one forwarded frame, for `voice_status`.
    ///
    /// Kept beside `push` because the two have to agree on what counts. These
    /// counters were read for a while without ever being written: `received`
    /// sat at 0 through playback audio that had arrived and been forwarded, and
    /// a 0 there reads exactly like a broken receive path. They are the only
    /// answer to "did audio arrive, and how loud is it" that does not need
    /// ears — the once-only log line above can prove a first frame and nothing
    /// about the stream behind it.
    fn record(&self, interleaved: &[f32]) {
        self.frames.fetch_add(1, Ordering::Relaxed);
        let peak = interleaved
            .iter()
            .fold(0.0f32, |loudest, sample| loudest.max(sample.abs()));
        // Compare-exchange rather than load-then-store: a backend is free to
        // push from more than one task, and a plain store would let the
        // quieter frame of a pair win the race and hide the loud one.
        let mut seen = self.peak_bits.load(Ordering::Relaxed);
        while peak > f32::from_bits(seen) {
            match self.peak_bits.compare_exchange_weak(
                seen,
                peak.to_bits(),
                Ordering::Relaxed,
                Ordering::Relaxed,
            ) {
                Ok(_) => break,
                Err(current) => seen = current,
            }
        }
    }
}

impl ts_protocol::AudioSink for WsAudioSink {
    fn push(&self, interleaved: &[f32]) {
        if self.output_muted.load(Ordering::Relaxed) {
            return;
        }
        // Counted past the mute gate, so the numbers mean "forwarded" rather
        // than "arrived": a deafened sink is silent at both ends of the
        // socket, and `voice_status` should not claim otherwise.
        self.record(interleaved);
        // Interleaved stereo from the backend; the page writes one message at
        // a time into its ring, so the layout travels as-is.
        let mut bytes = Vec::with_capacity(1 + interleaved.len() * 4);
        bytes.push(FRAME_OUTPUT);
        for sample in interleaved {
            bytes.extend_from_slice(&sample.to_le_bytes());
        }
        if !self.logged_first.swap(true, Ordering::Relaxed) {
            tracing::info!(
                samples = interleaved.len(),
                "voice: first playback frame forwarded"
            );
        }
        // No receivers (nobody connected) is not an error: the message is
        // simply not sent.
        let _ = self.outbound.send(Outbound::Binary(bytes));
    }

    fn space(&self) -> usize {
        usize::MAX
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn input_frames_round_trip_through_their_little_endian_bytes() {
        let samples: Vec<f32> = (0..FRAME_SAMPLES)
            .map(|i| (i as f32) / 960.0 - 0.5)
            .collect();
        let mut bytes = vec![FRAME_INPUT];
        for sample in &samples {
            bytes.extend_from_slice(&sample.to_le_bytes());
        }

        let parsed = parse_input_frame(&bytes).expect("a well-formed frame");
        assert_eq!(parsed, samples);
    }

    #[test]
    fn a_frame_of_the_wrong_shape_is_rejected_not_trimmed() {
        // Right tag, wrong length: the page and the gateway disagree about the
        // protocol, and guessing which side is right would hide that.
        let short = vec![FRAME_INPUT; 4 + 100];
        assert!(parse_input_frame(&short).is_none());

        let wrong_tag = vec![FRAME_OUTPUT; 4 + FRAME_SAMPLES * 4];
        assert!(parse_input_frame(&wrong_tag).is_none());

        assert!(parse_input_frame(&[]).is_none());
    }

    #[test]
    fn mixing_averages_and_cannot_clip() {
        let loud = vec![1.0f32; FRAME_SAMPLES];
        let quiet = vec![-1.0f32; FRAME_SAMPLES];
        let mut out = vec![0.0f32; FRAME_SAMPLES];

        assert!(mix(&[loud.clone(), loud.clone()], &mut out));
        assert!(
            out.iter().all(|s| (s - 1.0).abs() < f32::EPSILON),
            "two full-scale talkers clamp to 1.0"
        );

        assert!(mix(&[loud, quiet], &mut out));
        assert!(
            out.iter().all(|s| s.abs() < f32::EPSILON),
            "opposite talkers cancel"
        );
    }

    #[test]
    fn nobody_talking_opens_no_gate() {
        let mut out = vec![0.0f32; FRAME_SAMPLES];
        assert!(!mix(&[], &mut out));
    }

    #[test]
    fn the_sink_forwards_decoded_frames_in_the_playback_layout() {
        let (tx, mut rx) = broadcast::channel(4);
        let sink = WsAudioSink::new(tx, Arc::new(AtomicBool::new(false)));

        let interleaved: Vec<f32> = vec![0.25, -0.25, 0.5, -0.5];
        ts_protocol::AudioSink::push(&sink, &interleaved);

        let Ok(Outbound::Binary(bytes)) = rx.try_recv() else {
            panic!("expected a binary frame");
        };
        assert_eq!(bytes[0], FRAME_OUTPUT);
        assert_eq!(bytes.len(), 1 + interleaved.len() * 4);
        assert_eq!(
            f32::from_le_bytes([bytes[1], bytes[2], bytes[3], bytes[4]]),
            0.25
        );
    }

    #[test]
    fn the_sink_counts_what_it_forwarded() {
        // Regression: the counters were read by `voice_status` but never
        // written, so `received` and `received_peak` reported 0 through audio
        // that arrived and was forwarded — the two numbers whose whole job is
        // separating "nothing arrived" from "arrived and is a whisper" said
        // "nothing arrived" either way.
        let (tx, _rx) = broadcast::channel(4);
        let sink = WsAudioSink::new(tx, Arc::new(AtomicBool::new(false)));

        ts_protocol::AudioSink::push(&sink, &[0.25, -0.5]);
        ts_protocol::AudioSink::push(&sink, &[0.125, 0.75]);

        assert_eq!(sink.frames(), 2);
        assert_eq!(sink.peak(), 0.75, "the loudest sample of either frame");
    }

    #[test]
    fn a_quieter_frame_does_not_lower_the_peak() {
        let (tx, _rx) = broadcast::channel(4);
        let sink = WsAudioSink::new(tx, Arc::new(AtomicBool::new(false)));

        ts_protocol::AudioSink::push(&sink, &[0.8]);
        ts_protocol::AudioSink::push(&sink, &[0.1]);

        assert_eq!(sink.peak(), 0.8);
    }

    #[test]
    fn a_deafened_sink_counts_nothing() {
        // The counters answer "what did the browsers get". A sink that dropped
        // the frame on the floor must not claim it forwarded one.
        let (tx, _rx) = broadcast::channel(4);
        let sink = WsAudioSink::new(tx, Arc::new(AtomicBool::new(true)));

        ts_protocol::AudioSink::push(&sink, &[0.5]);

        assert_eq!(sink.frames(), 0);
        assert_eq!(sink.peak(), 0.0);
    }
}
