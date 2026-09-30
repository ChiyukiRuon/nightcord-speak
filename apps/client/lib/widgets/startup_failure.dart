// Shown when the Rust core could not start at all.
//
// This is deliberately not a dialog: without the core there is nothing the app
// can do, and the person running it is a developer who needs the paths that
// were tried.

import 'package:flutter/material.dart';

import '../ffi/native.dart';
import '../theme/app_theme.dart';

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
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.error_outline, color: AppColors.danger, size: 28),
                      SizedBox(width: 12),
                      Text(
                        '核心未能启动',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
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
                    const Text('调用栈', style: TextStyle(fontWeight: FontWeight.w600)),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
