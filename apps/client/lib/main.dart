// Nightcord Speak — the Flutter front-end.
//
// Everything below this file talks to the Rust core through `providers`; the
// only place that knows about FFI is `ffi/`.

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'design/theme/app_theme.dart';
import 'design/tokens/app_palette.dart';
import 'ffi/rust_client.dart';
import 'l10n/app_localizations.dart';
import 'providers/providers.dart';
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
    // The system locale, not the setting: the setting lives in the core, and
    // the core is what failed to start. It only decides which font family the
    // screen is drawn in (`docs/UI字体规范.md` §5), so guessing from the
    // operating system is as good as it gets here — and better than assuming
    // English on a Chinese desktop.
    runApp(
      StartupFailureApp(
        error: failure,
        stackTrace: trace,
        // Nightcord, not the theme setting: the setting lives in the
        // core, and the core is what failed to start.
        theme: buildAppTheme(AppPalette.nightcord, PlatformDispatcher.instance.locale),
      ),
    );
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
///
/// Consumer rather than plain widget because the language is a setting: the
/// core answers it a moment after the first frame, and the whole tree — the
/// window's strings, the Material widgets' own labels — has to turn over when
/// it does.
class NightcordApp extends ConsumerWidget {
  /// Builds the app.
  const NightcordApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Both resolved to concrete values in `providers.dart` — see there for why
    // neither is left to `MaterialApp`'s own resolution.
    final locale = ref.watch(localeProvider);
    final themes = ref.watch(themeChoiceProvider);

    return MaterialApp(
      title: 'Nightcord Speak',
      debugShowCheckedModeBanner: false,
      // Two slots rather than one. Choosing a theme explicitly fills both with
      // it, so the system's brightness cannot override the choice; "follow the
      // system" is the one case where they differ (White by day, Black by
      // night).
      //
      // `themeMode` stays `system` in every case, which is what makes the
      // follow-the-system case live: `MaterialApp` watches
      // `didChangePlatformBrightness` itself, so flipping the operating
      // system's theme changes the client without a restart.
      //
      // Each theme is rebuilt when the language changes too, because the font
      // family follows the locale (`docs/UI字体规范.md` §5) — so this is one
      // `ThemeData` per (theme, language) pair rather than one per frame.
      theme: buildAppTheme(themes.light, locale),
      darkTheme: buildAppTheme(themes.dark, locale),
      themeMode: ThemeMode.system,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const AppShell(),
    );
  }
}
