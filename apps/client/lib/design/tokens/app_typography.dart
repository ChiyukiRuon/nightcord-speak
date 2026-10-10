// The type scale, from `docs/UI设计与配色规范.md` §12.2 and
// `docs/UI字体规范.md` §3.
//
// Sizes and weights are the specifications' numbers. Two things they do not
// give, and where the values come from:
//
// * **Line heights.** Unspecified in both documents. Chosen here for CJK:
//   running text gets 1.5, which is what the chat already used and what
//   Chinese needs to stop lines from colliding, and headings get 1.25–1.35
//   because they are short and 1.5 would space them away from what they label.
// * **Letter spacing.** Only `overline` has one, 0.4 — it is an all-caps-ish
//   label at 11px, where the app already used that value.
//
// The families are variable fonts (one file carries every weight), so each
// style sets `fontWeight` *and* `fontVariations`. Flutter's documentation only
// promises that `fontVariations` drives a variable axis; whether `fontWeight`
// also reaches it is not stated. Setting both means the weights are correct
// either way, and the redundancy costs nothing.

import 'dart:ui' show FontVariation;

import 'package:flutter/material.dart' show TextTheme, TextStyle, FontWeight;

import 'app_fonts.dart';

/// Sizes, weights and the `TextTheme` built from them.
abstract final class AppTypography {
  // --- Weights (`docs/UI字体规范.md` §3) ------------------------------------
  //
  // Four, not nine: the spec keeps only these, and the bundled variable fonts
  // interpolate anything between them if a future design needs it.

  /// Body text and list rows.
  static const FontWeight regular = FontWeight.w400;

  /// Buttons and labels.
  static const FontWeight medium = FontWeight.w500;

  /// Headings.
  static const FontWeight semibold = FontWeight.w600;

  /// Emphasis.
  static const FontWeight bold = FontWeight.w700;

  // --- Sizes (§12.2) --------------------------------------------------------

  static const double displaySize = 28;
  static const double headlineSize = 22;
  static const double titleSize = 18;
  static const double bodyLargeSize = 16;
  static const double bodySize = 14;
  static const double labelSize = 13;
  static const double captionSize = 12;

  /// The floor from `docs/UI字体规范.md` §3: nothing in the UI is smaller.
  ///
  /// This is where the two specifications disagree. §12.2 of the colour
  /// specification lists a ninth level, `overline`, at **11px** — below this
  /// floor — and marks it "极少使用" itself. The floor wins: `docs/UI字体规范.md`
  /// is the more specific document about type, and it states the limit as a
  /// rule rather than as a table entry. `overline` is therefore not part of
  /// this scale, and nothing in the app draws at 11px.
  static const double minimumSize = captionSize;

  // --- Line heights (see the file header) ----------------------------------

  static const double _displayHeight = 1.25;
  static const double _headlineHeight = 1.3;
  static const double _titleHeight = 1.35;
  static const double _bodyHeight = 1.5;
  static const double _labelHeight = 1.4;

  /// The family for text that must line up column-wise — log paths, stack
  /// traces, captured key combinations.
  ///
  /// Deliberately still the platform's `monospace` rather than a bundled face:
  /// this is a *role*, not an accident, and Noto Sans is proportional, so
  /// substituting it would make the paths in the log section harder to read.
  /// `docs/UI字体规范.md` §7 asks that widgets not name a family themselves;
  /// this constant is how they stop doing that.
  static const String monospaceFamily = 'monospace';

  /// The theme's text styles, drawn in `family`.
  ///
  /// Material's slots do not line up one-for-one with §12.2's nine levels, so
  /// each spec level lands in the slot whose *use* matches — `titleLarge` is
  /// what `AlertDialog` draws its title with, and §25 wants a dialog title at
  /// 18/600, so that is where `title` goes. The one forced fit is `titleMedium`
  /// carrying §12.2's `bodyMedium` (14/500): Material has no emphasis-body slot,
  /// and `titleMedium` is the closest thing it has to "slightly heavier than
  /// body".
  ///
  /// All fifteen of Material's slots are filled, including the ones this app
  /// never names. A slot left null is not "unused" — it is whatever size
  /// Material's default happens to be, in whatever family the theme set, which
  /// is a way to end up with a 16px body somewhere nobody was looking.
  ///
  /// Widgets in this app should prefer the named accessors on `DesignTokens`
  /// over picking a slot by memory.
  static TextTheme textTheme(String family) {
    final display = _style(family, displaySize, bold, _displayHeight);
    final headline = _style(family, headlineSize, bold, _headlineHeight);
    final title = _style(family, titleSize, semibold, _titleHeight);
    final emphasis = _style(family, bodySize, medium, _bodyHeight);
    final bodyLarge = _style(family, bodyLargeSize, regular, _bodyHeight);
    final body = _style(family, bodySize, regular, _bodyHeight);
    final caption = _style(family, captionSize, regular, _labelHeight);
    final label = _style(family, labelSize, medium, _labelHeight);

    return TextTheme(
      displayLarge: display,
      displayMedium: display,
      displaySmall: headline,
      headlineLarge: headline,
      headlineMedium: headline,
      headlineSmall: title,
      titleLarge: title,
      titleMedium: emphasis,
      titleSmall: label,
      bodyLarge: bodyLarge,
      bodyMedium: body,
      bodySmall: caption,
      labelLarge: label,
      labelMedium: caption,
      labelSmall: caption,
    );
  }

  /// One spec level, with the family and both weight spellings applied.
  ///
  /// Public because components that need a level outside the `TextTheme`
  /// mapping (or a colour baked in) build from here rather than from a bare
  /// `TextStyle`.
  static TextStyle style(
    String family,
    double size,
    FontWeight weight,
    double height, {
    double? letterSpacing,
  }) => _style(family, size, weight, height, letterSpacing: letterSpacing);

  static TextStyle _style(
    String family,
    double size,
    FontWeight weight,
    double height, {
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: family,
    fontFamilyFallback: AppFonts.fallbacksFor(family),
    fontSize: size,
    fontWeight: weight,
    fontVariations: <FontVariation>[
      FontVariation('wght', weight.value.toDouble()),
    ],
    height: height,
    letterSpacing: letterSpacing,
  );
}
