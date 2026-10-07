// What is worth interrupting the user for (§43).
//
// No `BuildContext` and no widget tree, so the rules can be tested directly —
// the same reason `server_view.dart` is written this way. The clock is injected
// for the same reason: one rule is time-based, and a test that has to wait two
// seconds is a test that gets deleted.
//
// The sentences are injected too, as a getter: this class has no context to
// look a translation up from, and a frozen one would keep the old language
// after a switch (see [NotificationPolicy.strings]).
//
// §43 splits the work: "由 Rust Event 产生，Flutter 决定怎么显示". This file is
// the second half. It decides *whether* something is worth telling the user
// about and *what* to say; where it goes — a toast, a badge, the operating
// system — is the caller's business.

import '../l10n/app_localizations.dart';
import '../models/domain.dart';
import '../models/events.dart';
import '../models/settings.dart';
import 'server_view.dart';

/// How long after a handshake joins and leaves are assumed to be the replay.
///
/// The first snapshot after *every* handshake reports every client on the server
/// as newly joined — `diff::between`'s whole contract is "first snapshot:
/// everything is new" — and that happens again on every reconnect. Without this
/// window, connecting to a busy server announces a hundred people arriving.
///
/// Two seconds rather than the CLI's 400 ms: that one only has to cover a burst
/// it is about to print anyway, while this one must not swallow a real join on a
/// slow link. The burst itself is one batch and arrives in well under a second.
const Duration replayWindow = Duration(seconds: 2);

/// What a notice is about. One per kind of thing in §43's list.
enum NoticeKind {
  directMessage,
  channelMessage,
  poke,
  presence,
  connectionLost,
  connectionRestored,
}

/// Something worth telling the user about.
class Notice {
  const Notice({
    required this.kind,
    required this.session,
    required this.title,
    required this.body,
    this.conversation,
    this.toast = true,
  });

  final NoticeKind kind;

  /// Which server this happened on, so a click can switch to it.
  final int session;

  /// Who or what — a name, or a server.
  final String title;

  /// The detail: the message, or what happened.
  final String body;

  /// The thread this belongs to, when there is one to go and look at.
  ///
  /// A `ConversationKey` value — those are strings; the class is a namespace.
  /// Null for pokes (there is no history), for joins and leaves (nobody to
  /// reply to) and for connection changes (nothing to open), which is also
  /// what keeps those out of the unread count.
  final String? conversation;

  /// Whether a toast is worth it.
  ///
  /// Connection changes are not: the reconnect banner is already across the top
  /// of the window, and a second surface saying the same thing is noise.
  final bool toast;
}

/// What the user is looking at, so an event that is already on screen does not
/// interrupt them.
class Attention {
  const Attention({this.session, this.conversation, this.focused = true});

  /// The session on screen, or null on the connect screen.
  final int? session;

  /// The thread on screen, from `ServerView.shownConversation`.
  final String? conversation;

  /// Whether the window is in front.
  final bool focused;

  /// Whether [conversation] on [session] is what the user is looking at.
  bool isLookingAt(int session, String conversation) =>
      this.session == session && this.conversation == conversation;
}

/// Decides what to say about the events going past.
///
/// Stateful for one reason: the replay window needs to know when the last
/// handshake was. Everything else is a pure function of the event and the view.
class NotificationPolicy {
  NotificationPolicy({
    required this.settings,
    required this.strings,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Which kinds of event are worth saying anything about.
  final NotificationSettings settings;

  /// The sentences, fetched when one is needed.
  ///
  /// A getter rather than a ready-made instance: this object is rebuilt only
  /// when the notification switches change, so a frozen language would put the
  /// old language into the next toast. Rebuilding on a switch instead is not an
  /// option — it would reset the handshake timestamps and re-arm the replay
  /// window (a reconnect would then announce everyone all over again).
  final AppLocalizations Function() strings;

  /// Where "now" comes from. Injected so the replay window can be tested
  /// without waiting for it.
  final DateTime Function() _clock;

  /// When each session last finished a handshake.
  final Map<int, DateTime> _connectedAt = {};

  /// Sessions that have completed a handshake at least once, so the *first*
  /// connection is not announced as a recovery.
  final Set<int> _everConnected = {};

  /// Considers one event.
  ///
  /// Call this **before** applying the event to the view: a client on its way
  /// out is still in `view.clients`, and that is the only place its name can be
  /// read from.
  ///
  /// Returns null when there is nothing to say — which is the common case, and
  /// the point of the whole class.
  Notice? observe(int session, ClientEvent event, ServerView? view, Attention attention) {
    switch (event) {
      case ConnectedEvent():
        return _onConnected(session, view);

      case ConnectionStateChangedEvent(:final state):
        return _onConnectionState(session, state, view);

      case MessageReceivedEvent(:final message):
        return _onMessage(session, message, view, attention);

      case PokedEvent(:final senderName, :final message):
        if (!settings.poke) return null;
        return Notice(
          kind: NoticeKind.poke,
          session: session,
          title: senderName,
          body: message,
        );

      case ClientJoinedEvent(:final client):
        // Server-query connections are not people. `serveradmin` is on every
        // server for as long as it runs, so announcing it is noise the user can
        // do nothing about — and the tree does not draw it either.
        if (client.clientType != ClientType.voice) return null;
        // Someone already in the view is the tree being replayed, not a person
        // arriving.
        return _onPresence(
          session,
          view,
          title: client.name,
          body: strings().noticeJoined,
          replayed: view?.clients.containsKey(client.id) ?? false,
        );

      case ClientLeftEvent(:final clientId):
        // Same rule as joining. Read from the view, which still has them: the
        // event has already removed them from it.
        if (view?.clients[clientId]?.clientType != null &&
            view!.clients[clientId]!.clientType != ClientType.voice) {
          return null;
        }
        return _onPresence(
          session,
          view,
          // Read before the view drops them — afterwards the name is gone.
          title: view?.clients[clientId]?.name ?? strings().noticeSomeone,
          body: strings().noticeLeft,
          // Deliberately *not* the "already known" test the join uses: someone
          // on their way out is in the view, and that is the only place their
          // name can still be read from. Only the replay window silences these.
          replayed: false,
        );

      // Everything else is either state the UI redraws from, or an event that
      // fires constantly. `ServerInfoChanged` is the one worth naming: it fires
      // on almost every join and leave, because it carries the online count, so
      // binding a notification to it would double every arrival.
      case ServerInfoChangedEvent():
      case OwnClientIdentifiedEvent():
      case PermissionsChangedEvent():
      case CapabilitiesChangedEvent():
      case ChannelCreatedEvent():
      case ChannelUpdatedEvent():
      case ChannelRemovedEvent():
      case ClientUpdatedEvent():
      case ClientMovedEvent():
      case SpeakingEvent():
      case VoiceStateChangedEvent():
      case ErrorEvent():
      case DisconnectedEvent():
      case ReconnectScheduledEvent():
      case ScreenEvent():
      case UnknownEvent():
        return null;
    }
  }

  Notice? _onConnected(int session, ServerView? view) {
    final first = _everConnected.add(session);
    _connectedAt[session] = _clock();

    // The first handshake is how a session begins, not news. A later one means
    // the connection came back.
    if (first || !settings.connection) return null;

    return Notice(
      kind: NoticeKind.connectionRestored,
      session: session,
      title: view?.server?.displayName ?? strings().noticeServerFallback,
      body: strings().noticeConnectionRestored,
      // The banner across the window already says so.
      toast: false,
    );
  }

  Notice? _onConnectionState(int session, ConnectionState state, ServerView? view) {
    if (!settings.connection) return null;

    // Only the states that mean "this stopped working". `Connecting` and
    // `Disconnecting` are steps, and `Disconnected` is a clean end the user
    // asked for.
    final lost = switch (state) {
      ConnectionState.reconnecting => strings().noticeReconnecting,
      ConnectionState.failed => strings().noticeConnectionFailed,
      _ => null,
    };
    if (lost == null) return null;

    return Notice(
      kind: NoticeKind.connectionLost,
      session: session,
      title: view?.server?.displayName ?? strings().noticeServerFallback,
      body: lost,
      // The reconnect banner is on screen for exactly as long as this lasts.
      toast: false,
    );
  }

  Notice? _onMessage(int session, Message message, ServerView? view, Attention attention) {
    // Our own message, echoed back by the server. Whether the library filters
    // these is not something this side can see — `publish_book_event` has no
    // check on the invoker — and a client that notifies you about what you just
    // said is worse than one that misses a rare case.
    //
    // By id rather than by name: two people on a server can share a nickname.
    final own = view?.ownClientId;
    if (message.sender != null && message.sender == own) return null;

    final conversation = ConversationKey.of(message, view?.ownClientId);
    final private = message.isPrivate;

    if (private ? !settings.directMessage : !settings.channelMessage) return null;
    if (attention.isLookingAt(session, conversation)) return null;

    return Notice(
      kind: private ? NoticeKind.directMessage : NoticeKind.channelMessage,
      session: session,
      title: message.senderName,
      body: message.content,
      conversation: conversation,
    );
  }

  Notice? _onPresence(
    int session,
    ServerView? view, {
    required String title,
    required String body,
    required bool replayed,
  }) {
    if (!settings.presence) return null;
    if (replayed) return null;
    if (_isReplaying(session)) return null;

    // No conversation: there is nobody to reply to, and a join is not unread
    // anything.
    return Notice(
      kind: NoticeKind.presence,
      session: session,
      title: title,
      body: body,
    );
  }

  /// Whether [session] is still inside the window where joins are the replay.
  bool _isReplaying(int session) {
    final at = _connectedAt[session];
    if (at == null) return false;
    return _clock().difference(at) < replayWindow;
  }
}
