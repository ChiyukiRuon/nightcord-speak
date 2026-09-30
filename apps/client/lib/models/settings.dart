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
  });

  /// On-disk format version. The core refuses one it does not know.
  final int version;

  final AudioSettings audio;
  final ConnectionSettings connection;

  Settings copyWith({AudioSettings? audio, ConnectionSettings? connection}) => Settings(
    version: version,
    audio: audio ?? this.audio,
    connection: connection ?? this.connection,
  );

  factory Settings.fromJson(Map<String, dynamic> json) => Settings(
    version: json['version'] as int? ?? 1,
    audio: AudioSettings.fromJson(_object(json['audio'])),
    connection: ConnectionSettings.fromJson(_object(json['connection'])),
  );

  Map<String, dynamic> toJson() => {
    'version': version,
    'audio': audio.toJson(),
    'connection': connection.toJson(),
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
