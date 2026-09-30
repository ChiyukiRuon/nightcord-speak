// Shown when the Rust core could not start at all.
//
// This is deliberately not a dialog: without the core there is nothing the app
// can do, and the person running it is a developer who needs the paths that
// were tried.

import 'package:flutter/material.dart';

import '../design/theme/app_theme.dart';
import '../ffi/native.dart';
import '../ffi/rust_client.dart';
import '../l10n/app_localizations.dart';
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
      // language is the only honest answer left — and it is what the caller
      // already used to pick the theme's font family.
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
    final tokens = DesignTokens.of(context);
    final text = Theme.of(context).textTheme;

    // Three places want the same shape: a label, then text in the platform's
    // monospace. §7 of the font specification says widgets should not name a
    // font family; the name lives in `AppTypography` and is applied here.
    TextStyle mono(double size, Color colour, {double height = 1.4}) => TextStyle(
      fontFamily: AppTypography.monospaceFamily,
      fontSize: size,
      height: height,
      color: colour,
    );

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.space7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // §16 puts a page-level icon at 28–32.
                    Icon(Icons.error_outline, color: tokens.error, size: 28),
                    const SizedBox(width: AppSpacing.space3),
                    Text(l10n.startupFailureTitle, style: text.headlineMedium),
                  ],
                ),
                const SizedBox(height: AppSpacing.space4),
                SelectableText(
                  '$error',
                  style: mono(AppTypography.bodySize, tokens.textSecondary, height: 1.5),
                ),
                if (error is! NativeLibraryNotFound && stackTrace != null) ...[
                  const SizedBox(height: AppSpacing.space6),
                  Text(l10n.stackTraceLabel, style: text.titleMedium),
                  const SizedBox(height: AppSpacing.space2),
                  // Was 11px, which is under the floor
                  // `docs/UI字体规范.md` §3 sets. A stack trace is the last
                  // thing that should be hard to read.
                  SelectableText(
                    '$stackTrace',
                    style: mono(AppTypography.captionSize, tokens.textTertiary),
                  ),
                ],
                if (coreLogDirectory() case final directory?) ...[
                  const SizedBox(height: AppSpacing.space6),
                  Text(l10n.logLabel, style: text.titleMedium),
                  const SizedBox(height: AppSpacing.space2),
                  // A core that failed to start still wrote a reason down —
                  // if the library could be loaded far enough to have one.
                  Text(
                    l10n.startupFailureLogHint,
                    style: text.bodySmall?.copyWith(color: tokens.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.space1),
                  SelectableText(
                    directory,
                    style: mono(AppTypography.captionSize, tokens.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.space3),
                  OutlinedButton.icon(
                    onPressed: () => revealDirectory(directory),
                    // §16's small icon size, and the button's own height (§33)
                    // comes from the theme.
                    icon: const Icon(Icons.folder_open, size: 16),
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
