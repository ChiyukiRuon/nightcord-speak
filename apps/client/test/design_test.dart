// The design system, checked against the specification and against itself.
//
// These are the assertions a snapshot cannot make: a golden image tells you
// what something looked like on one machine, while these say *why* it has to
// look that way and hold for every theme. The distinction matters — the bug
// that prompted the "a control is visible" group was a slider whose inactive
// track was the same colour as the dialog behind it, which no amount of
// palette-value checking would have caught.
//
// `docs/UI设计与配色规范.md` defines exactly one palette. Nightcord is that
// palette, value for value. Black and White are this client's own, so they are
// checked against the *structure* the specification implies — the same layers,
// the same relationships, nothing invisible on the thing it sits on — rather
// than against values that document does not contain.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/design/theme/app_theme.dart';
import 'package:nightcord_client/design/tokens/app_fonts.dart';
import 'package:nightcord_client/design/tokens/app_palette.dart';

/// How far apart two colours look, as the mean absolute difference of their
/// red, green and blue channels.
///
/// Deliberately **not** relative luminance, which is what a contrast formula
/// uses. Luminance is heavily non-linear and crushes the dark end: Black's page
/// (`#17171A`) and its sidebar (`#121214`) differ by more than a twentieth of
/// their range and read as two clearly different greys on screen, yet their
/// luminances are 0.0091 and 0.0060 — a gap of 0.003, which any luminance
/// threshold coarse enough to be meaningful would fail. Gamma-encoded channels
/// are much closer to what the eye does.
double _step(Color a, Color b) {
  double gap(double x, double y) => (x - y).abs();
  return 255 * (gap(a.r, b.r) + gap(a.g, b.g) + gap(a.b, b.b)) / 3;
}

/// The smallest difference that counts as "you can see the boundary".
///
/// Not a scientifically derived figure: it is the smallest value any of the
/// three palettes actually uses for a boundary that a person has to see —
/// Black's input against its page — rounded down. Anything at or below it is a
/// pair that will look like one surface.
const double _visible = 5;

/// The colour roles Material reads when the theme is silent.
///
/// Each of these being unset is what used to put Material's own purple-grey
/// into the dropdowns and switches.
void _checkMaterialRoles(ColorScheme scheme, AppPalette palette) {
  expect(scheme.surface, palette.bgMain);
  expect(scheme.onSurface, palette.textPrimary);
  expect(scheme.outline, palette.borderDefault);
  expect(scheme.outlineVariant, palette.borderSubtle);
  expect(scheme.secondaryContainer, palette.surface1);
  expect(scheme.errorContainer, palette.errorBg);
  expect(scheme.surfaceContainerHighest, palette.surface2);
  expect(scheme.surfaceContainerLowest, palette.bgDeep);
  // §15 forbids glow; a surface tint is a wash applied by elevation.
  expect(scheme.surfaceTint, Colors.transparent);
}

void main() {
  final ThemeData theme = buildAppTheme(AppPalette.nightcord, const Locale('en'));

  group('the Nightcord palette', () {
    test('matches v2 §42, value for value', () {
      // The one palette the specification actually defines. A transcription
      // slip here is the mistake nothing else would notice.
      const p = AppPalette.nightcord;
      expect(p.bgMain, const Color(0xFF4F486E));
      expect(p.bgSidebar, const Color(0xFF3F3661));
      expect(p.bgDeep, const Color(0xFF302850));
      expect(p.bgElevated, const Color(0xFF554C75));
      expect(p.surface1, const Color(0xFF5A5278));
      expect(p.surface2, const Color(0xFF696180));
      expect(p.surface3, const Color(0xFF7A7190));
      expect(p.primary, const Color(0xFF8C82C2));
      expect(p.primaryHover, const Color(0xFF9A90CF));
      expect(p.primaryPressed, const Color(0xFF786EAD));
      expect(p.primaryFocus, const Color(0xFFAEA6D6));
      expect(p.primaryDisabled, const Color(0xFF625A78));
      expect(p.textPrimary, const Color(0xFFF8F7FA));
      expect(p.textSecondary, const Color(0xFFD2CCDE));
      expect(p.textTertiary, const Color(0xFFAAA3BB));
      expect(p.textDisabled, const Color(0xFF7C758E));
      expect(p.borderSubtle, const Color(0xFF575071));
      expect(p.borderDefault, const Color(0xFF625A7C));
      expect(p.error, const Color(0xFFCF858D));
      expect(p.online, const Color(0xFF8CC9A3));
    });

    test('the two colours a component section names are the ones it names', () {
      // Neither appears in §11's `AppColors` block nor in §42's Final Palette,
      // but §18 and §19 give them values of their own.
      const p = AppPalette.nightcord;
      expect(p.inputBg, const Color(0xFF3A3260)); // §18
      expect(p.channelHoverBg, const Color(0xFF51496F)); // §19
    });

    test('§2.2\'s ladder climbs', () {
      // Deep → Sidebar → Main → Elevated → Surface → Strong → Primary. "The
      // whole layout is meant to be legible from the background alone", which
      // only works if each step is lighter than the one below it.
      const p = AppPalette.nightcord;
      final List<Color> ladder = [
        p.bgDeep,
        p.bgSidebar,
        p.bgMain,
        p.bgElevated,
        p.surface1,
        p.surface2,
        p.surface3,
        p.primary,
      ];
      for (var i = 1; i < ladder.length; i++) {
        expect(
          ladder[i].computeLuminance(),
          greaterThan(ladder[i - 1].computeLuminance()),
          reason: 'step $i is not lighter than the one before it',
        );
      }
    });

    test('is not the palette the app used to have', () {
      // §41 禁止 8 forbids v1's colours, and the two palettes are close enough
      // that a wrong one would look *nearly* right — the worst kind of wrong.
      const List<Color> forbidden = [
        Color(0xFF484868), // v1 main
        Color(0xFF383060), // v1 sidebar
        Color(0xFF50486C), // v1 surface1 / elevated
        Color(0xFF686080), // v1 surface2
        Color(0xFF887EB4), // v1 primary
        Color(0xFFC0BBCD), // v1's ad-hoc row colours
        Color(0xFF443C68),
        Color(0xFFE8E5F0),
        Color(0xFF3B3B54), // older still: pre-design-system
        Color(0xFF454567),
        Color(0xFF8B7BD8),
      ];
      for (final palette in AppPalette.all) {
        for (final field in _colours(palette)) {
          expect(
            forbidden,
            isNot(contains(field)),
            reason: '${palette.name} carries a retired colour: $field',
          );
        }
      }
    });
  });

  group('every theme', () {
    for (final palette in AppPalette.all) {
      group(palette.name, () {
        final ThemeData built = buildAppTheme(palette, const Locale('en'));

        test('the layers are visible against each other', () {
          // The three that are always adjacent on screen: the page, the sidebar
          // beside it, and a selected row inside the sidebar.
          expect(
            _step(palette.bgMain, palette.bgSidebar),
            greaterThan(_visible),
            reason: 'the sidebar disappears into the page',
          );
          expect(
            _step(palette.bgMain, palette.surface1),
            greaterThan(_visible),
            reason: 'a selected row disappears into the page',
          );
          expect(
            _step(palette.bgSidebar, palette.surface1),
            greaterThan(_visible),
            reason: 'a selected row disappears into the sidebar',
          );
        });

        test('text drawn on a primary fill is legible on it', () {
          // This is the token that has to *flip*: two of the three themes fill
          // a primary button with a light colour and put dark text on it.
          expect(
            _step(palette.textOnPrimary, palette.primary),
            greaterThan(100),
            reason: '${palette.name} draws ${palette.textOnPrimary} on '
                '${palette.primary}',
          );
        });

        test('text drawn on a toast is legible on it', () {
          // §27's toasts are a coloured fill with `textPrimary` over it. On a
          // dark theme that is light-on-dark; on a light theme the fill had to
          // be re-cut pale, or this pair would have been dark-on-dark. Nothing
          // in the specification covers that case — it is the single sharpest
          // consequence of adding a light theme.
          expect(
            _step(palette.textPrimary, palette.infoBg),
            greaterThan(100),
            reason: '${palette.name} draws ${palette.textPrimary} on '
                '${palette.infoBg}',
          );
          expect(_step(palette.textPrimary, palette.errorBg), greaterThan(100));
          expect(_step(palette.textPrimary, palette.successBg), greaterThan(100));
          expect(_step(palette.textPrimary, palette.warningBg), greaterThan(100));
        });

        test('fills the colour roles Material reads', () {
          _checkMaterialRoles(built.colorScheme, palette);
        });

        test('the selected item of a dropdown is legible', () {
          // Regression, found by looking at the Black theme: Material paints a
          // dropdown's current entry with `focusColor` and draws `textPrimary`
          // on it. The theme had set that to §35's bright focus ring — so the
          // selected item came out a near-white bar with a near-white label on
          // it. Nightcord's lavender version was already hard to read; Black
          // made it obvious.
          expect(
            _step(built.focusColor, palette.textPrimary),
            greaterThan(100),
            reason: '${palette.name} paints a selected item it cannot label',
          );
        });

        test('a hover overlay lightens a dark theme and darkens a light one', () {
          // §35 describes hover as a *surface* step. On a dark theme that is
          // white at low alpha; on a light theme the same overlay lightens
          // something that is already nearly white and does nothing.
          final hover = built.hoverColor;
          final towardsLight = hover.r > 0.5 && hover.g > 0.5 && hover.b > 0.5;
          expect(
            towardsLight,
            palette.brightness == Brightness.dark,
            reason: '${palette.name}\'s hover overlay goes the wrong way',
          );
        });

        test('installs its own tokens', () {
          expect(built.extension<DesignTokens>()?.name, palette.name);
        });

        test('draws nothing below the font specification\'s floor', () {
          // `docs/UI字体规范.md` §3 sets a 12px minimum. This is why the
          // colour specification's 11px `overline` is not in the scale.
          for (final entry in _styles(built.textTheme).entries) {
            final size = entry.value?.fontSize;
            if (size == null) continue;
            expect(
              size,
              greaterThanOrEqualTo(AppTypography.minimumSize),
              reason: '${entry.key} is $size px',
            );
          }
        });
      });
    }
  });

  group('the two neutral themes', () {
    test('are actually neutral', () {
      // What "black and white" means here: the layer colours carry no hue. A
      // grey that leans blue is a different product decision, and one that
      // would be easy to introduce by copying a value out of Nightcord.
      for (final palette in [AppPalette.black, AppPalette.white]) {
        for (final colour in [
          palette.bgDeep,
          palette.bgSidebar,
          palette.bgMain,
          palette.bgElevated,
          palette.surface1,
          palette.surface2,
          palette.surface3,
        ]) {
          final spread = [
            (colour.r * 255).round(),
            (colour.g * 255).round(),
            (colour.b * 255).round(),
          ];
          spread.sort();
          expect(
            spread.last - spread.first,
            lessThanOrEqualTo(12),
            reason: '${palette.name} has a tinted layer: $colour',
          );
        }
      }
    });

    test('Nightcord is not one of them', () {
      // The counter-case, so the check above cannot pass by accident if
      // somebody makes the assertion vacuous.
      final purple = AppPalette.nightcord.bgMain;
      final spread = [
        (purple.r * 255).round(),
        (purple.g * 255).round(),
        (purple.b * 255).round(),
      ];
      spread.sort();
      expect(spread.last - spread.first, greaterThan(12));
    });

    test('the light theme inverts the ladder, and that is the design', () {
      // §37: a light theme has to be designed, not derived. On a light
      // background there is nothing above white, so a modal is the *brightest*
      // surface and the recessed things — sidebar, hover, selected — are grey.
      // The sequence is the same one Nightcord climbs; White walks it down.
      const p = AppPalette.white;
      final List<Color> ladder = [
        p.bgDeep,
        p.bgElevated,
        p.bgMain,
        p.bgSidebar,
        p.surface1,
        p.surface2,
        p.surface3,
        p.primary,
      ];
      for (var i = 1; i < ladder.length; i++) {
        expect(
          ladder[i].computeLuminance(),
          lessThan(ladder[i - 1].computeLuminance()),
          reason: 'step $i is not darker than the one before it',
        );
      }
    });
  });

  group('the theme', () {
    test('draws nothing below the font specification\'s floor', () {
      for (final entry in _styles(theme.textTheme).entries) {
        final size = entry.value?.fontSize;
        if (size == null) continue;
        expect(size, greaterThanOrEqualTo(AppTypography.minimumSize));
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
      expect(
        buildAppTheme(AppPalette.nightcord, const Locale('zh')).textTheme.bodyMedium?.fontFamily,
        AppFonts.simplifiedChinese,
      );
      expect(
        buildAppTheme(AppPalette.nightcord, const Locale('en')).textTheme.bodyMedium?.fontFamily,
        AppFonts.latin,
      );
    });

    test('every weighted style also sets the variable axis', () {
      // Flutter's documentation only promises that `fontVariations` drives a
      // variable font's weight axis; whether `fontWeight` reaches it is not
      // stated. Both are set, so the weight is right either way — and if a
      // future edit drops one, this says so.
      for (final entry in _styles(theme.textTheme).entries) {
        final style = entry.value;
        if (style == null || style.fontWeight == null) continue;
        expect(style.fontVariations, isNotNull, reason: '${entry.key} has no axis');
        expect(
          style.fontVariations!.single.value,
          style.fontWeight!.value.toDouble(),
          reason: '${entry.key} disagrees with itself',
        );
      }
    });
  });

  group('a control is visible on the surface it is drawn on', () {
    // The bug this group exists for: the sensitivity slider's inactive track
    // was set to `bgDeep`, which is exactly what §25 puts behind a dialog — so
    // most of the slider was the same colour as the page. Nothing but looking
    // at it (or measuring it) would have said so. Every theme gets the check,
    // because a new palette is exactly where it would happen again.
    for (final palette in AppPalette.all) {
      test(palette.name, () {
        final built = buildAppTheme(palette, const Locale('en'));

        expect(
          _step(built.sliderTheme.inactiveTrackColor!, palette.bgDeep),
          greaterThan(_visible),
          reason: 'a slider track is the dialog it sits in',
        );
        expect(
          _step(built.sliderTheme.activeTrackColor!, built.sliderTheme.inactiveTrackColor!),
          greaterThan(_visible),
          reason: 'the two halves of a slider look the same',
        );
        expect(
          _step(built.inputDecorationTheme.fillColor!, palette.bgMain),
          greaterThan(_visible),
          reason: 'an empty input is the page behind it',
        );
        expect(
          _step(built.dialogTheme.backgroundColor!, palette.bgMain),
          greaterThan(_visible),
          reason: 'a dialog is the page behind it',
        );
        expect(
          _step(built.bottomSheetTheme.backgroundColor!, palette.bgMain),
          greaterThan(_visible),
          reason: 'a sheet is the page behind it',
        );
        // §27: a toast carries its own background rather than falling through
        // to Material's `inverseSurface`, which in a dark theme is a *light*
        // bar. That was a real complaint once.
        expect(built.snackBarTheme.backgroundColor, palette.infoBg);
      });
    }
  });

  group('switching themes', () {
    test('cross-fades rather than snapping', () {
      // `MaterialApp` wraps the tree in an `AnimatedTheme`, which lerps the
      // extension on every frame. The extension used to return one palette or
      // the other, which made the change jump at the half-way point.
      const from = DesignTokens(AppPalette.nightcord);
      const to = DesignTokens(AppPalette.white);

      final mid = from.lerp(to, 0.5);
      expect(mid.palette.bgMain, isNot(AppPalette.nightcord.bgMain));
      expect(mid.palette.bgMain, isNot(AppPalette.white.bgMain));
      // Half way between purple and near-white is somewhere in the middle.
      expect(_step(mid.palette.bgMain, AppPalette.nightcord.bgMain), greaterThan(40));
      expect(_step(mid.palette.bgMain, AppPalette.white.bgMain), greaterThan(40));
    });

    test('a blend is still a usable palette', () {
      // Every frame of the animation goes through `buildAppTheme` indirectly,
      // so a blend has to satisfy the same "you can see the layers" rule the
      // endpoints do — otherwise a switch would flash something illegible.
      final mid = AppPalette.lerp(AppPalette.nightcord, AppPalette.black, 0.5);
      expect(_step(mid.bgMain, mid.bgSidebar), greaterThan(_visible / 2));
      expect(mid.name, 'black', reason: 'the blend names where it is going');
    });
  });

  group('the theme registry', () {
    test('every theme is reachable by the name the settings file uses', () {
      for (final palette in AppPalette.all) {
        expect(AppPalette.byName(palette.name), palette);
      }
      expect(AppPalette.byName('solarized'), isNull);
    });

    test('Nightcord is the default', () {
      // The settings file spells "not chosen" as a missing key, and the UI
      // shows it as Nightcord; the two must be the same theme.
      expect(AppPalette.nightcord.name, 'nightcord');
    });

    test('the names are unique', () {
      final names = AppPalette.all.map((p) => p.name).toSet();
      expect(names.length, AppPalette.all.length);
    });
  });
}

/// Every colour field of a palette, for the checks that loop.
List<Color> _colours(AppPalette p) => [
  p.bgDeep,
  p.bgSidebar,
  p.bgMain,
  p.bgElevated,
  p.surface1,
  p.surface2,
  p.surface3,
  p.primary,
  p.primaryHover,
  p.primaryPressed,
  p.primaryFocus,
  p.primaryDisabled,
  p.textPrimary,
  p.textSecondary,
  p.textTertiary,
  p.textDisabled,
  p.textOnPrimary,
  p.borderSubtle,
  p.borderDefault,
  p.borderStrong,
  p.success,
  p.successBg,
  p.warning,
  p.warningBg,
  p.error,
  p.errorBg,
  p.info,
  p.infoBg,
  p.online,
  p.idle,
  p.busy,
  p.offline,
  p.channelHoverBg,
  p.inputBg,
];

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
