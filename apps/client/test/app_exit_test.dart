import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/util/app_exit.dart';

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
}
