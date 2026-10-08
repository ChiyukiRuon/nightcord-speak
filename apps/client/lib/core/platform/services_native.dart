import 'dart:io';

import 'package:flutter/services.dart';

import '../../ffi/rust_client.dart';
import '../../ffi/native.dart';
import '../../models/crash.dart';
import '../transport/client_transport.dart';
import 'picked_screen_source.dart';

export '../../ffi/rust_client.dart' show coreLogDirectory, logToCore;

String? environmentValue(String name) => Platform.environment[name];
CrashStatus readCrashStatus(ClientTransport client) =>
    client is RustClient ? client.crashStatus() : CrashStatus.none;
({String? path, String? error}) buildCrashReport(ClientTransport client) =>
    client is RustClient
    ? client.buildCrashReport()
    : (path: null, error: 'No embedded core');

bool isMissingNativeLibrary(Object error) => error is NativeLibraryNotFound;
Future<void> requestNotificationPermission() async {}

/// Whether screen sharing picks its source in the system's own picker here.
///
/// macOS only, and macOS 14+ at that; the runner answers, because only it can
/// know which system it is on.
Future<bool> screenPickerAvailable() async {
  if (!Platform.isMacOS) return false;
  try {
    return await const MethodChannel('nightcord/screen_picker')
            .invokeMethod<bool>('available') ??
        false;
  } catch (_) {
    return false;
  }
}

/// Points the shared-screen audio at a specific output device, or at the
/// system default when [name] is null. macOS only; Windows and the browser
/// have their own routes (see `core/screen/screen_audio_output.dart`).
Future<void> setScreenAudioOutput(String? name) async {
  if (!Platform.isMacOS) return;
  await const MethodChannel('nightcord/screen_picker')
      .invokeMethod<void>('setOutputDevice', {'device': name ?? ''});
}

/// Shows the system picker and returns the choice, or null when the user
/// backed out (or the picker could not appear).
Future<PickedScreenSource?> pickScreenSource() async {
  if (!Platform.isMacOS) return null;
  try {
    final picked = await const MethodChannel('nightcord/screen_picker')
        .invokeMethod<Map<dynamic, dynamic>>('pick');
    if (picked == null) return null;
    return PickedScreenSource(
      id: picked['id'] as String,
      name: picked['name'] as String,
      kind: picked['kind'] as String,
    );
  } catch (_) {
    return null;
  }
}
