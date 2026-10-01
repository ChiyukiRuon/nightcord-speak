// What the audio engine is doing, as the core reports it.
//
// The shape mirrors what `nightcord_voice_status` answers, field for field.
// The distinguishing field is [DeviceStatus.fellBack]: "something is open" and
// "the one you asked for is open" are different answers, and a user who thinks
// they are on a headset while the laptop's microphone is live has no other way
// to find out.

/// A device the engine actually opened.
class DeviceStatus {
  const DeviceStatus({
    required this.id,
    required this.name,
    this.available = true,
    this.fellBack = false,
  });

  /// The id that was actually opened — not the one that was asked for.
  final String id;

  final String name;

  /// Whether the stream is still alive. False after the device is unplugged.
  final bool available;

  /// Whether the configured device could not be found and this is the system
  /// default standing in for it.
  final bool fellBack;

  /// What to call it in the UI.
  String get displayName => name.trim().isEmpty ? id : name;

  factory DeviceStatus.fromJson(Map<String, dynamic> json) => DeviceStatus(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    available: json['available'] as bool? ?? true,
    fellBack: json['fell_back'] as bool? ?? false,
  );

  /// Reads one side, tolerating an absent or unexpected payload.
  static DeviceStatus? maybe(Object? value) =>
      value is Map ? DeviceStatus.fromJson(value.cast<String, dynamic>()) : null;
}

/// The state of the audio engine at one moment.
class VoiceStatus {
  const VoiceStatus({
    this.input,
    this.output,
    this.level = 0,
    this.peak = 0,
    this.transmitting = false,
    this.healthy = false,
    this.bitrate,
  });

  /// The microphone, or null when none is open.
  final DeviceStatus? input;

  /// The speakers, or null when none is open.
  final DeviceStatus? output;

  /// The most recent frame's loudness, `0.0..=1.0`.
  final double level;

  /// The most recent frame's peak. Above 1.0 is clipping.
  final double peak;

  /// Whether the gate is open right now.
  final bool transmitting;

  /// Whether both open streams are still running.
  final bool healthy;

  /// What the encoder is sending, in bits per second, or null with no engine.
  ///
  /// Computed by the core, which owns the number. A copy of it here would be
  /// free to drift from the one doing the encoding, and "what am I actually
  /// sending" is exactly the question nobody can answer from the settings — the
  /// encoder has no settings.
  final int? bitrate;

  /// Whether voice has been started at all.
  bool get running => input != null || output != null;

  factory VoiceStatus.fromJson(Map<String, dynamic> json) => VoiceStatus(
    input: DeviceStatus.maybe(json['input']),
    output: DeviceStatus.maybe(json['output']),
    level: (json['level'] as num?)?.toDouble() ?? 0,
    peak: (json['peak'] as num?)?.toDouble() ?? 0,
    transmitting: json['transmitting'] as bool? ?? false,
    healthy: json['healthy'] as bool? ?? false,
    bitrate: (json['bitrate_bps'] as num?)?.round(),
  );
}
