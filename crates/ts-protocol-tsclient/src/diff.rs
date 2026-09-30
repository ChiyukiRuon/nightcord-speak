//! Turning snapshot transitions into domain events.
//!
//! `tsclientlib` reports changes as a stream of fine-grained property edits
//! against its own book. Rather than translate all ~200 property variants, the
//! adapter rebuilds a [`ServerState`] and diffs it against the previous one.
//! That keeps this module small and impossible to desynchronise from the book,
//! at the cost of one walk per update batch — fine for Milestone 0.1, and the
//! obvious thing to optimise if a profile ever shows it (§18).

use ts_events::ClientEvent;
use ts_model::ServerState;

/// Every event implied by moving from `old` to `new`.
///
/// `old` is `None` for the very first snapshot after a handshake, which reports
/// the whole server as newly appeared.
#[must_use]
pub fn between(old: Option<&ServerState>, new: &ServerState) -> Vec<ClientEvent> {
    let mut events = Vec::new();

    match old {
        None => {
            // First snapshot: everything is new. The UI can render immediately
            // instead of waiting for a second event to learn about the server.
            for channel in &new.channels {
                events.push(ClientEvent::ChannelCreated(channel.clone()));
            }
            for client in &new.clients {
                events.push(ClientEvent::ClientJoined(client.clone()));
            }
        }
        Some(old) => {
            diff_channels(old, new, &mut events);
            diff_clients(old, new, &mut events);
        }
    }

    if let Some(client_id) = new.own_client_id {
        if old.and_then(|o| o.own_client_id) != Some(client_id)
            || old.and_then(|o| o.own_channel_id) != new.own_channel_id
        {
            if let Some(channel_id) = new.own_channel_id {
                events.push(ClientEvent::OwnClientIdentified {
                    client_id,
                    channel_id,
                });
            }
        }
    }

    if old.is_none_or(|old| old.permissions != new.permissions) {
        events.push(ClientEvent::PermissionsChanged(new.permissions));
    }

    // Only on a transition. On the first snapshot the counts are necessarily
    // provisional — the server describes itself before it sends its channel and
    // client lists — and `Connected` already carries them. Reporting the change
    // once the lists land is what makes the count correct.
    if let Some(old) = old {
        if old.info != new.info {
            events.push(ClientEvent::ServerInfoChanged(new.info.clone()));
        }
    }

    events
}

fn diff_channels(old: &ServerState, new: &ServerState, events: &mut Vec<ClientEvent>) {
    for channel in &new.channels {
        match old.channel(channel.id) {
            None => events.push(ClientEvent::ChannelCreated(channel.clone())),
            Some(previous) if previous != channel => {
                events.push(ClientEvent::ChannelUpdated(channel.clone()));
            }
            Some(_) => {}
        }
    }

    for channel in &old.channels {
        if new.channel(channel.id).is_none() {
            events.push(ClientEvent::ChannelRemoved(channel.id));
        }
    }
}

fn diff_clients(old: &ServerState, new: &ServerState, events: &mut Vec<ClientEvent>) {
    for client in &new.clients {
        match old.client(client.id) {
            None => events.push(ClientEvent::ClientJoined(client.clone())),
            Some(previous) => {
                if previous.channel_id != client.channel_id {
                    // Report the move as a move. The channel tree needs to
                    // re-parent the client, which a generic "updated" would not
                    // convey.
                    events.push(ClientEvent::ClientMoved {
                        client_id: client.id,
                        channel_id: client.channel_id,
                    });
                } else if previous != client {
                    events.push(ClientEvent::ClientUpdated(client.clone()));
                }
            }
        }
    }

    for client in &old.clients {
        if new.client(client.id).is_none() {
            events.push(ClientEvent::ClientLeft(client.id));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ts_model::{
        Capabilities, Channel, ChannelId, Client, ClientId, Permissions, ProtocolKind, Server,
        ServerId, ServerInfo,
    };

    fn state() -> ServerState {
        ServerState {
            server: Server {
                id: ServerId::new(1),
                name: "Test".into(),
                address: "example.com:9987".into(),
                protocol: ProtocolKind::Ts3,
            },
            info: ServerInfo::default(),
            channels: vec![Channel::new(ChannelId::new(1), "Lobby", None)],
            clients: vec![Client::new(ClientId::new(10), "Alice", ChannelId::new(1))],
            own_client_id: Some(ClientId::new(10)),
            own_channel_id: Some(ChannelId::new(1)),
            permissions: Permissions::none(),
            capabilities: Capabilities::TS3,
        }
    }

    #[test]
    fn first_snapshot_reports_everything_as_new() {
        let events = between(None, &state());
        assert!(
            events
                .iter()
                .any(|e| matches!(e, ClientEvent::ChannelCreated(_)))
        );
        assert!(
            events
                .iter()
                .any(|e| matches!(e, ClientEvent::ClientJoined(_)))
        );
        assert!(
            events
                .iter()
                .any(|e| matches!(e, ClientEvent::PermissionsChanged(_)))
        );
    }

    #[test]
    fn an_unchanged_snapshot_produces_no_events() {
        let state = state();
        // Permissions compare equal, so nothing should be emitted.
        let events = between(Some(&state), &state);
        assert!(events.is_empty(), "unexpected events: {events:?}");
    }

    #[test]
    fn a_new_channel_is_reported_as_created() {
        let old = state();
        let mut new = state();
        new.channels.push(Channel::new(
            ChannelId::new(2),
            "Gaming",
            Some(ChannelId::new(1)),
        ));

        let events = between(Some(&old), &new);
        assert_eq!(events.len(), 1, "got {events:?}");
        assert!(matches!(&events[0], ClientEvent::ChannelCreated(c) if c.name == "Gaming"));
    }

    #[test]
    fn a_removed_channel_is_reported_as_removed() {
        let mut old = state();
        let new = state();
        old.channels
            .push(Channel::new(ChannelId::new(2), "Gaming", None));

        let events = between(Some(&old), &new);
        assert_eq!(events, vec![ClientEvent::ChannelRemoved(ChannelId::new(2))]);
    }

    #[test]
    fn a_channel_rename_is_an_update_not_a_recreate() {
        let old = state();
        let mut new = state();
        new.channels[0].name = "Hall".into();

        let events = between(Some(&old), &new);
        assert_eq!(events.len(), 1, "got {events:?}");
        assert!(matches!(&events[0], ClientEvent::ChannelUpdated(c) if c.name == "Hall"));
    }

    #[test]
    fn joining_client_is_reported_as_joined() {
        let old = state();
        let mut new = state();
        new.clients
            .push(Client::new(ClientId::new(11), "Bob", ChannelId::new(1)));

        let events = between(Some(&old), &new);
        assert!(matches!(&events[0], ClientEvent::ClientJoined(c) if c.name == "Bob"));
    }

    #[test]
    fn leaving_client_is_reported_as_left() {
        let mut old = state();
        let mut new = state();
        old.clients
            .push(Client::new(ClientId::new(11), "Bob", ChannelId::new(1)));
        new.channels[0].clients = vec![ClientId::new(10)];

        let events = between(Some(&old), &new);
        assert!(
            events.contains(&ClientEvent::ClientLeft(ClientId::new(11))),
            "got {events:?}"
        );
    }

    #[test]
    fn a_channel_switch_is_reported_as_a_move_not_an_update() {
        // The distinction matters: only a move tells the tree to re-parent.
        let old = state();
        let mut new = state();
        new.clients[0].channel_id = ChannelId::new(2);
        new.channels.push(Channel::new(
            ChannelId::new(2),
            "Gaming",
            Some(ChannelId::new(1)),
        ));

        let events = between(Some(&old), &new);
        assert!(
            events.iter().any(|e| matches!(
                e,
                ClientEvent::ClientMoved { client_id, channel_id }
                    if *client_id == ClientId::new(10) && *channel_id == ChannelId::new(2)
            )),
            "expected a move, got {events:?}"
        );
    }

    #[test]
    fn a_nickname_change_is_an_update() {
        let old = state();
        let mut new = state();
        new.clients[0].name = "Alice B".into();

        let events = between(Some(&old), &new);
        assert!(matches!(&events[0], ClientEvent::ClientUpdated(c) if c.name == "Alice B"));
    }

    #[test]
    fn late_arriving_counts_are_reported() {
        // Observed against a real server: `Connected` carries the server's
        // self-description from before the channel and client lists arrive, so
        // its counts start at zero and have to be corrected afterwards.
        let mut old = state();
        old.info.clients_online = 0;
        old.info.channels_online = 0;

        let mut new = state();
        new.info.clients_online = 1;
        new.info.channels_online = 1;

        let events = between(Some(&old), &new);
        let Some(ClientEvent::ServerInfoChanged(info)) = events
            .iter()
            .find(|e| matches!(e, ClientEvent::ServerInfoChanged(_)))
        else {
            panic!("expected a server info update, got {events:?}");
        };

        assert_eq!(info.clients_online, 1);
        assert_eq!(info.channels_online, 1);
    }

    #[test]
    fn the_first_snapshot_does_not_repeat_the_info() {
        // `Connected` carries it, so emitting `ServerInfoChanged` too would
        // have every front-end render the same thing twice.
        let events = between(None, &state());
        assert!(
            !events
                .iter()
                .any(|e| matches!(e, ClientEvent::ServerInfoChanged(_))),
            "got {events:?}"
        );
    }

    #[test]
    fn permission_changes_are_reported() {
        let old = state();
        let mut new = state();
        new.permissions = Permissions::all();

        let events = between(Some(&old), &new);
        assert_eq!(
            events,
            vec![ClientEvent::PermissionsChanged(Permissions::all())]
        );
    }
}
