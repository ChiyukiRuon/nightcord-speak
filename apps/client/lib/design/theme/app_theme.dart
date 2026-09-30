// The one `ThemeData` the client renders through.
//
// `docs/UI设计与配色规范.md` §32 puts Material 3 in charge of behaviour —
// widget states, focus, keyboard, semantics — and this file in charge of
// appearance. That division is why the `ColorScheme` below is filled *completely*
// rather than in the handful of roles a hand-written widget happens to read:
// every Material widget that this theme does not reach renders in Material's
// own purple-grey, which is how the dropdowns, switches and sliders ended up
// outside the palette while the rest of the app was inside it.
//
// There is exactly one theme. §30 is explicit that a light theme must be
// designed rather than derived by `Color.lerp`, and dark is the only one this
// client has, so `theme:` is the only slot `MaterialApp` needs.

import 'package:flutter/material.dart';

// Re-exported so a caller that has a `BuildContext` needs one import.
// `docs/UI设计与配色规范.md` §31 names the theme as the front door to the
// design system; these keep that literally true. Components reach for the
// metrics and the motion tokens far more often than they touch the palette.
export '../tokens/app_motion.dart' show AppMotion;
export '../tokens/app_radius.dart' show AppRadius;
export '../tokens/app_shadows.dart' show AppShadows;
export '../tokens/app_spacing.dart' show AppSpacing;
export '../tokens/app_typography.dart' show AppTypography;
export 'design_tokens.dart' show DesignTokens;

import '../tokens/app_colors.dart';
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
/// platform, which is §1.1's "Cross Platform" and §36's rule 9.
ThemeData buildAppTheme(Locale locale) {
  final String family = AppFonts.forLocale(locale);
  final TextTheme text = AppTypography.textTheme(family);
  final ColorScheme scheme = _colorScheme();

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: family,
    textTheme: text,
    scaffoldBackgroundColor: AppColors.backgroundPrimary,
    dividerColor: AppColors.borderSubtle,
    dividerTheme: const DividerThemeData(
      color: AppColors.borderSubtle,
      thickness: 1,
      space: 1,
    ),
    extensions: const <ThemeExtension<dynamic>>[DesignTokens()],

    // Pointer feedback (§28). The app previously turned all of it off with
    // `NoSplash.splashFactory`, which left hover as the only signal that a
    // control was live — and hover is exactly what a keyboard user never sees.
    //
    // 8% white over a surface is §28's own example: `#50486C` lightened by it
    // lands on `#686080`, the hover value §2.2 lists.
    splashFactory: InkRipple.splashFactory,
    hoverColor: const Color(0x14FFFFFF),
    highlightColor: const Color(0x1A000000),
    focusColor: AppColors.primaryFocus,

    // --- Components (§10–§19) ---------------------------------------------

    iconTheme: const IconThemeData(
      // §9: 20px is the default; the sizes at the far ends of its scale are
      // asked for at the call site.
      size: 20,
      color: AppColors.textSecondary,
    ),

    // §10.1 — the primary button.
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: _fill(<WidgetState, Color>{
          WidgetState.pressed: AppColors.primaryPressed,
          WidgetState.hovered: AppColors.primaryHover,
          WidgetState.disabled: AppColors.primaryDisabled,
        }, AppColors.primary),
        foregroundColor: const WidgetStatePropertyAll<Color>(
          AppColors.textOnPrimary,
        ),
        textStyle: WidgetStatePropertyAll<TextStyle>(text.labelLarge!),
        // §26: 36–40 on desktop. 40 is the comfortable end, and buttons here
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

    // §10.2 — the secondary button.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: _fill(<WidgetState, Color>{
          WidgetState.pressed: AppColors.backgroundSecondary,
          WidgetState.hovered: AppColors.surface2,
        }, AppColors.surface1),
        foregroundColor: const WidgetStatePropertyAll<Color>(
          AppColors.textPrimary,
        ),
        side: const WidgetStatePropertyAll<BorderSide>(
          BorderSide(color: AppColors.borderDefault),
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

    // §10.3 — the ghost button, which is what toolbars and banners use.
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        backgroundColor: _fill(<WidgetState, Color>{
          WidgetState.hovered: AppColors.surface1,
          WidgetState.pressed: AppColors.backgroundSecondary,
        }, Colors.transparent),
        foregroundColor: const WidgetStatePropertyAll<Color>(
          AppColors.textSecondary,
        ),
        textStyle: WidgetStatePropertyAll<TextStyle>(text.labelLarge!),
        shape: const WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: AppRadius.smAll),
        ),
      ),
    ),

    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: const WidgetStatePropertyAll<Color>(
          AppColors.textSecondary,
        ),
        // §26: a toolbar icon's hit area is 32–36. 36 is the top of that range
        // and still cheap in a 56px bar.
        minimumSize: const WidgetStatePropertyAll<Size>(Size(36, 36)),
        iconSize: const WidgetStatePropertyAll<double>(20),
      ),
    ),

    // §11 — inputs.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.backgroundSecondary,
      hintStyle: text.bodyMedium!.copyWith(color: AppColors.textTertiary),
      labelStyle: text.bodyMedium!.copyWith(color: AppColors.textTertiary),
      // The floating label sits at the top-left of a filled field; §11 does
      // not name a colour for it, so it takes the same tertiary as the hint
      // and lifts to primary on focus, where the border already is.
      floatingLabelStyle: text.bodyMedium!.copyWith(color: AppColors.primary),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space3,
        vertical: AppSpacing.space2,
      ),
      border: _inputBorder(AppColors.borderSubtle),
      enabledBorder: _inputBorder(AppColors.borderSubtle),
      focusedBorder: _inputBorder(AppColors.primary),
      errorBorder: _inputBorder(AppColors.error),
      focusedErrorBorder: _inputBorder(AppColors.error),
      disabledBorder: _inputBorder(AppColors.borderSubtle),
    ),

    // §16 — tooltips.
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      decoration: const BoxDecoration(
        color: AppColors.backgroundTertiary,
        borderRadius: AppRadius.smAll,
      ),
      textStyle: text.bodySmall!.copyWith(color: AppColors.textPrimary),
      // §16 says "8px 10px" for tooltip padding. 10 is off the 4px grid, but it
      // is the specification's own number, so it is written as itself rather
      // than rounded to 8 or 12.
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),

    // §17 — dialogs.
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.backgroundTertiary,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.lgAll,
        side: const BorderSide(color: AppColors.borderDefault),
      ),
      titleTextStyle: text.titleLarge!.copyWith(color: AppColors.textPrimary),
      contentTextStyle: text.bodyMedium!.copyWith(color: AppColors.textPrimary),
      barrierColor: AppShadows.scrim,
      insetPadding: const EdgeInsets.all(AppSpacing.space6),
    ),

    // A modal sheet is a modal, and §35 files modals under `#302850`.
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.backgroundTertiary,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: AppRadius.lg),
      ),
    ),

    // §19 — notifications. The default is the *info* variant; a caller that
    // knows better passes its own colours (see `AppToast`).
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.infoBg,
      contentTextStyle: text.bodyMedium!.copyWith(color: AppColors.textPrimary),
      actionTextColor: AppColors.primaryFocus,
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      elevation: 0,
    ),

    // §18 — context menus. The item height and padding are set here rather
    // than in each menu because every one of them in this app is the same
    // shape.
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.backgroundTertiary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.mdAll,
        side: const BorderSide(color: AppColors.borderDefault),
      ),
      textStyle: text.bodyMedium!.copyWith(color: AppColors.textPrimary),
    ),

    menuTheme: const MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll<Color?>(
          AppColors.backgroundTertiary,
        ),
        surfaceTintColor: WidgetStatePropertyAll<Color?>(Colors.transparent),
      ),
    ),

    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll<Color?>(
          AppColors.backgroundTertiary,
        ),
        surfaceTintColor: const WidgetStatePropertyAll<Color?>(
          Colors.transparent,
        ),
        shape: const WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        ),
      ),
      textStyle: text.bodyMedium!.copyWith(color: AppColors.textPrimary),
    ),

    listTileTheme: ListTileThemeData(
      iconColor: AppColors.textSecondary,
      textColor: AppColors.textPrimary,
      // §26 puts a desktop list row at 36–44. `dense` keeps the rows the
      // switcher and the saved-server list already had.
      dense: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3),
    ),

    // §2.2: elevation is a surface colour, not a drop shadow, so a card has
    // level 0 and a background a step up from the page.
    cardTheme: CardThemeData(
      color: AppColors.surface1,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      margin: EdgeInsets.zero,
    ),

    // §2.3 lists sliders as a primary-coloured control. The spec does not
    // describe a slider in detail, so the rest stays Material's shape.
    sliderTheme: SliderThemeData(
      activeTrackColor: AppColors.primary,
      thumbColor: AppColors.primary,
      // `surface1`, not `backgroundTertiary`. The sliders in this app live in
      // the settings dialog, and §35 puts a dialog at exactly
      // `backgroundTertiary` — so an inactive track in that colour is the same
      // colour as the thing behind it and the slider reads as a stub with no
      // range. A groove has to be a step *up* from the surface it is cut into;
      // the level meter beside it uses the same value for the same reason.
      inactiveTrackColor: AppColors.surface1,
      overlayColor: AppColors.primary.withValues(alpha: 0.12),
      valueIndicatorColor: AppColors.surface3,
      valueIndicatorTextStyle: text.bodySmall!.copyWith(
        color: AppColors.textPrimary,
      ),
    ),

    switchTheme: SwitchThemeData(
      thumbColor: _fill(<WidgetState, Color>{
        WidgetState.selected: AppColors.primary,
        WidgetState.disabled: AppColors.primaryDisabled,
      }, AppColors.textTertiary),
      trackColor: _fill(<WidgetState, Color>{
        WidgetState.selected: AppColors.primaryPressed,
      }, AppColors.backgroundTertiary),
      trackOutlineColor: _fill(<WidgetState, Color>{
        WidgetState.selected: Colors.transparent,
      }, AppColors.borderDefault),
    ),

    // The connect screen picks the protocol with one of these.
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: _fill(<WidgetState, Color>{
          WidgetState.selected: AppColors.surface1,
          WidgetState.hovered: AppColors.surface2,
        }, Colors.transparent),
        foregroundColor: _fill(<WidgetState, Color>{
          WidgetState.selected: AppColors.textPrimary,
        }, AppColors.textSecondary),
        side: const WidgetStatePropertyAll<BorderSide>(
          BorderSide(color: AppColors.borderDefault),
        ),
        textStyle: WidgetStatePropertyAll<TextStyle>(text.labelLarge!),
        shape: const WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: AppRadius.smAll),
        ),
      ),
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primary,
    ),

    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.primary,
      selectionColor: Color(0x4D887EB4),
      selectionHandleColor: AppColors.primary,
    ),

    scrollbarTheme: const ScrollbarThemeData(
      thickness: WidgetStatePropertyAll<double>(6),
      radius: AppRadius.round,
      thumbColor: WidgetStatePropertyAll<Color?>(AppColors.surface3),
    ),
  );
}

/// The colour roles, §33's list plus every other role a Material widget reads.
///
/// Roles the specifications do not name are mapped to the nearest thing they
/// *do* name, and each of those is called out below: the alternative — leaving
/// them unset — is what put Material's default purple-grey into the dropdowns.
ColorScheme _colorScheme() => const ColorScheme(
  brightness: Brightness.dark,

  primary: AppColors.primary,
  onPrimary: AppColors.textOnPrimary,
  primaryContainer: AppColors.primaryPressed,
  onPrimaryContainer: AppColors.textPrimary,

  // No role in §3 is "the secondary accent". `textSecondary` is used as the
  // neutral-on-surface pair, which is the closest fit — nothing in this app
  // draws a secondary-accent fill.
  secondary: AppColors.textSecondary,
  onSecondary: AppColors.backgroundTertiary,
  // §12.2's selected-row background is `#50486C`, which is `surface1`. This is
  // the role Material reaches for when a choice is selected.
  secondaryContainer: AppColors.surface1,
  onSecondaryContainer: AppColors.textPrimary,

  // §2.6's info blue, for the rare tertiary accent.
  tertiary: AppColors.info,
  onTertiary: AppColors.backgroundTertiary,
  tertiaryContainer: AppColors.infoBg,
  onTertiaryContainer: AppColors.textPrimary,

  error: AppColors.error,
  onError: AppColors.textOnPrimary,
  errorContainer: AppColors.errorBg,
  onErrorContainer: AppColors.textPrimary,

  // §4.1: `#484868` is the main background, and it is also what `surface`
  // should be — a page and a surface at the same level is the point of a
  // layered flat design.
  surface: AppColors.backgroundPrimary,
  onSurface: AppColors.textPrimary,
  onSurfaceVariant: AppColors.textSecondary,

  // The five tonal steps, in §35's order, so Material's own elevation model
  // reproduces the spec's ladder instead of inventing one.
  surfaceDim: AppColors.backgroundTertiary,
  surfaceBright: AppColors.surface3,
  surfaceContainerLowest: AppColors.backgroundTertiary,
  surfaceContainerLow: AppColors.backgroundSecondary,
  surfaceContainer: AppColors.backgroundPrimary,
  surfaceContainerHigh: AppColors.surface1,
  surfaceContainerHighest: AppColors.surface2,

  // §8's closing rule is that nothing glows. Material's surface tint is a
  // purple wash applied by elevation, which is exactly a glow; transparent
  // turns it off and lets the surface colours above do the work.
  surfaceTint: Colors.transparent,

  outline: AppColors.borderDefault,
  outlineVariant: AppColors.borderSubtle,

  shadow: Colors.black,
  scrim: AppShadows.scrim,

  // Material puts a snack bar on `inverseSurface` when nothing else is set.
  // The theme sets `snackBarTheme` outright (§19), so these two only matter
  // for any future inverse surface — they are the *light* end of the palette
  // because that is what "inverse" means, not because anything should use it.
  inverseSurface: AppColors.surface2,
  onInverseSurface: AppColors.textPrimary,
  inversePrimary: AppColors.primaryFocus,
);

/// A filled outline with the input radius (§7: inputs are the 6px step).
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
