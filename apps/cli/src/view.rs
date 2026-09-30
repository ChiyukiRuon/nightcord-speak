//! A front-end's view of one server, built purely from events.
//!
//! This is the pattern every front-end follows (§18): the core never hands out
//! a ready-made tree, it publishes changes, and the front-end accumulates them.
//! The CLI keeps a flat map and prints it; a Flutter app would feed the same
//! events into a Riverpod store.

use std::collections::BTreeMap;

use ts_events::ClientEvent;
use ts_model::{Channel, ChannelId, Client, ClientId, ServerInfo};

/// Everything needed to render one server.
#[derive(Debug, Default)]
pub struct View {
    /// What the server says about itself.
    pub info: Option<ServerInfo>,
    /// Channels, keyed by id. The tree is built from `parent_id` at render time.
    pub channels: BTreeMap<ChannelId, Channel>,
    /// Clients, keyed by id.
    pub clients: BTreeMap<ClientId, Client>,
    /// Our own client id, once the server has told us.
    pub own_client_id: Option<ClientId>,
}

impl View {
    /// Applies one event.
    pub fn apply(&mut self, event: &ClientEvent) {
        match event {
            ClientEvent::Connected { info, .. } | ClientEvent::ServerInfoChanged(info) => {
                self.info = Some(info.clone());
            }

            ClientEvent::ChannelCreated(channel) | ClientEvent::ChannelUpdated(channel) => {
                self.channels.insert(channel.id, channel.clone());
            }
            ClientEvent::ChannelRemoved(id) => {
                self.channels.remove(id);
            }

            ClientEvent::ClientJoined(client) | ClientEvent::ClientUpdated(client) => {
                self.clients.insert(client.id, client.clone());
            }
            ClientEvent::ClientLeft(id) => {
                self.clients.remove(id);
            }
            ClientEvent::ClientMoved {
                client_id,
                channel_id,
            } => {
                if let Some(client) = self.clients.get_mut(client_id) {
                    client.channel_id = *channel_id;
                }
            }

            ClientEvent::OwnClientIdentified {
                client_id,
                channel_id,
            } => {
                self.own_client_id = Some(*client_id);
                if let Some(client) = self.clients.get_mut(client_id) {
                    client.channel_id = *channel_id;
                }
            }

            // Lifecycle and interaction events do not change the view.
            ClientEvent::ConnectionStateChanged(_)
            | ClientEvent::Disconnected
            | ClientEvent::ReconnectScheduled { .. }
            | ClientEvent::PermissionsChanged(_)
            | ClientEvent::CapabilitiesChanged(_)
            | ClientEvent::MessageReceived(_)
            | ClientEvent::Poked { .. }
            | ClientEvent::Speaking(_)
            | ClientEvent::VoiceStateChanged(_)
            | ClientEvent::Error(_) => {}
        }
    }

    /// Every channel, as `(depth, channel)` pairs in tree order.
    ///
    /// Roots first, then their children, recursively. Channels whose parent is
    /// missing are treated as roots rather than being dropped — a server can
    /// send a child before its parent.
    #[must_use]
    pub fn tree(&self) -> Vec<(usize, &Channel)> {
        let mut out = Vec::new();
        let mut children: BTreeMap<Option<ChannelId>, Vec<&Channel>> = BTreeMap::new();

        for channel in self.channels.values() {
            // Treat a dangling parent as a root so the channel stays visible.
            let parent = channel
                .parent_id
                .filter(|id| self.channels.contains_key(id));
            children.entry(parent).or_default().push(channel);
        }

        // Sort siblings by the server's ordering key.
        for siblings in children.values_mut() {
            siblings.sort_by_key(|channel| (channel.order, channel.id));
        }

        let mut stack: Vec<(usize, &Channel)> = children
            .get(&None)
            .into_iter()
            .flatten()
            .rev()
            .map(|channel| (0, *channel))
            .collect();

        while let Some((depth, channel)) = stack.pop() {
            out.push((depth, channel));
            if let Some(descendants) = children.get(&Some(channel.id)) {
                for child in descendants.iter().rev() {
                    stack.push((depth + 1, child));
                }
            }
        }

        out
    }

    /// The channel we are currently in.
    #[must_use]
    pub fn own_channel_id(&self) -> Option<ChannelId> {
        self.own_client_id
            .and_then(|id| self.clients.get(&id))
            .map(|client| client.channel_id)
    }

    /// Clients in `channel_id`, ordered by name.
    #[must_use]
    pub fn clients_in(&self, channel_id: ChannelId) -> Vec<&Client> {
        let mut clients: Vec<&Client> = self
            .clients
            .values()
            .filter(|c| c.channel_id == channel_id)
            .collect();
        // Cached so the lowercased key is computed once per client, not once per
        // comparison.
        clients.sort_by_cached_key(|client| client.name.to_lowercase());
        clients
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ts_model::{Capabilities, MessageTarget, Permissions, ProtocolKind, Server, ServerId};

    fn channel(id: u64, name: &str, parent: Option<u64>, order: i64) -> Channel {
        let mut channel = Channel::new(ChannelId::new(id), name, parent.map(ChannelId::new));
        channel.order = order;
        channel
    }

    fn apply_all(view: &mut View, events: &[ClientEvent]) {
        for event in events {
            view.apply(event);
        }
    }

    #[test]
    fn channels_are_nested_by_parent() {
        let mut view = View::default();
        apply_all(
            &mut view,
            &[
                ClientEvent::ChannelCreated(channel(1, "Lobby", None, 0)),
                ClientEvent::ChannelCreated(channel(2, "Gaming", Some(1), 0)),
                ClientEvent::ChannelCreated(channel(3, "CS2", Some(2), 0)),
            ],
        );

        let tree: Vec<(usize, &str)> = view
            .tree()
            .iter()
            .map(|(depth, c)| (*depth, c.name.as_str()))
            .collect();
        assert_eq!(tree, vec![(0, "Lobby"), (1, "Gaming"), (2, "CS2")]);
    }

    #[test]
    fn siblings_follow_the_server_ordering() {
        let mut view = View::default();
        // Deliberately inserted out of order: the sort key must decide, not the
        // arrival order.
        apply_all(
            &mut view,
            &[
                ClientEvent::ChannelCreated(channel(1, "Lobby", None, 0)),
                ClientEvent::ChannelCreated(channel(3, "Second", Some(1), 20)),
                ClientEvent::ChannelCreated(channel(2, "First", Some(1), 10)),
            ],
        );

        let names: Vec<&str> = view.tree().iter().map(|(_, c)| c.name.as_str()).collect();
        assert_eq!(names, vec!["Lobby", "First", "Second"]);
    }

    #[test]
    fn a_channel_whose_parent_is_missing_is_still_shown() {
        // A server can send the child before the parent; losing the channel
        // would be worse than showing it at the root.
        let mut view = View::default();
        apply_all(
            &mut view,
            &[ClientEvent::ChannelCreated(channel(
                5,
                "Orphan",
                Some(99),
                0,
            ))],
        );

        let tree: Vec<(usize, &str)> = view
            .tree()
            .iter()
            .map(|(depth, c)| (*depth, c.name.as_str()))
            .collect();
        assert_eq!(tree, vec![(0, "Orphan")]);
    }

    #[test]
    fn a_removed_channel_leaves_the_tree() {
        let mut view = View::default();
        apply_all(
            &mut view,
            &[
                ClientEvent::ChannelCreated(channel(1, "Lobby", None, 0)),
                ClientEvent::ChannelCreated(channel(2, "Gaming", Some(1), 0)),
            ],
        );
        view.apply(&ClientEvent::ChannelRemoved(ChannelId::new(2)));

        assert_eq!(view.tree().len(), 1);
    }

    #[test]
    fn clients_are_grouped_by_channel() {
        let mut view = View::default();
        apply_all(
            &mut view,
            &[
                ClientEvent::ChannelCreated(channel(1, "Lobby", None, 0)),
                ClientEvent::ClientJoined(Client::new(
                    ClientId::new(10),
                    "Alice",
                    ChannelId::new(1),
                )),
                ClientEvent::ClientJoined(Client::new(ClientId::new(11), "Bob", ChannelId::new(2))),
            ],
        );

        let names: Vec<&str> = view
            .clients_in(ChannelId::new(1))
            .iter()
            .map(|c| c.name.as_str())
            .collect();
        assert_eq!(names, vec!["Alice"]);
    }

    #[test]
    fn a_move_reassigns_the_client() {
        let mut view = View::default();
        apply_all(
            &mut view,
            &[ClientEvent::ClientJoined(Client::new(
                ClientId::new(10),
                "Alice",
                ChannelId::new(1),
            ))],
        );
        view.apply(&ClientEvent::ClientMoved {
            client_id: ClientId::new(10),
            channel_id: ChannelId::new(7),
        });

        assert!(view.clients_in(ChannelId::new(1)).is_empty());
        assert_eq!(view.clients_in(ChannelId::new(7)).len(), 1);
    }

    #[test]
    fn a_join_after_an_update_replaces_rather_than_duplicates() {
        let mut view = View::default();
        let mut alice = Client::new(ClientId::new(10), "Alice", ChannelId::new(1));
        apply_all(&mut view, &[ClientEvent::ClientJoined(alice.clone())]);

        alice.name = "Alice B".into();
        view.apply(&ClientEvent::ClientUpdated(alice));

        assert_eq!(view.clients.len(), 1);
        assert_eq!(view.clients[&ClientId::new(10)].name, "Alice B");
    }

    #[test]
    fn interaction_events_leave_the_view_untouched() {
        // Guards against a future variant being wired into the wrong arm.
        let mut view = View::default();
        apply_all(
            &mut view,
            &[
                ClientEvent::ChannelCreated(channel(1, "Lobby", None, 0)),
                ClientEvent::MessageReceived(ts_model::Message {
                    id: ts_model::MessageId::new(1),
                    sender: None,
                    sender_name: "Server".into(),
                    target: MessageTarget::Server,
                    content: "welcome".into(),
                    timestamp: 0,
                }),
                ClientEvent::PermissionsChanged(Permissions::all()),
                ClientEvent::CapabilitiesChanged(Capabilities::TS3),
            ],
        );

        assert_eq!(view.tree().len(), 1);
        assert!(view.clients.is_empty());
    }

    #[test]
    fn connected_sets_the_server_info() {
        let mut view = View::default();
        let server = Server {
            id: ServerId::new(1),
            name: "Test".into(),
            address: "example.com:9987".into(),
            protocol: ProtocolKind::Ts3,
        };
        let info = ServerInfo {
            name: "Real Server Name".into(),
            ..ServerInfo::default()
        };

        view.apply(&ClientEvent::Connected { server, info });
        assert_eq!(view.info.unwrap().name, "Real Server Name");
    }
}
