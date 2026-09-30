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
use crate::format::{FRAME_MS, PLAYBACK_SAMPLES, is_full_frame};
use crate::playback::Playback;
use crate::vad::{VoiceGate, rms};

/// Decides whether a captured frame should be sent.
///
/// Holds all the state that makes that decision, and nothing else — no devices,
/// no codec — so every mode combination can be exercised directly.
#[derive(Debug, Clone)]
pub struct TransmitPolicy {
    gate: VoiceGate,
    mode: VoiceActivationMode,
    input_muted: bool,
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

        let wants = if self.input_muted {
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

    /// Whether the microphone is muted.
    #[must_use]
    pub const fn input_muted(&self) -> bool {
        self.input_muted
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
    /// Scratch for rendering one frame to stereo before queueing it.
    frame_stereo: Vec<f32>,
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

impl VoiceEngine {
    /// Builds an engine with no devices open.
    ///
    /// # Errors
    ///
    /// Returns [`AudioError::Backend`] if libopus refuses to initialise, which
    /// means voice cannot work at all.
    pub fn new(settings: VoiceActivationSettings) -> Result<Self, AudioError> {
        Ok(Self {
            capture: None,
            playback: None,
            encoder: OpusEncoder::new()?,
            policy: TransmitPolicy::new(VoiceActivationMode::default(), settings),
            output_muted: Arc::new(AtomicBool::new(false)),
            frame_stereo: vec![0.0; PLAYBACK_SAMPLES],
        })
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
                self.capture = Some(capture);
                false
            }
            Err(error) => {
                tracing::warn!(%error, "could not open a microphone; voice input is unavailable");
                true
            }
        };

        match Playback::open(output) {
            Ok(playback) => self.playback = Some(Arc::new(playback)),
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
    }

    /// Whether the speakers are muted.
    #[must_use]
    pub fn output_muted(&self) -> bool {
        self.output_muted.load(Ordering::Relaxed)
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
        let playback = Playback::open(id)?;
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

        let mut packets = Vec::new();
        let mut first_error = None;

        while let Some(frame) = capture.try_recv() {
            if !is_full_frame(frame.len()) {
                // The assembler only emits whole frames, so this cannot happen
                // — but sending a short frame would corrupt the stream, so it
                // is dropped rather than trusted.
                tracing::warn!(samples = frame.len(), "dropping a short capture frame");
                continue;
            }

            let level = rms(&frame);
            if !self.policy.should_transmit(level, FRAME_MS) {
                continue;
            }

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

        match first_error {
            Some(error) => Err(error),
            None => Ok(packets),
        }
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

impl std::fmt::Debug for VoiceEngine {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("VoiceEngine")
            .field("input", &self.input_available())
            .field("output", &self.output_available())
            .field("state", &self.state())
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
    fn an_engine_with_no_devices_still_reports_its_state() {
        let engine = VoiceEngine::new(settings()).expect("build engine");

        assert!(!engine.input_available());
        assert!(!engine.output_available());
        assert_eq!(engine.state(), VoiceState::default());
        assert_eq!(engine.buffered_samples(), 0);
        assert!(engine.devices_healthy(), "absent devices are not unhealthy");
    }

    #[test]
    fn polling_without_a_microphone_yields_nothing() {
        let mut engine = VoiceEngine::new(settings()).expect("build engine");
        assert!(engine.poll().expect("poll").is_empty());
    }

    #[test]
    fn playing_without_speakers_is_harmless() {
        // A user with no working output must still be able to connect.
        let mut engine = VoiceEngine::new(settings()).expect("build engine");
        engine.play(&[0.5; PLAYBACK_SAMPLES]);
        engine.play_silence();
        assert_eq!(engine.buffered_samples(), 0);
    }

    #[test]
    fn a_muted_output_discards_audio_instead_of_queueing_it() {
        let mut engine = VoiceEngine::new(settings()).expect("build engine");
        engine.set_output_muted(true);
        engine.play(&[0.5; PLAYBACK_SAMPLES]);

        // Nothing was queued, so unmuting cannot replay a backlog.
        assert_eq!(engine.buffered_samples(), 0);
    }

    #[test]
    fn voice_state_reflects_the_controls() {
        let mut engine = VoiceEngine::new(settings()).expect("build engine");

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
        let mut engine = VoiceEngine::new(settings()).expect("build engine");
        let _ = engine.open_devices(Some("no such microphone"), Some("no such speakers"));
        let _ = engine.set_input_device(Some("still not a device"));
        let _ = engine.set_output_device(Some("nor this"));
    }
}
