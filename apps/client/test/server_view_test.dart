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

Channel channel(int id, String name, {int? parent, int order = 0}) =>
    Channel(id: id, name: name, parentId: parent, order: order);

Client client(int id, String name, int channelId) =>
    Client(id: id, name: name, channelId: channelId);

Client clientWithUid(int id, String name, int channelId, String uid) =>
    Client(id: id, name: name, channelId: channelId, uniqueId: uid);

Message message(int id, String content, MessageTarget target, {String from = 'Alice'}) =>
    Message(id: id, senderName: from, target: target, content: content, timestamp: 0);

void main() {
  group('channel tree', () {
    test('channels nest by parent', () {
      final target = view();
      applyAll(target, [
        ChannelCreatedEvent(channel(1, 'Lobby')),
        ChannelCreatedEvent(channel(2, 'Gaming', parent: 1)),
        ChannelCreatedEvent(channel(3, 'CS2', parent: 2)),
      ]);

      expect(target.tree().map((r) => (r.depth, r.channel.name)), [
        (0, 'Lobby'),
        (1, 'Gaming'),
        (2, 'CS2'),
      ]);
    });

    test('siblings follow the server ordering, not arrival order', () {
      final target = view();
      applyAll(target, [
        ChannelCreatedEvent(channel(1, 'Lobby')),
        ChannelCreatedEvent(channel(3, 'Second', parent: 1, order: 20)),
        ChannelCreatedEvent(channel(2, 'First', parent: 1, order: 10)),
      ]);

      expect(target.tree().map((r) => r.channel.name), ['Lobby', 'First', 'Second']);
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
      target.apply(ClientUpdatedEvent(const Client(id: 10, name: 'Alice B', channelId: 1)));

      expect(target.clients, hasLength(1));
      expect(target.clients[10]!.name, 'Alice B');
    });

    test('a client that leaves is gone, not moved to an offline list', () {
      // It used to be kept, and drawn in an "offline" section of the tree. That
      // read as a roster of who is around with half of it being people who are
      // not, so the name goes with the connection.
      final target = view();
      target.apply(ClientJoinedEvent(client(10, 'Alice', 1)));

      target.apply(const ClientLeftEvent(10));

      expect(target.clients, isEmpty);
      expect(target.offline, isEmpty);
    });

    test('a server-query client is not a member of any channel', () {
      // `serveradmin` sits on every server for as long as it runs. Drawing it
      // beside real users only ever raises the question of what it is.
      final target = view();
      applyAll(target, [
        ClientJoinedEvent(client(10, 'Alice', 1)),
        ClientJoinedEvent(
          const Client(id: 99, name: 'serveradmin', channelId: 1, clientType: ClientType.query),
        ),
      ]);

      expect(target.clientsIn(1).map((c) => c.name), ['Alice']);
    });

    test('a query client that hides among members is still left out', () {
      // The filter is on the client's own type, not on anything about the
      // channel it chose to sit in.
      final target = view();
      target.apply(
        ClientJoinedEvent(
          const Client(id: 99, name: 'serveradmin', channelId: 7, clientType: ClientType.query),
        ),
      );

      expect(target.clientsIn(7), isEmpty);
    });

    test('a message from someone else lands in the thread with them', () {
      // Regression: TS3's private message names its *recipient*, and on a
      // message someone sends us that recipient is us. Keying the thread on it
      // filed everything a person said under a conversation with ourselves —
      // which marked our own row in the tree as unread and left the message
      // somewhere nothing could open.
      final target = view();
      target.apply(ClientJoinedEvent(client(10, 'Alice', 1)));
      target.apply(const OwnClientIdentifiedEvent(clientId: 1, channelId: 1));

      target.apply(
        MessageReceivedEvent(
          Message(
            id: 1,
            sender: 10,
            senderName: 'Alice',
            // The wire field, verbatim: the message was addressed to us.
            target: const ClientTarget(1),
            content: 'hello',
            timestamp: 0,
          ),
        ),
      );

      expect(target.conversations[ConversationKey.client(10)], hasLength(1));
      expect(
        target.conversations[ConversationKey.client(1)],
        isNull,
        reason: 'a conversation with ourselves is one nothing can open',
      );
    });

    test('a message we sent stays in the thread with the other person', () {
      // The other direction, which was already right and must stay so: our own
      // message comes back from the server with the *other* person as the
      // target.
      final target = view();
      target.apply(ClientJoinedEvent(client(10, 'Alice', 1)));
      target.apply(const OwnClientIdentifiedEvent(clientId: 1, channelId: 1));

      target.apply(
        MessageReceivedEvent(
          Message(
            id: 2,
            sender: 1,
            senderName: 'Me',
            target: const ClientTarget(10),
            content: 'hi Alice',
            timestamp: 0,
          ),
        ),
      );

      expect(target.conversations[ConversationKey.client(10)], hasLength(1));
    });

    test('a poke lands in the conversation with whoever sent it', () {
      // A poke is an interaction with a person, and the conversation with them
      // is where the user looks when their client beeps. It used to be shown
      // once as a notice and then lost.
      final target = view();
      target.apply(ClientJoinedEvent(client(10, 'Alice', 1)));

      target.apply(const PokedEvent(clientId: 10, senderName: 'Alice', message: 'wake up'));

      final thread = target.conversations[ConversationKey.client(10)];
      expect(thread, hasLength(1));
      expect(thread!.single.senderName, 'Alice');
      expect(thread.single.content, 'wake up');
      expect(thread.single.isPoke, isTrue, reason: 'not something they typed');
    });

    test('a poke gets an id of its own', () {
      // Two pokes in the same second must not collide in a list keyed by id,
      // and neither may collide with the first real message — whose id the
      // server assigns from one.
      final target = view();
      target.apply(const PokedEvent(clientId: 10, senderName: 'Alice', message: 'one'));
      target.apply(const PokedEvent(clientId: 10, senderName: 'Alice', message: 'two'));

      final thread = target.conversations[ConversationKey.client(10)]!;
      expect(thread, hasLength(2));
      expect(thread.map((m) => m.id).toSet(), hasLength(2));
      expect(thread.every((m) => m.id < 0), isTrue);
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

  group('reconnect', () {
    /// A view that was connected, with something on screen to lose.
    ServerView connectedView() {
      final target = view();
      applyAll(target, [
        const ConnectedEvent(
          server: Server(id: 1, name: 'Test', address: 'example.com', protocol: ProtocolKind.ts3),
          info: ServerInfo(name: 'Test'),
        ),
        ChannelCreatedEvent(channel(1, 'Lobby')),
        ClientJoinedEvent(client(10, 'Alice', 1)),
        MessageReceivedEvent(message(1, 'hello', MessageTarget.server)),
      ]);
      return target;
    }

    test('a scheduled retry is recorded with its attempt and delay', () {
      final target = connectedView();
      target.apply(const ReconnectScheduledEvent(attempt: 3, delayMs: 4000));

      expect(target.reconnect?.attempt, 3);
      expect(target.reconnect?.delayMs, 4000);
      expect(target.reconnect?.secondsLeft, 4);
    });

    test('a drop keeps the tree, the people and the conversation', () {
      // The reason a reconnect is not a crash: the core is putting the same
      // session back, and clearing the screen would throw away the context the
      // user was in the middle of.
      final target = connectedView();

      applyAll(target, [
        const ConnectionStateChangedEvent(ConnectionState.reconnecting),
        const ReconnectScheduledEvent(attempt: 1, delayMs: 1000),
      ]);

      expect(target.isConnected, isFalse);
      expect(target.tree(), hasLength(1));
      expect(target.clients, hasLength(1));
      expect(target.messagesIn(ConversationKey.server), hasLength(1));
      expect(target.info?.name, 'Test');
    });

    test('the connection coming back clears the retry', () {
      // Otherwise the banner would keep counting down to an attempt that has
      // already happened.
      final target = connectedView();
      applyAll(target, [
        const ConnectionStateChangedEvent(ConnectionState.reconnecting),
        const ReconnectScheduledEvent(attempt: 2, delayMs: 2000),
        const ConnectionStateChangedEvent(ConnectionState.connected),
      ]);

      expect(target.reconnect, isNull);
      expect(target.isConnected, isTrue);
    });

    test('a later attempt replaces the one before it', () {
      final target = connectedView();
      applyAll(target, [
        const ReconnectScheduledEvent(attempt: 1, delayMs: 1000),
        const ReconnectScheduledEvent(attempt: 2, delayMs: 2000),
      ]);

      expect(target.reconnect?.attempt, 2);
      expect(target.reconnect?.delayMs, 2000);
    });

    test('an ending session clears the retry', () {
      final target = connectedView();
      applyAll(target, [
        const ReconnectScheduledEvent(attempt: 1, delayMs: 1000),
        const DisconnectedEvent(),
      ]);

      expect(target.reconnect, isNull);
      expect(target.connection, ConnectionState.disconnected);
    });

    test('a drop with no scheduled retry yet shows nothing to count down', () {
      // The core reports `reconnecting` the moment it notices, and only says
      // how long it will wait once it has decided. A banner that invented a
      // number in between would be counting down to a moment nobody chose.
      final target = connectedView();
      target.apply(const ConnectionStateChangedEvent(ConnectionState.reconnecting));

      expect(target.connection, ConnectionState.reconnecting);
      expect(target.reconnect, isNull);
    });

    test('the countdown never goes negative', () {
      // The event can be read after its deadline has passed — a slow frame, or
      // a retry that is already being attempted.
      final target = connectedView();
      target.apply(const ReconnectScheduledEvent(attempt: 1, delayMs: 0));

      expect(target.reconnect?.secondsLeft, 0);
    });
  });

  group('messages', () {
    test('a channel message lands in that channel thread', () {
      final target = view();
      target.apply(MessageReceivedEvent(message(1, 'hello', const ChannelTarget(5))));

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

      expect(target.messagesIn(ConversationKey.server).map((m) => m.content), ['first', 'second']);
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

  group('speaking', () {
    test('local speech follows the audio gate and clears on disconnect', () {
      // Regression: servers do not echo our speech, so our avatar stayed idle.
      final target = view();
      target.ownClientId = 4;
      target.apply(const ConnectionStateChangedEvent(ConnectionState.connected));
      target.apply(const VoiceStateChangedEvent(VoiceState(transmitting: true)));
      expect(target.isSpeaking(4), isTrue);
      expect(target.isSpeaking(5), isFalse);
      target.apply(const VoiceStateChangedEvent(VoiceState()));
      expect(target.isSpeaking(4), isFalse);
      target.apply(const SpeakingEvent(clientId: 5, speaking: true));
      expect(target.isSpeaking(5), isTrue);
      target.apply(const VoiceStateChangedEvent(VoiceState(transmitting: true)));
      target.apply(const DisconnectedEvent());
      expect(target.isSpeaking(4), isFalse);
      expect(target.isSpeaking(5), isFalse);
    });

    test('a name lights up and goes out again', () {
      // Regression: `SpeakingEvent` was parsed and then dropped — and the core
      // never sent it either, so the two failures hid each other and nobody
      // was ever shown as talking. A talking light that only ever goes *on*
      // would be worse than none: names would stay lit for good.
      final target = view();

      target.apply(const SpeakingEvent(clientId: 4, speaking: true));
      expect(target.speaking, contains(4));

      target.apply(const SpeakingEvent(clientId: 4, speaking: false));
      expect(target.speaking, isNot(contains(4)));
    });

    test('someone talking who leaves stops talking', () {
      // The `false` half can be the packet that never arrives — a client that
      // dropped mid-sentence would otherwise leave a lit name behind.
      final target = view();
      target.apply(const SpeakingEvent(clientId: 4, speaking: true));

      target.apply(const ClientLeftEvent(4));
      expect(target.speaking, isNot(contains(4)));
    });

    test('a dropped session clears everyone', () {
      final target = view();
      applyAll(target, [
        const SpeakingEvent(clientId: 4, speaking: true),
        const SpeakingEvent(clientId: 5, speaking: true),
        const DisconnectedEvent(),
      ]);

      expect(target.speaking, isEmpty);
    });
  });
}
