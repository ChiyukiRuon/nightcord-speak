import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/core/screen/screen_audio_output.dart';
import 'package:nightcord_client/models/settings.dart';

void main() {
  test('the voice engine\'s id maps to the plugin\'s bare guid', () {
    // The settings speak `wasapi:{guid}`; the plugin's list speaks `{guid}`.
    expect(
      pluginOutputDeviceId('wasapi:{0.0.1.00000000}.{a1b2}', [
        '{0.0.1.00000000}.{a1b2}',
        'default',
      ]),
      '{0.0.1.00000000}.{a1b2}',
    );
  });

  test('matching tolerates case', () {
    expect(pluginOutputDeviceId('wasapi:{ABC}', ['{abc}']), '{abc}');
  });

  test('an empty setting means the system default', () {
    expect(pluginOutputDeviceId(null, ['default', 'x']), 'default');
    expect(pluginOutputDeviceId('', ['default']), 'default');
    // Regression: the first enumerated endpoint could be an unused HDMI port.
    expect(pluginOutputDeviceId(null, ['{first}', '{second}']), 'default');
    // Native resolution is independent of the plugin's enumeration.
    expect(pluginOutputDeviceId(null, []), 'default');
  });

  test('a device the plugin does not list stays put', () {
    // A miss is a share that keeps playing through the system default, not a
    // failure — so it answers null rather than guessing.
    expect(pluginOutputDeviceId('wasapi:{GONE}', ['default']), isNull);
  });

  test(
    'settings echoes do not restart output and changes are serialized',
    () async {
      // Regression: one edit and its echo both reconfigured the running engine.
      final entered = <String?>[];
      final first = Completer<void>();
      final router = ScreenAudioOutputRouter((settings) async {
        entered.add(settings?.audio.outputDevice);
        if (entered.length == 1) await first.future;
      });
      final headphones = Settings.fromJson({
        'audio': {'output_device': 'headphones'},
      });
      final speaker = Settings.fromJson({
        'audio': {'output_device': 'speaker'},
      });
      final pending = [
        router.apply(headphones),
        router.apply(headphones),
        router.apply(speaker),
      ];
      await Future<void>.delayed(Duration.zero);
      expect(entered, ['headphones']);
      first.complete();
      await Future.wait(pending);
      expect(entered, ['headphones', 'speaker']);
      await router.apply(null);
      expect(entered, ['headphones', 'speaker', null]);
    },
  );

  test(
    'a failed output can be retried and does not block later selections',
    () async {
      // Regression: a failed switch left all subsequent routes silent until reconnect.
      var attempts = 0;
      final router = ScreenAudioOutputRouter((_) async {
        if (++attempts == 1) throw StateError('device unavailable');
      });
      await expectLater(router.apply(null), throwsStateError);
      await router.apply(null);
      await router.apply(null);
      expect(attempts, 2);
    },
  );
  test('returning to the old route after a failure reapplies it', () async {
    // The previous engine may have stopped when a new route failed to start.
    final calls = <String?>[];
    final router = ScreenAudioOutputRouter((settings) async {
      final id = settings?.audio.outputDevice;
      calls.add(id);
      if (id == 'gone') throw StateError('failed restart');
    });
    await router.apply(null);
    await expectLater(
      router.apply(
        Settings.fromJson({
          'audio': {'output_device': 'gone'},
        }),
      ),
      throwsStateError,
    );
    await router.apply(null);
    expect(calls, [null, 'gone', null]);
  });
}
