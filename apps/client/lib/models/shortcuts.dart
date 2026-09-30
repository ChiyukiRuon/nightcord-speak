// Keyboard shortcuts (§42).
//
// The shape mirrors `ts_settings::ShortcutSettings` — which is why the key is
// stored as a raw code rather than something prettier. See [Chord].

import 'package:flutter/services.dart';

/// What a shortcut can set off.
enum ShortcutAction {
  mute('静音'),
  deafen('耳聋'),
  pushToTalk('按键说话');

  const ShortcutAction(this.label);

  /// What the settings screen calls it.
  final String label;
}

/// One key combination.
///
/// A **physical** key rather than a letter: on an AZERTY keyboard the key where
/// QWERTY has M is somewhere else entirely, and a shortcut — push to talk above
/// all — is about where the hand goes, not what letter comes out.
///
/// The cost is [key], which is a USB HID usage code. Flutter can look a key up
/// by code but not by name, so storing the name would not round-trip; the
/// settings dialog is the editor and the file is written for a machine.
class Chord {
  const Chord({
    required this.key,
    this.ctrl = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
  });

  /// The physical key, as `PhysicalKeyboardKey` identifies it.
  final PhysicalKeyboardKey key;

  final bool ctrl;
  final bool shift;
  final bool alt;
  final bool meta;

  /// Whether a press of [key] with exactly these modifiers held is this one.
  ///
  /// The modifiers are arguments rather than read from `HardwareKeyboard`: that
  /// makes the rule a pure function, testable without a keyboard — the same
  /// reason `NotificationPolicy` takes a clock instead of calling
  /// `DateTime.now`. It is also what the old push-to-talk handler got wrong:
  /// reading live modifier state meant that releasing Ctrl before P made the
  /// release look like a different chord, and transmission never stopped.
  bool matches(
    PhysicalKeyboardKey key, {
    required bool ctrl,
    required bool shift,
    required bool alt,
    required bool meta,
  }) =>
      this.key == key &&
      this.ctrl == ctrl &&
      this.shift == shift &&
      this.alt == alt &&
      this.meta == meta;

  /// The combination as a person would write it, e.g. `Ctrl+Shift+M`.
  String format() {
    final parts = <String>[
      if (ctrl) 'Ctrl',
      if (shift) 'Shift',
      if (alt) 'Alt',
      if (meta) 'Meta',
      _keyName(key),
    ];
    return parts.join('+');
  }

  Map<String, dynamic> toJson() => {
    'key': key.usbHidUsage,
    'ctrl': ctrl,
    'shift': shift,
    'alt': alt,
    'meta': meta,
  };

  /// Reads a combination, or null when there is not a usable one here.
  ///
  /// Null covers both "the file says null, meaning unbound" and "the file says
  /// a key this build has never heard of" — an unrecognised code cannot be
  /// matched against anything, so treating it as bound would be a lie the
  /// settings screen could not show.
  static Chord? maybeFromJson(Object? value) {
    if (value is! Map) return null;
    final json = value.cast<String, dynamic>();

    final code = json['key'];
    if (code is! int) return null;

    final key = PhysicalKeyboardKey.findKeyByCode(code);
    if (key == null) return null;

    return Chord(
      key: key,
      ctrl: json['ctrl'] as bool? ?? false,
      shift: json['shift'] as bool? ?? false,
      alt: json['alt'] as bool? ?? false,
      meta: json['meta'] as bool? ?? false,
    );
  }

  /// See [format].
  ///
  /// Flutter spells physical keys out in full — `Key M`, `Digit 1` — which is
  /// right for a debugger and wrong for a settings screen, where the point is
  /// to recognise your own shortcut at a glance.
  static String _keyName(PhysicalKeyboardKey key) {
    final name = key.debugName;
    if (name == null || name.isEmpty) {
      return '0x${key.usbHidUsage.toRadixString(16)}';
    }

    for (final prefix in ['Key ', 'Digit ']) {
      if (name.startsWith(prefix) && name.length > prefix.length) {
        return name.substring(prefix.length);
      }
    }
    return name;
  }
}

/// Which keys do what.
///
/// Each is nullable, and null means *unbound* — deliberately distinct from
/// absent, which falls back to §42's default. A user who clears a shortcut
/// means it, and having it come back on the next launch would be maddening.
class ShortcutSettings {
  const ShortcutSettings({this.mute = defaultMute, this.deafen = defaultDeafen, this.pushToTalk = defaultPushToTalk});

  final Chord? mute;
  final Chord? deafen;
  final Chord? pushToTalk;

  /// §42's combinations, and the defaults a file written before this section
  /// existed comes back with.
  static const Chord defaultMute = Chord(key: PhysicalKeyboardKey.keyM, ctrl: true, shift: true);
  static const Chord defaultDeafen = Chord(key: PhysicalKeyboardKey.keyD, ctrl: true, shift: true);
  static const Chord defaultPushToTalk = Chord(key: PhysicalKeyboardKey.keyP, ctrl: true, shift: true);

  /// The combination bound to [action], or null when it is unbound.
  Chord? operator [](ShortcutAction action) => switch (action) {
    ShortcutAction.mute => mute,
    ShortcutAction.deafen => deafen,
    ShortcutAction.pushToTalk => pushToTalk,
  };

  /// The same settings with [action] bound to [chord], or cleared when it is
  /// null.
  ShortcutSettings withBinding(ShortcutAction action, Chord? chord) => switch (action) {
    ShortcutAction.mute => ShortcutSettings(mute: chord, deafen: deafen, pushToTalk: pushToTalk),
    ShortcutAction.deafen => ShortcutSettings(mute: mute, deafen: chord, pushToTalk: pushToTalk),
    ShortcutAction.pushToTalk => ShortcutSettings(mute: mute, deafen: deafen, pushToTalk: chord),
  };

  factory ShortcutSettings.fromJson(Map<String, dynamic> json) => ShortcutSettings(
    // `containsKey` rather than `??`: a file that says `"mute": null` is a user
    // who cleared it, and a file that does not mention `mute` at all predates
    // this section. Only the second gets §42's default.
    mute: json.containsKey('mute') ? Chord.maybeFromJson(json['mute']) : defaultMute,
    deafen: json.containsKey('deafen') ? Chord.maybeFromJson(json['deafen']) : defaultDeafen,
    pushToTalk: json.containsKey('push_to_talk')
        ? Chord.maybeFromJson(json['push_to_talk'])
        : defaultPushToTalk,
  );

  /// Whether every action is unbound, which is what a cleared section looks
  /// like. Not the same as the defaults.
  bool get isEmpty => mute == null && deafen == null && pushToTalk == null;

  Map<String, dynamic> toJson() => {
    'mute': mute?.toJson(),
    'deafen': deafen?.toJson(),
    'push_to_talk': pushToTalk?.toJson(),
  };
}
