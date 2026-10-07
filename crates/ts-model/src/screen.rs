//! Transport-independent screen sharing control and media negotiation.
//!
//! Screen sharing is a *negotiation*, not a stream: the picture never travels
//! through the core. Two peers agree on a session here and then connect to each
//! other directly, so what this module carries is only who is sharing, who may
//! watch, and the descriptions needed to open that second connection.
//!
//! Stream ids stay opaque strings rather than becoming a numeric id type: TS6
//! issues them, we only echo them back, and a local newtype would imply a
//! stability the server never promised.

use crate::ClientId;
use serde::{Deserialize, Serialize};

/// One step of the media negotiation, carried inside [`ScreenCommand::Signal`]
/// or [`ScreenEvent::Signal`].
#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ScreenSignal {
    /// The publisher's session description.
    Offer { sdp: String },
    /// The viewer's reply to an offer.
    Answer { sdp: String },
    /// One trickled ICE candidate; `line` is its media-line index.
    Candidate {
        candidate: String,
        mid: String,
        line: u16,
    },
}

/// What is being captured.
///
/// The domain keeps three kinds because the front-end's source picker has three
/// tabs; which number each one becomes on the wire is the protocol's business
/// and lives in the TS6 encoder.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ScreenSource {
    /// A camera.
    Camera,
    /// A whole display.
    Screen,
    /// One window — which on a desktop is what "an application" amounts to.
    Window,
}

/// Who may watch.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ScreenAccess {
    /// Anyone in the channel.
    Public,
    /// People on a contact list — which this client does not have, so it is
    /// carried but not enforced (see `docs/screen-sharing.md`).
    Contacts,
    /// Only those the publisher admits.
    Private,
}

/// How viewers reach the picture.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ScreenMode {
    /// Straight between the two peers. The only one this client implements.
    P2p,
    /// Through the server's own media router, which needs a client for it that
    /// nobody here has written.
    Sfu,
}

/// Everything a publisher decides before it goes live.
///
/// Deliberately without a `Default`: the defaults a user sees are the ones in
/// `ts-settings`, and a second set here would be a second answer to the same
/// question. A front-end always sends every field, and a missing one is a bug
/// worth failing on rather than quietly sharing at some other resolution.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct ScreenOptions {
    pub source: ScreenSource,
    /// Wanted capture height in pixels; 0 keeps the source's own.
    pub height: u32,
    /// Wanted frames per second; 0 leaves it to the platform.
    pub fps: u32,
    /// What the encoder may spend on video.
    pub video_bitrate_kbps: u32,
    /// Whether to send the capture's own audio alongside the picture.
    pub audio: bool,
    /// What the encoder may spend on that audio. Ignored when `audio` is false.
    pub audio_bitrate_kbps: u32,
    pub access: ScreenAccess,
    /// How many viewers to allow; 0 means as many as the server will carry.
    pub viewer_limit: u32,
    pub mode: ScreenMode,
    /// Whether the picture is mostly still text rather than movement.
    ///
    /// The one field the server is never told: it says which way the encoder
    /// should give when it runs out of room, and the encoder is the front-end's
    /// (`flutter_webrtc` has no `contentHint`, so it becomes the degradation
    /// preference instead). It lives here because it is still something the
    /// publisher decides, and splitting it into a second type would mean two
    /// things to pass around for one decision.
    pub detail: bool,
}

/// What the frontend asks the core to do about screen sharing.
#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "action", rename_all = "snake_case")]
pub enum ScreenCommand {
    /// Asks what one client is sharing, since TS6 does not announce it.
    Discover { client_id: ClientId },
    /// Starts publishing with the given settings.
    Start {
        name: String,
        options: ScreenOptions,
    },
    /// Stops publishing our own stream.
    Stop { stream_id: String },
    /// Asks to watch someone else's stream.
    Join {
        stream_id: String,
        client_id: ClientId,
    },
    /// Gives up watching — or, when the publisher sends it, removes a viewer.
    Leave {
        stream_id: String,
        client_id: ClientId,
    },
    /// The publisher's answer to a viewer's request, carrying the offer when
    /// accepted.
    Respond {
        stream_id: String,
        client_id: ClientId,
        accept: bool,
        sdp: String,
    },
    /// Relays one negotiation step to the other peer.
    Signal {
        stream_id: String,
        client_id: ClientId,
        signal: ScreenSignal,
    },
}

/// What the core reports about screen sharing.
#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ScreenEvent {
    /// A stream exists. A publisher only ever hears its own this way, which is
    /// therefore also how a start is acknowledged.
    Available {
        stream_id: String,
        client_id: ClientId,
        name: String,
    },
    /// A stream ended, for any reason including the publisher disconnecting.
    Stopped { stream_id: String },
    /// Someone asked to watch us — or, with `leaving`, stopped.
    JoinRequested {
        stream_id: String,
        client_id: ClientId,
        leaving: bool,
    },
    /// The publisher answered our request; `sdp` is the offer when accepted.
    JoinAnswered {
        stream_id: String,
        client_id: ClientId,
        accepted: bool,
        sdp: String,
    },
    /// One viewer is gone. The stream itself may still be running.
    PeerLeft {
        stream_id: String,
        client_id: ClientId,
    },
    /// One negotiation step from the other peer.
    Signal {
        stream_id: String,
        client_id: ClientId,
        signal: ScreenSignal,
    },
}

// SDP carries the DTLS fingerprint and ICE credentials, and candidates carry
// network addresses; never derive Debug.
impl std::fmt::Debug for ScreenSignal {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("ScreenSignal(<redacted>)")
    }
}
impl std::fmt::Debug for ScreenCommand {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("ScreenCommand(<redacted>)")
    }
}
impl std::fmt::Debug for ScreenEvent {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("ScreenEvent(<redacted>)")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_front_ends_json_is_the_shape_this_module_reads() {
        // The literal below is what `ScreenOptions.toJson` writes, in
        // `apps/client/lib/models/screen_options.dart`. Neither side's own
        // tests cross the boundary — the Dart ones build the map by hand and
        // the Rust ones build the struct — so this is the only place the two
        // spellings actually meet. A rename on either side that the other did
        // not follow is a share that starts and then never does anything.
        let json = r#"{
            "action": "start",
            "name": "Screen share",
            "options": {
                "source": "window",
                "height": 1080,
                "fps": 30,
                "video_bitrate_kbps": 4000,
                "audio": true,
                "audio_bitrate_kbps": 128,
                "access": "private",
                "viewer_limit": 4,
                "mode": "p2p",
                "detail": true
            }
        }"#;

        let ScreenCommand::Start { name, options } =
            serde_json::from_str(json).expect("the front-end's own JSON")
        else {
            panic!("an action of `start` is a Start");
        };

        assert_eq!(name, "Screen share");
        assert_eq!(options.source, ScreenSource::Window);
        assert_eq!(options.height, 1080);
        assert_eq!(options.fps, 30);
        assert_eq!(options.video_bitrate_kbps, 4000);
        assert!(options.audio);
        assert_eq!(options.audio_bitrate_kbps, 128);
        assert_eq!(options.access, ScreenAccess::Private);
        assert_eq!(options.viewer_limit, 4);
        assert_eq!(options.mode, ScreenMode::P2p);
        assert!(options.detail);
    }
}
