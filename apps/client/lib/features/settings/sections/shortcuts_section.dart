// The portable key combinations for the three voice actions (§42).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/labels.dart';
import '../../../models/settings.dart';
import '../../../models/shortcuts.dart';
import '../../../providers/providers.dart';
import '../../shortcuts/chord_field.dart';

/// One recorder per action, plus the note about how to use them.
class ShortcutsSection extends ConsumerWidget {
  /// Edits `settings`.
  const ShortcutsSection({required this.settings, super.key});

  final Settings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final action in ShortcutAction.values)
          ChordField(
            label: action.label(l10n),
            chord: settings.shortcuts[action],
            // Per row, not one button for the three: a shortcut is something
            // tried one at a time, and "put that one back" is a different
            // request from "put everything back". Always enabled, even when the
            // row already holds the default — a page cannot tell whether it
            // does, and a button that guessed would be wrong on one platform or
            // the other.
            //
            // A button with a box around it, and not the bare icon this started
            // as: a lone grey glyph at the end of a row reads as decoration
            // rather than as a control, so the action was effectively invisible
            // — §17.2's secondary materials are what every other row action in
            // these settings wears. Icon only, where those others carry a
            // label: there is one of these per row, and the words would crowd
            // the recorder on a phone. The tooltip says them instead.
            trailing: Tooltip(
              message: l10n.settingsShortcutsReset,
              child: OutlinedButton(
                onPressed: () => ref.read(settingsProvider.notifier).resetShortcut(action),
                style: OutlinedButton.styleFrom(
                  // §33's hit area, and square: a lone icon in a wide button
                  // reads as a button with something missing.
                  minimumSize: const Size.square(36),
                  padding: EdgeInsets.zero,
                ),
                child: const Icon(Icons.settings_backup_restore, size: 18),
              ),
            ),
            onChanged: (chord) => ref
                .read(settingsProvider.notifier)
                .update(
                  settings.copyWith(
                    shortcuts: settings.shortcuts.withBinding(action, chord),
                  ),
                ),
          ),
        SizedBox(height: tokens.space3),
        Text(
          l10n.settingsShortcutsHelp,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: tokens.textTertiary),
        ),
      ],
    );
  }
}
