// The front-end's view of one server, accumulated from events.
//
// Pure Dart with no Flutter dependency, so the accumulation rules can be tested
// directly. This is the same design as the CLI's `view.rs`: the core publishes
// changes and the front-end holds the current picture (§18), rather than the
// core handing out a ready-made tree.

import '../models/domain.dart';
import '../models/events.dart';

/// Identifies a chat thread.
///
/// Server chat, one channel, or a private conversation. A string rather than a
/// sealed type because it is only ever a map key.
abstract final class ConversationKey {
  /// The server-wide thread.
  static const String server = 'server';

  /// A channel's thread.
  static String channel(int id) => 'channel:$id';

  /// A private thread with one client.
  static String client(int id) => 'client:$id';

  /// The thread a message belongs to.
  ///
  /// A private message names its **recipient**, and on a message someone sends
  /// us that recipient is *us*: keying the thread on it filed everything a
  /// person said into a conversation with ourselves — a thread nothing can open,
  /// marked unread on our own row in the tree. The thread belongs to the other
  /// party, so that is what this resolves to, and `ownClientId` is what tells
  /// the two directions apart.
  static String of(Message message, int? ownClientId) => switch (message.target) {
    ServerTarget() => server,
    ChannelTarget(:final channelId) => channel(channelId),
    ClientTarget(:final clientId) => client(
      clientId == ownClientId ? (message.sender ?? clientId) : clientId,
    ),
  };
}

/// A retry the core has scheduled, while a dropped session recovers.
///
/// Only ever set between `reconnect_scheduled` and the connection coming back.
class ReconnectProgress {
  /// Records a scheduled retry.
  ReconnectProgress({required this.attempt, required this.delayMs})
    : due = DateTime.now().add(Duration(milliseconds: delayMs));

  /// 1 for the first retry.
  final int attempt;

  /// How long the core said it would wait.
  final int delayMs;

  /// When that wait is up.
  ///
  /// Kept as a deadline rather than as the raw delay because the banner counts
  /// down, and "4 秒后" is wrong one second after it is drawn.
  final DateTime due;

  /// Whole seconds left, never negative.
  int get secondsLeft {
    final left = due.difference(DateTime.now()).inMilliseconds;
    return left <= 0 ? 0 : (left / 1000).ceil();
  }
}

/// One channel with the depth it sits at, ready to render as a flat list.
class TreeRow {
  const TreeRow({required this.depth, required this.channel, required this.hasChildren});

  /// Zero for a root channel.
  final int depth;
  final Channel channel;

  /// Whether sub-channels exist beneath this one.
  ///
  /// The widget uses it to decide between a collapsible category header and a
  /// plain channel row.
  final bool hasChildren;
}

/// Everything the UI needs to render one server.
class ServerView {
  ServerView({required this.session});

  /// The handle this view is for.
  final int session;

  Server? server;
  ServerInfo? info;
  ConnectionState connection = ConnectionState.disconnected;

  /// The retry the core has scheduled, while a dropped session recovers.
  ///
  /// Null whenever none is pending. The banner keys off [connection] to decide
  /// whether to appear at all and uses this only to say how long is left — a
  /// session that is reconnecting but has not yet been given a delay still has
  /// something worth saying.
  ReconnectProgress? reconnect;

  final Map<int, Channel> channels = {};
  final Map<int, Client> clients = {};

  /// Who is talking right now.
  ///
  /// A set here rather than a flag on [Client] because speaking is not a
  /// property of a person — it flips several times a second — and a flag would
  /// be carried into every snapshot diff as though it were one. It is also why
  /// the core sends it as a pair of events: an indicator that fails to go out
  /// leaves a name lit for good.
  final Set<int> speaking = {};

  /// The next id for something that never came from the server.
  ///
  /// Counts down from zero while the server counts up from one, so the two can
  /// never meet. A counter rather than a clock because two pokes can arrive in
  /// the same millisecond, and a list keyed by a duplicated id loses one of
  /// them.
  int _nextSyntheticId = 0;

  /// Messages by [ConversationKey].
  final Map<String, List<Message>> conversations = {};

  int? ownClientId;
  int? ownChannelId;
  Permissions permissions = const Permissions();
  Capabilities capabilities = const Capabilities();

  /// Our own voice configuration, as the core reports it.
  ///
  /// Driven by `voice_state_changed` events rather than by the buttons: the
  /// core owns the state, and a toggle that failed should not leave the UI
  /// claiming otherwise.
  VoiceState voice = const VoiceState();

  /// Clients that have gone offline.
  ///
  /// Deliberately never populated. TeamSpeak reports only connected clients, so
  /// a user who disconnects simply vanishes — and an earlier version kept the
  /// last known name in this list and drew an "offline" section in the tree.
  /// It read as a roster of who is around with half of it being people who are
  /// not, which is worse than the name being gone. The field survives so that
  /// [apply] can keep clearing it without a special case.
  final List<Client> offline = [];

  /// Whether the session is usable right now.
  bool get isConnected => connection == ConnectionState.connected;

  /// Our own client record, once the server has identified us.
  Client? get ownClient => ownClientId == null ? null : clients[ownClientId];

  /// Local speech comes from the audio gate, since servers do not echo it.
  bool isSpeaking(int clientId) =>
      isConnected && (clientId == ownClientId ? voice.transmitting : speaking.contains(clientId));

  /// The channel we are in.
  Channel? get ownChannel => ownChannelId == null ? null : channels[ownChannelId];

  /// The channels in tree order, for a picker that has no room for depht.
  ///
  /// Flat rather than nested because every consumer so far is a dropdown; a
  /// tree would be the right shape for a tree control, and there is not one.
  List<Channel> get channelsInTreeOrder => tree().map((row) => row.channel).toList(growable: false);

  /// Per-person playback gains the user has set this session.
  ///
  /// A memory of what we asked the core for, not a report of what it is doing:
  /// the core answers `set_client_volume` with nothing but success, and the
  /// alternative — a round trip to read one number back — would buy accuracy
  /// only in the case where the core rejected a value in range, which it does
  /// not. Cleared with the session, because a client id does not outlive it.
  final Map<int, double> clientVolumes = {};

  /// One client's gain, defaulting to unity.
  double clientVolume(int clientId) => clientVolumes[clientId] ?? 1.0;

  /// Records a gain the user just set.
  void setClientVolume(int clientId, double volume) {
    clientVolumes[clientId] = volume;
  }

  /// The channels we can see, as a flat list in tree order.
  ///
  /// Roots first, then their descendants, recursively. A channel whose parent is
  /// missing is treated as a root rather than dropped — a server can send a
  /// child before its parent.
  ///
  /// [isCollapsed] hides a channel's descendants while keeping the channel
  /// itself, which is what the sidebar's disclosure triangles need. It is a
  /// parameter rather than view state because collapsing is purely how the tree
  /// is being displayed, not something about the server.
  List<TreeRow> tree({bool Function(Channel channel)? isCollapsed}) {
    final children = <int?, List<Channel>>{};
    for (final channel in channels.values) {
      // A dangling parent is treated as no parent, so the channel stays visible.
      final parent = (channel.parentId != null && channels.containsKey(channel.parentId))
          ? channel.parentId
          : null;
      children.putIfAbsent(parent, () => []).add(channel);
    }

    // The server's ordering key, with the id as a tie-break so the order is
    // stable when two channels share one.
    for (final siblings in children.values) {
      siblings.sort((a, b) {
        final byOrder = a.order.compareTo(b.order);
        return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
      });
    }

    final rows = <TreeRow>[];
    void visit(int? parent, int depth) {
      for (final channel in children[parent] ?? const <Channel>[]) {
        final hasChildren = (children[channel.id] ?? const <Channel>[]).isNotEmpty;
        rows.add(TreeRow(depth: depth, channel: channel, hasChildren: hasChildren));

        if (hasChildren && (isCollapsed?.call(channel) ?? false)) continue;
        visit(channel.id, depth + 1);
      }
    }

    visit(null, 0);
    return rows;
  }

  /// The clients in one channel, ordered by name.
  ///
  /// Server-query connections are left out. `serveradmin` is a query client
  /// that sits on every server for as long as it is running, so listing it
  /// beside real users only ever raises the question of what it is. The
  /// official client hides them for the same reason.
  List<Client> clientsIn(int channelId) {
    final members =
        clients.values
            .where((c) => c.clientType == ClientType.voice && c.channelId == channelId)
            .toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return members;
  }

  /// The messages in one thread, oldest first.
  List<Message> messagesIn(String conversation) => conversations[conversation] ?? const <Message>[];

  /// The thread the UI should be showing: the channel we are in.
  String get activeConversation =>
      ownChannelId == null ? ConversationKey.server : ConversationKey.channel(ownChannelId!);

  /// The thread the user opened by hand, or null to follow [activeConversation].
  ///
  /// Opening a private conversation has to survive the channel we are in
  /// changing underneath it — walking into another channel should not yank the
  /// user out of a conversation they were reading.
  String? openConversation;

  /// Threads with something new in them that the user has not looked at.
  ///
  /// Deliberately not "everything that arrived": a message in the thread on
  /// screen has been seen, so marking it would be a lie — and a badge that is
  /// always lit is not a badge.
  final Set<String> unread = {};

  /// The thread the UI is actually showing.
  String get shownConversation => openConversation ?? activeConversation;

  /// Shows [conversation], and treats it as read.
  void open(String conversation) {
    openConversation = conversation;
    unread.remove(conversation);
  }

  /// Goes back to following the channel we are in.
  void closeConversation() {
    openConversation = null;
    unread.remove(activeConversation);
  }

  /// Marks [conversation] as having something new.
  void markUnread(String conversation) {
    if (conversation == shownConversation) return;
    unread.add(conversation);
  }

  /// Whether anything is unread anywhere in this session.
  bool get hasUnread => unread.isNotEmpty;

  /// Whether a channel has anything unread.
  ///
  /// Its own thread, or any private conversation with someone sitting in it —
  /// a dot on the channel is how a user finds the person who messaged them.
  bool channelHasUnread(int channelId) {
    if (unread.contains(ConversationKey.channel(channelId))) return true;
    for (final id in unread) {
      if (!id.startsWith('client:')) continue;
      final clientId = int.tryParse(id.substring('client:'.length));
      if (clientId != null && clients[clientId]?.channelId == channelId) return true;
    }
    return false;
  }

  /// Applies one event.
  ///
  /// Idempotent for every variant: replaying the same event twice leaves the
  /// view unchanged, which matters because a reconnect re-sends the whole tree.
  void apply(ClientEvent event) {
    switch (event) {
      case ConnectedEvent(:final server, :final info):
        this.server = server;
        this.info = info;
        // A `connected` event *is* the connected state. Deriving it here rather
        // than relying on a separate `connection_state_changed` matters: the
        // switcher showed every live server as 「未连接」, and the composer
        // stayed disabled, because nothing else ever set this.
        connection = ConnectionState.connected;
        // Whatever was being retried has arrived, and the countdown that was
        // running for it is about a moment that has passed.
        reconnect = null;

      case ServerInfoChangedEvent(:final info):
        this.info = info;

      case ConnectionStateChangedEvent(:final state):
        connection = state;
        // A scheduled retry only means anything while the session is actually
        // recovering. Any other state supersedes it — including the next attempt
        // starting, which would otherwise leave the previous delay on screen.
        if (state != ConnectionState.reconnecting) reconnect = null;

      case DisconnectedEvent():
        connection = ConnectionState.disconnected;
        reconnect = null;
        // Nobody is talking on a connection that is gone, and the last
        // `speaking: false` may have been the packet that never arrived.
        speaking.clear();
        voice = voice.copyWith(transmitting: false);

      case ReconnectScheduledEvent(:final attempt, :final delayMs):
        // Kept rather than ignored: this is the only thing that knows *when* the
        // next attempt is, and a banner that cannot count down is not worth the
        // space it takes.
        reconnect = ReconnectProgress(attempt: attempt, delayMs: delayMs);

      case ChannelCreatedEvent(:final channel) || ChannelUpdatedEvent(:final channel):
        channels[channel.id] = channel;

      case ChannelRemovedEvent(:final channelId):
        channels.remove(channelId);

      case ClientJoinedEvent(:final client) || ClientUpdatedEvent(:final client):
        clients[client.id] = client;

      case ClientLeftEvent(:final clientId):
        // Gone is gone: no last-known copy is kept. See [offline].
        if (ownClientId == clientId) {
          ownClientId = null;
          ownChannelId = null;
        }
        clients.remove(clientId);
        speaking.remove(clientId);

      case ClientMovedEvent(:final clientId, :final channelId):
        final client = clients[clientId];
        if (client != null) {
          clients[clientId] = client.movedTo(channelId);
        }
        if (ownClientId == clientId) {
          ownChannelId = channelId;
          // Walking into a channel is looking at it, so whatever was waiting
          // there has been seen. The private conversation stays open: changing
          // channels should not yank someone out of what they were reading.
          unread.remove(activeConversation);
        }

      case OwnClientIdentifiedEvent(:final clientId, :final channelId):
        ownClientId = clientId;
        ownChannelId = channelId;
        unread.remove(activeConversation);
        final client = clients[clientId];
        if (client != null) {
          clients[clientId] = client.movedTo(channelId);
        }

      case MessageReceivedEvent(:final message):
        conversations.putIfAbsent(ConversationKey.of(message, ownClientId), () => []).add(message);

      case PermissionsChangedEvent(:final permissions):
        this.permissions = permissions;

      case CapabilitiesChangedEvent(:final capabilities):
        this.capabilities = capabilities;

      case VoiceStateChangedEvent(:final state):
        voice = state;

      case SpeakingEvent(:final clientId, :final speaking):
        if (speaking) {
          this.speaking.add(clientId);
        } else {
          this.speaking.remove(clientId);
        }

      // A poke is an interaction with a person, so it goes in the
      // conversation with them — which is where the user looks when their
      // client beeps. Marked rather than plain, because it is not something
      // they typed, and the panel draws the two differently.
      case PokedEvent(:final clientId, :final senderName, :final message):
        conversations
            .putIfAbsent(ConversationKey.client(clientId), () => [])
            .add(
              Message.poke(
                // Pre-decremented, so the first one is -1 and zero is never
                // handed out: the server counts up from one, and a synthetic id
                // that could be zero is one a real message could be confused
                // with. A clock-derived id collided when two pokes arrived in
                // the same millisecond, and the list is keyed by this.
                id: --_nextSyntheticId,
                senderId: clientId,
                senderName: senderName,
                content: message,
                timestamp: DateTime.now().millisecondsSinceEpoch,
              ),
            );

      // Not part of the rendered state.
      case ErrorEvent():
      case ScreenEvent():
      case UnknownEvent():
        break;
    }
  }
}
