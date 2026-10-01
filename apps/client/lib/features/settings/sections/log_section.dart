// The "where did the log go" section.

import 'package:flutter/material.dart';

import '../../../design/theme/app_theme.dart';
import '../../../ffi/rust_client.dart';
import '../../../l10n/app_localizations.dart';
import '../../../util/reveal.dart';

/// Where the log is written, and the button that opens the folder.
class LogSection extends StatelessWidget {
  /// Shows the core's log directory.
  const LogSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    // Read here rather than passed in: it is a cached value, and the only thing
    // on this section is about the log.
    final directory = coreLogDirectory();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectableText(
          directory ?? l10n.settingsNoLogDirectory,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            // A path is read character by character; the family name lives in
            // `AppTypography` (`docs/UI字体规范.md` §7).
            fontFamily: AppTypography.monospaceFamily,
            color: tokens.textSecondary,
          ),
        ),
        SizedBox(height: tokens.space3),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: directory == null ? null : () => revealDirectory(directory),
            icon: const Icon(Icons.folder_open),
            label: Text(l10n.openLogFolder),
          ),
        ),
      ],
    );
  }
}
