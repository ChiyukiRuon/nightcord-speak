//! The voice engine: capture to packets, packets to speakers (§25, §29, §30).
//!
//! ```text
//! capture ─▶ gate/ptt ─▶ encode ─▶ VoicePacket ─▶ (backend sends)
//!
//! play(mixed) ◀── (backend decoded) ◀── UDP
//! ```
//!
//! The engine owns the devices and the codec; the protocol backend owns the
//! network and the receive-side jitter/decode. The two meet at
//! [`VoiceEngine::poll`] and [`VoiceEngine::play`], which keeps this crate free
//! of any protocol dependency.
//!
//! Whether a frame is transmitted at all is
//! [`TransmitPolicy`]'s decision, deliberately separated from the device
//! plumbing so it can be tested without a microphone.

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use ts_model::{AudioError, VoiceActivationMode, VoiceActivationSettings, VoiceState};
use ts_protocol::{AudioSink, VoicePacket};

use crate::capture::Capture;
use crate::encoder::OpusEncoder;
use crate::format::{FRAME_MS, FRAME_SAMPLES, PLAYBACK_CHANNELS, PLAYBACK_SAMPLES, is_full_frame};
use crate::playback::Playback;
use crate::vad::{VoiceGate, peak, rms};

/// Digital silence, as a decibel figure rather than a limit to approach.
///
/// `apply_gain` turns it into an amplitude of 1e-10, which encodes to silence
/// and is exactly what a user dragging a gain slider to the bottom asked for.
/// The number is the front-end's too: it is the bottom of the travel, not a
/// value the audio layer picks.
pub const SILENCE_DB: f32 = -200.0;

/// The loudest the microphone may be pushed, in decibels.
///
/// Above unity because a quiet microphone is the reason the control exists.
/// +10 dB is a gain of about 3.2, which will clip anything already loud — a
/// consequence of turning a microphone up, not a bug.
pub const MAX_GAIN_DB: f32 = 10.0;

/// The quietest gain that is still audible, in decibels.
///
/// Below this a signal is inaudible on any normal equipment, so the front-end's
/// slider spends its travel on the range that does something and treats
/// everything below as the silence position. The audio layer does not use it;
/// it is here so both the desktop and the web draw the same curve.
pub const MIN_AUDIBLE_DB: f32 = -60.0;

/// Converts a decibel figure into the linear gain the pipeline multiplies by.
///
/// Non-finite input is read as silence rather than propagated: `NaN` samples
/// reaching the encoder would corrupt the stream, and there is no reading of
/// "not a number decibels" that a user could have meant.
#[must_use]
pub fn gain_from_db(db: f32) -> f32 {
    if !db.is_finite() {
        return 0.0;
    }
    10f32.powf(db / 20.0)
}

/// Scales a frame in place, clipping rather than wrapping.
///
/// Unity returns untouched — the default setting spends no work and leaves the
/// samples bit-for-bit as the microphone produced them. The clamp is what makes
/// a large positive gain sound loud instead of producing infinities the encoder
/// would have to guess at.
pub fn apply_gain(frame: &mut [f32], gain: f32) {
    if gain == 1.0 {
        return;
    }
    for sample in frame {
        *sample = (*sample * gain).clamp(-1.0, 1.0);
    }
}

/// Decides whether a captured frame should be sent.
///
/// Holds all the state that makes that decision, and nothing else — no devices,
/// no codec — so every mode combination can be exercised directly.
#[derive(Debug, Clone)]
pub struct TransmitPolicy {
    gate: VoiceGate,
    mode: VoiceActivationMode,
    input_muted: bool,
    /// Whether the speakers are muted — deafened.
    ///
    /// Deafening closes the transmit gate too, because the server refuses voice
    /// from a deafened client: `can_send_audio` is false while
    /// `client_output_muted` is set, so every frame sent through that window
    /// came back as `VoiceError::NotConnected` — an error the user could do
    /// nothing about, caused by a button they had just pressed on purpose.
    /// TeamSpeak's own deafen stops the microphone as well.
    output_muted: bool,
    /// Whether we have marked ourselves away.
    ///
    /// Away closes the gate for exactly the reason deafening does — the same
    /// field of the library's `can_send_audio` is false while
    /// `client_away_message` is set, and every frame sent through that window
    /// came back as `VoiceError::NotConnected`. Being away means being
    /// elsewhere; the microphone stopping is the honest reading of that, and
    /// the alternative was an error dialog per brush of the microphone.
    away: bool,
    /// Whether the push-to-talk key is currently held.
    ptt_held: bool,
    /// Whether the previous frame was transmitted.
    transmitted_last: bool,
    /// Whether the *current* frame resumes after silence — sent when the
    /// previous one was not.
    resume: bool,
}

impl TransmitPolicy {
    /// A policy starting in `mode`, not muted, with the key released.
    #[must_use]
    pub fn new(mode: VoiceActivationMode, settings: VoiceActivationSettings) -> Self {
        Self {
            gate: VoiceGate::new(settings),
            mode,
            input_muted: false,
            output_muted: false,
            away: false,
            ptt_held: false,
            transmitted_last: false,
            resume: false,
        }
    }

    /// Whether the next frame of `level` should be transmitted.
    ///
    /// Advances the gate, so this must be called exactly once per frame.
    pub fn should_transmit(&mut self, level: f32, frame_ms: u32) -> bool {
        let previous = self.transmitted_last;

        let wants = if self.input_muted || self.output_muted || self.away {
            false
        } else {
            match self.mode {
                // Defer to the gate, which is what applies the threshold and
                // the attack/release timing.
                VoiceActivationMode::VoiceActivation => self.gate.update(level, frame_ms),
                // Both of these bypass the gate entirely, so the gate is reset
                // to avoid it reopening stale when the mode changes back.
                VoiceActivationMode::PushToTalk => {
                    self.gate.reset();
                    self.ptt_held
                }
                VoiceActivationMode::Continuous => {
                    self.gate.reset();
                    true
                }
                VoiceActivationMode::Muted => {
                    self.gate.reset();
                    false
                }
            }
        };

        self.resume = wants && !previous;
        self.transmitted_last = wants;
        wants
    }

    /// Whether the last frame was transmitted.
    #[must_use]
    pub const fn transmitted_last(&self) -> bool {
        self.transmitted_last
    }

    /// Whether the frame just decided on resumes after silence.
    ///
    /// True only for the first frame sent after a gap, which is what lets the
    /// far end tell "they started talking again" from "packets were lost".
    #[must_use]
    pub const fn is_resume(&self) -> bool {
        self.resume
    }

    /// The current mode.
    #[must_use]
    pub const fn mode(&self) -> VoiceActivationMode {
        self.mode
    }

    /// Switches mode.
    pub fn set_mode(&mut self, mode: VoiceActivationMode) {
        if self.mode != mode {
            // The gate's timings belong to the old mode.
            self.gate.reset();
            self.mode = mode;
        }
    }

    /// Mutes or unmutes the microphone.
    pub fn set_input_muted(&mut self, muted: bool) {
        if self.input_muted != muted {
            self.gate.reset();
            self.input_muted = muted;
        }
    }

    /// Deafens or undeafens, which closes the transmit gate with the speakers.
    ///
    /// Deafening closes the transmit gate with it: see the note on
    /// `TransmitPolicy::output_muted` for why the two travel together.
    pub fn set_output_muted(&mut self, muted: bool) {
        if self.output_muted != muted {
            self.gate.reset();
            self.output_muted = muted;
        }
    }

    /// Whether the microphone is muted.
    #[must_use]
    pub const fn input_muted(&self) -> bool {
        self.input_muted
    }

    /// Marks us away or back, which closes the transmit gate with it.
    ///
    /// See the note on `TransmitPolicy::away` for why away stops the
    /// microphone.
    pub fn set_away(&mut self, away: bool) {
        if self.away != away {
            self.gate.reset();
            self.away = away;
        }
    }

    /// Whether we are marked away.
    #[must_use]
    pub const fn away(&self) -> bool {
        self.away
    }

    /// Records the push-to-talk key going down or up.
    pub fn set_push_to_talk(&mut self, held: bool) {
        self.ptt_held = held;
    }

    /// Whether the push-to-talk key is held.
    #[must_use]
    pub const fn ptt_held(&self) -> bool {
        self.ptt_held
    }

    /// Retunes the voice-activation gate.
    pub fn set_settings(&mut self, settings: VoiceActivationSettings) {
        self.gate.set_settings(settings);
    }

    /// Whether the gate is open, for a speaking indicator.
    #[must_use]
    pub const fn gate_open(&self) -> bool {
        self.gate.is_open()
    }

    /// Forgets all timing, as after a reconnect.
    pub fn reset(&mut self) {
        self.gate.reset();
        self.transmitted_last = false;
        self.resume = false;
    }
}

/// Owns the devices and turns captured audio into packets.
///
/// Devices are opened lazily: a user may want to connect and read chat without
/// granting microphone access, and a machine may have no speakers at all. Both
/// halves are optional and the engine works with either missing — it simply
/// cannot transmit, or cannot be heard.
pub struct VoiceEngine {
    capture: Option<Capture>,
    /// Shared because a backend holds an [`AudioSink`] over the same device and
    /// writes into it from its own task.
    playback: Option<Arc<Playback>>,
    encoder: OpusEncoder,
    policy: TransmitPolicy,
    /// Shared for the same reason: the sink reads it on every frame.
    output_muted: Arc<AtomicBool>,
    /// Playback gain, remembered so a device switch does not reset it.
    output_volume: f32,
    /// Microphone gain, as a linear factor — the decibels the user chose,
    /// converted once on the way in.
    ///
    /// A plain field rather than the atomic `output_volume` needs: this one is
    /// applied while frames are encoded, on the worker task, never inside a
    /// device callback.
    input_gain: f32,
    /// Scratch for rendering one frame to stereo before queueing it.
    frame_stereo: Vec<f32>,
    /// Scratch for downmixing a captured stereo frame, for the gate and the
    /// meters. The encoder is fed the stereo frame itself.
    frame_mono: Vec<f32>,
    /// The most recent frame's loudness, for a level meter.
    ///
    /// Stored on *every* frame, before the transmission policy is consulted —
    /// push-to-talk, continuous and muted all bypass the gate, and a meter that
    /// only moved in voice-activation mode would look broken in the three modes
    /// people actually use to test a microphone.
    last_level: f32,
    /// The most recent frame's peak, for a clipping indicator.
    last_peak: f32,
    /// What each side actually opened, when it did.
    input_device: Option<OpenDevice>,
    output_device: Option<OpenDevice>,
}

/// A device that was successfully opened, and whether it is the one that was
/// asked for.
///
/// The distinction matters: `resolve` falls back to the system default when a
/// saved device is gone, and a user who thinks they are on a headset while the
/// laptop's built-in microphone is live has no way to find out otherwise.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OpenDevice {
    /// The id that was actually opened.
    pub id: String,
    /// Its name, as the host reports it.
    pub name: String,
    /// Whether the configured device could not be found and this is the
    /// fallback.
    pub fell_back: bool,
}

/// The pitch of the speaker test. Concert A — the note every reference tone
/// uses, and the one a person is most likely to recognise as "a sound" rather
/// than as a fault.
const TEST_TONE_HZ: f32 = 440.0;

/// How long the stream outlives the queued tone before the device is released.
///
/// The tone plays out of the device's own buffer, so the stream cannot be
/// dropped the moment the samples are written. A little slack beyond the
/// tone's own length costs nothing and covers whatever the device still had
/// queued when the tone went in.
const TEST_TONE_TAIL: std::time::Duration = std::time::Duration::from_millis(250);

/// Plays the test tone through `output`, with no engine and no microphone.
///
/// The engine owns the playback stream, so a tone needs one either way — but
/// nothing else: no capture device, no session, no sink. The speaker check used
/// to require a running engine, and starting an engine opens a microphone, so
/// "can I hear anything" could not be asked without also grabbing the mic.
///
/// The stream is kept alive for exactly as long as the tone needs and then
/// dropped, which is what releases the device again.
///
/// `volume` is the user's playback gain, so the tone arrives at the level they
/// would hear anything else at — a check that answers "can I hear anything"
/// while playing at a different volume from the call answers the wrong
/// question.
///
/// # Errors
///
/// Whatever opening the output device returns; see [`Playback::open`].
pub fn play_test_tone(output: Option<&str>, volume: f32) -> Result<(), AudioError> {
    let playback = Playback::open_with_volume(output, volume)?;

    let mut phase = 0.0;
    // The same length and amplitude as the engine's own test tone, so the two
    // paths are indistinguishable to the person listening — the point of the
    // check is the answer, not which code produced it.
    let mono = crate::tone::sine(
        TEST_TONE_HZ,
        0.2,
        crate::format::FRAME_SAMPLES * 16,
        &mut phase,
    );
    let queued = playback.write(&crate::tone::to_stereo(&mono));

    let seconds =
        queued as f32 / (crate::SAMPLE_RATE as f32 * crate::format::PLAYBACK_CHANNELS as f32);
    let lifetime = std::time::Duration::from_secs_f32(seconds) + TEST_TONE_TAIL;
    std::thread::spawn(move || {
        std::thread::sleep(lifetime);
        drop(playback);
    });

    Ok(())
}

/// Routes a backend's decoded audio into the engine's speakers.
///
/// A separate type rather than an implementation of [`AudioSink`] on
/// `VoiceEngine` itself, because the backend holds this across await points
/// while the engine stays owned by the caller.
struct PlaybackSink {
    playback: Arc<Playback>,
    muted: Arc<AtomicBool>,
}

impl AudioSink for PlaybackSink {
    fn push(&self, interleaved: &[f32]) {
        if self.muted.load(Ordering::Relaxed) {
            // Discard rather than queue, so unmuting does not replay a backlog.
            return;
        }
        let written = self.playback.write(interleaved);
        if written < interleaved.len() {
            tracing::debug!(
                dropped = interleaved.len() - written,
                "playback queue is full; dropped audio"
            );
        }
    }

    fn space(&self) -> usize {
        if self.muted.load(Ordering::Relaxed) {
            // Report unlimited room while muted: the backend keeps decoding and
            // we throw it away, which keeps its jitter buffer draining. Saying
            // "no room" would let a backlog build that plays on unmute.
            usize::MAX
        } else {
            self.playback.space()
        }
    }
}

impl From<&crate::device::Resolved> for OpenDevice {
    fn from(resolved: &crate::device::Resolved) -> Self {
        Self {
            id: resolved.id.clone(),
            name: resolved.name.clone(),
            fell_back: resolved.fell_back,
        }
    }
}

impl VoiceEngine {
    /// The loudness of the most recent captured frame, `0.0..=1.0`.
    ///
    /// Zero until a frame arrives, and zero forever without a microphone. This
    /// is what a level meter draws, and why it is worth having: picking a
    /// device from a list tells you nothing about whether it is picking up
    /// sound.
    #[must_use]
    pub fn input_level(&self) -> f32 {
        self.last_level
    }

    /// The peak sample of the most recent captured frame.
    ///
    /// Above 1.0 means the input is clipping, which no amount of gain staging
    /// downstream can undo.
    #[must_use]
    pub fn input_peak(&self) -> f32 {
        self.last_peak
    }

    /// The microphone actually open, and whether it is the one that was asked
    /// for.
    #[must_use]
    pub fn input_device(&self) -> Option<&OpenDevice> {
        self.input_device.as_ref()
    }

    /// The speakers actually open. See [`VoiceEngine::input_device`].
    #[must_use]
    pub fn output_device(&self) -> Option<&OpenDevice> {
        self.output_device.as_ref()
    }

    /// Builds an engine with no devices open.
    ///
    /// `output_volume` comes from the user's settings; the engine deliberately
    /// does not read that store itself, so `ts-audio` keeps depending on
    /// nothing but `ts-model`.
    ///
    /// The encoder is always the stereo profile at its top bitrate: capture is
    /// stereo whatever the device offers, so there is nothing here to choose.
    ///
    /// # Errors
    ///
    /// Returns [`AudioError::Backend`] if libopus refuses to initialise, which
    /// means voice cannot work at all.
    pub fn new(settings: VoiceActivationSettings, output_volume: f32) -> Result<Self, AudioError> {
        Ok(Self {
            capture: None,
            playback: None,
            encoder: OpusEncoder::new(PLAYBACK_CHANNELS)?,
            policy: TransmitPolicy::new(VoiceActivationMode::default(), settings),
            output_muted: Arc::new(AtomicBool::new(false)),
            output_volume: clamp_volume(output_volume),
            // Unity until told otherwise, which is what every build before the
            // gain existed did.
            input_gain: 1.0,
            frame_stereo: vec![0.0; PLAYBACK_SAMPLES],
            frame_mono: vec![0.0; FRAME_SAMPLES],
            last_level: 0.0,
            last_peak: 0.0,
            input_device: None,
            output_device: None,
        })
    }

    /// The bitrate the encoder is running at, for `voice_status`.
    #[must_use]
    pub const fn bitrate(&self) -> i32 {
        self.encoder.bitrate()
    }

    /// The codec byte this engine's packets carry, for `voice_status`.
    ///
    /// Always the stereo profile: capture is stereo and the encoder is built to
    /// match it.
    #[must_use]
    pub const fn packet_codec(&self) -> ts_protocol::Codec {
        self.encoder.packet_codec()
    }

    /// The playback gain in force.
    #[must_use]
    pub const fn output_volume(&self) -> f32 {
        self.output_volume
    }

    /// The microphone gain in force, in decibels.
    #[must_use]
    pub fn input_gain_db(&self) -> f32 {
        if self.input_gain <= 0.0 {
            return SILENCE_DB;
        }
        20.0 * self.input_gain.log10()
    }

    /// Sets the microphone gain, in decibels: how loud everyone else hears us.
    ///
    /// Applied where frames are encoded, so the gate and the level meter keep
    /// reading the microphone itself. A gain that moved the level the
    /// sensitivity threshold is compared against would make one slider silently
    /// retune the other.
    pub fn set_input_gain_db(&mut self, db: f32) {
        self.input_gain = gain_from_db(clamp_gain_db(db));
    }

    /// Sets the playback gain, `0.0..=1.0`.
    ///
    /// Heard on the next device callback. Stored as well as forwarded, so that
    /// replacing the output device — which builds a new stream — comes back at
    /// the level the user chose rather than at unity.
    pub fn set_output_volume(&mut self, volume: f32) {
        self.output_volume = clamp_volume(volume);
        if let Some(playback) = &self.playback {
            playback.set_volume(self.output_volume);
        }
    }

    /// Opens a microphone and speakers.
    ///
    /// A device that cannot be opened is reported but does not fail the other
    /// one: a user with no working microphone can still listen.
    ///
    /// # Errors
    ///
    /// Returns an error only when *both* sides fail; a single failure is
    /// logged and left for [`VoiceEngine::input_available`] to report.
    pub fn open_devices(
        &mut self,
        input: Option<&str>,
        output: Option<&str>,
    ) -> Result<(), AudioError> {
        let input_failed = match Capture::open(input) {
            Ok(capture) => {
                self.input_device = Some(OpenDevice::from(capture.device()));
                self.capture = Some(capture);
                false
            }
            Err(error) => {
                tracing::warn!(%error, "could not open a microphone; voice input is unavailable");
                true
            }
        };

        match Playback::open_with_volume(output, self.output_volume) {
            Ok(playback) => {
                self.output_device = Some(OpenDevice::from(playback.device()));
                self.playback = Some(Arc::new(playback));
            }
            Err(error) => {
                tracing::warn!(%error, "could not open speakers; voice output is unavailable");
                if input_failed {
                    // Both halves are gone, so there is nothing voice can do —
                    // worth reporting rather than connecting into silence.
                    return Err(error);
                }
            }
        }

        Ok(())
    }

    /// Closes both devices.
    pub fn close_devices(&mut self) {
        self.capture = None;
        self.playback = None;
    }

    /// Whether a microphone is open.
    #[must_use]
    pub const fn input_available(&self) -> bool {
        self.capture.is_some()
    }

    /// Whether speakers are open.
    #[must_use]
    pub const fn output_available(&self) -> bool {
        self.playback.is_some()
    }

    /// Whether both device streams are still healthy.
    ///
    /// Goes false when a device is unplugged, which the UI should surface.
    #[must_use]
    pub fn devices_healthy(&self) -> bool {
        self.capture
            .as_ref()
            .is_none_or(|capture| capture.is_running())
            && self
                .playback
                .as_ref()
                .is_none_or(|playback| playback.is_running())
    }

    /// The engine's current voice state, for the UI and for events.
    #[must_use]
    pub fn state(&self) -> VoiceState {
        VoiceState {
            mode: self.policy.mode(),
            input_muted: self.policy.input_muted(),
            output_muted: self.output_muted(),
            transmitting: self.policy.transmitted_last(),
        }
    }

    /// Switches how transmission is triggered.
    pub fn set_mode(&mut self, mode: VoiceActivationMode) {
        self.policy.set_mode(mode);
    }

    /// Mutes or unmutes the microphone.
    pub fn set_input_muted(&mut self, muted: bool) {
        self.policy.set_input_muted(muted);
    }

    /// Mutes or unmutes the speakers.
    ///
    /// Takes effect immediately for audio already in flight, because the sink
    /// reads the same switch.
    pub fn set_output_muted(&mut self, muted: bool) {
        self.output_muted.store(muted, Ordering::Relaxed);
        self.policy.set_output_muted(muted);
    }

    /// Whether the speakers are muted.
    #[must_use]
    pub fn output_muted(&self) -> bool {
        self.output_muted.load(Ordering::Relaxed)
    }

    /// Marks us away or back.
    ///
    /// Applied to transmission only: the server is told separately, by the
    /// session, and the speakers keep playing — an away client still hears the
    /// room it walked out of.
    pub fn set_away(&mut self, away: bool) {
        self.policy.set_away(away);
    }

    /// Whether we are marked away.
    #[must_use]
    pub fn away(&self) -> bool {
        self.policy.away()
    }

    /// Records the push-to-talk key going down or up (§30).
    pub fn set_push_to_talk(&mut self, held: bool) {
        self.policy.set_push_to_talk(held);
    }

    /// Retunes voice activation.
    pub fn set_settings(&mut self, settings: VoiceActivationSettings) {
        self.policy.set_settings(settings);
    }

    /// Replaces the capture device, keeping playback as it is.
    ///
    /// # Errors
    ///
    /// Returns the device error, leaving the previous device in place.
    pub fn set_input_device(&mut self, id: Option<&str>) -> Result<(), AudioError> {
        let capture = Capture::open(id)?;
        self.capture = Some(capture);
        Ok(())
    }

    /// Replaces the playback device, keeping capture as it is.
    ///
    /// Queued audio is discarded, since it belongs to the old device.
    ///
    /// # Errors
    ///
    /// Returns the device error, leaving the previous device in place.
    pub fn set_output_device(&mut self, id: Option<&str>) -> Result<(), AudioError> {
        let playback = Playback::open_with_volume(id, self.output_volume)?;
        self.playback = Some(Arc::new(playback));
        Ok(())
    }

    /// A sink that routes a backend's decoded audio into this engine's speakers.
    ///
    /// `None` when no output device is open, in which case the backend simply
    /// discards incoming audio — which is what a user with no working speakers
    /// wants, rather than an error.
    ///
    /// The returned sink shares the mute switch, so muting takes effect on the
    /// very next frame without the backend being told.
    #[must_use]
    pub fn sink(&self) -> Option<Arc<dyn AudioSink>> {
        self.playback.as_ref().map(|playback| {
            Arc::new(PlaybackSink {
                playback: Arc::clone(playback),
                muted: Arc::clone(&self.output_muted),
            }) as Arc<dyn AudioSink>
        })
    }

    /// Drains captured audio and returns the frames that should be sent.
    ///
    /// Returns an empty vector when muted, when the gate is shut, or when no
    /// microphone is open. An error means a frame failed to encode — the
    /// remaining frames are still returned, because losing one frame is better
    /// than losing the sentence.
    ///
    /// # Errors
    ///
    /// Returns [`AudioError::Backend`] if libopus fails on a frame.
    pub fn poll(&mut self) -> Result<Vec<VoicePacket>, AudioError> {
        let Some(capture) = &self.capture else {
            return Ok(Vec::new());
        };

        // Drained before anything is done with them: `measure` needs the engine
        // mutably, and the capture holds it borrowed for as long as it is
        // looked at. The channel only ever holds whole frames (the assembler
        // emits nothing else), so collecting first changes nothing else.
        let mut frames = Vec::new();
        while let Some(frame) = capture.try_recv() {
            frames.push(frame);
        }

        let mut packets = Vec::new();
        let mut first_error = None;

        for mut frame in frames {
            if !is_full_frame(frame.len(), PLAYBACK_CHANNELS) {
                // The assembler only emits whole frames, so this cannot happen
                // — but sending a short frame would corrupt the stream, so it
                // is dropped rather than trusted.
                tracing::warn!(
                    samples = frame.len(),
                    "dropping a capture frame that is not one whole frame"
                );
                continue;
            }

            // Moved out of `self` for the length of the iteration rather than
            // borrowed: `measure` needs the engine mutably, and the buffer it
            // would be borrowing is engine state. `mem::take` moves the
            // allocation rather than copying samples, and it goes back below.
            let mut mono = std::mem::take(&mut self.frame_mono);

            // The gate and the meters read a downmix, never the interleaved
            // frame. Not for quality — the encoder is handed the whole stereo
            // frame — but because an RMS over interleaved samples of a
            // hard-panned signal is as loud as one over a centred signal of
            // twice the amplitude, and the sensitivity slider would then mean
            // different things for different material.
            downmix(&frame, &mut mono);

            if self.measure(&mono) {
                // After the gate, never before: the gain is what other people
                // hear, and the levels above are what the sensitivity slider is
                // compared against. Applying it earlier would make turning the
                // gain down close the gate — one control silently moving the
                // other's threshold.
                apply_gain(&mut frame, self.input_gain);

                match self.encoder.encode(&frame) {
                    Ok(mut packet) => {
                        packet.is_dtx_resume = self.policy.is_resume();
                        packets.push(packet);
                    }
                    Err(error) => {
                        tracing::warn!(%error, "could not encode a voice frame");
                        first_error.get_or_insert(error);
                    }
                }
            }

            self.frame_mono = mono;
        }

        match first_error {
            Some(error) => Err(error),
            None => Ok(packets),
        }
    }

    /// Records what a meter should show, then asks whether to transmit.
    ///
    /// Split out so the ordering can be tested without a microphone: the level
    /// must be recorded *before* the policy runs, because push-to-talk,
    /// continuous and muted all short-circuit the gate — and those are exactly
    /// the modes someone uses while testing whether their microphone works.
    fn measure(&mut self, frame: &[f32]) -> bool {
        let level = rms(frame);
        self.last_level = level;
        self.last_peak = peak(frame);
        self.policy.should_transmit(level, FRAME_MS)
    }

    /// Queues decoded, mixed stereo audio for playback.
    ///
    /// `interleaved` is what the protocol backend's mixer produced. A muted
    /// output drops the audio rather than queueing it, so unmuting does not
    /// replay a backlog.
    pub fn play(&mut self, interleaved: &[f32]) {
        if let Some(sink) = self.sink() {
            sink.push(interleaved);
        }
    }

    /// Plays a short tone through the speakers.
    ///
    /// For "can I hear anything at all" — the question a device list cannot
    /// answer, and the reason a user opens the settings screen in the first
    /// place. Straight to playback, so it is heard and never transmitted.
    ///
    /// Quiet on purpose: the tone is generated at a low amplitude, and a test
    /// tone that startles someone tells them nothing that turning it down would
    /// not. It still rides the user's playback gain, so what they hear is the
    /// level the call will be at.
    pub fn play_test_tone(&mut self) {
        let mut phase = 0.0;
        // A third of a second: long enough to recognise as a tone rather than
        // as a click, short enough not to be in the way.
        let samples = crate::format::FRAME_SAMPLES * 16;
        let mono = crate::tone::sine(TEST_TONE_HZ, 0.2, samples, &mut phase);
        self.play(&crate::tone::to_stereo(&mono));
    }

    /// Queues a frame of silence, so playback keeps up when nobody is talking.
    ///
    /// Lets the device buffer drain naturally instead of underrunning once a
    /// burst ends.
    pub fn play_silence(&mut self) {
        if self.output_muted() {
            return;
        }
        if let Some(playback) = &self.playback {
            self.frame_stereo.fill(0.0);
            playback.write(&self.frame_stereo);
        }
    }

    /// How many samples are queued for playback.
    #[must_use]
    pub fn buffered_samples(&self) -> usize {
        self.playback
            .as_ref()
            .map_or(0, |playback| playback.buffered())
    }

    /// Forgets encoder and gate state, as after a reconnect.
    ///
    /// The encoder profile and the output volume survive: a reconnect is not a
    /// reason to forget what the user chose.
    pub fn reset(&mut self) {
        self.encoder.reset();
        self.policy.reset();
    }

    /// The encoder's next sequence number, for diagnostics.
    #[must_use]
    pub fn sequence(&self) -> u16 {
        self.encoder.sequence()
    }
}

/// Averages an interleaved stereo frame into `out`, which must be half its
/// length.
///
/// Averaging rather than summing, so a signal already present on both channels
/// keeps its level instead of clipping — the same rule capture used to apply to
/// the device's own channels before it started emitting stereo.
///
/// A short `out` is filled as far as it goes rather than panicking: this runs on
/// the path a microphone feeds, and silence from a wrong-sized buffer beats a
/// crashed audio thread.
fn downmix(interleaved: &[f32], out: &mut [f32]) {
    for (index, slot) in out.iter_mut().enumerate() {
        let left = interleaved.get(index * 2).copied().unwrap_or(0.0);
        let right = interleaved.get(index * 2 + 1).copied().unwrap_or(0.0);
        *slot = (left + right) * 0.5;
    }
}

/// Pulls a requested playback gain into the range [`Playback`] can use.
///
/// Mirrors `playback::clamp_gain`, which is private to that module; this copy
/// exists so the engine can remember a sane value before any device is open.
/// Non-finite values become unity rather than silence.
fn clamp_volume(volume: f32) -> f32 {
    if volume.is_finite() {
        volume.clamp(0.0, 1.0)
    } else {
        1.0
    }
}

/// Keeps a microphone gain inside the range the front-end offers.
///
/// Public because the gateway's voice path applies the same setting and must
/// clamp it the same way: two implementations of one range is how the two hosts
/// end up disagreeing about what "-300 dB" means.
///
/// Unlike [`clamp_volume`], non-finite input becomes silence rather than unity:
/// a gain nobody could express is not a reason to be suddenly loud.
#[must_use]
pub fn clamp_gain_db(db: f32) -> f32 {
    if db.is_finite() {
        db.clamp(SILENCE_DB, MAX_GAIN_DB)
    } else {
        SILENCE_DB
    }
}

impl std::fmt::Debug for VoiceEngine {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("VoiceEngine")
            .field("input", &self.input_available())
            .field("output", &self.output_available())
            .field("state", &self.state())
            .field("codec", &self.encoder.packet_codec())
            .field("bitrate", &self.encoder.bitrate())
            .field("volume", &self.output_volume)
            .finish_non_exhaustive()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn settings() -> VoiceActivationSettings {
        VoiceActivationSettings {
            sensitivity: 0.1,
            attack_ms: 40,
            release_ms: 100,
        }
    }

    fn policy(mode: VoiceActivationMode) -> TransmitPolicy {
        TransmitPolicy::new(mode, settings())
    }

    /// An engine on the default profile and at unity gain, which is what every
    /// test that is not about profiles or volume wants.
    fn engine_with(activation: VoiceActivationSettings) -> VoiceEngine {
        VoiceEngine::new(activation, 1.0).expect("build engine")
    }

    fn engine_with_defaults() -> VoiceEngine {
        engine_with(VoiceActivationSettings::default())
    }

    const LOUD: f32 = 0.5;
    const QUIET: f32 = 0.01;

    #[test]
    fn voice_activation_opens_after_the_attack() {
        let mut policy = policy(VoiceActivationMode::VoiceActivation);
        assert!(!policy.should_transmit(LOUD, FRAME_MS));
        assert!(policy.should_transmit(LOUD, FRAME_MS));
    }

    #[test]
    fn voice_activation_ignores_quiet_input() {
        let mut policy = policy(VoiceActivationMode::VoiceActivation);
        for _ in 0..50 {
            assert!(!policy.should_transmit(QUIET, FRAME_MS));
        }
    }

    #[test]
    fn push_to_talk_transmits_only_while_held() {
        let mut policy = policy(VoiceActivationMode::PushToTalk);
        assert!(!policy.should_transmit(LOUD, FRAME_MS), "key is up");

        policy.set_push_to_talk(true);
        assert!(
            policy.should_transmit(QUIET, FRAME_MS),
            "PTT transmits even when quiet"
        );

        policy.set_push_to_talk(false);
        assert!(!policy.should_transmit(LOUD, FRAME_MS), "key released");
    }

    #[test]
    fn continuous_transmits_regardless_of_level() {
        let mut policy = policy(VoiceActivationMode::Continuous);
        assert!(policy.should_transmit(0.0, FRAME_MS));
        assert!(policy.should_transmit(QUIET, FRAME_MS));
    }

    #[test]
    fn muted_never_transmits() {
        let mut policy = policy(VoiceActivationMode::Muted);
        policy.set_push_to_talk(true);
        for _ in 0..10 {
            assert!(!policy.should_transmit(LOUD, FRAME_MS));
        }
    }

    #[test]
    fn deafening_beats_every_mode() {
        // Regression: deafening muted the speakers and nothing else. The server
        // refuses voice from a deafened client — `can_send_audio` is false while
        // `client_output_muted` is set — so every frame encoded while deafened
        // came back refused, and the refusal reached the UI as "voice error: not
        // connected": an error nobody can act on, produced by a button they
        // pressed on purpose. TeamSpeak's own deafen stops the microphone too.
        for mode in [
            VoiceActivationMode::PushToTalk,
            VoiceActivationMode::Continuous,
            VoiceActivationMode::VoiceActivation,
        ] {
            let mut policy = policy(mode);
            policy.set_push_to_talk(true);

            // Drive the mode until it is actually transmitting: voice
            // activation needs its attack to elapse before the gate opens.
            let mut open = false;
            for _ in 0..40 {
                if policy.should_transmit(LOUD, FRAME_MS) {
                    open = true;
                    break;
                }
            }
            assert!(open, "{mode:?} never opened its gate");

            policy.set_output_muted(true);
            for _ in 0..40 {
                assert!(
                    !policy.should_transmit(LOUD, FRAME_MS),
                    "{mode:?} transmitted while deafened"
                );
            }

            // Undeafening restarts the gate like muting the microphone does, so
            // voice activation has to attack again before it transmits.
            policy.set_output_muted(false);
            let mut reopened = false;
            for _ in 0..40 {
                if policy.should_transmit(LOUD, FRAME_MS) {
                    reopened = true;
                    break;
                }
            }
            assert!(reopened, "{mode:?} stayed silent after undeafening");
        }
    }

    #[test]
    fn being_away_beats_every_mode() {
        // Regression, and the twin of the deafening test above: the away button
        // stopped nothing. The server refuses voice from an away client —
        // `can_send_audio` is false while `client_away_message` is set — so
        // every frame encoded while away came back refused, and the refusal
        // reached the UI as "voice error: not connected": an error about a
        // connection that is fine, produced by a button pressed on purpose, and
        // repeated every time the microphone was triggered.
        for mode in [
            VoiceActivationMode::PushToTalk,
            VoiceActivationMode::Continuous,
            VoiceActivationMode::VoiceActivation,
        ] {
            let mut policy = policy(mode);
            policy.set_push_to_talk(true);

            let mut open = false;
            for _ in 0..40 {
                if policy.should_transmit(LOUD, FRAME_MS) {
                    open = true;
                    break;
                }
            }
            assert!(open, "{mode:?} never opened its gate");

            policy.set_away(true);
            for _ in 0..40 {
                assert!(
                    !policy.should_transmit(LOUD, FRAME_MS),
                    "{mode:?} transmitted while away"
                );
            }

            // Coming back restarts the gate, exactly as unmuting does: the
            // first frame after a minute away should not be a burst of whatever
            // the room was doing.
            policy.set_away(false);
            let mut reopened = false;
            for _ in 0..40 {
                if policy.should_transmit(LOUD, FRAME_MS) {
                    reopened = true;
                    break;
                }
            }
            assert!(reopened, "{mode:?} stayed silent after coming back");
        }
    }

    #[test]
    fn input_mute_beats_every_mode() {
        for mode in [
            VoiceActivationMode::PushToTalk,
            VoiceActivationMode::Continuous,
            VoiceActivationMode::VoiceActivation,
        ] {
            let mut policy = policy(mode);
            policy.set_input_muted(true);
            policy.set_push_to_talk(true);

            assert!(
                !policy.should_transmit(LOUD, FRAME_MS),
                "{mode:?} transmitted while the microphone was muted"
            );
        }
    }

    #[test]
    fn unmuting_does_not_reopen_the_gate_immediately() {
        // The gate was reset on mute, so reopening pays the attack again —
        // otherwise the first frame after unmuting would be a burst of
        // whatever the room was doing.
        let mut policy = policy(VoiceActivationMode::VoiceActivation);
        policy.should_transmit(LOUD, FRAME_MS);
        assert!(policy.should_transmit(LOUD, FRAME_MS));

        policy.set_input_muted(true);
        assert!(!policy.should_transmit(LOUD, FRAME_MS));

        policy.set_input_muted(false);
        assert!(
            !policy.should_transmit(LOUD, FRAME_MS),
            "attack not yet elapsed"
        );
        assert!(policy.should_transmit(LOUD, FRAME_MS));
    }

    #[test]
    fn switching_mode_does_not_carry_gate_timing_over() {
        let mut policy = policy(VoiceActivationMode::VoiceActivation);
        policy.should_transmit(LOUD, FRAME_MS);
        assert!(policy.should_transmit(LOUD, FRAME_MS), "gate is open");

        // A gate left open would make push-to-talk transmit with the key up.
        policy.set_mode(VoiceActivationMode::PushToTalk);
        assert!(!policy.should_transmit(LOUD, FRAME_MS));
    }

    #[test]
    fn switching_back_to_voice_activation_pays_the_attack_again() {
        let mut policy = policy(VoiceActivationMode::VoiceActivation);
        policy.should_transmit(LOUD, FRAME_MS);
        policy.should_transmit(LOUD, FRAME_MS);

        policy.set_mode(VoiceActivationMode::PushToTalk);
        policy.set_mode(VoiceActivationMode::VoiceActivation);

        assert!(
            !policy.should_transmit(LOUD, FRAME_MS),
            "must not open instantly"
        );
    }

    #[test]
    fn setting_the_same_mode_is_a_no_op() {
        let mut policy = policy(VoiceActivationMode::VoiceActivation);
        policy.should_transmit(LOUD, FRAME_MS);
        assert!(policy.should_transmit(LOUD, FRAME_MS), "gate is open");

        // Re-selecting the current mode must not disturb an open gate.
        policy.set_mode(VoiceActivationMode::VoiceActivation);
        assert!(policy.should_transmit(LOUD, FRAME_MS));
    }

    #[test]
    fn resume_is_reported_only_on_the_frame_that_follows_silence() {
        // The far end uses this to tell "they started talking again" from
        // "packets were lost".
        let mut policy = policy(VoiceActivationMode::PushToTalk);
        policy.set_push_to_talk(true);

        // Nothing was transmitted before, so the first frame is a resume.
        assert!(policy.should_transmit(LOUD, FRAME_MS));
        assert!(policy.is_resume(), "the first frame after silence resumes");

        // This one continues an unbroken run.
        assert!(policy.should_transmit(LOUD, FRAME_MS));
        assert!(!policy.is_resume(), "a continuing frame is not a resume");

        // Key up, then down: the frame that comes back resumes.
        policy.set_push_to_talk(false);
        assert!(!policy.should_transmit(LOUD, FRAME_MS));
        assert!(!policy.is_resume(), "a silent frame is never a resume");

        policy.set_push_to_talk(true);
        assert!(policy.should_transmit(LOUD, FRAME_MS));
        assert!(policy.is_resume(), "resuming after a gap must be marked");
    }

    #[test]
    fn retuning_the_gate_is_visible() {
        let mut policy = policy(VoiceActivationMode::VoiceActivation);
        policy.set_settings(VoiceActivationSettings {
            sensitivity: 0.9,
            ..settings()
        });
        // Well below the new threshold.
        for _ in 0..10 {
            assert!(!policy.should_transmit(LOUD, FRAME_MS));
        }
    }

    #[test]
    fn reset_clears_the_resume_flag() {
        let mut policy = policy(VoiceActivationMode::Continuous);
        policy.should_transmit(LOUD, FRAME_MS);
        assert!(policy.transmitted_last());

        policy.reset();
        assert!(!policy.transmitted_last());
        assert!(!policy.is_resume());
    }

    #[test]
    fn the_level_is_recorded_in_every_transmission_mode() {
        // The trap: push-to-talk, continuous and muted all return from
        // `should_transmit` without ever looking at the level, so a meter filled
        // in *after* that call would sit at zero in three of the four modes —
        // including the two people use to check a microphone without
        // transmitting a word.
        for mode in [
            VoiceActivationMode::PushToTalk,
            VoiceActivationMode::VoiceActivation,
            VoiceActivationMode::Continuous,
            VoiceActivationMode::Muted,
        ] {
            let mut engine = engine_with_defaults();
            engine.set_mode(mode);
            assert_eq!(engine.input_level(), 0.0, "{mode:?} starts silent");

            let loud = vec![0.5_f32; crate::format::FRAME_SAMPLES];
            let _ = engine.measure(&loud);

            assert!(
                (engine.input_level() - 0.5).abs() < 1e-3,
                "{mode:?} did not record the level"
            );
            assert!(
                (engine.input_peak() - 0.5).abs() < 1e-3,
                "{mode:?} did not record the peak"
            );
        }
    }

    #[test]
    fn muting_does_not_stop_the_meter() {
        // Muted capture keeps running — `should_transmit` says no, so nothing is
        // sent — and that is exactly what makes "start voice while muted" a
        // microphone test.
        let mut engine = engine_with_defaults();
        engine.set_input_muted(true);

        let quiet = vec![0.02_f32; crate::format::FRAME_SAMPLES];
        let _ = engine.measure(&quiet);

        assert!(
            engine.input_level() > 0.0,
            "a muted microphone still measures"
        );
        assert!(!engine.state().transmitting, "but it transmits nothing");
    }

    #[test]
    fn an_engine_with_no_devices_still_reports_its_state() {
        let engine = engine_with(settings());

        assert!(!engine.input_available());
        assert!(!engine.output_available());
        assert_eq!(engine.state(), VoiceState::default());
        assert_eq!(engine.buffered_samples(), 0);
        assert!(engine.devices_healthy(), "absent devices are not unhealthy");
    }

    #[test]
    fn polling_without_a_microphone_yields_nothing() {
        let mut engine = engine_with(settings());
        assert!(engine.poll().expect("poll").is_empty());
    }

    #[test]
    fn playing_without_speakers_is_harmless() {
        // A user with no working output must still be able to connect.
        let mut engine = engine_with(settings());
        engine.play(&[0.5; PLAYBACK_SAMPLES]);
        engine.play_silence();
        assert_eq!(engine.buffered_samples(), 0);
    }

    #[test]
    fn a_muted_output_discards_audio_instead_of_queueing_it() {
        let mut engine = engine_with(settings());
        engine.set_output_muted(true);
        engine.play(&[0.5; PLAYBACK_SAMPLES]);

        // Nothing was queued, so unmuting cannot replay a backlog.
        assert_eq!(engine.buffered_samples(), 0);
    }

    #[test]
    fn voice_state_reflects_the_controls() {
        let mut engine = engine_with(settings());

        engine.set_mode(VoiceActivationMode::PushToTalk);
        engine.set_input_muted(true);
        engine.set_output_muted(true);

        let state = engine.state();
        assert_eq!(state.mode, VoiceActivationMode::PushToTalk);
        assert!(state.input_muted);
        assert!(state.output_muted);
        assert!(state.is_deafened());
        assert!(!state.can_transmit());
    }

    #[test]
    fn opening_a_missing_device_does_not_panic() {
        // Both device paths report rather than abort, so a machine with no
        // audio hardware still connects and reads chat.
        let mut engine = engine_with(settings());
        let _ = engine.open_devices(Some("no such microphone"), Some("no such speakers"));
        let _ = engine.set_input_device(Some("still not a device"));
        let _ = engine.set_output_device(Some("nor this"));
    }

    #[test]
    fn the_engine_encodes_the_stereo_profile_at_the_top_of_its_range() {
        // There is no profile to choose: capture is stereo, so the engine sends
        // stereo, and the bitrate is the ceiling of the published range.
        let engine = engine_with_defaults();
        assert_eq!(engine.packet_codec(), ts_protocol::Codec::OpusMusic);
        assert_eq!(engine.bitrate(), 79_200);
    }

    #[test]
    fn the_output_volume_is_clamped_to_the_usable_range() {
        // Hand-edited settings files produce every one of these.
        let mut engine = engine_with_defaults();
        assert_eq!(engine.output_volume(), 1.0, "unity until told otherwise");

        engine.set_output_volume(0.4);
        assert!((engine.output_volume() - 0.4).abs() < f32::EPSILON);

        engine.set_output_volume(-1.0);
        assert_eq!(engine.output_volume(), 0.0);

        engine.set_output_volume(7.0);
        assert_eq!(engine.output_volume(), 1.0);

        // NaN would turn every sample into silence indistinguishable from a
        // broken device, so it falls back to unity rather than propagating.
        engine.set_output_volume(f32::NAN);
        assert_eq!(engine.output_volume(), 1.0);
    }

    #[test]
    fn decibels_convert_to_the_gain_the_pipeline_multiplies_by() {
        assert!((gain_from_db(0.0) - 1.0).abs() < f32::EPSILON);
        assert!((gain_from_db(6.0) - 2.0).abs() < 0.01, "twice as loud");
        assert!((gain_from_db(-6.0) - 0.5).abs() < 0.01, "half as loud");
        assert!(
            gain_from_db(SILENCE_DB) < 1e-9,
            "the bottom of the slider has to be silence, not a quiet signal"
        );

        // There is no reading of "not a number decibels" a user could have
        // meant, and NaN samples would corrupt the encoded stream.
        assert_eq!(gain_from_db(f32::NAN), 0.0);
        assert_eq!(gain_from_db(f32::INFINITY), 0.0);
    }

    #[test]
    fn applying_unity_leaves_the_frame_exactly_as_it_was() {
        // The default setting must cost nothing and change nothing: the samples
        // the encoder sees are the microphone's own, bit for bit.
        let original: Vec<f32> = vec![0.25, -0.5, 1.0, -1.0];
        let mut frame = original.clone();
        apply_gain(&mut frame, 1.0);
        assert_eq!(frame, original);
    }

    #[test]
    fn a_gain_scales_the_frame_and_a_loud_one_clips() {
        let mut frame = vec![0.25, -0.25];
        apply_gain(&mut frame, gain_from_db(6.0));
        assert!((frame[0] - 0.5).abs() < 0.01);
        assert!((frame[1] + 0.5).abs() < 0.01);

        // +10 dB on material that is already loud: louder, and bounded. The
        // clamp is what keeps a boosted signal from becoming infinity.
        let mut loud = vec![0.9, -0.9];
        apply_gain(&mut loud, gain_from_db(MAX_GAIN_DB));
        assert!((loud[0] - 1.0).abs() < f32::EPSILON);
        assert!((loud[1] + 1.0).abs() < f32::EPSILON);
    }

    #[test]
    fn the_microphone_gain_is_clamped_to_the_offered_range() {
        // Hand-edited settings files produce every one of these.
        let mut engine = engine_with_defaults();
        assert_eq!(engine.input_gain_db(), 0.0, "unity until told otherwise");

        engine.set_input_gain_db(-12.0);
        assert!((engine.input_gain_db() + 12.0).abs() < 0.01);

        engine.set_input_gain_db(-300.0);
        assert_eq!(engine.input_gain_db(), SILENCE_DB);

        engine.set_input_gain_db(50.0);
        assert_eq!(engine.input_gain_db(), MAX_GAIN_DB);

        // Unlike the playback volume, nonsense becomes silence rather than
        // unity: a gain nobody could express is not a reason to be suddenly
        // loud.
        engine.set_input_gain_db(f32::NAN);
        assert_eq!(engine.input_gain_db(), SILENCE_DB);
    }

    #[test]
    fn an_engine_that_cannot_open_an_encoder_still_reports_itself() {
        // Nothing here needs a device, and nothing here can fail once the
        // encoder exists — which is the point of building one with no choices
        // to get wrong.
        let engine = engine_with_defaults();
        assert_eq!(engine.bitrate(), crate::encoder::max_bitrate(2));
        assert!(!engine.input_available());
        assert!(!engine.output_available());
    }

    #[test]
    fn a_downmix_halves_a_signal_present_on_both_channels() {
        // The level the gate sees must not double when the same audio arrives
        // on two channels — that would open the gate at half the sensitivity
        // the slider claims.
        let interleaved = [0.5_f32, 0.5, -0.25, -0.25];
        let mut out = [0.0_f32; 2];
        downmix(&interleaved, &mut out);
        assert!((out[0] - 0.5).abs() < 1e-6, "got {}", out[0]);
        assert!((out[1] + 0.25).abs() < 1e-6, "got {}", out[1]);
    }

    #[test]
    fn a_downmix_of_opposite_channels_is_silence() {
        let interleaved = [1.0_f32, -1.0];
        let mut out = [1.0_f32; 1];
        downmix(&interleaved, &mut out);
        assert!(out[0].abs() < 1e-6, "got {}", out[0]);
    }

    #[test]
    fn a_short_downmix_buffer_is_filled_without_panicking() {
        // This runs on the thread a microphone feeds. A wrong-sized buffer has
        // to produce silence, not a panic that takes the audio thread with it.
        let interleaved = [0.5_f32, 0.5, 0.5, 0.5];
        let mut out = [7.0_f32; 3];
        downmix(&interleaved, &mut out);
        assert!((out[0] - 0.5).abs() < 1e-6);
        assert!((out[1] - 0.5).abs() < 1e-6);
        assert_eq!(out[2], 0.0, "past the end of the input is silence");
    }
}
