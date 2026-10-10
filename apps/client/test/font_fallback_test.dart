import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/design/theme/app_theme.dart';
import 'package:nightcord_client/design/tokens/app_fonts.dart';
import 'package:nightcord_client/design/tokens/app_palette.dart';

void main() {
  const families = <String>{
    AppFonts.latin,
    AppFonts.simplifiedChinese,
    AppFonts.traditionalChinese,
    AppFonts.japanese,
    AppFonts.korean,
  };
  const locales = <Locale>[
    Locale('en'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    Locale('ja'),
    Locale('ko'),
  ];

  // Mixed-language names and messages previously relied on platform fonts,
  // leaving missing glyphs when the selected UI font did not cover them.
  for (final locale in locales) {
    testWidgets('mixed text retains bundled fallbacks in $locale', (tester) async {
      final theme = buildAppTheme(AppPalette.nightcord, locale);
      final family = AppFonts.forLocale(locale);
      final expected = families.where((candidate) => candidate != family).toList();
      for (final textTheme in [theme.textTheme, theme.primaryTextTheme]) {
        final styles = <TextStyle?>[
          textTheme.displayLarge,
          textTheme.displayMedium,
          textTheme.displaySmall,
          textTheme.headlineLarge,
          textTheme.headlineMedium,
          textTheme.headlineSmall,
          textTheme.titleLarge,
          textTheme.titleMedium,
          textTheme.titleSmall,
          textTheme.bodyLarge,
          textTheme.bodyMedium,
          textTheme.bodySmall,
          textTheme.labelLarge,
          textTheme.labelMedium,
          textTheme.labelSmall,
        ];
        for (final style in styles) {
          expect(style!.fontFamily, family);
          expect(style.fontFamilyFallback, expected);
        }
      }

      late TextStyle inherited;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                inherited = DefaultTextStyle.of(context).style;
                return const Column(children: [Text('English 简体 繁體 日本語 한국어'), TextField()]);
              },
            ),
          ),
        ),
      );
      expect(inherited.fontFamily, family);
      expect(inherited.fontFamilyFallback, expected);
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.style.fontFamilyFallback, expected);
      expect(tester.takeException(), isNull);
    });
  }

  test('standalone typography keeps fallbacks including monospace text', () {
    for (final family in [...families, AppTypography.monospaceFamily]) {
      final style = AppTypography.style(family, 14, FontWeight.w400, 1.5);
      expect(style.fontFamily, family);
      expect(style.fontFamilyFallback, families.where((candidate) => candidate != family).toList());
    }
  });
}
