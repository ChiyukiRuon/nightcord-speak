// Shown when the Rust core could not start at all.
//
// This is deliberately not a dialog: without the core there is nothing the app
// can do, and the person running it is a developer who needs the paths that
// were tried.

import 'package:flutter/material.dart';

import '../ffi/native.dart';
import '../ffi/rust_client.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../util/reveal.dart';

/// A minimal app that explains why the core is missing.
class StartupFailureApp extends StatelessWidget {
  /// Wraps the failure.
  const StartupFailureApp({
    required this.error,
    required this.theme,
    this.stackTrace,
    super.key,
  });

  /// What went wrong.
  final Object error;

  /// Where, when it is known.
  final StackTrace? stackTrace;

  /// The theme to use, so the screen matches the app it failed to start.
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nightcord Speak',
      debugShowCheckedModeBanner: false,
      theme: theme,
      // No `locale:` here on purpose: this screen runs when the core did not
      // start, and the core is what owns the language setting. The system's
      // language is the only honest answer left.
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: _FailureScreen(error: error, stackTrace: stackTrace),
    );
  }
}

/// The screen itself.
///
/// A separate widget rather than inlined into [StartupFailureApp]: the strings
/// are read with `AppLocalizations.of`, and that has to happen *below* the
/// `MaterialApp` that installs the delegate.
class _FailureScreen extends StatelessWidget {
  const _FailureScreen({required this.error, this.stackTrace});

  final Object error;
  final StackTrace? stackTrace;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.danger, size: 28),
                    const SizedBox(width: 12),
                    Text(
                      l10n.startupFailureTitle,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SelectableText(
                  '$error',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (error is! NativeLibraryNotFound && stackTrace != null) ...[
                  const SizedBox(height: 24),
                  Text(l10n.stackTraceLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  SelectableText(
                    '$stackTrace',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      height: 1.4,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
                if (coreLogDirectory() case final directory?) ...[
                  const SizedBox(height: 24),
                  Text(l10n.logLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  // A core that failed to start still wrote a reason down —
                  // if the library could be loaded far enough to have one.
                  Text(
                    l10n.startupFailureLogHint,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    directory,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => revealDirectory(directory),
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: Text(l10n.openLogFolder),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
