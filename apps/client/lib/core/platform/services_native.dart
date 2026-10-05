import 'dart:io';

import '../../ffi/rust_client.dart';
import '../../ffi/native.dart';
import '../../models/crash.dart';
import '../transport/client_transport.dart';

export '../../ffi/rust_client.dart' show coreLogDirectory, logToCore;

String? environmentValue(String name) => Platform.environment[name];
CrashStatus readCrashStatus(ClientTransport client) =>
    client is RustClient ? client.crashStatus() : CrashStatus.none;
({String? path, String? error}) buildCrashReport(ClientTransport client) =>
    client is RustClient ? client.buildCrashReport() : (path: null, error: 'No embedded core');

bool isMissingNativeLibrary(Object error) => error is NativeLibraryNotFound;
Future<void> requestNotificationPermission() async {}
