// The tokens, reachable from a `BuildContext`.
//
// `docs/UI设计与配色规范.md` §39 asks for a `ThemeExtension` carrying the tokens
// Material has no slot for. This is that, and it is also the *only* thing
// widgets read — which is what makes a theme switch cost nothing outside this
// layer: none of the call sites names a colour directly.
//
// The extension holds a whole [AppPalette] rather than forwarding to a class of
// constants. That is the difference that let a second and third theme exist at
// all: a constant cannot vary, and a widget reading `AppColors.textPrimary`
// would have gone on drawing the purple one after the theme changed.

import 'package:flutter/material.dart';

import '../tokens/app_palette.dart';
import '../tokens/app_radius.dart';
import '../tokens/app_shadows.dart';
import '../tokens/app_spacing.dart';

/// The colours of the current theme, plus the metrics that never vary.
@immutable
class DesignTokens extends ThemeExtension<DesignTokens> {
  /// Wraps `palette` for the theme.
  const DesignTokens(this.palette);

  /// The theme's colours.
  final AppPalette palette;

  /// The tokens in scope, or Nightcord's if the theme has not installed them.
  ///
  /// Falls back rather than asserting because there is a second `MaterialApp`
  /// in this app — `StartupFailureApp`, which exists precisely for the case
  /// where the core never started — and a crash inside the screen that reports
  /// a crash would be the worst possible trade. Nightcord is the default theme,
  /// so it is also the least surprising thing to draw with.
  static DesignTokens of(BuildContext context) =>
      Theme.of(context).extension<DesignTokens>() ??
      const DesignTokens(AppPalette.nightcord);

  /// Which theme this is, by the settings file's spelling.
  ///
  /// Exposed for the tests that have to reason about the palette rather than
  /// draw it.
  String get name => palette.name;

  /// Whether this is a dark theme.
  Brightness get brightness => palette.brightness;

  // --- Background (§3.1) ---------------------------------------------------

  /// Modals, context menus, deep popups.
  Color get bgDeep => palette.bgDeep;

  /// Sidebars and navigation.
  Color get bgSidebar => palette.bgSidebar;

  /// The chat and the page behind everything else.
  Color get bgMain => palette.bgMain;

  /// Floating panels.
  Color get bgElevated => palette.bgElevated;

  // --- Surface (§4) --------------------------------------------------------

  Color get surface1 => palette.surface1;
  Color get surface2 => palette.surface2;
  Color get surface3 => palette.surface3;

  // --- Text (§6) -----------------------------------------------------------

  Color get textPrimary => palette.textPrimary;
  Color get textSecondary => palette.textSecondary;
  Color get textTertiary => palette.textTertiary;
  Color get textDisabled => palette.textDisabled;
  Color get textOnPrimary => palette.textOnPrimary;

  // --- Border (§7) ---------------------------------------------------------

  Color get borderSubtle => palette.borderSubtle;
  Color get borderDefault => palette.borderDefault;
  Color get borderStrong => palette.borderStrong;

  // --- Primary and the states around it (§5, §19, §35) ---------------------

  Color get primary => palette.primary;
  Color get primaryHover => palette.primaryHover;
  Color get primaryPressed => palette.primaryPressed;
  Color get primaryFocus => palette.primaryFocus;
  Color get primaryDisabled => palette.primaryDisabled;

  /// A channel row under the pointer (§19).
  Color get channelHoverBg => palette.channelHoverBg;

  /// The message composer and every other text field (§18).
  Color get inputBg => palette.inputBg;

  // --- Semantic (§8) -------------------------------------------------------

  Color get success => palette.success;
  Color get successBg => palette.successBg;
  Color get warning => palette.warning;
  Color get warningBg => palette.warningBg;
  Color get error => palette.error;
  Color get errorBg => palette.errorBg;
  Color get info => palette.info;
  Color get infoBg => palette.infoBg;

  // --- Presence (§9) -------------------------------------------------------

  Color get online => palette.online;
  Color get idle => palette.idle;
  Color get busy => palette.busy;
  Color get offline => palette.offline;

  // --- Layout and motion ---------------------------------------------------
  //
  // Re-exported so a component needs one import rather than five. Not fields:
  // these are the same in every theme, which is §43's "same spacing language"
  // and the reason a theme switch does not move anything.

  double get space1 => AppSpacing.space1;
  double get space2 => AppSpacing.space2;
  double get space3 => AppSpacing.space3;
  double get space4 => AppSpacing.space4;
  double get space5 => AppSpacing.space5;
  double get space6 => AppSpacing.space6;
  double get space7 => AppSpacing.space7;
  double get space8 => AppSpacing.space8;
  double get space9 => AppSpacing.space9;
  double get space10 => AppSpacing.space10;

  Radius get radiusXs => AppRadius.xs;
  Radius get radiusSm => AppRadius.sm;
  Radius get radiusMd => AppRadius.md;
  Radius get radiusLg => AppRadius.lg;
  Radius get radiusXl => AppRadius.xl;
  Radius get radiusRound => AppRadius.round;

  List<BoxShadow> get shadow1 => AppShadows.level1;
  List<BoxShadow> get shadow2 => AppShadows.level2;
  List<BoxShadow> get shadow3 => AppShadows.level3;

  /// The modal scrim.
  ///
  /// Part of the palette in spirit but not in shape: §25 gives it as
  /// `rgba(10, 8, 20, 0.55)` regardless of what is behind it, and a dim scrim
  /// over a light page is how every light modal is drawn too.
  Color get scrim => AppShadows.scrim;

  @override
  DesignTokens copyWith({AppPalette? palette}) =>
      DesignTokens(palette ?? this.palette);

  /// Blends towards `other`, so a theme switch cross-fades.
  ///
  /// `MaterialApp` wraps its subtree in an `AnimatedTheme`, which calls this on
  /// every frame of the switch. Returning one palette or the other — which is
  /// what this did while there was only one theme — would make the change snap
  /// at the half-way point instead.
  @override
  DesignTokens lerp(covariant DesignTokens? other, double t) => other == null
      ? this
      : DesignTokens(AppPalette.lerp(palette, other.palette, t));
}
