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
            onChanged: (chord) => ref
                .read(settingsProvider.notifier)
                .update(
                  settings.copyWith(
                    shortcuts: settings.shortcuts.withBinding(action, chord),
                  ),
                ),
          ),
        SizedBox(height: tokens.space1),
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
