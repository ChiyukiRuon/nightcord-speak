// The user's preferences, as the core stores them.
//
// The shape here mirrors `ts_settings::Settings` field for field, because this
// is what goes over the FFI as JSON. Every reader defaults the way serde does on
// the other side, so a core that adds a field, or a settings file someone edited
// by hand, does not break the UI.

import 'domain.dart';
import 'screen_options.dart';
import 'shortcuts.dart';

/// Everything the client remembers between runs.
class Settings {
  const Settings({
    this.version = 1,
    this.audio = const AudioSettings(),
    this.connection = const ConnectionSettings(),
    this.notifications = const NotificationSettings(),
    this.shortcuts = const ShortcutSettings(),
    this.presence = const PresenceSettings(),
    this.ui = const UiSettings(),
    this.screen = const ScreenSettings(),
  });

  /// On-disk format version. The core refuses one it does not know.
  final int version;

  final AudioSettings audio;
  final ConnectionSettings connection;
  final NotificationSettings notifications;
  final ShortcutSettings shortcuts;
  final PresenceSettings presence;
  final UiSettings ui;
  final ScreenSettings screen;

  Settings copyWith({
    AudioSettings? audio,
    ConnectionSettings? connection,
    NotificationSettings? notifications,
    ShortcutSettings? shortcuts,
    PresenceSettings? presence,
    UiSettings? ui,
    ScreenSettings? screen,
  }) => Settings(
    version: version,
    audio: audio ?? this.audio,
    connection: connection ?? this.connection,
    notifications: notifications ?? this.notifications,
    shortcuts: shortcuts ?? this.shortcuts,
    presence: presence ?? this.presence,
    ui: ui ?? this.ui,
    screen: screen ?? this.screen,
  );

  factory Settings.fromJson(Map<String, dynamic> json) => Settings(
    version: json['version'] as int? ?? 1,
    audio: AudioSettings.fromJson(_object(json['audio'])),
    connection: ConnectionSettings.fromJson(_object(json['connection'])),
    notifications: NotificationSettings.fromJson(
      _object(json['notifications']),
    ),
    shortcuts: ShortcutSettings.fromJson(_object(json['shortcuts'])),
    presence: PresenceSettings.fromJson(_object(json['presence'])),
    ui: UiSettings.fromJson(_object(json['ui'])),
    screen: ScreenSettings.fromJson(_object(json['screen'])),
  );

  Map<String, dynamic> toJson() => {
    'version': version,
    'audio': audio.toJson(),
    'connection': connection.toJson(),
    'notifications': notifications.toJson(),
    'shortcuts': shortcuts.toJson(),
    'presence': presence.toJson(),
    'ui': ui.toJson(),
    'screen': screen.toJson(),
  };
}

/// What raises a notification (§43).
///
/// Everything is on by default, so a settings file written before this section
/// existed comes back with the switches *on* rather than off — a client that
/// starts silent looks broken rather than quiet.
class NotificationSettings {
  const NotificationSettings({
    this.sounds = true,
    this.soundPack = 'nightcord',
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
  final bool sounds;
  final String soundPack;

  NotificationSettings copyWith({
    bool? sounds,
    String? soundPack,
    bool? presence,
    bool? poke,
    bool? channelMessage,
    bool? directMessage,
    bool? connection,
    bool? system,
  }) => NotificationSettings(
    sounds: sounds ?? this.sounds,
    soundPack: soundPack ?? this.soundPack,
    presence: presence ?? this.presence,
    poke: poke ?? this.poke,
    channelMessage: channelMessage ?? this.channelMessage,
    directMessage: directMessage ?? this.directMessage,
    connection: connection ?? this.connection,
    system: system ?? this.system,
  );

  factory NotificationSettings.fromJson(Map<String, dynamic> json) =>
      NotificationSettings(
        sounds: json['sounds'] as bool? ?? true,
        soundPack: json['sound_pack'] as String? ?? 'nightcord',
        presence: json['presence'] as bool? ?? true,
        poke: json['poke'] as bool? ?? true,
        channelMessage: json['channel_message'] as bool? ?? true,
        directMessage: json['direct_message'] as bool? ?? true,
        connection: json['connection'] as bool? ?? true,
        system: json['system'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
    'sounds': sounds,
    'sound_pack': soundPack,
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
    this.outputVolume = 1.0,
    this.inputGainDb = 0.0,
  });

  /// Capture device id, or null for the system default.
  final String? inputDevice;

  /// Playback device id, or null for the system default.
  final String? outputDevice;

  final VoiceActivationMode mode;
  final VoiceActivationSettings activation;

  /// Playback gain, `0.0..=1.0`.
  ///
  /// The codec has no setting: it always runs the stereo profile at the top of
  /// its range, see `ts_audio::encoder`.
  final double outputVolume;

  /// Microphone gain in decibels: how loud everyone else hears us.
  ///
  /// `0.0` is unity, and [`gainSilenceDb`] is silence. Not the same control as
  /// [outputVolume], which is what *we* hear — the two are deliberately
  /// separate fields with separate units.
  final double inputGainDb;

  AudioSettings copyWith({
    String? inputDevice,
    bool clearInputDevice = false,
    String? outputDevice,
    bool clearOutputDevice = false,
    VoiceActivationMode? mode,
    VoiceActivationSettings? activation,
    double? outputVolume,
    double? inputGainDb,
  }) => AudioSettings(
    // A nullable field cannot be set back to null by passing null — that is what
    // `copyWith` means everywhere else — so choosing 「系统默认」 says so
    // explicitly.
    inputDevice: clearInputDevice ? null : (inputDevice ?? this.inputDevice),
    outputDevice: clearOutputDevice
        ? null
        : (outputDevice ?? this.outputDevice),
    mode: mode ?? this.mode,
    activation: activation ?? this.activation,
    outputVolume: outputVolume ?? this.outputVolume,
    inputGainDb: inputGainDb ?? this.inputGainDb,
  );

  factory AudioSettings.fromJson(Map<String, dynamic> json) => AudioSettings(
    inputDevice: json['input_device'] as String?,
    outputDevice: json['output_device'] as String?,
    mode: VoiceActivationMode.fromWire(json['mode'] as String?),
    activation: VoiceActivationSettings.fromJson(_object(json['activation'])),
    outputVolume: _volume(json['output_volume']),
    inputGainDb: _gainDb(json['input_gain_db']),
  );

  Map<String, dynamic> toJson() => {
    'input_device': inputDevice,
    'output_device': outputDevice,
    'mode': mode.wire,
    'activation': activation.toJson(),
    'output_volume': outputVolume,
    'input_gain_db': inputGainDb,
  };
}

/// A playback gain read back from a file, pulled into range.
///
/// A missing value is unity, not zero — a file written before volume existed
/// must not load as silence.
double _volume(Object? value) =>
    (value as num?)?.toDouble().clamp(0.0, 1.0) ?? 1.0;

/// A microphone gain read back from a file, pulled into range.
///
/// Missing is unity, for the same reason as the volume beside it — except that
/// unity *is* zero for a gain in decibels, so the two defaults agree by
/// construction.
///
/// A value that is not a number at all is silence rather than unity: it cannot
/// come from the file (JSON has no such literal), so it means something is
/// broken rather than something is old, and a slider holding one would assert
/// on the first frame. The core reads it the same way.
double _gainDb(Object? value) {
  final db = (value as num?)?.toDouble() ?? 0.0;
  if (db.isNaN) return gainSilenceDb;
  return db.clamp(gainSilenceDb, gainMaxDb);
}

/// The bottom of the microphone gain range, in decibels: silence.
///
/// The core clamps to the same pair (`ts_audio::SILENCE_DB` and
/// `ts_audio::MAX_GAIN_DB`) — they are the contract of the stored value, which
/// is why they live beside the field rather than in the slider that draws them.
const double gainSilenceDb = -200.0;

/// The top of it: loud enough to rescue a quiet microphone, and honest about
/// clipping anything already loud.
const double gainMaxDb = 10.0;

/// The voice-activation gate's tuning (§29).
enum VadAlgorithm { smart, level }

class VoiceActivationSettings {
  const VoiceActivationSettings({
    this.algorithm = VadAlgorithm.smart,
    this.sensitivity = 0.05,
    this.attackMs = 60,
    this.releaseMs = 400,
  });

  final VadAlgorithm algorithm;

  /// RMS level above which transmission opens, `0.0..=1.0`.
  ///
  /// Higher means louder speech is needed to open the microphone, which is why
  /// the UI calls the opposite of this "sensitivity".
  final double sensitivity;

  /// How long the level must stay above the threshold before opening, ms.
  final int attackMs;

  /// How long it may stay below the threshold before closing, ms.
  final int releaseMs;

  VoiceActivationSettings copyWith({
    VadAlgorithm? algorithm,
    double? sensitivity,
    int? attackMs,
    int? releaseMs,
  }) => VoiceActivationSettings(
    algorithm: algorithm ?? this.algorithm,
    sensitivity: sensitivity ?? this.sensitivity,
    attackMs: attackMs ?? this.attackMs,
    releaseMs: releaseMs ?? this.releaseMs,
  );

  factory VoiceActivationSettings.fromJson(Map<String, dynamic> json) =>
      VoiceActivationSettings(
        algorithm: json['algorithm'] == 'level'
            ? VadAlgorithm.level
            : VadAlgorithm.smart,
        sensitivity: (json['sensitivity'] as num?)?.toDouble() ?? 0.05,
        attackMs: json['attack_ms'] as int? ?? 60,
        releaseMs: json['release_ms'] as int? ?? 400,
      );

  Map<String, dynamic> toJson() => {
    'algorithm': algorithm.name,
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

  factory ConnectionSettings.fromJson(Map<String, dynamic> json) =>
      ConnectionSettings(
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

/// What other people see about us when we are away.
///
/// The core stores this but never reads it: the message is sent to the server
/// when we go away, and until then it is just a preference.
class PresenceSettings {
  const PresenceSettings({this.awayMessage = ''});

  /// What to say when we go away. Empty — the default — is a legitimate value:
  /// the away button says nothing until someone has set something.
  final String awayMessage;

  PresenceSettings copyWith({String? awayMessage}) =>
      PresenceSettings(awayMessage: awayMessage ?? this.awayMessage);

  factory PresenceSettings.fromJson(Map<String, dynamic> json) =>
      PresenceSettings(awayMessage: json['away_message'] as String? ?? '');

  Map<String, dynamic> toJson() => {'away_message': awayMessage};
}

/// How the front-end presents itself.
///
/// The core stores these but never reads them — they are here because
/// `settings.json` is the application's single preferences file.
class UiSettings {
  const UiSettings({this.language, this.theme});

  /// The language the front-end renders in: `'zh'` or `'en'`.
  ///
  /// Null means "follow the system", which is the default. A hand-edited value
  /// the UI does not know is kept in the file but read through
  /// [requestedLanguage], which treats it as unset.
  final String? language;

  /// Which theme the front-end draws in.
  ///
  /// `'nightcord'`, `'black'`, `'white'` or `'system'`. Null is **not** "follow
  /// the system" here, unlike [language] — it is the default theme, Nightcord.
  /// Both spellings resolve to the same thing; keeping the null is what lets a
  /// settings file written before this key existed mean "whatever the app
  /// ships with" rather than freezing today's default into the file.
  final String? theme;

  /// The language actually asked for, or null for "follow the system".
  ///
  /// Separate from [language] so an unrecognized value — a typo, or a language
  /// this build does not have yet — falls back to the system language instead
  /// of reaching the locale lookup and matching nothing.
  String? get requestedLanguage => switch (language) {
    'zh' || 'zh_Hant' || 'en' || 'ja' || 'ko' => language,
    _ => null,
  };

  /// The theme actually asked for, or null for the default.
  ///
  /// The whitelist, for the same reason as [requestedLanguage]: a theme this
  /// build does not know must fall back rather than reach the palette lookup
  /// and match nothing. `'system'` survives it — it is a real choice, not the
  /// absence of one.
  String? get requestedTheme => switch (theme) {
    'nightcord' || 'black' || 'white' || 'system' => theme,
    _ => null,
  };

  UiSettings copyWith({
    String? language,
    bool clearLanguage = false,
    String? theme,
  }) => UiSettings(
    // Same convention as `AudioSettings`: null cannot mean "clear", so
    // choosing 「跟随系统」 says so explicitly.
    language: clearLanguage ? null : (language ?? this.language),
    // No `clearTheme`: there is no "unset" item in the theme dropdown, because
    // an unset theme and Nightcord are the same choice. Every edit writes one
    // of the four concrete values.
    theme: theme ?? this.theme,
  );

  factory UiSettings.fromJson(Map<String, dynamic> json) => UiSettings(
    language: json['language'] as String?,
    theme: json['theme'] as String?,
  );

  Map<String, dynamic> toJson() => {'language': language, 'theme': theme};
}

/// What a screen share is started with.
///
/// Mirrors `ts_settings::ScreenSettings`. The core never reads these — they are
/// consumed by the capture and the encoder on this side, and travel to the
/// server inside the start command.
///
/// No `preset` field, on purpose: a preset is a named set of these numbers, so
/// the selected one is *derived* from them (see `ScreenPreset.matching`). Two
/// answers to "which preset is this" is exactly what a preset must not have.
class ScreenSettings {
  const ScreenSettings({
    this.height = 720,
    this.fps = 30,
    this.videoBitrateKbps = 2500,
    this.audio = false,
    this.audioBitrateKbps = 128,
    this.access = ScreenAccess.public,
    this.viewerLimit = 0,
    this.mode = ScreenMode.p2p,
  });

  /// Wanted capture height in pixels; 0 keeps the source's own.
  final int height;

  /// Wanted frames per second; 0 leaves it to the platform.
  final int fps;

  /// What the encoder may spend on the picture.
  final int videoBitrateKbps;

  /// Whether to send the capture's own audio with it.
  ///
  /// Off by default even though the reference client starts with it on: there
  /// is no audio capture path here yet, and asking the server for a stream with
  /// sound that carries none is worse than asking for one without.
  final bool audio;

  /// What the encoder may spend on that audio. Ignored while [audio] is false.
  final int audioBitrateKbps;

  final ScreenAccess access;

  /// How many viewers to allow; 0 means as many as the server will carry.
  final int viewerLimit;

  final ScreenMode mode;

  ScreenSettings copyWith({
    int? height,
    int? fps,
    int? videoBitrateKbps,
    bool? audio,
    int? audioBitrateKbps,
    ScreenAccess? access,
    int? viewerLimit,
    ScreenMode? mode,
  }) => ScreenSettings(
    height: height ?? this.height,
    fps: fps ?? this.fps,
    videoBitrateKbps: videoBitrateKbps ?? this.videoBitrateKbps,
    audio: audio ?? this.audio,
    audioBitrateKbps: audioBitrateKbps ?? this.audioBitrateKbps,
    access: access ?? this.access,
    viewerLimit: viewerLimit ?? this.viewerLimit,
    mode: mode ?? this.mode,
  );

  factory ScreenSettings.fromJson(Map<String, dynamic> json) => ScreenSettings(
    // `?? 720` rather than `?? 0`, matching serde: a missing height means the
    // default preset, and zero would mean "the source's own resolution" — a
    // different picture entirely.
    height: (json['height'] as num?)?.toInt() ?? 720,
    fps: (json['fps'] as num?)?.toInt() ?? 30,
    videoBitrateKbps: (json['video_bitrate_kbps'] as num?)?.toInt() ?? 2500,
    audio: json['audio'] as bool? ?? false,
    audioBitrateKbps: (json['audio_bitrate_kbps'] as num?)?.toInt() ?? 128,
    access: ScreenAccess.fromWire(json['access'] as String?),
    viewerLimit: (json['viewer_limit'] as num?)?.toInt() ?? 0,
    mode: ScreenMode.fromWire(json['mode'] as String?),
  );

  Map<String, dynamic> toJson() => {
    'height': height,
    'fps': fps,
    'video_bitrate_kbps': videoBitrateKbps,
    'audio': audio,
    'audio_bitrate_kbps': audioBitrateKbps,
    'access': access.wire,
    'viewer_limit': viewerLimit,
    'mode': mode.wire,
  };
}

/// Reads a nested object, tolerating anything else.
///
/// A settings file is editable by hand, so a section replaced with a string (or
/// deleted) has to fall back to defaults rather than throw on the way in.
Map<String, dynamic> _object(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : const <String, dynamic>{};
