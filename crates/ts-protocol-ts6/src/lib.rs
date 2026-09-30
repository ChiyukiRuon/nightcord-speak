//! # ts-protocol-ts6
//!
//! The TeamSpeak 6 backend.
//!
//! TS6 is **not** a separate protocol. Measured against a real
//! `6.0.0-beta13.1` server: the shared adapter connects, lists channels and
//! clients, carries chat and moves two-way voice with no changes at all. What
//! TS6 adds is the `stream` family — `setupstream`, `joinstreamrequest`,
//! `respondjoinstreamrequest`, `stopstream`, `streamsignaling`,
//! `requeststreaminfo` — which upstream neither models nor names.
//!
//! So this crate starts as the boundary that says *"this server is TS6"*, and
//! is where those commands will land. Until they exist, what a caller gets is
//! the base protocol with [`ts_model::Capabilities::TS6`] — which is already
//! true and useful, rather than a stub that refuses to connect (§85).

use ts_events::EventBus;
use ts_identity::IdentityStore;
use ts_model::{ProtocolKind, Server, SessionId};
use ts_protocol::Backend;

pub use ts_protocol_tsclient::generate_identity;

/// Builds a TeamSpeak 6 [`Backend`] for one session.
///
/// Forces the protocol rather than trusting the caller's label: this crate only
/// exists to serve TS6, and a mislabelled server would otherwise be handed
/// TS3's capability set — losing the stream capability that is the whole point
/// of the protocol here.
#[must_use]
pub fn backend(
    events: EventBus,
    session: SessionId,
    mut server: Server,
    identity: Option<(IdentityStore, String)>,
) -> Backend {
    server.protocol = ProtocolKind::Ts6;
    ts_protocol_tsclient::backend(events, session, server, identity)
}

#[cfg(test)]
mod tests {
    use super::*;
    use ts_model::ServerId;

    fn server(protocol: ProtocolKind) -> Server {
        Server {
            id: ServerId::new(1),
            name: "Test".into(),
            address: "example.com:9988".into(),
            protocol,
        }
    }

    #[test]
    fn the_protocol_is_forced_to_ts6() {
        let backend = backend(
            EventBus::with_default_capacity(),
            SessionId::new(1),
            server(ProtocolKind::Ts3),
            None,
        );
        assert_eq!(backend.kind(), ProtocolKind::Ts6);
    }

    #[test]
    fn a_ts6_backend_reports_itself_as_ts6() {
        let backend = backend(
            EventBus::with_default_capacity(),
            SessionId::new(1),
            server(ProtocolKind::Ts6),
            None,
        );
        assert_eq!(backend.connection_ref().kind(), ProtocolKind::Ts6);
    }
}
