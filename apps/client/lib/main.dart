// Nightcord Speak — the Flutter front-end.
//
// Everything below this file talks to the Rust core through `providers`; the
// only place that knows about FFI is `ffi/`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ffi/rust_client.dart';
import 'providers/providers.dart';
import 'theme/app_theme.dart';
import 'widgets/startup_failure.dart';
import 'widgets/app_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

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
