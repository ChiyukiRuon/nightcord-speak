// The design system, checked against the two specifications.
//
// These are the assertions a snapshot cannot make: a golden image tells you
// what something looked like on one machine, while these say *why* it has to
// look that way. The distinction matters — the bug that prompted this file was
// a slider whose inactive track was the same colour as the dialog behind it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/design/theme/app_theme.dart';
import 'package:nightcord_client/design/tokens/app_colors.dart';
import 'package:nightcord_client/design/tokens/app_fonts.dart';

/// How different two colours look, roughly.
///
/// Relative luminance, which is the same measure the contrast formula uses. The
/// threshold below is deliberately far below any real accessibility bar — this
/// is not checking readability, it is checking that a thing is *there*.
double _apart(Color a, Color b) => (a.computeLuminance() - b.computeLuminance()).abs();

void main() {
  final ThemeData theme = buildAppTheme(const Locale('en'));
  final ColorScheme scheme = theme.colorScheme;

  group('the palette', () {
    test('matches §2, value for value', () {
      // Spot checks across every family; a transcription slip in this file is
      // the one mistake nothing else would notice.
      expect(AppColors.backgroundPrimary, const Color(0xFF484868));
      expect(AppColors.backgroundSecondary, const Color(0xFF383060));
      expect(AppColors.backgroundTertiary, const Color(0xFF302850));
      expect(AppColors.primary, const Color(0xFF887EB4));
      expect(AppColors.textPrimary, const Color(0xFFF8F7FA));
      expect(AppColors.textSecondary, const Color(0xFFD0CBDD));
      expect(AppColors.textTertiary, const Color(0xFFA7A1B8));
      expect(AppColors.error, const Color(0xFFCF858D));
      expect(AppColors.online, const Color(0xFF8CC9A3));
    });

    test('is not the palette the app used to have', () {
      // The old values, from before the design system. If one of them comes
      // back it is because something was copied from an older file.
      const List<Color> old = [
        Color(0xFF3B3B54),
        Color(0xFF454567),
        Color(0xFF8B7BD8),
        Color(0xFFF2F2F7),
      ];
      final List<Color> current = [
        AppColors.backgroundPrimary,
        AppColors.backgroundSecondary,
        AppColors.primary,
        AppColors.textPrimary,
      ];
      for (final gone in old) {
        expect(current, isNot(contains(gone)), reason: 'the old palette crept back in');
      }
    });
  });

  group('the theme', () {
    test('fills the colour roles Material reads', () {
      // Not every role — the ones a Material widget reaches for when the theme
      // is silent. Each of these being unset is what used to put Material's
      // own purple-grey into the dropdowns and switches.
      expect(scheme.surface, AppColors.backgroundPrimary);
      expect(scheme.onSurface, AppColors.textPrimary);
      expect(scheme.outline, AppColors.borderDefault);
      expect(scheme.outlineVariant, AppColors.borderSubtle);
      expect(scheme.secondaryContainer, AppColors.surface1);
      expect(scheme.errorContainer, AppColors.errorBg);
      expect(scheme.surfaceContainerHighest, AppColors.surface2);
      expect(scheme.surfaceContainerLowest, AppColors.backgroundTertiary);
    });

    test('turns off Material\'s elevation tint', () {
      // §8 forbids glow; a surface tint is a purple wash applied by elevation.
      expect(scheme.surfaceTint, Colors.transparent);
    });

    test('installs the tokens', () {
      expect(theme.extension<DesignTokens>(), isNotNull);
    });

    test('draws nothing below the font specification\'s floor', () {
      // `docs/UI字体规范.md` §3 sets a 12px minimum. This is why the colour
      // specification's 11px `overline` is not in the scale.
      for (final MapEntry<String, TextStyle?> entry in _styles(theme.textTheme).entries) {
        final size = entry.value?.fontSize;
        if (size == null) continue;
        expect(size, greaterThanOrEqualTo(AppTypography.minimumSize),
            reason: '${entry.key} is $size px');
      }
    });
  });

  group('the font family follows the locale', () {
    // `docs/UI字体规范.md` §5: the same text has to render with the right
    // regional glyph shapes, so the family is chosen per locale rather than
    // fixed.
    test('Simplified Chinese gets the CJK face', () {
      expect(AppFonts.forLocale(const Locale('zh')), AppFonts.simplifiedChinese);
      expect(AppFonts.forLocale(const Locale('zh', 'CN')), AppFonts.simplifiedChinese);
    });

    test('everything else falls back to the Latin face', () {
      expect(AppFonts.forLocale(const Locale('en')), AppFonts.latin);
      // Not a supported locale, but it must not pick a family that is not
      // bundled — Flutter would render it in the system font and say nothing.
      expect(AppFonts.forLocale(const Locale('fr')), AppFonts.latin);
      expect(AppFonts.forLocale(const Locale('ja')), AppFonts.latin);
    });

    test('the theme carries the family through', () {
      expect(buildAppTheme(const Locale('zh')).textTheme.bodyMedium?.fontFamily,
          AppFonts.simplifiedChinese);
      expect(buildAppTheme(const Locale('en')).textTheme.bodyMedium?.fontFamily,
          AppFonts.latin);
    });

    test('every weighted style also sets the variable axis', () {
      // Flutter's documentation only promises that `fontVariations` drives a
      // variable font's weight axis; whether `fontWeight` reaches it is not
      // stated. Both are set, so the weight is right either way — and if a
      // future edit drops one, this says so.
      for (final MapEntry<String, TextStyle?> entry in _styles(theme.textTheme).entries) {
        final style = entry.value;
        if (style == null || style.fontWeight == null) continue;
        expect(style.fontVariations, isNotNull, reason: '${entry.key} has no axis');
        expect(style.fontVariations!.single.value, style.fontWeight!.value.toDouble(),
            reason: '${entry.key} disagrees with itself');
      }
    });
  });

  group('a control is visible on the surface it is drawn on', () {
    // The bug this group exists for: the sensitivity slider's inactive track
    // was set to `backgroundTertiary`, which is exactly what §35 puts behind a
    // dialog — so most of the slider was the same colour as the page. Nothing
    // but looking at it (or measuring it) would have said so.

    test('a slider track is not the dialog it sits in', () {
      expect(_apart(theme.sliderTheme.inactiveTrackColor!, scheme.surfaceContainerLowest),
          greaterThan(0.01));
    });

    test('the active half of a slider is not the inactive half', () {
      expect(_apart(theme.sliderTheme.activeTrackColor!, theme.sliderTheme.inactiveTrackColor!),
          greaterThan(0.01));
    });

    test('an empty input is not the page behind it', () {
      // §11 puts an input at `backgroundSecondary`; §4.1 keeps the page at
      // `backgroundPrimary`. If those ever become the same value the fields
      // disappear.
      expect(_apart(theme.inputDecorationTheme.fillColor!, scheme.surface), greaterThan(0.01));
    });

    test('a modal is not the page behind it', () {
      // §35: a modal is the darkest step, the page is two above it.
      expect(_apart(theme.dialogTheme.backgroundColor!, scheme.surface), greaterThan(0.01));
      expect(_apart(theme.bottomSheetTheme.backgroundColor!, scheme.surface), greaterThan(0.01));
    });

    test('a toast carries its own background', () {
      // §19. This is also the fix for the old `inverseSurface` complaint: a
      // snack bar with no colour of its own went to Material's default, which
      // in a dark theme is a *light* bar.
      expect(theme.snackBarTheme.backgroundColor, AppColors.infoBg);
    });
  });
}

/// Every named style in a `TextTheme`, so the checks above can loop.
Map<String, TextStyle?> _styles(TextTheme text) => {
  'displayLarge': text.displayLarge,
  'displayMedium': text.displayMedium,
  'displaySmall': text.displaySmall,
  'headlineLarge': text.headlineLarge,
  'headlineMedium': text.headlineMedium,
  'headlineSmall': text.headlineSmall,
  'titleLarge': text.titleLarge,
  'titleMedium': text.titleMedium,
  'titleSmall': text.titleSmall,
  'bodyLarge': text.bodyLarge,
  'bodyMedium': text.bodyMedium,
  'bodySmall': text.bodySmall,
  'labelLarge': text.labelLarge,
  'labelMedium': text.labelMedium,
  'labelSmall': text.labelSmall,
};
