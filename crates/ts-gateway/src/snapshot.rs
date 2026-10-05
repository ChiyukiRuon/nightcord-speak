//! A domain-only projection for browsers joining an already-running gateway.
//!
//! This is presentation state, not another core. Chat history and transient
//! notifications are deliberately not replayed when a page is refreshed.

use std::collections::BTreeMap;

use ts_events::ClientEvent;
use ts_model::{ChannelId, ClientId, SessionId};
use ts_wire::FfiEvent;

#[derive(Default)]
pub(crate) struct Snapshots {
    sessions: BTreeMap<SessionId, SessionSnapshot>,
}

#[derive(Default)]
struct SessionSnapshot {
    connected: Option<ClientEvent>,
    info: Option<ClientEvent>,
    state: Option<ClientEvent>,
    own: Option<ClientEvent>,
    permissions: Option<ClientEvent>,
    capabilities: Option<ClientEvent>,
    voice: Option<ClientEvent>,
    channels: BTreeMap<ChannelId, ClientEvent>,
    clients: BTreeMap<ClientId, ClientEvent>,
}

impl Snapshots {
    pub(crate) fn apply(&mut self, id: SessionId, event: &ClientEvent) {
        if matches!(event, ClientEvent::Disconnected) {
            self.sessions.remove(&id);
            return;
        }
        let session = self.sessions.entry(id).or_default();
        match event {
            ClientEvent::Connected { .. } => {
                *session = SessionSnapshot::default();
                session.connected = Some(event.clone());
            }
            ClientEvent::ServerInfoChanged(_) => session.info = Some(event.clone()),
            ClientEvent::ConnectionStateChanged(_) => session.state = Some(event.clone()),
            ClientEvent::OwnClientIdentified { .. } => session.own = Some(event.clone()),
            ClientEvent::PermissionsChanged(_) => session.permissions = Some(event.clone()),
            ClientEvent::CapabilitiesChanged(_) => session.capabilities = Some(event.clone()),
            ClientEvent::VoiceStateChanged(_) => session.voice = Some(event.clone()),
            ClientEvent::ChannelCreated(channel) | ClientEvent::ChannelUpdated(channel) => {
                session
                    .channels
                    .insert(channel.id, ClientEvent::ChannelCreated(channel.clone()));
            }
            ClientEvent::ChannelRemoved(id) => {
                session.channels.remove(id);
            }
            ClientEvent::ClientJoined(client) | ClientEvent::ClientUpdated(client) => {
                session
                    .clients
                    .insert(client.id, ClientEvent::ClientJoined(client.clone()));
            }
            ClientEvent::ClientLeft(id) => {
                session.clients.remove(id);
            }
            ClientEvent::ClientMoved {
                client_id,
                channel_id,
            } => {
                if let Some(ClientEvent::ClientJoined(client)) = session.clients.get_mut(client_id)
                {
                    client.channel_id = *channel_id;
                }
                if let Some(ClientEvent::OwnClientIdentified {
                    client_id: own,
                    channel_id: channel,
                }) = session.own.as_mut()
                    && own == client_id
                {
                    *channel = *channel_id;
                }
            }
            // Transient events do not belong in a late subscriber's snapshot.
            _ => {}
        }
    }

    pub(crate) fn events(&self) -> Vec<FfiEvent> {
        let mut result = Vec::new();
        for (id, session) in &self.sessions {
            for event in session
                .connected
                .iter()
                .chain(session.info.iter())
                .chain(session.channels.values())
                .chain(session.clients.values())
                .chain(session.own.iter())
                .chain(session.permissions.iter())
                .chain(session.capabilities.iter())
                .chain(session.voice.iter())
                .chain(session.state.iter())
            {
                result.push(FfiEvent::client(*id, event.clone()));
            }
            result.push(FfiEvent::ok("connect", Some(*id)));
        }
        result
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ts_model::{Channel, Client, ConnectionState};

    #[test]
    fn refresh_gets_current_members_and_channels_without_replaying_notifications() {
        // Previously, refreshing a browser left an empty tree even while the
        // gateway remained connected; replaying all history would repeat chat.
        let mut snapshots = Snapshots::default();
        let session = SessionId::new(1);
        snapshots.apply(
            session,
            &ClientEvent::ChannelCreated(Channel::new(ChannelId::new(1), "old", None)),
        );
        snapshots.apply(session, &ClientEvent::ChannelRemoved(ChannelId::new(1)));
        snapshots.apply(
            session,
            &ClientEvent::ClientJoined(Client::new(ClientId::new(2), "member", ChannelId::new(1))),
        );
        snapshots.apply(
            session,
            &ClientEvent::OwnClientIdentified {
                client_id: ClientId::new(2),
                channel_id: ChannelId::new(1),
            },
        );
        snapshots.apply(
            session,
            &ClientEvent::ClientMoved {
                client_id: ClientId::new(2),
                channel_id: ChannelId::new(3),
            },
        );
        snapshots.apply(
            session,
            &ClientEvent::ConnectionStateChanged(ConnectionState::Connected),
        );
        let events = serde_json::to_value(snapshots.events()).expect("serialises");
        let events = events.as_array().expect("array");
        assert_eq!(events.len(), 4);
        assert_eq!(events[0]["event"]["payload"]["channel_id"], 3);
        assert_eq!(events[1]["event"]["payload"]["channel_id"], 3);
        snapshots.apply(session, &ClientEvent::Disconnected);
        assert!(snapshots.events().is_empty());
    }
}
