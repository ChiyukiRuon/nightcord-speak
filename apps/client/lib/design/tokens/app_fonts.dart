// Which family text is drawn in, from `docs/UI字体规范.md` §2 and §5.
//
// Two families are bundled, both variable: one Latin and one Simplified
// Chinese. They are *not* in the repository — `scripts/fetch-fonts.sh`
// downloads them before a build, and `assets/fonts/` is gitignored, so a fresh
// clone that skips that step will fail to build rather than silently render in
// the system font. The reasoning is in the script's header.

import 'package:flutter/widgets.dart';

/// The bundled families, and the rule for picking one.
abstract final class AppFonts {
  /// Latin, and everything the other families do not cover.
  static const String latin = 'NotoSans';

  /// Simplified Chinese.
  static const String simplifiedChinese = 'NotoSansSC';

  /// Which family `locale`'s text is drawn in.
  ///
  /// Only these two are reachable today: `supportedLocales` is exactly `en`
  /// and `zh` (see `l10n.yaml`), so locale resolution never produces anything
  /// else — a `ja`, `ko` or `zh_TW` system locale resolves to one of the two
  /// before it gets here.
  ///
  /// `docs/UI字体规范.md` §2 also specifies Noto Sans TC (zh-TW/HK/MO), JP and
  /// KR, and §5 wants a branch for each, because sharing one CJK face across
  /// languages draws Japanese kanji with Chinese glyph shapes. Adding one is
  /// three edits **together** — the font in `assets/fonts/`, the family in
  /// `pubspec.yaml`, and a case here. A case on its own would name a family
  /// that does not exist, and Flutter would quietly draw the default font
  /// instead of failing.
  ///
  /// Until then, text in a language we do not bundle still renders: Flutter
  /// falls back per glyph to the system fonts, the same mechanism §8 relies on
  /// for emoji.
  static String forLocale(Locale locale) => switch (locale.languageCode) {
    'zh' => simplifiedChinese,
    _ => latin,
  };
}
