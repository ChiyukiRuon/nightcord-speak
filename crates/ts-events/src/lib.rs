//! # ts-events
//!
//! The one-way channel from the client core out to whatever is displaying it.
//!
//! The core never calls into a UI: it publishes events, and a front-end decides
//! what to do with them (DEVELOPMENT.md §18, §43). That keeps the core usable
//! from the CLI, from Flutter, and later from the Web gateway without changes.
//!
//! ```text
//! core ──publish──▶ EventBus ──▶ CLI
//!                          ├──▶ FFI queue ──▶ Dart stream
//!                          └──▶ Web gateway
//! ```

use serde::{Deserialize, Serialize};
use ts_model::{
    Capabilities, Channel, ChannelId, Client, ClientError, ClientId, ConnectionState, Message,
    Permissions, Server, ServerInfo, SessionId, Speaking, VoiceState,
};

/// Something that happened on one session.
///
/// Variants are additive: a front-end must ignore events it does not recognise
/// rather than treating them as an error, so that a newer core can talk to an
/// older UI.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "event", content = "payload", rename_all = "snake_case")]
pub enum ClientEvent {
    /// Client-wide preference; the session identifies the initiating action.
    OwnAvatarChanged(ts_model::OwnAvatar),
    /// Screen sharing discovery and peer negotiation.
    Screen(ts_model::ScreenEvent),
    // --- lifecycle --------------------------------------------------------
    /// The session moved to a different lifecycle state.
    ConnectionStateChanged(ConnectionState),

    /// The handshake finished and the server introduced itself.
    ///
    /// The fields are what the server had reported *at that moment*. A
    /// TeamSpeak server describes itself before it sends the channel and client
    /// lists, so the counts here can legitimately be zero; a later
    /// [`ClientEvent::ServerInfoChanged`] corrects them.
    Connected {
        /// The server we reached.
        server: Server,
        /// What it says about itself.
        info: ServerInfo,
    },

    /// The server's self-description changed.
    ///
    /// Emitted for anything that moves — the online client count changes on
    /// almost every join and leave, so this is not a rare event.
    ServerInfoChanged(ServerInfo),

    /// The session shut down cleanly. No further events will follow.
    Disconnected,

    /// A retry has been scheduled after a failure.
    ReconnectScheduled {
        /// 1 for the first retry.
        attempt: u32,
        /// How long the core will wait before trying, in milliseconds.
        delay_ms: u64,
    },

    /// The server told us which client and channel are ours.
    OwnClientIdentified {
        /// Our client id on this server.
        client_id: ClientId,
        /// The channel we landed in.
        channel_id: ChannelId,
    },

    // --- server state -----------------------------------------------------
    /// What this server lets us do, or a change to it.
    PermissionsChanged(Permissions),

    /// What this server can do at all.
    CapabilitiesChanged(Capabilities),

    // --- channels ---------------------------------------------------------
    /// A channel was created.
    ChannelCreated(Channel),

    /// A channel's properties changed.
    ChannelUpdated(Channel),

    /// A channel was deleted.
    ChannelRemoved(ChannelId),

    // --- clients ----------------------------------------------------------
    /// A client connected.
    ClientJoined(Client),

    /// A client's properties changed — nickname, flags, groups.
    ClientUpdated(Client),

    /// A client disconnected.
    ClientLeft(ClientId),

    /// A client changed channel.
    ClientMoved {
        /// Who moved.
        client_id: ClientId,
        /// Where they went.
        channel_id: ChannelId,
    },

    // --- interaction ------------------------------------------------------
    /// A chat message arrived.
    MessageReceived(Message),

    /// Someone poked us.
    ///
    /// Pokes are not messages: they are a separate interaction with no reply,
    /// no history and a different presentation, so they get their own event
    /// (§66).
    Poked {
        /// Who poked us.
        client_id: ClientId,
        /// Their nickname, captured at delivery time.
        sender_name: String,
        /// The message they attached.
        message: String,
    },

    /// Someone started or stopped talking.
    Speaking(Speaking),

    /// Our own voice configuration changed.
    VoiceStateChanged(VoiceState),

    /// Something failed.
    Error(ClientError),
}

impl ClientEvent {
    /// Whether this event ends the session's event stream.
    #[must_use]
    pub const fn is_terminal(&self) -> bool {
        matches!(self, Self::Disconnected)
    }

    /// Whether this event reports a failure.
    #[must_use]
    pub const fn is_error(&self) -> bool {
        matches!(self, Self::Error(_))
    }

    /// A stable name for this variant, for logs and metrics labels.
    ///
    /// Hand-written rather than derived so log output stays stable when a
    /// variant is renamed.
    #[must_use]
    pub const fn name(&self) -> &'static str {
        match self {
            Self::OwnAvatarChanged(_) => "own_avatar_changed",
            Self::ConnectionStateChanged(_) => "connection_state_changed",
            Self::Connected { .. } => "connected",
            Self::Screen(_) => "screen",
            Self::ServerInfoChanged(_) => "server_info_changed",
            Self::Disconnected => "disconnected",
            Self::ReconnectScheduled { .. } => "reconnect_scheduled",
            Self::OwnClientIdentified { .. } => "own_client_identified",
            Self::PermissionsChanged(_) => "permissions_changed",
            Self::CapabilitiesChanged(_) => "capabilities_changed",
            Self::ChannelCreated(_) => "channel_created",
            Self::ChannelUpdated(_) => "channel_updated",
            Self::ChannelRemoved(_) => "channel_removed",
            Self::ClientJoined(_) => "client_joined",
            Self::ClientUpdated(_) => "client_updated",
            Self::ClientLeft(_) => "client_left",
            Self::ClientMoved { .. } => "client_moved",
            Self::MessageReceived(_) => "message_received",
            Self::Poked { .. } => "poked",
            Self::Speaking(_) => "speaking",
            Self::VoiceStateChanged(_) => "voice_state_changed",
            Self::Error(_) => "error",
        }
    }
}

/// A [`ClientEvent`] tagged with the session it came from.
///
/// With several servers connected at once, an event without a session id is
/// ambiguous, so the id travels with it rather than being tracked separately.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SessionEvent {
    /// Which session produced this.
    pub session: SessionId,
    /// What happened.
    pub event: ClientEvent,
}

impl SessionEvent {
    /// Pairs a session with an event.
    #[must_use]
    pub const fn new(session: SessionId, event: ClientEvent) -> Self {
        Self { session, event }
    }

    /// Whether this event ends the session's stream.
    #[must_use]
    pub const fn is_terminal(&self) -> bool {
        self.event.is_terminal()
    }
}

/// Fan-out point for [`SessionEvent`]s.
///
/// Built on a broadcast channel: every subscriber sees every event, and a
/// subscriber that falls behind loses its oldest events rather than stalling
/// the core. A slow UI must never be able to block the network loop.
#[derive(Debug, Clone)]
pub struct EventBus {
    sender: tokio::sync::broadcast::Sender<SessionEvent>,
}

impl EventBus {
    /// Creates a bus where each subscriber may fall this many events behind.
    ///
    /// Big enough that a UI which misses a frame during a burst — a hundred
    /// clients joining on connect — still sees the whole burst.
    #[must_use]
    pub fn new(capacity: usize) -> Self {
        let (sender, _) = tokio::sync::broadcast::channel(capacity.max(1));
        Self { sender }
    }

    /// A bus with the default buffer size.
    #[must_use]
    pub fn with_default_capacity() -> Self {
        Self::new(1024)
    }

    /// Subscribes to every event published from now on.
    ///
    /// Events published before subscribing are not replayed — a new subscriber
    /// should read current state from the session, not reconstruct it from
    /// history.
    #[must_use]
    pub fn subscribe(&self) -> tokio::sync::broadcast::Receiver<SessionEvent> {
        self.sender.subscribe()
    }

    /// Publishes an event.
    ///
    /// Returns the number of subscribers that received it. Zero is normal and
    /// not an error: a CLI run with no UI attached still has to work.
    pub fn publish(&self, event: SessionEvent) -> usize {
        self.sender.send(event).unwrap_or(0)
    }

    /// How many subscribers are currently attached.
    #[must_use]
    pub fn subscriber_count(&self) -> usize {
        self.sender.receiver_count()
    }
}

impl Default for EventBus {
    fn default() -> Self {
        Self::with_default_capacity()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ts_model::ProtocolKind;

    #[test]
    fn subscriber_receives_published_events() {
        let bus = EventBus::with_default_capacity();
        let mut rx = bus.subscribe();

        assert_eq!(
            bus.publish(SessionEvent::new(
                SessionId::new(7),
                ClientEvent::Disconnected
            )),
            1
        );

        let received = rx.try_recv().expect("event delivered");
        assert_eq!(received.session, SessionId::new(7));
        assert_eq!(received.event, ClientEvent::Disconnected);
        assert!(received.is_terminal());
    }

    #[test]
    fn publishing_with_no_subscribers_is_not_an_error() {
        let bus = EventBus::with_default_capacity();
        assert_eq!(
            bus.publish(SessionEvent::new(
                SessionId::new(1),
                ClientEvent::Disconnected
            )),
            0
        );
    }

    #[test]
    fn every_subscriber_sees_every_event() {
        let bus = EventBus::with_default_capacity();
        let mut a = bus.subscribe();
        let mut b = bus.subscribe();

        bus.publish(SessionEvent::new(
            SessionId::new(1),
            ClientEvent::Disconnected,
        ));

        assert!(a.try_recv().is_ok());
        assert!(b.try_recv().is_ok());
        assert_eq!(bus.subscriber_count(), 2);
    }

    #[test]
    fn the_capability_flags_arrive_under_the_names_the_front_ends_read() {
        // The screen-sharing entry exists only because Dart reads
        // `capabilities.screen_stream` out of this payload, and nothing but
        // this test sits between the two spellings. Renaming either half is
        // otherwise a silent "the feature vanished from the UI" — which is
        // exactly what happened once: the event was defined, serialised and
        // handled, and no backend ever published it.
        let json =
            serde_json::to_value(ClientEvent::CapabilitiesChanged(Capabilities::TS6)).unwrap();
        assert_eq!(json["event"], "capabilities_changed");
        assert_eq!(json["payload"]["screen_stream"], true);
        assert_eq!(
            serde_json::to_value(Capabilities::for_protocol(ProtocolKind::Ts3)).unwrap()["screen_stream"],
            false
        );
    }

    #[test]
    fn events_survive_a_json_round_trip() {
        // These cross the FFI boundary as JSON, so the encoding is part of the
        // contract with Flutter.
        let events = vec![
            ClientEvent::Disconnected,
            ClientEvent::ConnectionStateChanged(ConnectionState::Reconnecting),
            ClientEvent::ClientMoved {
                client_id: ClientId::new(3),
                channel_id: ChannelId::new(9),
            },
            ClientEvent::CapabilitiesChanged(Capabilities::TS3),
            ClientEvent::Error(ClientError::Timeout),
            ClientEvent::Poked {
                client_id: ClientId::new(2),
                sender_name: "Bob".into(),
                message: "ping".into(),
            },
            ClientEvent::ServerInfoChanged(ServerInfo {
                name: "Test".into(),
                max_clients: 32,
                ..ServerInfo::default()
            }),
        ];

        for event in events {
            let json = serde_json::to_string(&event).expect("serialize");
            let back: ClientEvent = serde_json::from_str(&json).expect("deserialize");
            assert_eq!(event, back, "round trip changed {json}");
        }
    }

    #[test]
    fn variant_names_are_stable() {
        assert_eq!(ClientEvent::Disconnected.name(), "disconnected");
        assert_eq!(ClientEvent::Error(ClientError::Timeout).name(), "error");
        assert!(ClientEvent::Error(ClientError::Timeout).is_error());
    }
}
