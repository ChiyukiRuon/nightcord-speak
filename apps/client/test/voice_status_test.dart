// The audio engine's state, as the core reports it.
//
// The contract with `nightcord_voice_status`: a field renamed on one side and
// not the other would leave the meter flat and the "which device is in use"
// line blank, with nothing on screen to say why.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/models/voice_status.dart';

Map<String, dynamic> roundTrip(Map<String, dynamic> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

void main() {
  group('device status', () {
    test('a fallback is distinguishable from choosing the default', () {
      // The whole reason `fell_back` exists: "you are on the system default
      // because you chose it" and "you are on the system default because the
      // headset you chose is gone" look identical otherwise, and only one of
      // them is worth telling someone about.
      final chosen = DeviceStatus.fromJson(const {
        'id': 'wasapi:default',
        'name': 'Speakers',
        'available': true,
        'fell_back': false,
      });
      final fellBack = DeviceStatus.fromJson(const {
        'id': 'wasapi:default',
        'name': 'Speakers',
        'available': true,
        'fell_back': true,
      });

      expect(chosen.fellBack, isFalse);
      expect(fellBack.fellBack, isTrue);
    });

    test('an unnamed device falls back to its id', () {
      // Some hosts hand back an empty name; showing nothing at all would read
      // as "no device".
      const unnamed = DeviceStatus(id: 'wasapi:headset', name: '  ');
      expect(unnamed.displayName, 'wasapi:headset');
    });
  });

  group('voice status', () {
    test('an engine that is not running is not a failure', () {
      // What the core answers before 开始语音. Rendering it as an error would
      // put a banner on screen every time the settings page opened.
      final status = VoiceStatus.fromJson(const {
        'input': null,
        'output': null,
        'level': 0.0,
        'peak': 0.0,
        'transmitting': false,
        'healthy': false,
      });

      expect(status.running, isFalse);
      expect(status.level, 0.0);
      expect(status.input, isNull);
    });

    test('a running engine reports both sides and a level', () {
      final status = VoiceStatus.fromJson(const {
        'input': {'id': 'wasapi:mic', 'name': 'Headset Mic', 'available': true, 'fell_back': false},
        'output': {'id': 'wasapi:spk', 'name': 'Headset', 'available': false, 'fell_back': true},
        'level': 0.42,
        'peak': 0.93,
        'transmitting': true,
        'healthy': false,
      });

      expect(status.running, isTrue);
      expect(status.input?.displayName, 'Headset Mic');
      expect(status.output?.available, isFalse);
      expect(status.output?.fellBack, isTrue);
      expect(status.level, closeTo(0.42, 1e-9));
      expect(status.transmitting, isTrue);
      expect(status.healthy, isFalse);
    });

    test('an integer where a level is expected still parses', () {
      // JSON has one number type; a level that happens to be exactly 0 or 1
      // arrives as an int and would throw on a plain `as double`.
      expect(VoiceStatus.fromJson(const {'level': 0}).level, 0.0);
      expect(VoiceStatus.fromJson(const {'level': 1}).level, 1.0);
    });

    test('a missing or unexpected payload falls back rather than throwing', () {
      // A newer core, or a hand-edited shape. Nothing here is worth a crash.
      expect(VoiceStatus.fromJson(const {}).running, isFalse);
      expect(VoiceStatus.fromJson(const {'input': 'nonsense'}).input, isNull);
    });

    test('the shape survives the JSON round trip', () {
      const json = {
        'input': {'id': 'a', 'name': 'b', 'available': true, 'fell_back': true},
        'output': null,
        'level': 0.1,
        'peak': 0.2,
        'transmitting': false,
        'healthy': true,
      };

      final status = VoiceStatus.fromJson(roundTrip(json));
      expect(status.input?.id, 'a');
      expect(status.input?.fellBack, isTrue);
      expect(status.output, isNull);
      expect(status.healthy, isTrue);
    });
  });
}
