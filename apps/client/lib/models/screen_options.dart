// What a publisher decides before going live, as it reaches the core.
//
// Mirrors `ts_model::ScreenOptions` field for field, because this is what goes
// over the FFI as JSON — the same reason `settings.dart` mirrors
// `ts_settings::Settings` and the two must be changed together.
//
// There are no defaults here. The defaults a user sees belong to the settings
// store (see `ScreenSettings`), and a second set in this file would be a second
// answer to the same question.

/// What is being captured.
enum ScreenSourceKind {
  camera,
  screen,

  /// One window — which on a desktop is what "an application" amounts to.
  window;

  String get wire => name;

  static ScreenSourceKind fromWire(String? value) =>
      values.firstWhere((kind) => kind.wire == value, orElse: () => ScreenSourceKind.screen);
}

/// Who may watch.
enum ScreenAccess {
  public,
  contacts,
  private;

  String get wire => name;

  static ScreenAccess fromWire(String? value) =>
      values.firstWhere((kind) => kind.wire == value, orElse: () => ScreenAccess.public);
}

/// How viewers reach the picture.
enum ScreenMode {
  p2p,
  sfu;

  String get wire => name;

  static ScreenMode fromWire(String? value) =>
      values.firstWhere((kind) => kind.wire == value, orElse: () => ScreenMode.p2p);
}

/// Everything a publisher decides before going live.
class ScreenOptions {
  const ScreenOptions({
    required this.source,
    required this.height,
    required this.fps,
    required this.videoBitrateKbps,
    required this.audio,
    required this.audioBitrateKbps,
    required this.access,
    required this.viewerLimit,
    required this.mode,
    required this.detail,
  });

  final ScreenSourceKind source;

  /// Wanted capture height in pixels; 0 keeps the source's own.
  final int height;

  /// Wanted frames per second; 0 leaves it to the platform.
  final int fps;

  /// What the encoder may spend on video.
  final int videoBitrateKbps;

  /// Whether to send the capture's own audio alongside the picture.
  final bool audio;

  /// What the encoder may spend on that audio. Ignored when [audio] is false.
  final int audioBitrateKbps;

  final ScreenAccess access;

  /// How many viewers to allow; 0 means as many as the server will carry.
  final int viewerLimit;

  final ScreenMode mode;

  /// Whether the picture is mostly still text rather than movement.
  ///
  /// The one field the server is never told: it picks which way the encoder
  /// gives when it runs out of room. `flutter_webrtc` has no `contentHint`, so
  /// it becomes the degradation preference.
  final bool detail;

  ScreenOptions copyWith({
    ScreenSourceKind? source,
    int? height,
    int? fps,
    int? videoBitrateKbps,
    bool? audio,
    int? audioBitrateKbps,
    ScreenAccess? access,
    int? viewerLimit,
    ScreenMode? mode,
    bool? detail,
  }) => ScreenOptions(
    source: source ?? this.source,
    height: height ?? this.height,
    fps: fps ?? this.fps,
    videoBitrateKbps: videoBitrateKbps ?? this.videoBitrateKbps,
    audio: audio ?? this.audio,
    audioBitrateKbps: audioBitrateKbps ?? this.audioBitrateKbps,
    access: access ?? this.access,
    viewerLimit: viewerLimit ?? this.viewerLimit,
    mode: mode ?? this.mode,
    detail: detail ?? this.detail,
  );

  factory ScreenOptions.fromJson(Map<String, dynamic> json) => ScreenOptions(
    source: ScreenSourceKind.fromWire(json['source'] as String?),
    height: _int(json['height']),
    fps: _int(json['fps']),
    videoBitrateKbps: _int(json['video_bitrate_kbps']),
    audio: json['audio'] as bool? ?? false,
    audioBitrateKbps: _int(json['audio_bitrate_kbps']),
    access: ScreenAccess.fromWire(json['access'] as String?),
    viewerLimit: _int(json['viewer_limit']),
    mode: ScreenMode.fromWire(json['mode'] as String?),
    detail: json['detail'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'source': source.wire,
    'height': height,
    'fps': fps,
    'video_bitrate_kbps': videoBitrateKbps,
    'audio': audio,
    'audio_bitrate_kbps': audioBitrateKbps,
    'access': access.wire,
    'viewer_limit': viewerLimit,
    'mode': mode.wire,
    'detail': detail,
  };

  static int _int(Object? value) => (value as num?)?.toInt() ?? 0;
}

/// A named set of numbers, as the reference client offers them.
///
/// The numbers are the reference implementation's own preset table, read out of
/// TS6's UI bundle rather than invented: picking 「720」 there and picking it
/// here should produce the same stream.
///
/// The name is not stored. Which preset is selected is derived from the numbers
/// (see [matching]), so the two cannot drift apart — and hand-editing a number
/// lands on "custom" by itself, with nothing to keep in step.
class ScreenPreset {
  const ScreenPreset({
    required this.height,
    required this.fps,
    required this.bitrateKbps,
    this.detail = false,
  });

  /// Capture height; 0 keeps the source's own resolution.
  final int height;
  final int fps;
  final int bitrateKbps;

  /// Whether this preset is for something with small text in it rather than
  /// something moving.
  ///
  /// The reference client switches its track's `contentHint` between "motion"
  /// and "detail" for exactly this. `flutter_webrtc` exposes no `contentHint`,
  /// so this becomes the degradation preference instead — close, not the same,
  /// and worth knowing when a 「演示」 share does not look like the original's.
  final bool detail;

  bool matches(int height, int fps, int bitrateKbps) =>
      this.height == height && this.fps == fps && this.bitrateKbps == bitrateKbps;

  /// The presets the picker offers, in the order it offers them.
  static const all = [
    ScreenPreset(height: 360, fps: 30, bitrateKbps: 1000),
    ScreenPreset(height: 480, fps: 30, bitrateKbps: 1500),
    ScreenPreset(height: 720, fps: 30, bitrateKbps: 2500),
    ScreenPreset(height: 1080, fps: 30, bitrateKbps: 4000),
    ScreenPreset(height: 1440, fps: 30, bitrateKbps: 6000),
    ScreenPreset(height: 0, fps: 60, bitrateKbps: 8000),
    ScreenPreset(height: 0, fps: 5, bitrateKbps: 3000, detail: true),
  ];

  /// The preset these numbers are, or null when they are the user's own.
  static ScreenPreset? matching(int height, int fps, int bitrateKbps) {
    for (final preset in all) {
      if (preset.matches(height, fps, bitrateKbps)) return preset;
    }
    return null;
  }
}
