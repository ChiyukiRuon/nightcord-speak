// The tokens, reachable from a `BuildContext`.
//
// `docs/UI设计与配色规范.md` §33 asks for a `ThemeExtension` carrying the tokens
// Material has no slot for — presence, subtle borders, row states, spacing,
// radii, shadows. This is that, and it is also the *only* thing widgets should
// read: `AppColors` is the palette the theme is built from, not an API.
//
// The extension has no fields. The design is dark-only (§30 is explicit that a
// light theme must be designed rather than derived), so every value is a
// compile-time constant and there is nothing for a theme to vary — see `lerp`
// below. Keeping the indirection anyway means a future light theme, or a test
// that wants different colours, has exactly one place to intervene, and it is
// the shape §33 asked for.

import 'package:flutter/material.dart';

import '../tokens/app_colors.dart';
import '../tokens/app_radius.dart';
import '../tokens/app_shadows.dart';
import '../tokens/app_spacing.dart';

/// Every design token, grouped the way the specifications group them.
@immutable
class DesignTokens extends ThemeExtension<DesignTokens> {
  /// The single instance the theme installs.
  const DesignTokens();

  /// The tokens in scope, or the standard ones if the theme has not installed
  /// them.
  ///
  /// Falls back rather than asserting because there is a second `MaterialApp`
  /// in this app — `StartupFailureApp`, which exists precisely for the case
  /// where the core never started — and a crash inside the screen that reports
  /// a crash would be the worst possible trade.
  static DesignTokens of(BuildContext context) =>
      Theme.of(context).extension<DesignTokens>() ?? const DesignTokens();

  // --- Background (§2.1) ---------------------------------------------------

  Color get backgroundPrimary => AppColors.backgroundPrimary;
  Color get backgroundSecondary => AppColors.backgroundSecondary;
  Color get backgroundTertiary => AppColors.backgroundTertiary;
  Color get backgroundElevated => AppColors.backgroundElevated;

  // --- Surface (§2.2) ------------------------------------------------------

  Color get surface1 => AppColors.surface1;
  Color get surface2 => AppColors.surface2;
  Color get surface3 => AppColors.surface3;

  // --- Text (§2.4) ---------------------------------------------------------

  Color get textPrimary => AppColors.textPrimary;
  Color get textSecondary => AppColors.textSecondary;
  Color get textTertiary => AppColors.textTertiary;
  Color get textDisabled => AppColors.textDisabled;
  Color get textOnPrimary => AppColors.textOnPrimary;

  /// An unselected channel name, and attachment metadata (§12.2, §15).
  Color get textRow => AppColors.rowText;

  /// A channel row's name under the pointer (§12.2).
  Color get textRowHover => AppColors.rowHoverText;

  // --- Border (§2.5) -------------------------------------------------------

  Color get borderSubtle => AppColors.borderSubtle;
  Color get borderDefault => AppColors.borderDefault;
  Color get borderStrong => AppColors.borderStrong;

  // --- Primary and the states around it (§2.3, §12.2, §28) -----------------

  Color get primary => AppColors.primary;
  Color get primaryHover => AppColors.primaryHover;
  Color get primaryPressed => AppColors.primaryPressed;
  Color get primaryFocus => AppColors.primaryFocus;
  Color get primaryDisabled => AppColors.primaryDisabled;

  /// A channel row under the pointer (§12.2).
  ///
  /// Darker than `surface1`, unlike every other hover in the system: §12.2
  /// measures this one against the *sidebar*, which is a step darker than the
  /// rest of the page.
  Color get rowHoverBg => AppColors.rowHoverBg;

  // --- Semantic (§2.6) -----------------------------------------------------

  Color get success => AppColors.success;
  Color get successBg => AppColors.successBg;
  Color get warning => AppColors.warning;
  Color get warningBg => AppColors.warningBg;
  Color get error => AppColors.error;
  Color get errorBg => AppColors.errorBg;
  Color get info => AppColors.info;
  Color get infoBg => AppColors.infoBg;

  // --- Presence (§2.7) -----------------------------------------------------

  Color get online => AppColors.online;
  Color get idle => AppColors.idle;
  Color get busy => AppColors.busy;
  Color get offline => AppColors.offline;

  // --- Layout and motion ---------------------------------------------------
  //
  // Re-exported so a component needs one import rather than five. They are not
  // theme-dependent either; the same note as the class comment applies.

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
  Color get scrim => AppShadows.scrim;

  @override
  DesignTokens copyWith() => this;

  /// Returns `this`, because there is nothing to interpolate.
  ///
  /// Every token is a constant and the app ships one theme, so a lerp between
  /// two `DesignTokens` would be interpolating a value with itself. §30 is why
  /// there is no second theme to blend towards: it says a light theme has to be
  /// designed rather than derived by `Color.lerp`, and dark is the only one
  /// this client has.
  @override
  DesignTokens lerp(covariant DesignTokens? other, double t) => this;
}
