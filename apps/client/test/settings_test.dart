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

    test('the language defaults to following the system and round trips', () {
      // A file written before this section existed has no `ui` key, and it has
      // to come back as null — "follow the system" — not as a fixed language
      // nobody chose.
      final bare = Settings.fromJson(const {});
      expect(bare.ui.language, isNull);

      const english = Settings(ui: UiSettings(language: 'en'));
      final back = Settings.fromJson(roundTrip(english));
      expect(back.ui.language, 'en');
    });

    test('an unrecognized language reads as following the system', () {
      // Hand-edited, or a language this build does not have yet. The stored
      // value survives — a future build may know it — but what the UI acts on
      // is null, so a typo cannot make the locale lookup match nothing.
      const unknown = UiSettings(language: 'fr');
      expect(unknown.requestedLanguage, isNull);
      expect(unknown.toJson()['language'], 'fr');

      expect(const UiSettings(language: 'zh').requestedLanguage, 'zh');
      expect(const UiSettings().requestedLanguage, isNull);
    });

    test('going back to following the system is expressible', () {
      // The same convention as the audio devices: null cannot mean "clear" in
      // a `copyWith`, so choosing 「跟随系统」 says so explicitly.
      const chosen = UiSettings(language: 'en');
      expect(chosen.copyWith(language: 'zh').language, 'zh');
      expect(chosen.copyWith().language, 'en');
      expect(chosen.copyWith(clearLanguage: true).language, isNull);
    });

    test('the theme defaults to the app default and round trips', () {
      // Unlike the language, an absent theme is *not* "follow the system" — it
      // is Nightcord, so that a file written before the key existed means
      // "whatever the app ships with" rather than freezing today's default.
      final bare = Settings.fromJson(const <String, dynamic>{});
      expect(bare.ui.theme, isNull);
      expect(bare.ui.requestedTheme, isNull);

      const black = Settings(ui: UiSettings(theme: 'black'));
      final back = Settings.fromJson(black.toJson());
      expect(back.ui.theme, 'black');
      expect(back.ui.requestedTheme, 'black');
    });

    test('an unrecognized theme reads as the default', () {
      // A hand-edited file, or a theme a newer build has. The stored value
      // stays — see the round trip above — but the UI falls back rather than
      // matching no palette.
      const unknown = UiSettings(theme: 'solarized');
      expect(unknown.requestedTheme, isNull);
      expect(unknown.toJson()['theme'], 'solarized');

      for (final known in ['nightcord', 'black', 'white', 'system']) {
        expect(UiSettings(theme: known).requestedTheme, known);
      }
    });

    test('every theme value survives a round trip', () {
      for (final name in ['nightcord', 'black', 'white', 'system']) {
        final settings = Settings(ui: UiSettings(theme: name));
        expect(Settings.fromJson(settings.toJson()).ui.theme, name);
      }
    });

    test('a theme change leaves the language alone', () {
      const both = UiSettings(language: 'en', theme: 'black');
      final changed = both.copyWith(theme: 'white');
      expect(changed.theme, 'white');
      expect(changed.language, 'en', reason: 'the two settings are independent');
    });
  });

  group('audio and volume', () {
    test('a file written before any of it existed comes back at the defaults', () {
      // The upgrade path, and the one that would be a silent bug: a missing
      // volume read as 0 would load every existing file muted.
      final audio = AudioSettings.fromJson(const <String, dynamic>{
        'input_device': 'wasapi:Mic',
        'mode': 'push_to_talk',
      });

      expect(audio.inputDevice, 'wasapi:Mic');
      expect(audio.mode, VoiceActivationMode.pushToTalk);
      expect(audio.outputVolume, 1.0);
    });

    test('a file that still carries a codec and a quality still loads', () {
      // The keys are gone from the model, so the core ignores them and so does
      // this — which is what makes removing a field safe.
      final audio = AudioSettings.fromJson(const <String, dynamic>{
        'codec': 'music',
        'voice_quality': 9,
        'music_quality': 10,
        'output_volume': 0.5,
      });

      expect(audio.outputVolume, closeTo(0.5, 1e-9));
    });

    test('an out-of-range volume from a hand-edited file is pulled into range', () {
      expect(
        AudioSettings.fromJson(const <String, dynamic>{'output_volume': 7.5}).outputVolume,
        1.0,
      );
      expect(
        AudioSettings.fromJson(const <String, dynamic>{'output_volume': -3}).outputVolume,
        0.0,
      );
    });

    test('the volume survives a round trip', () {
      const settings = Settings(audio: AudioSettings(outputVolume: 0.4));
      final back = Settings.fromJson(settings.toJson()).audio;
      expect(back.outputVolume, closeTo(0.4, 1e-9));
    });

    test('copyWith leaves the volume alone when it was not given', () {
      const audio = AudioSettings(outputVolume: 0.25);
      final changed = audio.copyWith(mode: VoiceActivationMode.continuous);

      expect(changed.mode, VoiceActivationMode.continuous);
      expect(changed.outputVolume, closeTo(0.25, 1e-9));
    });

    test('the settings still carry nothing about the codec', () {
      // The encoder runs the stereo profile at the top of its range and has no
      // knobs, so nothing about it belongs in a file the user can edit. This
      // fails if somebody adds one back.
      final json = const Settings().toJson()['audio'] as Map<String, dynamic>;
      expect(json.keys, isNot(contains('codec')));
      expect(json.keys, isNot(contains('voice_quality')));
      expect(json.keys, isNot(contains('music_quality')));
      expect(json.keys, contains('output_volume'));
    });
  });

  group('the moderation vocabulary', () {
    test('a kick scope encodes as the bare string the core parses', () {
      // Externally tagged unit variants: the quotes are part of the encoding,
      // and dropping them makes the core reject the whole command.
      expect(jsonEncode(KickScope.channel.wire), '"channel"');
      expect(jsonEncode(KickScope.server.wire), '"server"');
    });

    test('a permanent ban is not a number of seconds', () {
      // The wire spells permanent as zero, which is the value a mistake would
      // be least likely to notice — so the type does not offer it.
      expect(jsonEncode(BanDuration.permanent.encoded), '"permanent"');
      expect(jsonEncode(BanDuration.seconds(600).encoded), '{"seconds":600}');
      expect(BanDuration.permanent.isPermanent, isTrue);
      expect(BanDuration.seconds(0).isPermanent, isFalse);
    });

    test('the two kick scopes are not interchangeable', () {
      expect(KickScope.channel, isNot(KickScope.server));
      expect(BanDuration.seconds(60), BanDuration.seconds(60));
      expect(BanDuration.seconds(60), isNot(BanDuration.seconds(61)));
      expect(BanDuration.permanent, isNot(BanDuration.seconds(60)));
    });
  });
}
