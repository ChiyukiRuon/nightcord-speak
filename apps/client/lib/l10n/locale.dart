import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

/// All app roots and fonts must agree on the Chinese script and fallback.
Locale resolveAppLocale({
  String? language,
  required Iterable<Locale> systemLocales,
}) {
  final preferred = language == null
      ? systemLocales
      : [localeFromTag(language)];
  return basicLocaleListResolution(
    preferred.map(_withChineseScript).toList(),
    AppLocalizations.supportedLocales,
  );
}

/// Stored settings use underscores; engine arguments use BCP 47 tags.
Locale localeFromTag(String tag) {
  final parts = tag.replaceAll('-', '_').split('_');
  return Locale.fromSubtags(
    languageCode: parts.first,
    scriptCode: parts.length > 1 && parts[1].length == 4 ? parts[1] : null,
    countryCode: parts.length > 1 && parts.last.length != 4 ? parts.last : null,
  );
}

Locale _withChineseScript(Locale locale) {
  if (locale.languageCode != 'zh') return locale;
  return Locale.fromSubtags(
    languageCode: 'zh',
    scriptCode:
        locale.scriptCode ??
        (const {'TW', 'HK', 'MO'}.contains(locale.countryCode)
            ? 'Hant'
            : 'Hans'),
    countryCode: locale.countryCode,
  );
}
