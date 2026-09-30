// Dart mirrors of the Rust domain model.
//
// These parse the JSON `ts-model` produces. The Rust types are the definition;
// these exist so the widget layer can be typed rather than working with maps.
//
// Every `fromJson` is deliberately tolerant of missing keys: a newer core may
// add a field, and an older one may omit an optional field. Only fields the UI
// actually needs to render are required.

/// Which TeamSpeak dialect a server speaks.
enum ProtocolKind {
  ts3('ts3', 'TS3'),
  ts6('ts6', 'TS6');

  const ProtocolKind(this.wire, this.label);

  /// The `serde` name.
  final String wire;

  /// Short label for a server chip.
  final String label;

  static ProtocolKind fromWire(String? value) =>
      values.firstWhere((k) => k.wire == value, orElse: () => ProtocolKind.ts3);
}

/// Where a session is in its lifecycle.
enum ConnectionState {
  disconnected('disconnected'),
  connecting('connecting'),
  connected('connected'),
  reconnecting('reconnecting'),
  disconnecting('disconnecting'),
  failed('failed');

  const ConnectionState(this.wire);

  /// The `serde` name.
  final String wire;

  static ConnectionState fromWire(String? value) => values.firstWhere(
    (s) => s.wire == value,
    orElse: () => ConnectionState.disconnected,
  );

  /// Whether the session is usable right now.
  bool get isUsable => this == ConnectionState.connected;

  /// Whether it is between states.
  bool get isTransitional =>
      this == ConnectionState.connecting ||
      this == ConnectionState.reconnecting ||
      this == ConnectionState.disconnecting;
}

/// A server as the address book knows it.
class Server {
  const Server({
    required this.id,
    required this.name,
    required this.address,
    required this.protocol,
  });

  final int id;
  final String name;
  final String address;
  final ProtocolKind protocol;

  /// Falls back to the address when the server has not named itself yet.
  String get displayName => name.isEmpty ? address : name;

  factory Server.fromJson(Map<String, dynamic> json) => Server(
    id: json['id'] as int? ?? 0,
    name: json['name'] as String? ?? '',
    address: json['address'] as String? ?? '',
    protocol: ProtocolKind.fromWire(json['protocol'] as String?),
  );
}

/// What the server says about itself.
class ServerInfo {
  const ServerInfo({
    this.name = '',
    this.welcomeMessage,
    this.platform,
    this.version,
    this.maxClients = 0,
    this.clientsOnline = 0,
    this.channelsOnline = 0,
    this.uptime,
  });

  final String name;
  final String? welcomeMessage;
  final String? platform;
  final String? version;
  final int maxClients;

  /// Connected clients right now.
  ///
  /// Arrives as zero on the first `connected` event — the server describes
  /// itself before it sends its lists — and is corrected by a later
  /// `server_info_changed`.
  final int clientsOnline;
  final int channelsOnline;
  final int? uptime;

  factory ServerInfo.fromJson(Map<String, dynamic> json) => ServerInfo(
    name: json['name'] as String? ?? '',
    welcomeMessage: json['welcome_message'] as String?,
    platform: json['platform'] as String?,
    version: json['version'] as String?,
    maxClients: json['max_clients'] as int? ?? 0,
    clientsOnline: json['clients_online'] as int? ?? 0,
    channelsOnline: json['channels_online'] as int? ?? 0,
    uptime: json['uptime'] as int?,
  );
}

/// One node of the channel tree.
class Channel {
  const Channel({
    required this.id,
    required this.name,
    this.parentId,
    this.order = 0,
    this.clients = const [],
    this.topic,
    this.description,
    this.hasPassword = false,
    this.isDefault = false,
    this.isPermanent = false,
    this.maxClients,
  });

  final int id;
  final String name;

  /// `null` for a root channel.
  final int? parentId;

  /// The server's ordering key among siblings.
  final int order;

  /// Ids of the clients currently in this channel.
  final List<int> clients;

  final String? topic;
  final String? description;
  final bool hasPassword;
  final bool isDefault;
  final bool isPermanent;
  final int? maxClients;

  factory Channel.fromJson(Map<String, dynamic> json) => Channel(
    id: json['id'] as int,
    name: json['name'] as String? ?? '',
    parentId: json['parent_id'] as int?,
    order: json['order'] as int? ?? 0,
    clients: (json['clients'] as List?)?.cast<int>() ?? const [],
    topic: json['topic'] as String?,
    description: json['description'] as String?,
    hasPassword: json['has_password'] as bool? ?? false,
    isDefault: json['is_default'] as bool? ?? false,
    isPermanent: json['is_permanent'] as bool? ?? false,
    maxClients: json['max_clients'] as int?,
  );
}

/// Everything that can be true about a user at once.
class ClientFlags {
  const ClientFlags({
    this.away = false,
    this.inputMuted = false,
    this.outputMuted = false,
    this.recording = false,
    this.channelCommander = false,
  });

  final bool away;
  final bool inputMuted;
  final bool outputMuted;
  final bool recording;
  final bool channelCommander;

  /// Neither heard nor hearing.
  bool get isDeafened => inputMuted && outputMuted;

  factory ClientFlags.fromJson(Map<String, dynamic> json) => ClientFlags(
    away: json['away'] as bool? ?? false,
    inputMuted: json['input_muted'] as bool? ?? false,
    outputMuted: json['output_muted'] as bool? ?? false,
    recording: json['recording'] as bool? ?? false,
    channelCommander: json['channel_commander'] as bool? ?? false,
  );
}

/// A user connected to the server.
class Client {
  const Client({
    required this.id,
    required this.name,
    required this.channelId,
    this.flags = const ClientFlags(),
    this.uniqueId,
    this.isSelf = false,
  });

  final int id;
  final String name;
  final int channelId;
  final ClientFlags flags;

  /// Stable per-user id. Survives reconnects, unlike [id].
  final String? uniqueId;

  /// Whether this client is us.
  final bool isSelf;

  factory Client.fromJson(Map<String, dynamic> json) => Client(
    id: json['id'] as int,
    name: json['name'] as String? ?? '',
    channelId: json['channel_id'] as int? ?? 0,
    flags: ClientFlags.fromJson(
      (json['flags'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
    uniqueId: json['unique_id'] as String?,
    isSelf: json['is_self'] as bool? ?? false,
  );

  /// A copy with a different channel, for a `client_moved` event.
  Client movedTo(int channel) => Client(
    id: id,
    name: name,
    channelId: channel,
    flags: flags,
    uniqueId: uniqueId,
    isSelf: isSelf,
  );
}

/// Who a chat message is addressed to.
sealed class MessageTarget {
  const MessageTarget();

  /// The `serde` encoding, ready to hand to the Rust core.
  Map<String, dynamic> toJson();

  factory MessageTarget.fromJson(Map<String, dynamic> json) =>
      switch (json['kind'] as String?) {
        'channel' => ChannelTarget(json['id'] as int),
        'client' => ClientTarget(json['id'] as int),
        _ => const ServerTarget(),
      };

  /// Everyone on the server.
  static const MessageTarget server = ServerTarget();
}

/// Visible to everyone on the server.
class ServerTarget extends MessageTarget {
  const ServerTarget();

  @override
  Map<String, dynamic> toJson() => {'kind': 'server'};

  @override
  bool operator ==(Object other) => other is ServerTarget;

  @override
  int get hashCode => 'server'.hashCode;
}

/// Visible to everyone in one channel.
class ChannelTarget extends MessageTarget {
  const ChannelTarget(this.channelId);

  final int channelId;

  @override
  Map<String, dynamic> toJson() => {'kind': 'channel', 'id': channelId};

  @override
  bool operator ==(Object other) =>
      other is ChannelTarget && other.channelId == channelId;

  @override
  int get hashCode => Object.hash('channel', channelId);
}

/// A direct message.
class ClientTarget extends MessageTarget {
  const ClientTarget(this.clientId);

  final int clientId;

  @override
  Map<String, dynamic> toJson() => {'kind': 'client', 'id': clientId};

  @override
  bool operator ==(Object other) =>
      other is ClientTarget && other.clientId == clientId;

  @override
  int get hashCode => Object.hash('client', clientId);
}

/// A file shared in a chat message.
///
/// File transfer is the second phase (§39), so the core does not send these
/// yet and this is always empty in practice. It exists so the message list
/// already renders the shape — the reference design shows file cards — rather
/// than being rewritten once uploads and downloads land.
class Attachment {
  const Attachment({
    required this.name,
    required this.size,
    this.mimeType,
    this.url,
  });

  /// The file's name, shown on the card.
  final String name;

  /// Size in bytes.
  final int size;

  /// Content type, when the server reported one.
  final String? mimeType;

  /// Where to fetch it.
  ///
  /// Absent until file transfer exists, which is exactly why the card renders
  /// without a working download button rather than a button that does nothing.
  final String? url;

  /// Whether this attachment can actually be downloaded yet.
  bool get isAvailable => url != null;

  /// The size, rendered the way a person reads it.
  String get readableSize {
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = size.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final rounded = value >= 10 || unit == 0 ? value.round().toString() : value.toStringAsFixed(1);
    return '$rounded ${units[unit]}';
  }

  /// A label for the file's kind, from its extension.
  String get kindLabel {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return 'FILE';
    return name.substring(dot + 1).toUpperCase();
  }

  factory Attachment.fromJson(Map<String, dynamic> json) => Attachment(
    name: json['name'] as String? ?? 'file',
    size: json['size'] as int? ?? 0,
    mimeType: json['mime_type'] as String?,
    url: json['url'] as String?,
  );
}

/// A chat message.
class Message {
  const Message({
    required this.id,
    required this.senderName,
    required this.target,
    required this.content,
    required this.timestamp,
    this.sender,
    this.attachments = const [],
  });

  final int id;
  final int? sender;

  /// Captured at delivery, so a message from a client that has since
  /// disconnected still renders.
  final String senderName;
  final MessageTarget target;
  final String content;

  /// Unix milliseconds.
  final int timestamp;

  /// Files shared with this message. Always empty until §39 lands.
  final List<Attachment> attachments;

  DateTime get sentAt => DateTime.fromMillisecondsSinceEpoch(timestamp);

  /// Whether this is a one-to-one message.
  bool get isPrivate => target is ClientTarget;

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: json['id'] as int,
    sender: json['sender'] as int?,
    senderName: json['sender_name'] as String? ?? '',
    target: MessageTarget.fromJson(
      (json['target'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
    content: json['content'] as String? ?? '',
    timestamp: json['timestamp'] as int? ?? 0,
    attachments:
        (json['attachments'] as List?)
            ?.map((e) => Attachment.fromJson((e as Map).cast<String, dynamic>()))
            .toList(growable: false) ??
        const [],
  );
}

/// What the server lets us do.
class Permissions {
  const Permissions({
    this.canJoinChannel = false,
    this.canMoveClients = false,
    this.canSendChannelMessage = false,
    this.canSendPrivateMessage = false,
    this.canKick = false,
    this.canBan = false,
  });

  final bool canJoinChannel;
  final bool canMoveClients;
  final bool canSendChannelMessage;
  final bool canSendPrivateMessage;
  final bool canKick;
  final bool canBan;

  factory Permissions.fromJson(Map<String, dynamic> json) => Permissions(
    canJoinChannel: json['can_join_channel'] as bool? ?? false,
    canMoveClients: json['can_move_clients'] as bool? ?? false,
    canSendChannelMessage: json['can_send_channel_message'] as bool? ?? false,
    canSendPrivateMessage: json['can_send_private_message'] as bool? ?? false,
    canKick: json['can_kick'] as bool? ?? false,
    canBan: json['can_ban'] as bool? ?? false,
  );
}

/// What the server can do at all.
///
/// The UI branches on these rather than on [ProtocolKind], so a TS6-only
/// feature shows up as a capability gap instead of a version check scattered
/// through the widgets (§15, §55).
class Capabilities {
  const Capabilities({
    this.textChat = false,
    this.privateChat = false,
    this.voice = false,
    this.whisper = false,
    this.fileTransfer = false,
    this.screenStream = false,
    this.poke = false,
  });

  final bool textChat;
  final bool privateChat;
  final bool voice;
  final bool whisper;
  final bool fileTransfer;
  final bool screenStream;
  final bool poke;

  factory Capabilities.fromJson(Map<String, dynamic> json) => Capabilities(
    textChat: json['text_chat'] as bool? ?? false,
    privateChat: json['private_chat'] as bool? ?? false,
    voice: json['voice'] as bool? ?? false,
    whisper: json['whisper'] as bool? ?? false,
    fileTransfer: json['file_transfer'] as bool? ?? false,
    screenStream: json['screen_stream'] as bool? ?? false,
    poke: json['poke'] as bool? ?? false,
  );
}

/// How transmission is triggered.
enum VoiceActivationMode {
  pushToTalk('push_to_talk', '按键说话'),
  voiceActivation('voice_activation', '语音激活'),
  continuous('continuous', '持续传输'),
  muted('muted', '静音');

  const VoiceActivationMode(this.wire, this.label);

  /// The name the FFI accepts.
  final String wire;

  /// Label for the UI.
  final String label;

  static VoiceActivationMode fromWire(String? value) => values.firstWhere(
    (m) => m.wire == value,
    orElse: () => VoiceActivationMode.voiceActivation,
  );
}

/// The local user's voice state.
class VoiceState {
  const VoiceState({
    this.mode = VoiceActivationMode.voiceActivation,
    this.inputMuted = false,
    this.outputMuted = false,
    this.transmitting = false,
  });

  final VoiceActivationMode mode;
  final bool inputMuted;
  final bool outputMuted;
  final bool transmitting;

  /// Neither heard nor hearing.
  bool get isDeafened => inputMuted && outputMuted;

  VoiceState copyWith({
    VoiceActivationMode? mode,
    bool? inputMuted,
    bool? outputMuted,
    bool? transmitting,
  }) => VoiceState(
    mode: mode ?? this.mode,
    inputMuted: inputMuted ?? this.inputMuted,
    outputMuted: outputMuted ?? this.outputMuted,
    transmitting: transmitting ?? this.transmitting,
  );

  factory VoiceState.fromJson(Map<String, dynamic> json) => VoiceState(
    mode: VoiceActivationMode.fromWire(json['mode'] as String?),
    inputMuted: json['input_muted'] as bool? ?? false,
    outputMuted: json['output_muted'] as bool? ?? false,
    transmitting: json['transmitting'] as bool? ?? false,
  );
}

/// One selectable audio device.
class AudioDevice {
  const AudioDevice({
    required this.id,
    required this.name,
    this.isDefault = false,
    this.sampleRate,
    this.channels,
  });

  final String id;
  final String name;
  final bool isDefault;
  final int? sampleRate;
  final int? channels;

  factory AudioDevice.fromJson(Map<String, dynamic> json) => AudioDevice(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    isDefault: json['is_default'] as bool? ?? false,
    sampleRate: json['sample_rate'] as int?,
    channels: json['channels'] as int?,
  );
}
