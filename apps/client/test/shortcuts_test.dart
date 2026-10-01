// Keyboard shortcuts (§42).
//
// `Chord.matches` takes the modifier state as arguments rather than reading
// `HardwareKeyboard`, so the matching rule is a plain function and these tests
// need no keyboard, no binding and no window.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/models/settings.dart';
import 'package:nightcord_client/models/shortcuts.dart';

Map<String, dynamic> roundTrip(Settings settings) =>
    jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>;

void main() {
  group('a combination', () {
    test('formats the way a person writes it', () {
      expect(ShortcutSettings.defaultMute.format(), 'Ctrl+Shift+M');
      expect(ShortcutSettings.defaultDeafen.format(), 'Ctrl+Shift+D');
      expect(ShortcutSettings.defaultPushToTalk.format(), 'Ctrl+Shift+P');
    });

    test('spells the modifiers the way the platform does', () {
      // A Mac has no key labelled Alt or Meta — it has Option and Command — and
      // Apple lists the modifiers in the opposite order from this file's
      // Windows-first one. Both spellings are checked on whatever machine this
      // runs on, which is why the getter reads `defaultTargetPlatform` rather
      // than the OS.
      const everything = Chord(
        key: PhysicalKeyboardKey.keyM,
        ctrl: true,
        shift: true,
        alt: true,
        meta: true,
      );
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(everything.format(), 'Cmd+Ctrl+Option+Shift+M');

      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(everything.format(), 'Ctrl+Shift+Alt+Meta+M');
    });

    test('the default the core sends on macOS reads as Command', () {
      // What `ts_settings` produces there. The constant in this file is the
      // Windows spelling, so this is the shape the UI actually receives.
      const macDefault = Chord(key: PhysicalKeyboardKey.keyM, shift: true, meta: true);
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(macDefault.format(), 'Cmd+Shift+M');

      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(macDefault.format(), 'Shift+Meta+M');
    });

    test('matches only its own modifiers', () {
      // The old push-to-talk handler read *live* modifier state, so releasing
      // Ctrl before P made the release look like a different chord and
      // transmission never stopped. Exact matching is what fixes that, so it is
      // worth pinning down.
      const mute = ShortcutSettings.defaultMute;

      expect(
        mute.matches(PhysicalKeyboardKey.keyM, ctrl: true, shift: true, alt: false, meta: false),
        isTrue,
      );
      expect(
        mute.matches(PhysicalKeyboardKey.keyM, ctrl: true, shift: false, alt: false, meta: false),
        isFalse,
        reason: 'Ctrl+M is a different shortcut',
      );
      expect(
        mute.matches(PhysicalKeyboardKey.keyM, ctrl: true, shift: true, alt: true, meta: false),
        isFalse,
        reason: 'an extra modifier is a different shortcut',
      );
      expect(
        mute.matches(PhysicalKeyboardKey.keyN, ctrl: true, shift: true, alt: false, meta: false),
        isFalse,
      );
    });

    test('survives the JSON round trip', () {
      // Through the whole settings object, because that is what crosses the
      // FFI — a chord that only round-trips on its own would be a chord the
      // core hands back differently.
      const chord = Chord(key: PhysicalKeyboardKey.f5, ctrl: false, alt: true);
      final back = Settings.fromJson(
        roundTrip(const Settings(shortcuts: ShortcutSettings(mute: chord, deafen: null, pushToTalk: null))),
      );

      expect(back.shortcuts.mute?.format(), 'Alt+F5');
      expect(back.shortcuts.mute?.alt, isTrue);
      expect(back.shortcuts.mute?.ctrl, isFalse);
      expect(back.shortcuts.deafen, isNull, reason: 'cleared chords stay cleared');
    });

    test('an unknown key code is unbound rather than a crash', () {
      // A hand-edited file, or one written by a build that knew a key this one
      // does not. A chord that cannot be matched is not a chord.
      final settings = Settings.fromJson(const {
        'shortcuts': {
          'mute': {'key': 99999999, 'ctrl': true},
        },
      });

      expect(settings.shortcuts.mute, isNull);
    });
  });

  group('the shortcuts section', () {
    test('a file written before it existed comes back with §42s defaults', () {
      // The whole point of defaulting per field: a client whose shortcuts
      // silently stopped working is worse than one that never had them.
      final settings = Settings.fromJson(const {});

      expect(settings.shortcuts.mute?.format(), 'Ctrl+Shift+M');
      expect(settings.shortcuts.deafen?.format(), 'Ctrl+Shift+D');
      expect(settings.shortcuts.pushToTalk?.format(), 'Ctrl+Shift+P');
    });

    test('clearing a shortcut is not the same as never setting it', () {
      // A user who clears a shortcut means it; having it reappear on the next
      // launch would be maddening.
      final cleared = Settings.fromJson(const {
        'shortcuts': {'mute': null},
      });

      expect(cleared.shortcuts.mute, isNull, reason: 'cleared stays cleared');
      expect(cleared.shortcuts.deafen, isNotNull, reason: 'and only that one');
    });

    test('a section replaced by something else falls back to the defaults', () {
      final settings = Settings.fromJson(const {'shortcuts': 42});
      expect(settings.shortcuts.mute?.format(), 'Ctrl+Shift+M');
    });

    test('every action is addressable by name', () {
      // The settings page iterates the enum, so a new action that the lookup
      // does not know about would silently show the wrong binding.
      // The unmentioned ones take their defaults — that is what a `const`
      // constructor with defaults means, and why a *cleared* one has to be
      // written out as an explicit null.
      const settings = ShortcutSettings(mute: Chord(key: PhysicalKeyboardKey.f1));

      expect(settings[ShortcutAction.mute]?.key, PhysicalKeyboardKey.f1);
      expect(settings[ShortcutAction.deafen]?.format(), 'Ctrl+Shift+D');

      const noneBound = ShortcutSettings(deafen: null, pushToTalk: null);
      expect(noneBound[ShortcutAction.deafen], isNull);
      expect(noneBound[ShortcutAction.pushToTalk], isNull);
    });

    test('rebinding one action leaves the others alone', () {
      var settings = const ShortcutSettings();
      settings = settings.withBinding(ShortcutAction.deafen, null);

      expect(settings.deafen, isNull);
      expect(settings.mute?.format(), 'Ctrl+Shift+M');
      expect(settings.pushToTalk?.format(), 'Ctrl+Shift+P');
    });
  });
}
