// Language and theme: the two settings that change the front-end itself.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/settings.dart';
import '../../../providers/providers.dart';

/// Which language the app is drawn in, and which palette.
class InterfaceSection extends ConsumerWidget {
  /// Edits `settings`.
  const InterfaceSection({required this.settings, super.key});

  final Settings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    final ui = settings.ui;

    void update(UiSettings next) =>
        ref.read(settingsProvider.notifier).update(settings.copyWith(ui: next));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String?>(
          // `requestedLanguage`, not `language`: a hand-edited value this
          // build does not know would match no item, and the dropdown
          // asserts on that.
          initialValue: ui.requestedLanguage,
          isExpanded: true,
          decoration: InputDecoration(labelText: l10n.settingsLanguageLabel),
          items: [
            DropdownMenuItem(value: null, child: Text(l10n.settingsLanguageSystem)),
            // Each language under its own name, in its own script: the
            // one list a reader can use without already knowing the
            // language they are looking for.
            DropdownMenuItem(value: 'zh', child: Text(l10n.settingsLanguageZh)),
            DropdownMenuItem(
              value: 'zh_Hant',
              child: Text(l10n.settingsLanguageZhHant),
            ),
            DropdownMenuItem(value: 'en', child: Text(l10n.settingsLanguageEn)),
            DropdownMenuItem(value: 'ja', child: Text(l10n.settingsLanguageJa)),
            DropdownMenuItem(value: 'ko', child: Text(l10n.settingsLanguageKo)),
          ],
          onChanged: (language) => update(
            ui.copyWith(language: language, clearLanguage: language == null),
          ),
        ),
        SizedBox(height: tokens.space3),
        DropdownButtonFormField<String>(
          // `?? 'nightcord'` because this dropdown has no null item:
          // unlike the language above, an unset theme and the default
          // theme are the same thing, so "not chosen" is shown as
          // Nightcord and written back as `'nightcord'`. A null
          // `initialValue` with no matching item is an assertion inside
          // `DropdownButtonFormField`, and it would fire on every fresh
          // settings file.
          //
          // The item order is the useful order, not the storage order:
          // 「跟随系统」 first because it is what most people want, then
          // the default, then the two neutrals.
          initialValue: ui.requestedTheme ?? 'nightcord',
          isExpanded: true,
          decoration: InputDecoration(labelText: l10n.settingsThemeLabel),
          items: [
            DropdownMenuItem(value: 'system', child: Text(l10n.settingsThemeSystem)),
            DropdownMenuItem(
              value: 'nightcord',
              child: Text(l10n.settingsThemeNightcord),
            ),
            DropdownMenuItem(value: 'black', child: Text(l10n.settingsThemeBlack)),
            DropdownMenuItem(value: 'white', child: Text(l10n.settingsThemeWhite)),
          ],
          onChanged: (theme) {
            if (theme == null) return;
            update(ui.copyWith(theme: theme));
          },
        ),
      ],
    );
  }
}
