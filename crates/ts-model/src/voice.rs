use serde::{Deserialize, Serialize};

use crate::ClientId;

/// How the microphone decides when to transmit (§29).
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum VoiceActivationMode {
    /// Transmit only while the push-to-talk key is held.
    PushToTalk,
    /// Transmit while the input level exceeds a threshold.
    #[default]
    VoiceActivation,
    /// Transmit whenever connected.
    Continuous,
    /// Never transmit.
    Muted,
}

/// The local user's voice state.
///
/// This describes *us*. Remote clients' mute flags live in
/// [`crate::ClientFlags`], and their live speaking indicator arrives as a
/// separate transient event.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct VoiceState {
    /// How transmission is triggered.
    pub mode: VoiceActivationMode,
    /// Our microphone is disabled.
    pub input_muted: bool,
    /// Our speakers are disabled.
    pub output_muted: bool,
    /// Voice packets are leaving the encoder right now.
    pub transmitting: bool,
}

impl VoiceState {
    /// Whether we are fully muted — neither heard nor hearing.
    #[must_use]
    pub const fn is_deafened(self) -> bool {
        self.input_muted && self.output_muted
    }

    /// Whether a packet would be sent if the encoder produced one.
    ///
    /// Note this is not the same as [`Self::transmitting`]: under push-to-talk
    /// with the key released the mode still permits voice, but nothing is
    /// leaving right now.
    #[must_use]
    pub const fn can_transmit(self) -> bool {
        !self.input_muted && !matches!(self.mode, VoiceActivationMode::Muted)
    }
}

/// Tuning for [`VoiceActivationMode::VoiceActivation`] (§29).
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct VoiceActivationSettings {
    /// RMS level above which transmission opens, `0.0..=1.0`.
    pub sensitivity: f32,
    /// How long the level must stay above the threshold before opening, ms.
    /// Prevents consonants from being clipped.
    pub attack_ms: u32,
    /// How long the level may stay below the threshold before closing, ms.
    /// Prevents gaps between words from cutting transmission.
    pub release_ms: u32,
}

impl Default for VoiceActivationSettings {
    fn default() -> Self {
        Self {
            sensitivity: 0.05,
            attack_ms: 60,
            release_ms: 400,
        }
    }
}

/// A transient "this client is talking" signal.
///
/// Speaking is not a stable property of a client — it flips several times a
/// second — so it is delivered as an event rather than stored in
/// [`crate::Client`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Speaking {
    /// Who is talking.
    pub client_id: ClientId,
    /// `true` when speech started, `false` when it stopped.
    pub speaking: bool,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deafened_requires_both_mutes() {
        let input_only = VoiceState {
            input_muted: true,
            ..VoiceState::default()
        };
        assert!(!input_only.is_deafened());

        let both = VoiceState {
            input_muted: true,
            output_muted: true,
            ..VoiceState::default()
        };
        assert!(both.is_deafened());
    }

    #[test]
    fn muted_mode_blocks_transmission() {
        let state = VoiceState {
            mode: VoiceActivationMode::Muted,
            ..VoiceState::default()
        };
        assert!(!state.can_transmit());

        let ptt = VoiceState {
            mode: VoiceActivationMode::PushToTalk,
            ..VoiceState::default()
        };
        // Push-to-talk with the key released still *may* transmit later.
        assert!(ptt.can_transmit());
    }

    #[test]
    fn input_mute_blocks_transmission() {
        let state = VoiceState {
            input_muted: true,
            ..VoiceState::default()
        };
        assert!(!state.can_transmit());
    }
}
