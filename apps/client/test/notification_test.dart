// What is worth interrupting the user for (§43).
//
// No widgets, like `server_view_test.dart` — the policy takes a clock so the
// one time-based rule can be tested without waiting for it (a test that has to
// sleep two seconds is a test that gets deleted), and the sentences as a
// getter, so the rules are tested in one language and the switch is covered
// separately.

import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/l10n/app_localizations.dart';
import 'package:nightcord_client/models/domain.dart';
import 'package:nightcord_client/models/events.dart';
import 'package:nightcord_client/models/settings.dart';
import 'package:nightcord_client/state/notifications.dart';
import 'package:nightcord_client/state/server_view.dart';

/// A clock the test moves by hand.
class TestClock {
  DateTime now = DateTime(2026, 1, 1);

  DateTime call() => now;

  void advance(Duration by) => now = now.add(by);
}

const session = 1;

ServerView view() => ServerView(session: session);

Client client(int id, String name, {int channelId = 1}) =>
    Client(id: id, name: name, channelId: channelId);

/// A server-query connection, which is not a person.
Client queryClient(int id, String name) =>
    Client(id: id, name: name, channelId: 1, clientType: ClientType.query);

Message message(int id, String content, {int? from, String fromName = 'Alice'}) => Message(
  id: id,
  sender: from,
  senderName: fromName,
  target: const ChannelTarget(1),
  content: content,
  timestamp: 0,
);

Message privateMessage(int id, String content, {int? from, String fromName = 'Bob'}) => Message(
  id: id,
  sender: from,
  senderName: fromName,
  target: const ClientTarget(9),
  content: content,
  timestamp: 0,
);

/// The Chinese strings, which is what these assertions were written in.
///
/// The policy itself is language-blind — it asks the getter for a sentence when
/// it needs one — but the tests below pin the actual words, so they say which
/// language they mean. `en` output is covered by the one test that asks for it.
final AppLocalizations zh = lookupAppLocalizations(const Locale('zh'));

/// A policy with everything switched on, and a clock the test drives.
({NotificationPolicy policy, TestClock clock}) policyWith({
  NotificationSettings? settings,
  AppLocalizations? strings,
}) {
  final clock = TestClock();
  final l10n = strings ?? zh;
  return (
    policy: NotificationPolicy(
      settings: settings ?? const NotificationSettings(),
      strings: () => l10n,
      clock: clock.call,
    ),
    clock: clock,
  );
}

/// Establishes a session: first handshake, then past the replay window.
void settle(NotificationPolicy policy, TestClock clock, ServerView target) {
  policy.observe(session, connected(), target, const Attention());
  clock.advance(replayWindow + const Duration(seconds: 1));
}

ConnectedEvent connected() => const ConnectedEvent(
  server: Server(id: 1, name: 'Test', address: 'example.com', protocol: ProtocolKind.ts3),
  info: ServerInfo(name: 'Test'),
);

void main() {
  group('messages', () {
    test('a channel message the user is not looking at is worth saying', () {
      final (:policy, :clock) = policyWith();
      final target = view();
      settle(policy, clock, target);

      final notice = policy.observe(
        session,
        MessageReceivedEvent(message(1, 'hello', from: 9)),
        target,
        const Attention(session: session, conversation: 'channel:2'),
      );

      expect(notice?.kind, NoticeKind.channelMessage);
      expect(notice?.title, 'Alice');
      expect(notice?.body, 'hello');
      expect(notice?.conversation, ConversationKey.channel(1));
      expect(notice?.toast, isTrue);
    });

    test('a message in the thread on screen is not worth saying', () {
      // The whole point of the "don't interrupt" rule: the text is already in
      // front of the user, and a toast would cover it.
      final (:policy, :clock) = policyWith();
      final target = view();
      settle(policy, clock, target);

      final notice = policy.observe(
        session,
        MessageReceivedEvent(message(1, 'hello', from: 9)),
        target,
        const Attention(session: session, conversation: 'channel:1'),
      );

      expect(notice, isNull);
    });

    test('the same thread on another server still interrupts', () {
      // `channel:1` exists on every server; only the one on screen is quiet.
      final (:policy, :clock) = policyWith();
      final target = view();
      settle(policy, clock, target);

      final notice = policy.observe(
        session,
        MessageReceivedEvent(message(1, 'hello', from: 9)),
        target,
        const Attention(session: 2, conversation: 'channel:1'),
      );

      expect(notice, isNotNull);
    });

    test('our own message is never announced', () {
      // The server echoes it back. Whether the library filters those is not
      // visible from here, and being told what you just said is worse than
      // missing a rare case.
      final (:policy, :clock) = policyWith();
      final target = view();
      settle(policy, clock, target);
      target.ownClientId = 9;

      final notice = policy.observe(
        session,
        MessageReceivedEvent(message(1, 'hello', from: 9)),
        target,
        const Attention(session: session, conversation: 'channel:2'),
      );

      expect(notice, isNull);
    });

    test('a private message points at its own thread', () {
      final (:policy, :clock) = policyWith();
      final target = view();
      settle(policy, clock, target);

      final notice = policy.observe(
        session,
        MessageReceivedEvent(privateMessage(1, 'psst', from: 9)),
        target,
        const Attention(session: session, conversation: 'channel:1'),
      );

      expect(notice?.kind, NoticeKind.directMessage);
      expect(notice?.conversation, ConversationKey.client(9));
    });
  });

  group('presence', () {
    test('a join after the replay window is announced by name', () {
      final (:policy, :clock) = policyWith();
      final target = view();
      settle(policy, clock, target);

      final notice = policy.observe(
        session,
        ClientJoinedEvent(client(7, 'Bob')),
        target,
        const Attention(),
      );

      expect(notice?.kind, NoticeKind.presence);
      expect(notice?.title, 'Bob');
    });

    test('a server-query connection joining announces nothing', () {
      // `serveradmin` is on every server for as long as it runs, and comes and
      // goes as the server does. The tree does not draw it, so announcing it
      // would be a notice about somebody the user cannot find or do anything
      // about.
      final (:policy, :clock) = policyWith();
      final target = view();
      settle(policy, clock, target);

      final notice = policy.observe(
        session,
        ClientJoinedEvent(queryClient(9, 'serveradmin')),
        target,
        const Attention(),
      );

      expect(notice, isNull);
    });

    test('a server-query connection leaving announces nothing either', () {
      // The other half, and the one that would otherwise fire on every server
      // restart: the query client disconnects and reconnects, and nobody wants
      // a notice about it.
      final (:policy, :clock) = policyWith();
      final target = view();
      target.apply(ClientJoinedEvent(queryClient(9, 'serveradmin')));
      settle(policy, clock, target);

      final notice = policy.observe(
        session,
        const ClientLeftEvent(9),
        target,
        const Attention(),
      );

      expect(notice, isNull);
    });

    test('the handshake burst announces nobody', () {
      // `diff::between`'s contract is "first snapshot: everything is new", and
      // it runs after *every* handshake — including every reconnect. Without
      // this window, connecting to a busy server announces a hundred arrivals.
      final (:policy, :clock) = policyWith();
      final target = view();

      policy.observe(session, connected(), target, const Attention());

      final notice = policy.observe(
        session,
        ClientJoinedEvent(client(7, 'Bob')),
        target,
        const Attention(),
      );

      expect(notice, isNull);
    });

    test('a reconnect does not announce the whole server again', () {
      // The ids are new after a reconnect, so matching on them would not help:
      // the window is what makes this quiet.
      final (:policy, :clock) = policyWith();
      final target = view();
      settle(policy, clock, target);

      // ...the connection drops and comes back...
      policy.observe(session, connected(), target, const Attention());

      final notice = policy.observe(
        session,
        ClientJoinedEvent(client(99, 'Bob')),
        target,
        const Attention(),
      );

      expect(notice, isNull);
    });

    test('a replayed join for someone already known is not announced', () {
      final (:policy, :clock) = policyWith();
      final target = view();
      settle(policy, clock, target);
      target.apply(ClientJoinedEvent(client(7, 'Bob')));

      final notice = policy.observe(
        session,
        ClientJoinedEvent(client(7, 'Bob')),
        target,
        const Attention(),
      );

      expect(notice, isNull);
    });

    test('a departure names the person, read before the view drops them', () {
      final (:policy, :clock) = policyWith();
      final target = view();
      settle(policy, clock, target);
      target.apply(ClientJoinedEvent(client(7, 'Bob')));

      final notice = policy.observe(
        session,
        const ClientLeftEvent(7),
        target,
        const Attention(),
      );

      expect(notice?.title, 'Bob');
      expect(notice?.body, contains('离开'));
    });
  });

  group('connection', () {
    test('the first handshake is not a recovery', () {
      final (:policy, :clock) = policyWith();

      final notice = policy.observe(session, connected(), view(), const Attention());

      expect(notice, isNull);
    });

    test('a later handshake is a recovery, without a toast', () {
      final (:policy, :clock) = policyWith();
      final target = view();
      settle(policy, clock, target);

      final notice = policy.observe(session, connected(), target, const Attention());

      expect(notice?.kind, NoticeKind.connectionRestored);
      // The reconnect banner already spans the window; a second surface saying
      // the same thing is noise.
      expect(notice?.toast, isFalse);
    });

    test('reconnecting and failing are announced', () {
      for (final state in [ConnectionState.reconnecting, ConnectionState.failed]) {
        final (:policy, :clock) = policyWith();
        final notice = policy.observe(
          session,
          ConnectionStateChangedEvent(state),
          view(),
          const Attention(),
        );
        expect(notice?.kind, NoticeKind.connectionLost, reason: '$state');
        expect(notice?.toast, isFalse, reason: '$state');
      }
    });

    test('the steps along the way are not', () {
      // Connecting, disconnecting and a clean disconnect are things the user
      // either asked for or is watching happen.
      for (final state in [
        ConnectionState.connecting,
        ConnectionState.connected,
        ConnectionState.disconnecting,
        ConnectionState.disconnected,
      ]) {
        final (:policy, :clock) = policyWith();
        expect(
          policy.observe(session, ConnectionStateChangedEvent(state), view(), const Attention()),
          isNull,
          reason: '$state',
        );
      }
    });
  });

  group('the switches', () {
    test('each kind can be turned off', () {
      final target = view();

      for (final (settings, event) in [
        (
          const NotificationSettings(directMessage: false),
          MessageReceivedEvent(privateMessage(1, 'x', from: 9)),
        ),
        (
          const NotificationSettings(channelMessage: false),
          MessageReceivedEvent(message(1, 'x', from: 9)),
        ),
        (const NotificationSettings(poke: false), const PokedEvent(clientId: 9, senderName: 'A', message: 'x')),
        (const NotificationSettings(presence: false), ClientJoinedEvent(client(7, 'A'))),
      ]) {
        final (:policy, :clock) = policyWith(settings: settings);
        settle(policy, clock, target);

        expect(policy.observe(session, event, target, const Attention()), isNull, reason: '$event');
      }
    });

    test('turning one off leaves the others on', () {
      final (:policy, :clock) = policyWith(
        settings: const NotificationSettings(presence: false),
      );
      final target = view();
      settle(policy, clock, target);

      expect(
        policy.observe(session, ClientJoinedEvent(client(7, 'A')), target, const Attention()),
        isNull,
      );
      expect(
        policy.observe(
          session,
          MessageReceivedEvent(message(1, 'x', from: 9)),
          target,
          const Attention(),
        ),
        isNotNull,
      );
    });
  });

  group('things that are never news', () {
    test('a poke carries no thread, because there is no history to open', () {
      final (:policy, :clock) = policyWith();
      final notice = policy.observe(
        session,
        const PokedEvent(clientId: 9, senderName: 'Alice', message: 'hey'),
        view(),
        const Attention(),
      );

      expect(notice?.kind, NoticeKind.poke);
      expect(notice?.conversation, isNull);
    });

    test('state the UI redraws from produces nothing', () {
      // `ServerInfoChanged` is the one worth naming: it fires on almost every
      // join and leave because it carries the online count, so binding a
      // notification to it would double every arrival.
      final (:policy, :clock) = policyWith();
      final target = view();
      settle(policy, clock, target);

      for (final event in [
        const ServerInfoChangedEvent(ServerInfo(name: 'Test', clientsOnline: 3)),
        const OwnClientIdentifiedEvent(clientId: 9, channelId: 1),
        const PermissionsChangedEvent(Permissions()),
        const CapabilitiesChangedEvent(Capabilities()),
        ClientUpdatedEvent(client(7, 'Bob')),
        const ClientMovedEvent(clientId: 7, channelId: 2),
        const DisconnectedEvent(),
        const ReconnectScheduledEvent(attempt: 1, delayMs: 1000),
        const UnknownEvent('something_new'),
      ]) {
        expect(
          policy.observe(session, event, target, const Attention()),
          isNull,
          reason: '$event',
        );
      }
    });
  });

  group('language', () {
    test('the sentences follow the getter, not the language at construction', () {
      // The policy is built once per settings change and lives for the session
      // — rebuilding it on a language switch would re-arm the replay window —
      // so a switch has to be picked up by the strings getter alone.
      final clock = TestClock();
      var l10n = zh;
      final policy = NotificationPolicy(
        settings: const NotificationSettings(),
        strings: () => l10n,
        clock: clock.call,
      );
      final target = view();
      settle(policy, clock, target);

      final before = policy.observe(session, const ClientLeftEvent(7), target, const Attention());
      expect(before?.body, '已离开服务器');

      l10n = lookupAppLocalizations(const Locale('en'));
      final after = policy.observe(session, const ClientLeftEvent(7), target, const Attention());
      expect(after?.body, 'left the server');
    });
  });
}
