export '../../util/system_notifications_web.dart' show requestNotificationPermission;

import 'package:flutter/foundation.dart';

import '../../models/crash.dart';
import '../transport/client_transport.dart';

String? environmentValue(String name) => null;
String? coreLogDirectory() => null;
void logToCore(String level, String message) => debugPrint('[nightcord:$level] $message');
CrashStatus readCrashStatus(ClientTransport client) => CrashStatus.none;
({String? path, String? error}) buildCrashReport(ClientTransport client) =>
    (path: null, error: 'Reports are on the gateway host');

bool isMissingNativeLibrary(Object error) => false;
