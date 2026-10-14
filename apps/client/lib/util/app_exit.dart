import 'dart:ui' show AppExitType, AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/updates/update_log.dart';

const _channel = MethodChannel('nightcord/lifecycle');

/// Use the same cleanup path as a user closing the main window.
Future<void> exitForUpdate() async {
  if (defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows) {
    await _channel.invokeMethod<void>('quitForUpdate');
  } else {
    final response = await ServicesBinding.instance.exitApplication(
      AppExitType.cancelable,
    );
    if (response == AppExitResponse.cancel) {
      throw StateError('Application exit cancelled');
    }
  }
}

/// Only the main engine owns the core. Secondary engines must never register
/// here: Flutter's default macOS termination handler follows the newest engine.
Future<void> registerMainWindowExit(void Function() shutdown) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
  var stopped = false;
  _channel.setMethodCallHandler((call) async {
    if (call.method != 'shutdown') throw MissingPluginException();
    if (!stopped) {
      updateLogger('info', 'main isolate shutdown started');
      shutdown();
      stopped = true;
    }
    return true;
  });
  await _channel.invokeMethod<void>('ready');
}
