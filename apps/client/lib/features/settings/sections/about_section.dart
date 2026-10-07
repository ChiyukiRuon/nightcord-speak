import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design/components/app_logo.dart';
import '../../../design/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_info.dart';

Future<void>? _licensesLoaded;

/// Register once: reopening About must not duplicate the bundled notices.
Future<void> loadBundledLicenses() => _licensesLoaded ??= _registerLicenses();

Future<void> _registerLicenses() async {
  final entries =
      jsonDecode(await rootBundle.loadString('assets/licenses/third_party.json')) as List;
  LicenseRegistry.addLicense(() async* {
    for (final entry in entries.cast<Map<String, dynamic>>()) {
      yield LicenseEntryWithLineBreaks(
        (entry['packages'] as List).cast<String>(),
        entry['text'] as String,
      );
    }
  });
}

/// Product information is available even before settings arrive from the core.
class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const AppLogo(size: 48),
            SizedBox(width: tokens.space4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Nightcord Speak', style: text.titleLarge),
                  Text(
                    l10n.aboutVersion(appVersion),
                    style: text.bodySmall?.copyWith(color: tokens.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: tokens.space5),
        Text(l10n.aboutDescription, style: text.bodyMedium),
        SizedBox(height: tokens.space4),
        Text(l10n.aboutProject, style: text.titleMedium),
        const SelectableText(appProjectUrl),
        SizedBox(height: tokens.space4),
        Text(l10n.aboutLicense, style: text.titleMedium),
        const SelectableText('MIT OR Apache-2.0'),
        SizedBox(height: tokens.space5),
        Text(l10n.aboutOpenSource, style: text.titleMedium),
        SizedBox(height: tokens.space2),
        Text(l10n.aboutOpenSourceDescription, style: text.bodyMedium),
        SizedBox(height: tokens.space3),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.description_outlined),
            label: Text(l10n.aboutViewLicenses),
            onPressed: () async {
              await loadBundledLicenses();
              if (!context.mounted) return;
              showLicensePage(
                context: context,
                applicationName: 'Nightcord Speak',
                applicationVersion: appVersion,
              );
            },
          ),
        ),
      ],
    );
  }
}
