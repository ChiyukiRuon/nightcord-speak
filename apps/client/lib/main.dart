// Nightcord Speak — the Flutter front-end.
//
// Everything below this file talks to the Rust core through `providers`; the
// only place that knows about FFI is `ffi/`.

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ffi/rust_client.dart';
import 'providers/providers.dart';
import 'theme/app_theme.dart';
import 'widgets/startup_failure.dart';
import 'widgets/app_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Installed before anything else can fail, and before the core is asked to
  // start — the failure worth recording might be that very call.
  _recordUncaughtErrors();

  // The core is started before the first frame rather than lazily by a
  // provider, so a missing or mismatched shared library produces one clear
  // screen instead of an exception thrown from inside a build method.
  RustClient? client;
  Object? failure;
  StackTrace? trace;

  try {
    client = RustClient.start();
  } catch (error, stack) {
    failure = error;
    trace = stack;
  }

  if (failure != null) {
    runApp(StartupFailureApp(error: failure, stackTrace: trace, theme: buildAppTheme()));
    return;
  }

  runApp(
    ProviderScope(
      // The already-started client, so nothing starts a second one.
      overrides: [rustClientProvider.overrideWithValue(client!)],
      child: const NightcordApp(),
    ),
  );
}

/// Sends uncaught errors to the same log the core writes to.
///
/// In a release build these used to reach only the platform's console, which
/// nobody running an installed app ever reads. The core's own failures already
/// land in the log; leaving Dart's to vanish would make a bug report a coin
/// toss over which half of the story survived.
void _recordUncaughtErrors() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    // The existing handler first: it prints the whole report, and one line in
    // a log file is not a replacement for it.
    (previous ?? FlutterError.presentError)(details);
    logToCore('error', '${details.exceptionAsString()}\n${details.stack ?? ''}');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    logToCore('error', '$error\n$stack');
    // Deliberately not claimed. Returning true would swallow the error and
    // leave the app running in whatever state produced it; whether that should
    // change is a question about error policy, not about logging, so this
    // keeps the behaviour that was already there and only adds the record.
    return false;
  };
}

/// The application.
class NightcordApp extends StatelessWidget {
  /// Builds the app.
  const NightcordApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nightcord Speak',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const AppShell(),
    );
  }
}
