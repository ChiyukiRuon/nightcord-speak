// The user's preferences, as the core stores them.
//
// The shape here mirrors `ts_settings::Settings` field for field, because this
// is what goes over the FFI as JSON. Every reader defaults the way serde does on
// the other side, so a core that adds a field, or a settings file someone edited
// by hand, does not break the UI.

import 'domain.dart';

/// Everything the client remembers between runs.
class Settings {
  const Settings({
    this.version = 1,
    this.audio = const AudioSettings(),
    this.connection = const ConnectionSettings(),
    this.notifications = const NotificationSettings(),
  });

  /// On-disk format version. The core refuses one it does not know.
  final int version;

  final AudioSettings audio;
  final ConnectionSettings connection;
  final NotificationSettings notifications;

  Settings copyWith({
    AudioSettings? audio,
    ConnectionSettings? connection,
    NotificationSettings? notifications,
  }) => Settings(
    version: version,
    audio: audio ?? this.audio,
    connection: connection ?? this.connection,
    notifications: notifications ?? this.notifications,
  );

  factory Settings.fromJson(Map<String, dynamic> json) => Settings(
    version: json['version'] as int? ?? 1,
    audio: AudioSettings.fromJson(_object(json['audio'])),
    connection: ConnectionSettings.fromJson(_object(json['connection'])),
    notifications: NotificationSettings.fromJson(_object(json['notifications'])),
  );

  Map<String, dynamic> toJson() => {
    'version': version,
    'audio': audio.toJson(),
    'connection': connection.toJson(),
    'notifications': notifications.toJson(),
  };
}

/// What raises a notification (§43).
///
/// Everything is on by default, so a settings file written before this section
/// existed comes back with the switches *on* rather than off — a client that
/// starts silent looks broken rather than quiet.
class NotificationSettings {
  const NotificationSettings({
    this.presence = true,
    this.poke = true,
    this.channelMessage = true,
    this.directMessage = true,
    this.connection = true,
    this.system = true,
  });

  /// Someone joined or left.
  final bool presence;

  /// Someone poked us.
  final bool poke;

  /// A message in a channel, or to the whole server.
  final bool channelMessage;

  /// A private message.
  final bool directMessage;

  /// A connection dropped or came back.
  final bool connection;

  /// Whether the above should also reach the operating system when the window
  /// is not in front. A different question — *where* rather than *whether* —
  /// and a desktop notification is far more intrusive than one inside the app.
  final bool system;

  NotificationSettings copyWith({
    bool? presence,
    bool? poke,
    bool? channelMessage,
    bool? directMessage,
    bool? connection,
    bool? system,
  }) => NotificationSettings(
    presence: presence ?? this.presence,
    poke: poke ?? this.poke,
    channelMessage: channelMessage ?? this.channelMessage,
    directMessage: directMessage ?? this.directMessage,
    connection: connection ?? this.connection,
    system: system ?? this.system,
  );

  factory NotificationSettings.fromJson(Map<String, dynamic> json) => NotificationSettings(
    presence: json['presence'] as bool? ?? true,
    poke: json['poke'] as bool? ?? true,
    channelMessage: json['channel_message'] as bool? ?? true,
    directMessage: json['direct_message'] as bool? ?? true,
    connection: json['connection'] as bool? ?? true,
    system: json['system'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'presence': presence,
    'poke': poke,
    'channel_message': channelMessage,
    'direct_message': directMessage,
    'connection': connection,
    'system': system,
  };
}

/// How audio is captured and played.
class AudioSettings {
  const AudioSettings({
    this.inputDevice,
    this.outputDevice,
    this.mode = VoiceActivationMode.voiceActivation,
    this.activation = const VoiceActivationSettings(),
  });

  /// Capture device id, or null for the system default.
  final String? inputDevice;

  /// Playback device id, or null for the system default.
  final String? outputDevice;

  final VoiceActivationMode mode;
  final VoiceActivationSettings activation;

  AudioSettings copyWith({
    String? inputDevice,
    bool clearInputDevice = false,
    String? outputDevice,
    bool clearOutputDevice = false,
    VoiceActivationMode? mode,
    VoiceActivationSettings? activation,
  }) => AudioSettings(
    // A nullable field cannot be set back to null by passing null — that is what
    // `copyWith` means everywhere else — so choosing 「系统默认」 says so
    // explicitly.
    inputDevice: clearInputDevice ? null : (inputDevice ?? this.inputDevice),
    outputDevice: clearOutputDevice ? null : (outputDevice ?? this.outputDevice),
    mode: mode ?? this.mode,
    activation: activation ?? this.activation,
  );

  factory AudioSettings.fromJson(Map<String, dynamic> json) => AudioSettings(
    inputDevice: json['input_device'] as String?,
    outputDevice: json['output_device'] as String?,
    mode: VoiceActivationMode.fromWire(json['mode'] as String?),
    activation: VoiceActivationSettings.fromJson(_object(json['activation'])),
  );

  Map<String, dynamic> toJson() => {
    'input_device': inputDevice,
    'output_device': outputDevice,
    'mode': mode.wire,
    'activation': activation.toJson(),
  };
}

/// The voice-activation gate's tuning (§29).
class VoiceActivationSettings {
  const VoiceActivationSettings({
    this.sensitivity = 0.05,
    this.attackMs = 60,
    this.releaseMs = 400,
  });

  /// RMS level above which transmission opens, `0.0..=1.0`.
  ///
  /// Higher means louder speech is needed to open the microphone, which is why
  /// the UI calls the opposite of this "sensitivity".
  final double sensitivity;

  /// How long the level must stay above the threshold before opening, ms.
  final int attackMs;

  /// How long it may stay below the threshold before closing, ms.
  final int releaseMs;

  VoiceActivationSettings copyWith({double? sensitivity, int? attackMs, int? releaseMs}) =>
      VoiceActivationSettings(
        sensitivity: sensitivity ?? this.sensitivity,
        attackMs: attackMs ?? this.attackMs,
        releaseMs: releaseMs ?? this.releaseMs,
      );

  factory VoiceActivationSettings.fromJson(Map<String, dynamic> json) =>
      VoiceActivationSettings(
        sensitivity: (json['sensitivity'] as num?)?.toDouble() ?? 0.05,
        attackMs: json['attack_ms'] as int? ?? 60,
        releaseMs: json['release_ms'] as int? ?? 400,
      );

  Map<String, dynamic> toJson() => {
    'sensitivity': sensitivity,
    'attack_ms': attackMs,
    'release_ms': releaseMs,
  };
}

/// How connections to servers are made.
class ConnectionSettings {
  const ConnectionSettings({
    this.nickname = 'Nightcord User',
    this.profile = 'default',
    this.maxReconnectAttempts,
  });

  /// Nickname offered to servers, and the starting value for the field on the
  /// connect screen.
  final String nickname;

  /// Which identity profile to present.
  ///
  /// One profile means one client to every server that sees it. TeamSpeak
  /// refuses a second live connection from the same identity, so two clients
  /// side by side need different profiles.
  final String profile;

  /// How many times a dropped connection may be retried.
  ///
  /// * `null` — forever, which is the default.
  /// * `0` — never; the drop is reported and the session ends.
  /// * `n` — up to `n` attempts.
  final int? maxReconnectAttempts;

  ConnectionSettings copyWith({
    String? nickname,
    String? profile,
    int? maxReconnectAttempts,
    bool clearMaxReconnectAttempts = false,
  }) => ConnectionSettings(
    nickname: nickname ?? this.nickname,
    profile: profile ?? this.profile,
    maxReconnectAttempts: clearMaxReconnectAttempts
        ? null
        : (maxReconnectAttempts ?? this.maxReconnectAttempts),
  );

  factory ConnectionSettings.fromJson(Map<String, dynamic> json) => ConnectionSettings(
    nickname: json['nickname'] as String? ?? 'Nightcord User',
    profile: json['profile'] as String? ?? 'default',
    maxReconnectAttempts: json['max_reconnect_attempts'] as int?,
  );

  Map<String, dynamic> toJson() => {
    'nickname': nickname,
    'profile': profile,
    'max_reconnect_attempts': maxReconnectAttempts,
  };
}

/// Reads a nested object, tolerating anything else.
///
/// A settings file is editable by hand, so a section replaced with a string (or
/// deleted) has to fall back to defaults rather than throw on the way in.
Map<String, dynamic> _object(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : const <String, dynamic>{};
