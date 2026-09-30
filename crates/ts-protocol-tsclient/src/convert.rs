//! Translating the `tsclientlib` book into the domain model.
//!
//! Every TS3-shaped value stops here. Above this module nothing knows what a
//! book, a channel-order pointer or a permission hint is (§53, §54).

use ts_model::{
    Capabilities, Channel, ChannelId, Client, ClientFlags, ClientId, ClientType, Permissions,
    Server, ServerInfo, ServerState,
};

use tsclientlib::data::{
    Channel as BookChannel, Client as BookClient, Connection as BookConnection,
};
use tsclientlib::{ChannelPermissionHint, ChannelType, ClientPermissionHint, MaxClients};

/// Builds a full snapshot of a server from the protocol library's book.
///
/// Called after the handshake and after every batch of book changes. Rebuilding
/// wholesale rather than patching in place is deliberate for Milestone 0.1: it
/// cannot drift out of sync with the book, and a server with a few hundred
/// channels is cheap to walk. Per-entity incremental updates are the obvious
/// optimisation once this shows up in a profile.
#[must_use]
pub fn snapshot(book: &BookConnection, server: Server) -> ServerState {
    // Read before `server` is moved into the state below.
    let protocol = server.protocol;

    let mut channels: Vec<Channel> = book
        .channels
        .iter()
        .map(|(id, channel)| channel_of(*id, channel))
        .collect();
    let clients: Vec<Client> = book
        .clients
        .iter()
        .map(|(id, client)| client_of(*id, client, book.own_client))
        .collect();

    // Attach occupants so the channel tree can render its children without a
    // second pass over every client.
    let mut by_channel: std::collections::HashMap<tsclientlib::ChannelId, Vec<ClientId>> =
        std::collections::HashMap::new();
    for client in &clients {
        by_channel
            .entry(tsclientlib::ChannelId(client.channel_id.get()))
            .or_default()
            .push(client.id);
    }
    for channel in &mut channels {
        channel.clients = by_channel
            .remove(&tsclientlib::ChannelId(channel.id.get()))
            .unwrap_or_default();
    }

    let own_client_id = ClientId::new(book.own_client.0);
    let own_channel_id = clients
        .iter()
        .find(|c| c.id == own_client_id)
        .map(|c| c.channel_id);

    ServerState {
        server,
        info: server_info(book),
        channels,
        clients,
        own_client_id: Some(own_client_id),
        own_channel_id,
        permissions: permissions(book),
        // Taken from the server's own kind rather than hard-coded: the same
        // adapter serves TS3 and TS6, and the two differ in what they offer.
        capabilities: Capabilities::for_protocol(protocol),
    }
}

/// Reads the server's self-description out of the book.
#[must_use]
pub fn server_info(book: &BookConnection) -> ServerInfo {
    let server = &book.server;
    ServerInfo {
        name: server.name.clone(),
        // The book always carries these as strings; an empty one means "unset".
        welcome_message: non_empty(&server.welcome_message),
        platform: non_empty(&server.platform),
        version: non_empty(&server.version),
        max_clients: u32::from(server.max_clients),
        clients_online: book.clients.len() as u32,
        channels_online: book.channels.len() as u32,
        // Not part of the book — it comes from the server-variables query, which
        // Milestone 0.1 does not make. Left absent rather than guessed.
        uptime: None,
    }
}

/// Converts one book channel.
#[must_use]
fn channel_of(id: tsclientlib::ChannelId, channel: &BookChannel) -> Channel {
    Channel {
        id: ChannelId::new(id.0),
        name: channel.name.clone(),
        parent_id: parent_of(channel.parent),
        // TS3's `channel_order` is the id of the channel that sorts *after* this
        // one, not a rank. It is a stable key but not a directly sortable value;
        // see the note in `docs/architecture.md`.
        order: channel.order.0 as i64,
        clients: Vec::new(),
        description: None,
        topic: channel.topic.clone(),
        has_password: channel.has_password.unwrap_or(false),
        is_default: channel.is_default.unwrap_or(false),
        is_permanent: matches!(channel.channel_type, ChannelType::Permanent),
        max_clients: channel.max_clients.and_then(max_clients_of),
    }
}

/// Converts one book client.
#[must_use]
fn client_of(id: tsclientlib::ClientId, client: &BookClient, own: tsclientlib::ClientId) -> Client {
    Client {
        id: ClientId::new(id.0),
        name: client.name.clone(),
        channel_id: ChannelId::new(client.channel.0),
        flags: ClientFlags {
            // An away *message* is how the book records being away; there is no
            // separate boolean.
            away: client.away_message.is_some(),
            input_muted: client.input_muted,
            output_muted: client.output_muted,
            recording: client.is_recording,
            channel_commander: client.is_channel_commander,
        },
        unique_id: client.uid.as_ref().map(|uid| base64_encode(&uid.0)),
        // The book does not report the TS3 client type, so query clients are
        // indistinguishable here. Cosmetic only: nothing branches on it yet.
        client_type: ClientType::Voice,
        is_self: id == own,
    }
}

/// Reads what we are allowed to do from the book's permission hints.
///
/// Absent hints mean *unknown*, and unknown is read as allowed.
///
/// The hints are a summary the server sends so a client can grey out actions
/// without a round trip per permission — but they are optional. Treating their
/// absence as denial is how the message composer ended up disabled on servers
/// that simply do not volunteer them: it hid an action the user could perform.
///
/// The server stays the authority either way. It refuses with a proper error,
/// and that error reaches the user; greying out something that would have
/// worked gives them no way to find out.
#[must_use]
pub fn permissions(book: &BookConnection) -> Permissions {
    let own = book.clients.get(&book.own_client);
    let channel = own.and_then(|client| book.channels.get(&client.channel));

    permissions_from(
        channel.and_then(|c| c.permission_hints),
        own.and_then(|c| c.permission_hints),
    )
}

/// Maps the two hint sets onto the domain's permissions.
///
/// Split out from [`permissions`] so the rule above can be tested without
/// constructing a whole `BookConnection` — see `absent_hints_read_as_allowed`.
fn permissions_from(
    channel_hints: Option<ChannelPermissionHint>,
    client_hints: Option<ClientPermissionHint>,
) -> Permissions {
    Permissions {
        // `is_none_or` reads as "no hints, or hints that include the bit".
        can_join_channel: channel_hints.is_none_or(|h| h.contains(ChannelPermissionHint::JOIN)),
        can_move_clients: client_hints
            .is_none_or(|h| h.contains(ClientPermissionHint::MOVE_CLIENT)),
        // Posting in a channel we are subscribed to is the closest hint TS3
        // offers; there is no dedicated "send channel message" hint.
        can_send_channel_message: channel_hints
            .is_none_or(|h| h.contains(ChannelPermissionHint::SUBSCRIBE)),
        can_send_private_message: client_hints
            .is_none_or(|h| h.contains(ClientPermissionHint::PRIVATE_MESSAGE)),
        can_kick: client_hints.is_none_or(|h| {
            h.intersects(ClientPermissionHint::KICK_SERVER | ClientPermissionHint::KICK_CHANNEL)
        }),
        can_ban: client_hints.is_none_or(|h| h.contains(ClientPermissionHint::BAN)),
    }
}

fn max_clients_of(value: MaxClients) -> Option<u32> {
    match value {
        MaxClients::Limited(limit) => Some(u32::from(limit)),
        // Both mean "no limit of its own". `Inherited` delegates to the parent
        // channel, which the UI resolves by walking up the tree.
        MaxClients::Unlimited | MaxClients::Inherited => None,
    }
}

/// Maps TS3's `pid` field onto an optional parent.
///
/// TS3 signals "no parent" with a zero id rather than an absent field.
fn parent_of(parent: tsclientlib::ChannelId) -> Option<ChannelId> {
    match parent.0 {
        0 => None,
        id => Some(ChannelId::new(id)),
    }
}

fn non_empty(value: &str) -> Option<String> {
    if value.is_empty() {
        None
    } else {
        Some(value.to_string())
    }
}

fn base64_encode(bytes: &[u8]) -> String {
    use base64::Engine as _;
    base64::engine::general_purpose::STANDARD.encode(bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_strings_become_none() {
        assert_eq!(non_empty(""), None);
        assert_eq!(non_empty("on"), Some("on".to_string()));
    }

    #[test]
    fn only_an_explicit_limit_is_reported() {
        assert_eq!(max_clients_of(MaxClients::Limited(32)), Some(32));
        // Both of these mean "no limit of its own", so the UI shows no cap
        // rather than inventing one.
        assert_eq!(max_clients_of(MaxClients::Unlimited), None);
        assert_eq!(max_clients_of(MaxClients::Inherited), None);
    }

    #[test]
    fn zero_parent_means_root() {
        // Guards the TS3 convention that a root channel names parent id 0
        // rather than omitting the field.
        assert_eq!(parent_of(tsclientlib::ChannelId(0)), None);
        assert_eq!(
            parent_of(tsclientlib::ChannelId(7)),
            Some(ChannelId::new(7))
        );
    }

    #[test]
    fn absent_hints_read_as_allowed() {
        // Regression: hints are optional, and reading their absence as a denial
        // is how the message composer ended up disabled on servers that simply
        // do not volunteer them. The server stays the authority — it refuses
        // with an error the user can see — so unknown must mean allowed.
        assert_eq!(permissions_from(None, None), Permissions::all());
    }

    #[test]
    fn present_hints_are_taken_at_their_word() {
        // The other half: once the server does volunteer hints, an unset bit is
        // a real answer, not a missing one.
        let permissions = permissions_from(
            Some(ChannelPermissionHint::JOIN | ChannelPermissionHint::SUBSCRIBE),
            Some(ClientPermissionHint::KICK_CHANNEL),
        );

        assert_eq!(
            permissions,
            Permissions {
                can_join_channel: true,
                can_send_channel_message: true,
                // Either kick hint on its own is enough.
                can_kick: true,
                ..Permissions::none()
            }
        );
    }
}
