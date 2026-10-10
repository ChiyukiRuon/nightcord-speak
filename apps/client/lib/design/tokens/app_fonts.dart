// Which family text is drawn in, from `docs/UI字体规范.md` §2 and §5.
//
// Five families are bundled, all variable: one Latin and four CJK. They are
// *not* in the repository — `scripts/fetch-fonts.sh` downloads them before a
// build, and `assets/fonts/` is gitignored, so a fresh clone that skips that
// step will fail to build rather than silently render in the system font. The
// reasoning is in the script's header.

import 'package:flutter/widgets.dart';

/// The bundled families, and the rule for picking one.
abstract final class AppFonts {
  /// Latin, and everything the other families do not cover.
  static const String latin = 'NotoSans';

  /// Simplified Chinese.
  static const String simplifiedChinese = 'NotoSansSC';

  /// Traditional Chinese — Taiwan, Hong Kong, Macao.
  static const String traditionalChinese = 'NotoSansTC';

  /// Japanese.
  static const String japanese = 'NotoSansJP';

  /// Korean.
  static const String korean = 'NotoSansKR';

  /// Keep mixed-language content independent of the device's installed fonts.
  /// The primary family still decides regional shapes for shared ideographs.
  static List<String> fallbacksFor(String family) => <String>[
    latin,
    simplifiedChinese,
    traditionalChinese,
    japanese,
    korean,
  ].where((candidate) => candidate != family).toList(growable: false);

  /// Which family `locale`'s text is drawn in.
  ///
  /// One CJK face per language rather than one for all of them, because they
  /// are not interchangeable: 直 and 骨 and a great many others are drawn with
  /// different shapes in each, and a reader of one notices immediately when
  /// handed another's. §2 of the specification is where that rule lives.
  ///
  /// **The script matters as much as the case.** Writing a case for a family
  /// that `pubspec.yaml` does not declare would not fail: Flutter would draw
  /// the default font and say nothing. So adding a language is three edits
  /// together — the file in `assets/fonts/` (via `scripts/fetch-fonts.sh`), the
  /// family in `pubspec.yaml`, and the case here.
  ///
  /// Script subtags are what separate the two Chinese faces: a `zh` locale
  /// carrying `Hant` is Traditional, and one carrying nothing or `Hans` is
  /// Simplified. `flutter gen-l10n` produces exactly `zh` and `zh_Hant` from
  /// the ARB files, so those are the two that arrive here.
  static String forLocale(Locale locale) => switch (locale.languageCode) {
    'zh' => switch (locale.scriptCode) {
      'Hant' => traditionalChinese,
      _ => simplifiedChinese,
    },
    'ja' => japanese,
    'ko' => korean,
    _ => latin,
  };
}
