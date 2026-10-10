// The one `ThemeData` the client renders through.
//
// `docs/UI设计与配色规范.md` §38 puts Material 3 in charge of behaviour —
// widget states, focus, keyboard, semantics — and this file in charge of
// appearance. That division is why the `ColorScheme` below is filled *completely*
// rather than in the handful of roles a hand-written widget happens to read:
// every Material widget that this theme does not reach renders in Material's
// own purple-grey, which is how the dropdowns, switches and sliders ended up
// outside the palette while the rest of the app was inside it.
//
// There is exactly one theme. §37 is explicit that a light theme must be
// designed rather than derived by `Color.lerp`, and dark is the only one this
// client has, so `theme:` is the only slot `MaterialApp` needs.

import 'package:flutter/material.dart';

// Re-exported so a caller that has a `BuildContext` needs one import.
// `docs/UI设计与配色规范.md` §40 names the theme as the front door to the
// design system; these keep that literally true. Components reach for the
// metrics and the motion tokens far more often than they touch the palette.
export '../tokens/app_motion.dart' show AppMotion;
export '../tokens/app_radius.dart' show AppRadius;
export '../tokens/app_shadows.dart' show AppShadows;
export '../tokens/app_spacing.dart' show AppSpacing;
export '../tokens/app_typography.dart' show AppTypography;
export 'design_tokens.dart' show DesignTokens;

import '../tokens/app_palette.dart';
import '../tokens/app_fonts.dart';
import '../tokens/app_radius.dart';
import '../tokens/app_shadows.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';
import 'design_tokens.dart';

/// Builds the client's theme for `locale`.
///
/// The locale is an argument because the font family depends on it — see
/// [`AppFonts.forLocale`] and `docs/UI字体规范.md` §5. Nothing else about the
/// theme varies by locale; the palette and the metrics are the same on every
/// platform, which is §2.1's "Cross Platform" and §43's rule 13.
ThemeData buildAppTheme(AppPalette palette, Locale locale) {
  final String family = AppFonts.forLocale(locale);
  final TextTheme text = AppTypography.textTheme(family);
  final ColorScheme scheme = _colorScheme(palette);
  final bool isDark = palette.brightness == Brightness.dark;

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: family,
    fontFamilyFallback: AppFonts.fallbacksFor(family),
    textTheme: text,
    scaffoldBackgroundColor: palette.bgMain,
    dividerColor: palette.borderSubtle,
    dividerTheme: DividerThemeData(
      color: palette.borderSubtle,
      thickness: 1,
      space: 1,
    ),
    extensions: <ThemeExtension<dynamic>>[DesignTokens(palette)],

    // Pointer feedback (§35). The app previously turned all of it off with
    // `NoSplash.splashFactory`, which left hover as the only signal that a
    // control was live — and hover is exactly what a keyboard user never sees.
    //
    // §35's example pair is `#5A5278` → `#696180`; 8% white over the first
    // lands within a point or two of the second. On a light theme the same
    // move is a *darkening* — lightening something against white does nothing.
    splashFactory: InkRipple.splashFactory,
    hoverColor: isDark ? const Color(0x14FFFFFF) : const Color(0x0F000000),
    highlightColor: const Color(0x1A000000),
    // **Not** the focus colour, despite the name. Material uses this as the
    // *background* of a selected item — a dropdown's current entry, among
    // others — so it has to be a surface that text can sit on. Filling it with
    // §35's bright focus ring (`#AEA6D6` in Nightcord, `#F2F2F5` in Black)
    // painted the selected dropdown item near-white and left its near-white
    // label invisible on it.
    //
    // The bright colour still exists as `primaryFocus`; a 2px focus *ring* is
    // drawn by whatever needs one, not by a full-bleed overlay.
    focusColor: palette.surface1,

    // --- Components (§17–§27) ---------------------------------------------

    iconTheme: IconThemeData(
      // §16: 20px is the default; the sizes at the far ends of its scale are
      // asked for at the call site.
      size: 20,
      color: palette.textSecondary,
    ),

    // §17.1 — the primary button.
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: _fill(<WidgetState, Color>{
          WidgetState.pressed: palette.primaryPressed,
          WidgetState.hovered: palette.primaryHover,
          WidgetState.disabled: palette.primaryDisabled,
        }, palette.primary),
        foregroundColor: WidgetStatePropertyAll<Color>(
          palette.textOnPrimary,
        ),
        textStyle: WidgetStatePropertyAll<TextStyle>(text.labelLarge!),
        // §33: 36–40 on desktop. 40 is the comfortable end, and buttons here
        // are sparse enough not to cost layout.
        minimumSize: const WidgetStatePropertyAll<Size>(Size(0, 40)),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(horizontal: AppSpacing.space4),
        ),
        shape: const WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: AppRadius.smAll),
        ),
      ),
    ),

    // §17.2 — the secondary button.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: _fill(<WidgetState, Color>{
          WidgetState.pressed: palette.bgSidebar,
          WidgetState.hovered: palette.surface2,
        }, palette.surface1),
        foregroundColor: WidgetStatePropertyAll<Color>(
          palette.textPrimary,
        ),
        side: WidgetStatePropertyAll<BorderSide>(
          BorderSide(color: palette.borderDefault),
        ),
        textStyle: WidgetStatePropertyAll<TextStyle>(text.labelLarge!),
        minimumSize: const WidgetStatePropertyAll<Size>(Size(0, 40)),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(horizontal: AppSpacing.space4),
        ),
        shape: const WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: AppRadius.smAll),
        ),
      ),
    ),

    // §17.3 — the ghost button, which is what toolbars and banners use.
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        backgroundColor: _fill(<WidgetState, Color>{
          WidgetState.hovered: palette.surface1,
          WidgetState.pressed: palette.bgSidebar,
        }, Colors.transparent),
        foregroundColor: WidgetStatePropertyAll<Color>(
          palette.textSecondary,
        ),
        textStyle: WidgetStatePropertyAll<TextStyle>(text.labelLarge!),
        shape: const WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: AppRadius.smAll),
        ),
      ),
    ),

    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll<Color>(
          palette.textSecondary,
        ),
        // §33: a toolbar icon's hit area is 32–36. 36 is the top of that range
        // and still cheap in a 56px bar.
        minimumSize: const WidgetStatePropertyAll<Size>(Size(36, 36)),
        iconSize: const WidgetStatePropertyAll<double>(20),
      ),
    ),

    // §18 — inputs.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      // §18 names the field's own background — `#3A3260`, a step darker than
      // the sidebar. It is not `bgSidebar`, which is what this used before v2
      // put a number on it; the field is meant to read as cut into the window.
      fillColor: palette.inputBg,
      hintStyle: text.bodyMedium!.copyWith(color: palette.textTertiary),
      labelStyle: text.bodyMedium!.copyWith(color: palette.textTertiary),
      // The floating label sits at the top-left of a filled field; §18 does
      // not name a colour for it, so it takes the same tertiary as the hint
      // and lifts to primary on focus, where the border already is.
      floatingLabelStyle: text.bodyMedium!.copyWith(color: palette.primary),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space3,
        vertical: AppSpacing.space2,
      ),
      // §18 puts the resting border at `borderDefault`, not `borderSubtle`: on
      // a fill this dark, the subtler step disappears entirely.
      border: _inputBorder(palette.borderDefault),
      enabledBorder: _inputBorder(palette.borderDefault),
      focusedBorder: _inputBorder(palette.primary),
      errorBorder: _inputBorder(palette.error),
      focusedErrorBorder: _inputBorder(palette.error),
      // §18 also gives the disabled field a deeper fill (`bgDeep`). Material
      // has no `disabledFillColor` on `InputDecorationTheme`, so that half
      // cannot be expressed here; the disabled *text* colour still comes from
      // the theme, and a field that has to look right while disabled needs the
      // fill set at the call site.
      disabledBorder: _inputBorder(palette.borderDefault),
    ),

    // §24 — tooltips.
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        color: palette.bgDeep,
        borderRadius: AppRadius.smAll,
      ),
      textStyle: text.bodySmall!.copyWith(color: palette.textPrimary),
      // §24 says "8px 10px" for tooltip padding. 10 is off the 4px grid, but it
      // is the specification's own number, so it is written as itself rather
      // than rounded to 8 or 12.
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),

    // §25 — dialogs.
    dialogTheme: DialogThemeData(
      backgroundColor: palette.bgDeep,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.lgAll,
        side: BorderSide(color: palette.borderDefault),
      ),
      titleTextStyle: text.titleLarge!.copyWith(color: palette.textPrimary),
      contentTextStyle: text.bodyMedium!.copyWith(color: palette.textPrimary),
      barrierColor: AppShadows.scrim,
      insetPadding: const EdgeInsets.all(AppSpacing.space6),
    ),

    // A modal sheet is a modal, and §2.2 files modals under `#302850`.
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.bgDeep,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: AppRadius.lg),
      ),
    ),

    // §27 — notifications. The default is the *info* variant; a caller that
    // knows better passes its own colours (see `AppToast`).
    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.infoBg,
      contentTextStyle: text.bodyMedium!.copyWith(color: palette.textPrimary),
      actionTextColor: palette.primaryFocus,
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      elevation: 0,
    ),

    // §26 — context menus. The item height and padding are set here rather
    // than in each menu because every one of them in this app is the same
    // shape.
    popupMenuTheme: PopupMenuThemeData(
      color: palette.bgDeep,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.mdAll,
        side: BorderSide(color: palette.borderDefault),
      ),
      textStyle: text.bodyMedium!.copyWith(color: palette.textPrimary),
    ),

    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll<Color?>(
          palette.bgDeep,
        ),
        surfaceTintColor: WidgetStatePropertyAll<Color?>(Colors.transparent),
      ),
    ),

    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll<Color?>(
          palette.bgDeep,
        ),
        surfaceTintColor: const WidgetStatePropertyAll<Color?>(
          Colors.transparent,
        ),
        shape: const WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        ),
      ),
      textStyle: text.bodyMedium!.copyWith(color: palette.textPrimary),
    ),

    listTileTheme: ListTileThemeData(
      iconColor: palette.textSecondary,
      textColor: palette.textPrimary,
      // §33 puts a desktop list row at 36–44. `dense` keeps the rows the
      // switcher and the saved-server list already had.
      dense: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3),
    ),

    // §4: elevation is a surface colour, not a drop shadow, so a card has
    // level 0 and a background a step up from the page.
    cardTheme: CardThemeData(
      color: palette.surface1,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      margin: EdgeInsets.zero,
    ),

    // §5 lists sliders as a primary-coloured control. The spec does not
    // describe a slider in detail, so the rest stays Material's shape.
    sliderTheme: SliderThemeData(
      activeTrackColor: palette.primary,
      thumbColor: palette.primary,
      // `surface1`, not `bgDeep`. The sliders in this app live in the settings
      // dialog, and §25 puts a dialog at exactly `bgDeep` — so an inactive
      // track in that colour is the same colour as the thing behind it and the
      // slider reads as a stub with no range. A groove has to be a step *up*
      // from the surface it is cut into; the level meter beside it uses the
      // same value for the same reason.
      inactiveTrackColor: palette.surface1,
      overlayColor: palette.primary.withValues(alpha: 0.12),
      valueIndicatorColor: palette.surface3,
      valueIndicatorTextStyle: text.bodySmall!.copyWith(
        color: palette.textPrimary,
      ),
    ),

    // The track carries the state; the knob contrasts *with the track*, not
    // with the page.
    //
    // It used to be `primaryPressed` under a `primary` thumb — two adjacent
    // steps of the same ramp, twenty levels apart, both desaturated. An "on"
    // switch came out a flat lavender blob whose knob you could barely find,
    // which reads as a broken render or a disabled control rather than as
    // "this is on". The knob is now the on-primary colour, so it is white in
    // two themes and near-black in the third, ~115 levels from its track.
    //
    // The "off" track also moved: it was `bgDeep`, which is exactly the dialog
    // a switch sits in, so the off state had an invisible track held together
    // by a hairline outline.
    switchTheme: SwitchThemeData(
      thumbColor: _fill(<WidgetState, Color>{
        WidgetState.disabled: palette.textDisabled,
        WidgetState.selected: palette.textOnPrimary,
      }, palette.textTertiary),
      trackColor: _fill(<WidgetState, Color>{
        WidgetState.disabled: palette.surface1,
        WidgetState.selected: palette.primary,
      }, palette.surface2),
      trackOutlineColor: _fill(<WidgetState, Color>{
        WidgetState.disabled: palette.borderSubtle,
        WidgetState.selected: Colors.transparent,
      }, palette.borderStrong),
    ),

    // The connect screen picks the protocol with one of these.
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: _fill(<WidgetState, Color>{
          WidgetState.selected: palette.surface1,
          WidgetState.hovered: palette.surface2,
        }, Colors.transparent),
        foregroundColor: _fill(<WidgetState, Color>{
          WidgetState.selected: palette.textPrimary,
        }, palette.textSecondary),
        side: WidgetStatePropertyAll<BorderSide>(
          BorderSide(color: palette.borderDefault),
        ),
        textStyle: WidgetStatePropertyAll<TextStyle>(text.labelLarge!),
        shape: const WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: AppRadius.smAll),
        ),
      ),
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: palette.primary,
    ),

    textSelectionTheme: TextSelectionThemeData(
      cursorColor: palette.primary,
      selectionColor: Color(0x4D887EB4),
      selectionHandleColor: palette.primary,
    ),

    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStatePropertyAll<double>(6),
      radius: AppRadius.round,
      thumbColor: WidgetStatePropertyAll<Color?>(palette.surface3),
    ),
  );
}

/// The colour roles, §39's list plus every other role a Material widget reads.
///
/// Roles the specifications do not name are mapped to the nearest thing they
/// *do* name, and each of those is called out below: the alternative — leaving
/// them unset — is what put Material's default purple-grey into the dropdowns.
ColorScheme _colorScheme(AppPalette palette) => ColorScheme(
  brightness: Brightness.dark,

  primary: palette.primary,
  onPrimary: palette.textOnPrimary,
  primaryContainer: palette.primaryPressed,
  onPrimaryContainer: palette.textPrimary,

  // No role in §3 is "the secondary accent". `textSecondary` is used as the
  // neutral-on-surface pair, which is the closest fit — nothing in this app
  // draws a secondary-accent fill.
  secondary: palette.textSecondary,
  onSecondary: palette.bgDeep,
  // §19's selected-row background is `#5A5278`, which is `surface1`. This is
  // the role Material reaches for when a choice is selected.
  secondaryContainer: palette.surface1,
  onSecondaryContainer: palette.textPrimary,

  // §8's info blue, for the rare tertiary accent.
  tertiary: palette.info,
  onTertiary: palette.bgDeep,
  tertiaryContainer: palette.infoBg,
  onTertiaryContainer: palette.textPrimary,

  error: palette.error,
  onError: palette.textOnPrimary,
  errorContainer: palette.errorBg,
  onErrorContainer: palette.textPrimary,

  // §3.1: `#4F486E` is the main background, and it is also what `surface`
  // should be — a page and a surface at the same level is the point of a
  // layered flat design.
  surface: palette.bgMain,
  onSurface: palette.textPrimary,
  onSurfaceVariant: palette.textSecondary,

  // The five tonal steps, in §2.2's order, so Material's own elevation model
  // reproduces the spec's ladder instead of inventing one.
  surfaceDim: palette.bgDeep,
  surfaceBright: palette.surface3,
  surfaceContainerLowest: palette.bgDeep,
  surfaceContainerLow: palette.bgSidebar,
  surfaceContainer: palette.bgMain,
  surfaceContainerHigh: palette.surface1,
  surfaceContainerHighest: palette.surface2,

  // §15's closing rule is that nothing glows. Material's surface tint is a
  // purple wash applied by elevation, which is exactly a glow; transparent
  // turns it off and lets the surface colours above do the work.
  surfaceTint: Colors.transparent,

  outline: palette.borderDefault,
  outlineVariant: palette.borderSubtle,

  shadow: Colors.black,
  scrim: AppShadows.scrim,

  // Material puts a snack bar on `inverseSurface` when nothing else is set.
  // The theme sets `snackBarTheme` outright (§27), so these two only matter
  // for any future inverse surface — they are the *light* end of the palette
  // because that is what "inverse" means, not because anything should use it.
  inverseSurface: palette.surface2,
  onInverseSurface: palette.textPrimary,
  inversePrimary: palette.primaryFocus,
);

/// A filled outline with the input radius (§14: inputs are the 6px step).
OutlineInputBorder _inputBorder(Color color) => OutlineInputBorder(
  borderRadius: AppRadius.smAll,
  borderSide: BorderSide(color: color),
);

/// A `WidgetStateProperty` that resolves through `states` and falls back to
/// `rest`.
///
/// Material's own resolution walks a long list of states in its own order
/// (disabled, hovered, focused, pressed…); this says exactly which state gets
/// which colour and lets anything unspecified — including the widget's own
/// overlay — show through.
WidgetStateProperty<Color> _fill(Map<WidgetState, Color> states, Color rest) =>
    WidgetStateProperty.resolveWith<Color>((Set<WidgetState> active) {
      for (final MapEntry<WidgetState, Color> entry in states.entries) {
        if (active.contains(entry.key)) return entry.value;
      }
      return rest;
    });
