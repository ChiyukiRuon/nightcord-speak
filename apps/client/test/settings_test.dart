// The settings model, and its agreement with what the core stores.
//
// These are the Dart half of a contract: the JSON here is produced and consumed
// by `ts_settings::Settings`, and a field renamed on one side and not the other
// would silently reset a user's preferences.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/models/domain.dart';
import 'package:nightcord_client/models/settings.dart';

Map<String, dynamic> roundTrip(Settings settings) =>
    jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>;

void main() {
  group('settings', () {
    test('survive the JSON round trip unchanged', () {
      const settings = Settings(
        audio: AudioSettings(
          inputDevice: 'wasapi:Headset',
          outputDevice: null,
          mode: VoiceActivationMode.pushToTalk,
          activation: VoiceActivationSettings(
            sensitivity: 0.21,
            attackMs: 45,
            releaseMs: 250,
          ),
        ),
        connection: ConnectionSettings(
          nickname: 'Alice',
          profile: 'alt',
          maxReconnectAttempts: 3,
        ),
      );

      final json = roundTrip(settings);
      expect(Settings.fromJson(json).toJson(), settings.toJson());
    });

    test('an empty object is the defaults, not a crash', () {
      // The first run has no file, and the core answers with a full object
      // anyway — but a hand-edited file can be missing any of it.
      final settings = Settings.fromJson(const {});

      expect(settings.audio.inputDevice, isNull);
      expect(settings.audio.mode, VoiceActivationMode.voiceActivation);
      expect(settings.connection.nickname, 'Nightcord User');
      expect(settings.connection.profile, 'default');
      expect(settings.connection.maxReconnectAttempts, isNull);
    });

    test('a section replaced by something else falls back to defaults', () {
      // What "settings.json: audio: 42" looks like. Refusing to open the
      // settings screen over it would be worse than ignoring it.
      final settings = Settings.fromJson(const {'audio': 42, 'connection': 'nope'});

      expect(settings.audio, isA<AudioSettings>());
      expect(settings.audio.activation.sensitivity, 0.05);
      expect(settings.connection.nickname, 'Nightcord User');
    });

    test('never retrying is not the same as retrying forever', () {
      // The two are one field apart — `0` versus `null` — and getting it
      // backwards means either a client that never comes back or one that never
      // stops.
      expect(const ConnectionSettings(maxReconnectAttempts: 0).toJson()['max_reconnect_attempts'], 0);
      expect(const ConnectionSettings().toJson()['max_reconnect_attempts'], isNull);

      final off = Settings.fromJson(const {
        'connection': {'max_reconnect_attempts': 0},
      });
      final forever = Settings.fromJson(const {
        'connection': {'max_reconnect_attempts': null},
      });
      expect(off.connection.maxReconnectAttempts, 0);
      expect(forever.connection.maxReconnectAttempts, isNull);
    });

    test('clearing a device selection is expressible', () {
      // `copyWith` cannot set a nullable field back to null by passing null —
      // that is what `copyWith` means everywhere else — so going back to the
      // system default says so explicitly.
      const chosen = AudioSettings(inputDevice: 'wasapi:Headset');
      expect(chosen.copyWith().inputDevice, 'wasapi:Headset');
      expect(chosen.copyWith(clearInputDevice: true).inputDevice, isNull);
      expect(chosen.copyWith(inputDevice: 'wasapi:Other').inputDevice, 'wasapi:Other');
    });

    test('notification switches default to on and round trip', () {
      // A settings file written before this section existed has no
      // `notifications` key, and it has to come back with the switches *on*:
      // a client that starts silent looks broken rather than quiet.
      final bare = Settings.fromJson(const {});
      expect(bare.notifications.presence, isTrue);
      expect(bare.notifications.directMessage, isTrue);
      expect(bare.notifications.system, isTrue);

      const oneOff = Settings(
        notifications: NotificationSettings(presence: false, directMessage: false),
      );
      final back = Settings.fromJson(roundTrip(oneOff));
      expect(back.notifications.presence, isFalse);
      expect(back.notifications.directMessage, isFalse);
      // Turning one off must not turn the others off.
      expect(back.notifications.channelMessage, isTrue);
      expect(back.notifications.poke, isTrue);
    });

    test('the mode names are the ones the core accepts', () {
      // The transmission mode travels inside this object now, so renaming one
      // here would silently change what the core does.
      for (final mode in VoiceActivationMode.values) {
        final json = Settings(audio: AudioSettings(mode: mode)).toJson();
        final audio = json['audio'] as Map<String, dynamic>;
        expect(VoiceActivationMode.fromWire(audio['mode'] as String), mode);
      }
    });
  });
}
