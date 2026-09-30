use serde::{Deserialize, Serialize};

/// What the connected server can actually do.
///
/// Front-ends branch on these flags rather than on the protocol kind, so a
/// feature TS3 lacks shows up as a capability gap instead of a version check
/// scattered through the UI (§15, §55).
///
/// Backends own their own constant. When TS6 changes upstream — it is still
/// beta — the correction belongs in [`Capabilities::TS6`], not in a caller.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Capabilities {
    /// Posting to the server and to channels.
    pub text_chat: bool,
    /// One-to-one messages.
    pub private_chat: bool,
    /// Two-way voice.
    pub voice: bool,
    /// Whisper lists and targeted voice.
    pub whisper: bool,
    /// File upload and download.
    pub file_transfer: bool,
    /// Screen streaming.
    pub screen_stream: bool,
    /// Poking a client to get their attention.
    pub poke: bool,
}

impl Capabilities {
    /// What a given protocol offers.
    ///
    /// The single place the two are mapped onto each other, so a backend never
    /// has to branch on the protocol kind to report what it can do (§15, §55).
    #[must_use]
    pub const fn for_protocol(kind: crate::ProtocolKind) -> Self {
        match kind {
            crate::ProtocolKind::Ts3 => Self::TS3,
            crate::ProtocolKind::Ts6 => Self::TS6,
        }
    }

    /// Nothing is known yet — the state before a handshake completes.
    pub const NONE: Self = Self {
        text_chat: false,
        private_chat: false,
        voice: false,
        whisper: false,
        file_transfer: false,
        screen_stream: false,
        poke: false,
    };

    /// What a stock TeamSpeak 3 server offers.
    pub const TS3: Self = Self {
        text_chat: true,
        private_chat: true,
        voice: true,
        whisper: true,
        file_transfer: true,
        screen_stream: false,
        poke: true,
    };

    /// TeamSpeak 6, which adds screen streaming.
    pub const TS6: Self = Self {
        text_chat: true,
        private_chat: true,
        voice: true,
        whisper: true,
        file_transfer: true,
        screen_stream: true,
        poke: true,
    };

    /// Whether the server can carry voice at all.
    #[must_use]
    pub const fn supports_voice(self) -> bool {
        self.voice
    }
}

impl Default for Capabilities {
    fn default() -> Self {
        Self::NONE
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ProtocolKind;

    #[test]
    fn each_protocol_maps_onto_its_own_set() {
        assert_eq!(
            Capabilities::for_protocol(ProtocolKind::Ts3),
            Capabilities::TS3
        );
        assert_eq!(
            Capabilities::for_protocol(ProtocolKind::Ts6),
            Capabilities::TS6
        );
    }

    #[test]
    fn only_ts6_streams() {
        // The one capability that actually differs today. A UI branches on this
        // rather than on the protocol kind, so if it were wrong the stream
        // button would appear on TS3.
        assert!(!Capabilities::for_protocol(ProtocolKind::Ts3).screen_stream);
        assert!(Capabilities::for_protocol(ProtocolKind::Ts6).screen_stream);
    }

    #[test]
    fn everything_else_is_shared() {
        let ts3 = Capabilities::for_protocol(ProtocolKind::Ts3);
        let ts6 = Capabilities::for_protocol(ProtocolKind::Ts6);
        assert_eq!(ts3.text_chat, ts6.text_chat);
        assert_eq!(ts3.voice, ts6.voice);
        assert_eq!(ts3.whisper, ts6.whisper);
        assert_eq!(ts3.file_transfer, ts6.file_transfer);
        assert_eq!(ts3.poke, ts6.poke);
    }
}
