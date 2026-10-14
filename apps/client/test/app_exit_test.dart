import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/util/app_exit.dart';
import 'package:nightcord_client/core/updates/update_windows.dart';
import 'package:nightcord_client/core/updates/update_macos.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('nightcord/lifecycle');
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<Object?> shutdown() async {
    final response = Completer<Object?>();
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(const MethodCall('shutdown')),
      (data) => response.complete(codec.decodeEnvelope(data!)),
    );
    return response.future;
  }

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
    channel.setMethodCallHandler(null);
  });

  test(
    'main isolate is ready only after its shutdown handler is installed',
    () async {
      // A child engine used to receive macOS exit requests, skipping core cleanup.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'ready');
        expect(await shutdown(), isTrue);
        expect(calls, 1);
        return null;
      });
      await registerMainWindowExit(() => calls++);
      expect(await shutdown(), isTrue);
      expect(calls, 1);
    },
  );

  test('startup failure can exit cleanly without a core', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    await registerMainWindowExit(() {});
    expect(await shutdown(), isTrue);
  });

  test('other platforms keep their existing lifecycle', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    messenger.setMockMethodCallHandler(channel, (_) async {
      fail('macOS channel was invoked');
    });
    await registerMainWindowExit(() => fail('shutdown was invoked'));
  });

  test('Windows update exits through the main native window', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    var requests = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'quitForUpdate');
      requests++;
      return null;
    });
    await exitForUpdate();
    expect(requests, 1);
  });

  test(
    'Windows passes helper paths intact to the native GUI launcher',
    () async {
      const script = "C:\\更新's path\\helper.ps1";
      const configuration = "C:\\更新's path\\update.json";
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'startUpdateHelper');
        expect(call.arguments, {
          'script': script,
          'configuration': configuration,
        });
        return 12345;
      });
      expect(await launchWindowsUpdateHelper(script, configuration), 12345);
    },
  );
  test('macOS helper startup uses the native lifecycle channel', () async {
    const configuration = '/tmp/更新路径/update.json';
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'startUpdateHelper');
      expect(call.arguments, {'configuration': configuration});
      return 23456;
    });
    expect(await launchMacOSUpdateHelper(configuration), 23456);
  });
}
