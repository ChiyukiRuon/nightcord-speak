export '../../util/system_notifications_web.dart' show requestNotificationPermission;

import 'package:flutter/foundation.dart';

import '../../models/crash.dart';
import '../transport/client_transport.dart';
import 'picked_screen_source.dart';

// The browser runs its own picker out of getDisplayMedia; there is no system
// one to ask for — and its audio follows the page's own output routing.
Future<bool> screenPickerAvailable() async => false;
Future<PickedScreenSource?> pickScreenSource() async => null;
Future<void> setScreenAudioOutput(String? name) async {}

String? environmentValue(String name) => null;
String? coreLogDirectory() => null;
void logToCore(String level, String message) => debugPrint('[nightcord:$level] $message');
CrashStatus readCrashStatus(ClientTransport client) => CrashStatus.none;
({String? path, String? error}) buildCrashReport(ClientTransport client) =>
    (path: null, error: 'Reports are on the gateway host');

bool isMissingNativeLibrary(Object error) => false;
