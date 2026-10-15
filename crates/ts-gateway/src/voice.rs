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

use std::collections::{HashMap, VecDeque};
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

/// 浏览器与网关使用独立时钟，先缓冲 60 ms，再按顺序消费音频。
#[derive(Default)]
pub(crate) struct InputFrames {
    sources: HashMap<u64, InputQueue>,
    empty_ticks: usize,
}

#[derive(Default)]
struct InputQueue {
    frames: VecDeque<Vec<f32>>,
    started: bool,
    waiting_ticks: usize,
}

impl InputFrames {
    const PREFILL: usize = 3;
    const CAPACITY: usize = 10;

    pub(crate) fn push(&mut self, from: u64, frame: Vec<f32>) {
        let source = self.sources.entry(from).or_default();
        // 长时间阻塞后限制积压到 200 ms，避免把旧语音持续播放下去。
        if source.frames.len() == Self::CAPACITY {
            source.frames.pop_front();
        }
        source.frames.push_back(frame);
    }

    pub(crate) fn mix_next(&mut self, out: &mut [f32]) -> bool {
        let mut frames = Vec::with_capacity(self.sources.len());
        self.sources.retain(|_, source| {
            source.waiting_ticks = source.waiting_ticks.saturating_add(1);
            if source.frames.len() >= Self::PREFILL || source.waiting_ticks >= Self::PREFILL {
                source.started = true;
            }
            if source.started {
                if let Some(frame) = source.frames.pop_front() {
                    frames.push(frame);
                } else {
                    return false;
                }
            }
            true
        });
        let ready = mix(&frames, out);
        self.empty_ticks = if ready {
            0
        } else {
            self.empty_ticks.saturating_add(1)
        };
        ready
    }

    pub(crate) fn is_idle(&self) -> bool {
        self.empty_ticks >= Self::PREFILL
    }

    pub(crate) fn clear(&mut self) {
        self.sources.clear();
        self.empty_ticks = 0;
    }
}

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
    send_buffer: ts_audio::send_buffer::VoiceSendBuffer,
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
            // The same boosted baseline as the desktop; the worker applies
            // the user's relative gain immediately after construction.
            input_gain: ts_audio::microphone_gain(0.0),
            send_buffer: ts_audio::send_buffer::VoiceSendBuffer::default(),
            last_level: 0.0,
            last_peak: 0.0,
            last_transmitting: false,
        })
    }

    /// Missing browser frames must clear speech rather than retain the last word.
    pub(crate) fn mark_idle(&mut self) {
        self.policy.reset();
        self.send_buffer.reset();
        self.last_transmitting = false;
        self.last_level = 0.0;
        self.last_peak = 0.0;
    }

    /// 门控并编码一帧；激活时可能先返回按时间排序的字头缓冲。
    ///
    /// Takes the frame mutably because the microphone gain is applied to it —
    /// after the gate, never before, so the level the sensitivity threshold is
    /// compared against stays the browser's own. See the desktop's
    /// `VoiceEngine::poll` for the same argument.
    pub(crate) fn encode_frame(
        &mut self,
        mixed: &mut [f32],
    ) -> Result<Vec<VoicePacket>, AudioError> {
        // The order matters and mirrors `VoiceEngine::measure`: the level is
        // recorded *before* the policy runs, or the meter lies in the modes
        // that keep the gate shut.
        self.last_level = rms(mixed);
        self.last_peak = ts_audio::peak(mixed);
        let transmitting = self.policy.should_transmit_frame(mixed, FRAME_MS);
        self.last_transmitting = transmitting;
        let frames = self.send_buffer.prepare(
            mixed.to_vec(),
            &self.policy,
            ts_audio::VOICE_CHANNELS,
            self.input_gain,
        );
        frames
            .into_iter()
            .enumerate()
            .map(|(index, frame)| {
                let mut packet = self.encoder.encode(&frame)?;
                packet.is_dtx_resume = self.policy.is_resume() && index == 0;
                Ok(packet)
            })
            .collect()
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
        self.input_gain = ts_audio::microphone_gain(db);
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
    fn activation_encodes_preroll_with_one_resume_and_contiguous_sequences() {
        let mut voice = RemoteVoice::new(
            SessionId::new(1),
            VoiceActivationMode::VoiceActivation,
            VoiceActivationSettings {
                algorithm: ts_model::VadAlgorithm::Level,
                sensitivity: 0.1,
                attack_ms: 60,
                ..VoiceActivationSettings::default()
            },
        )
        .unwrap();
        for _ in 0..2 {
            assert!(
                voice
                    .encode_frame(&mut vec![0.12; FRAME_SAMPLES])
                    .unwrap()
                    .is_empty()
            );
        }
        let packets = voice.encode_frame(&mut vec![0.12; FRAME_SAMPLES]).unwrap();
        assert_eq!(packets.len(), 3);
        for (index, packet) in packets.iter().enumerate() {
            assert_eq!(packet.sequence as usize, index);
            assert_eq!(packet.is_dtx_resume, index == 0);
            assert!(!packet.payload.is_empty());
        }
        voice.set_input_muted(true);
        assert!(
            voice
                .encode_frame(&mut vec![0.8; FRAME_SAMPLES])
                .unwrap()
                .is_empty()
        );
        voice.set_input_muted(false);
        voice.set_mode(VoiceActivationMode::Continuous);
        let packets = voice.encode_frame(&mut vec![0.12; FRAME_SAMPLES]).unwrap();
        assert_eq!(packets.len(), 1);
        assert!(packets[0].is_dtx_resume);
    }

    #[test]
    fn browser_bursts_keep_every_frame_in_order() {
        let mut input = InputFrames::default();
        let mut out = vec![0.0; FRAME_SAMPLES];
        // 模拟每 40 ms 成批到达两帧，消费端仍每 20 ms 得到一帧。
        input.push(1, vec![0.01; FRAME_SAMPLES]);
        assert!(!input.mix_next(&mut out));
        for tick in 0..40 {
            if tick % 2 == 0 {
                for index in tick + 2..=tick + 3 {
                    input.push(1, vec![index as f32 / 100.0; FRAME_SAMPLES]);
                }
            }
            assert!(input.mix_next(&mut out), "missing frame at {tick}");
            assert!((out[0] - (tick + 1) as f32 / 100.0).abs() < 0.00001);
            assert!(!input.is_idle());
        }
    }

    #[test]
    fn short_capture_drains_and_stopping_becomes_idle() {
        let mut input = InputFrames::default();
        let mut out = vec![0.0; FRAME_SAMPLES];
        input.push(1, vec![0.25; FRAME_SAMPLES]);
        assert!(!input.mix_next(&mut out));
        assert!(!input.mix_next(&mut out));
        assert!(input.mix_next(&mut out));
        assert_eq!(out[0], 0.25);
        for _ in 0..2 {
            assert!(!input.mix_next(&mut out));
            assert!(!input.is_idle());
        }
        assert!(!input.mix_next(&mut out));
        assert!(input.is_idle());
    }

    #[test]
    fn browser_backlog_is_bounded_and_sources_mix_independently() {
        let mut input = InputFrames::default();
        let mut out = vec![0.0; FRAME_SAMPLES];
        for index in 0..20 {
            input.push(1, vec![index as f32 / 100.0; FRAME_SAMPLES]);
        }
        for _ in 0..3 {
            input.push(2, vec![0.5; FRAME_SAMPLES]);
        }
        assert!(input.mix_next(&mut out));
        assert!((out[0] - 0.3).abs() < 0.00001);
        for _ in 0..9 {
            assert!(input.mix_next(&mut out));
        }
        assert!(!input.mix_next(&mut out));
        input.push(1, vec![0.75; FRAME_SAMPLES]);
        input.clear();
        for _ in 0..3 {
            assert!(!input.mix_next(&mut out));
        }
        assert!(input.is_idle());
    }

    #[test]
    fn disabled_detection_encodes_silent_browser_frames() {
        let mut voice = RemoteVoice::new(
            SessionId::new(1),
            VoiceActivationMode::VoiceActivation,
            VoiceActivationSettings {
                algorithm: ts_model::VadAlgorithm::Disabled,
                ..VoiceActivationSettings::default()
            },
        )
        .expect("encoder");
        for _ in 0..30 {
            assert!(
                voice
                    .encode_frame(&mut vec![0.0; FRAME_SAMPLES])
                    .expect("frame")
                    .len()
                    == 1
            );
        }
        assert!(voice.levels().2);
    }

    #[test]
    fn missing_browser_frames_clear_local_speech() {
        // Regression: stopping browser capture retained the last speaking frame.
        let mut voice = RemoteVoice::new(
            SessionId::new(1),
            VoiceActivationMode::Continuous,
            VoiceActivationSettings::default(),
        )
        .expect("encoder");
        voice
            .encode_frame(&mut vec![0.25; FRAME_SAMPLES])
            .expect("frame");
        assert!(voice.levels().2);
        voice.mark_idle();
        assert_eq!(voice.levels(), (0.0, 0.0, false));
    }

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
