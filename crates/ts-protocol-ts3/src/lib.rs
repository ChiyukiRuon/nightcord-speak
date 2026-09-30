//! # ts-protocol-ts3
//!
//! The TeamSpeak 3 backend.
//!
//! TS3 shares its base protocol with TS6 — measured, not assumed — so the wire
//! handling lives in [`ts_protocol_tsclient`]. This crate is the boundary that
//! says *"this server is TS3"*, and the home for anything TS3 grows that TS6
//! must not inherit (§14).
//!
//! Keeping it this thin is deliberate rather than lazy: the alternative was two
//! copies of the adapter that would drift apart, and the isolation that §14
//! actually protects — TS3's behaviour not leaking into `ts-core` — is the crate
//! boundary, not the line count.

use ts_events::EventBus;
use ts_identity::IdentityStore;
use ts_model::{ProtocolKind, Server, SessionId};
use ts_protocol::Backend;

pub use ts_protocol_tsclient::generate_identity;

/// Builds a TeamSpeak 3 [`Backend`] for one session.
///
/// Forces the protocol rather than trusting the caller's label: this crate only
/// exists to serve TS3, and a mislabelled server would otherwise be handed
/// TS6's capability set.
#[must_use]
pub fn backend(
    events: EventBus,
    session: SessionId,
    mut server: Server,
    identity: Option<(IdentityStore, String)>,
) -> Backend {
    server.protocol = ProtocolKind::Ts3;
    ts_protocol_tsclient::backend(events, session, server, identity)
}

#[cfg(test)]
mod tests {
    use super::*;
    use ts_model::ServerId;

    #[test]
    fn the_protocol_is_forced_to_ts3() {
        // A caller that mislabels a server must not thereby get TS6 features.
        let server = Server {
            id: ServerId::new(1),
            name: "Mislabelled".into(),
            address: "example.com:9987".into(),
            protocol: ProtocolKind::Ts6,
        };

        let backend = backend(
            EventBus::with_default_capacity(),
            SessionId::new(1),
            server,
            None,
        );
        assert_eq!(backend.kind(), ProtocolKind::Ts3);
    }

    #[test]
    fn a_ts3_backend_reports_itself_as_ts3() {
        let server = Server {
            id: ServerId::new(1),
            name: "Test".into(),
            address: "example.com:9987".into(),
            protocol: ProtocolKind::Ts3,
        };

        let backend = backend(
            EventBus::with_default_capacity(),
            SessionId::new(1),
            server,
            None,
        );
        assert_eq!(backend.connection_ref().kind(), ProtocolKind::Ts3);
    }
}
