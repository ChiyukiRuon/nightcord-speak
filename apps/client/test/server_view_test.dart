// The accumulation rules, tested directly.
//
// These mirror the CLI's `view.rs` suite, so the two front-ends cannot quietly
// disagree about what the same event stream means.

import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/models/domain.dart';
import 'package:nightcord_client/models/events.dart';
import 'package:nightcord_client/state/server_view.dart';

ServerView view() => ServerView(session: 1);

void applyAll(ServerView target, List<ClientEvent> events) {
  for (final event in events) {
    target.apply(event);
  }
}

Channel channel(int id, String name, {int? parent, int order = 0}) => Channel(
  id: id,
  name: name,
  parentId: parent,
  order: order,
);

Client client(int id, String name, int channelId) =>
    Client(id: id, name: name, channelId: channelId);

Client clientWithUid(int id, String name, int channelId, String uid) =>
    Client(id: id, name: name, channelId: channelId, uniqueId: uid);

Message message(int id, String content, MessageTarget target, {String from = 'Alice'}) =>
    Message(
      id: id,
      senderName: from,
      target: target,
      content: content,
      timestamp: 0,
    );

void main() {
  group('channel tree', () {
    test('channels nest by parent', () {
      final target = view();
      applyAll(target, [
        ChannelCreatedEvent(channel(1, 'Lobby')),
        ChannelCreatedEvent(channel(2, 'Gaming', parent: 1)),
        ChannelCreatedEvent(channel(3, 'CS2', parent: 2)),
      ]);

      expect(
        target.tree().map((r) => (r.depth, r.channel.name)),
        [(0, 'Lobby'), (1, 'Gaming'), (2, 'CS2')],
      );
    });

    test('siblings follow the server ordering, not arrival order', () {
      final target = view();
      applyAll(target, [
        ChannelCreatedEvent(channel(1, 'Lobby')),
        ChannelCreatedEvent(channel(3, 'Second', parent: 1, order: 20)),
        ChannelCreatedEvent(channel(2, 'First', parent: 1, order: 10)),
      ]);

      expect(
        target.tree().map((r) => r.channel.name),
        ['Lobby', 'First', 'Second'],
      );
    });

    test('equal ordering keys fall back to the id, so the order is stable', () {
      // TeamSpeak's ordering key is not guaranteed unique; without a tie-break
      // the list would reshuffle on every rebuild.
      final target = view();
      applyAll(target, [
        ChannelCreatedEvent(channel(9, 'Nine', order: 5)),
        ChannelCreatedEvent(channel(3, 'Three', order: 5)),
      ]);

      expect(target.tree().map((r) => r.channel.name), ['Three', 'Nine']);
      // And again, to prove it is not just insertion order.
      expect(target.tree().map((r) => r.channel.name), ['Three', 'Nine']);
    });

    test('a channel whose parent is missing is shown at the root', () {
      // A server can send the child first; dropping it would hide a channel.
      final target = view();
      target.apply(ChannelCreatedEvent(channel(5, 'Orphan', parent: 99)));

      expect(target.tree().map((r) => (r.depth, r.channel.name)), [(0, 'Orphan')]);
    });

    test('a removed channel leaves the tree', () {
      final target = view();
      applyAll(target, [
        ChannelCreatedEvent(channel(1, 'Lobby')),
        ChannelCreatedEvent(channel(2, 'Gaming', parent: 1)),
      ]);

      target.apply(const ChannelRemovedEvent(2));
      expect(target.tree().map((r) => r.channel.name), ['Lobby']);
    });

    test('a channel update replaces rather than duplicates', () {
      final target = view();
      applyAll(target, [
        ChannelCreatedEvent(channel(1, 'Lobby')),
        ChannelUpdatedEvent(channel(1, 'Hall')),
      ]);

      expect(target.channels, hasLength(1));
      expect(target.tree().single.channel.name, 'Hall');
    });
  });

  group('clients', () {
    test('clients are grouped by channel and sorted by name', () {
      final target = view();
      applyAll(target, [
        ClientJoinedEvent(client(10, 'Charlie', 1)),
        ClientJoinedEvent(client(11, 'alice', 1)),
        ClientJoinedEvent(client(12, 'Bob', 2)),
      ]);

      // Case-insensitive, so a lowercase name does not sort after every
      // capitalised one.
      expect(target.clientsIn(1).map((c) => c.name), ['alice', 'Charlie']);
      expect(target.clientsIn(2).map((c) => c.name), ['Bob']);
    });

    test('a move reassigns the client', () {
      final target = view();
      target.apply(ClientJoinedEvent(client(10, 'Alice', 1)));

      target.apply(const ClientMovedEvent(clientId: 10, channelId: 7));

      expect(target.clientsIn(1), isEmpty);
      expect(target.clientsIn(7), hasLength(1));
    });

    test('updating a client replaces rather than duplicating', () {
      final target = view();
      target.apply(ClientJoinedEvent(client(10, 'Alice', 1)));
      target.apply(
        ClientUpdatedEvent(const Client(id: 10, name: 'Alice B', channelId: 1)),
      );

      expect(target.clients, hasLength(1));
      expect(target.clients[10]!.name, 'Alice B');
    });

    test('a client that leaves moves to the offline list', () {
      final target = view();
      target.apply(ClientJoinedEvent(client(10, 'Alice', 1)));

      target.apply(const ClientLeftEvent(10));

      expect(target.clients, isEmpty);
      expect(target.offline.map((c) => c.name), ['Alice']);
    });

    test('a returning client leaves the offline list despite a new client id', () {
      // TeamSpeak assigns a fresh client id on every reconnect, so matching on
      // it would leave the old entry in the offline list forever and show one
      // person twice.
      final target = view();
      applyAll(target, [
        ClientJoinedEvent(clientWithUid(10, 'Alice', 1, 'uid-alice')),
        const ClientLeftEvent(10),
      ]);
      expect(target.offline, hasLength(1));

      target.apply(ClientJoinedEvent(clientWithUid(11, 'Alice', 1, 'uid-alice')));
      expect(target.offline, isEmpty, reason: 'the same person came back');
    });

    test('a different person joining does not clear someone else', () {
      final target = view();
      applyAll(target, [
        ClientJoinedEvent(clientWithUid(10, 'Alice', 1, 'uid-alice')),
        const ClientLeftEvent(10),
      ]);

      target.apply(ClientJoinedEvent(clientWithUid(20, 'Bob', 1, 'uid-bob')));
      expect(target.offline.map((c) => c.name), ['Alice']);
    });

    test('without a stable id, the client id is the only thing to match on', () {
      // Server-query clients have no unique id; the fallback must still work.
      final target = view();
      applyAll(target, [
        ClientJoinedEvent(client(10, 'Query', 1)),
        const ClientLeftEvent(10),
      ]);
      expect(target.offline, hasLength(1));

      target.apply(ClientJoinedEvent(client(10, 'Query', 1)));
      expect(target.offline, isEmpty);
    });

    test('our own client is identified and tracked', () {
      final target = view();
      applyAll(target, [
        ChannelCreatedEvent(channel(1, 'Lobby')),
        ClientJoinedEvent(client(10, 'Me', 1)),
        const OwnClientIdentifiedEvent(clientId: 10, channelId: 1),
      ]);

      expect(target.ownClient?.name, 'Me');
      expect(target.ownChannel?.name, 'Lobby');
      expect(target.activeConversation, ConversationKey.channel(1));
    });

    test('our own move updates the active conversation', () {
      final target = view();
      applyAll(target, [
        ChannelCreatedEvent(channel(1, 'Lobby')),
        ChannelCreatedEvent(channel(2, 'Gaming')),
        ClientJoinedEvent(client(10, 'Me', 1)),
        const OwnClientIdentifiedEvent(clientId: 10, channelId: 1),
      ]);

      target.apply(const ClientMovedEvent(clientId: 10, channelId: 2));
      expect(target.activeConversation, ConversationKey.channel(2));
    });

    test('losing our own client clears the identity', () {
      // Otherwise the UI would keep offering to speak in a channel we are no
      // longer in.
      final target = view();
      applyAll(target, [
        ClientJoinedEvent(client(10, 'Me', 1)),
        const OwnClientIdentifiedEvent(clientId: 10, channelId: 1),
      ]);

      target.apply(const ClientLeftEvent(10));
      expect(target.ownClientId, isNull);
      expect(target.ownChannelId, isNull);
    });
  });

  group('server info', () {
    test('connected sets it', () {
      final target = view();
      target.apply(
        const ConnectedEvent(
          server: Server(id: 1, name: 'Test', address: 'example.com', protocol: ProtocolKind.ts3),
          info: ServerInfo(name: 'Real Name'),
        ),
      );

      expect(target.info?.name, 'Real Name');
      expect(target.server?.address, 'example.com');
    });

    test('a connected event marks the session usable', () {
      // Not implied by anything else: without this the switcher labels every
      // live server as disconnected and the composer stays disabled.
      final target = view();
      expect(target.isConnected, isFalse);

      target.apply(
        const ConnectedEvent(
          server: Server(id: 1, name: 'T', address: 'a', protocol: ProtocolKind.ts3),
          info: ServerInfo(name: 'T'),
        ),
      );

      expect(target.isConnected, isTrue);
      expect(target.connection, ConnectionState.connected);
    });

    test('a disconnected event marks it unusable again', () {
      final target = view();
      target.apply(
        const ConnectedEvent(
          server: Server(id: 1, name: 'T', address: 'a', protocol: ProtocolKind.ts3),
          info: ServerInfo(name: 'T'),
        ),
      );

      target.apply(const DisconnectedEvent());
      expect(target.isConnected, isFalse);
    });

    test('a later update corrects the provisional counts', () {
      // The server describes itself before it sends its lists, so the first
      // count is zero and has to be replaced.
      final target = view();
      applyAll(target, [
        const ConnectedEvent(
          server: Server(id: 1, name: 'Test', address: 'example.com', protocol: ProtocolKind.ts3),
          info: ServerInfo(name: 'Test'),
        ),
        const ServerInfoChangedEvent(ServerInfo(name: 'Test', clientsOnline: 3, channelsOnline: 2)),
      ]);

      expect(target.info?.clientsOnline, 3);
      expect(target.info?.channelsOnline, 2);
    });
  });

  group('messages', () {
    test('a channel message lands in that channel thread', () {
      final target = view();
      target.apply(
        MessageReceivedEvent(message(1, 'hello', const ChannelTarget(5))),
      );

      expect(target.messagesIn(ConversationKey.channel(5)), hasLength(1));
      expect(target.messagesIn(ConversationKey.server), isEmpty);
    });

    test('a server message lands in the server thread', () {
      final target = view();
      target.apply(MessageReceivedEvent(message(1, 'hi', MessageTarget.server)));

      expect(target.messagesIn(ConversationKey.server), hasLength(1));
    });

    test('a private message gets its own thread', () {
      final target = view();
      target.apply(MessageReceivedEvent(message(1, 'psst', const ClientTarget(9))));

      expect(target.messagesIn(ConversationKey.client(9)), hasLength(1));
      expect(target.messagesIn(ConversationKey.server), isEmpty);
    });

    test('messages keep arrival order', () {
      final target = view();
      applyAll(target, [
        MessageReceivedEvent(message(1, 'first', MessageTarget.server)),
        MessageReceivedEvent(message(2, 'second', MessageTarget.server)),
      ]);

      expect(
        target.messagesIn(ConversationKey.server).map((m) => m.content),
        ['first', 'second'],
      );
    });
  });

  group('robustness', () {
    test('a reconnect replaying the tree does not duplicate anything', () {
      // The whole tree is re-sent on reconnect, so every event has to be
      // idempotent or the channel list would double.
      final target = view();
      final replay = [
        ChannelCreatedEvent(channel(1, 'Lobby')),
        ChannelCreatedEvent(channel(2, 'Gaming', parent: 1)),
        ClientJoinedEvent(client(10, 'Alice', 1)),
      ];

      applyAll(target, replay);
      applyAll(target, replay);

      expect(target.channels, hasLength(2));
      expect(target.clients, hasLength(1));
      expect(target.tree(), hasLength(2));
    });

    test('an unknown event variant does not disturb the view', () {
      // A newer core may send something this build has never heard of.
      final target = view();
      target.apply(ChannelCreatedEvent(channel(1, 'Lobby')));

      target.apply(const UnknownEvent('something_new'));
      expect(target.tree(), hasLength(1));
    });

    test('interaction events leave the view untouched', () {
      final target = view();
      applyAll(target, [
        ChannelCreatedEvent(channel(1, 'Lobby')),
        MessageReceivedEvent(message(1, 'hello', MessageTarget.server)),
        const PermissionsChangedEvent(Permissions()),
        const CapabilitiesChangedEvent(Capabilities()),
        const ConnectionStateChangedEvent(ConnectionState.connected),
      ]);

      expect(target.tree(), hasLength(1));
      expect(target.clients, isEmpty);
      expect(target.isConnected, isTrue);
    });
  });
}
