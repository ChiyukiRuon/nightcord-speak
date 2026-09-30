// The palette and typography, matched to the reference design.
//
// One place for every colour, so a change of mood does not become a hunt
// through widgets.

import 'package:flutter/material.dart';

/// The colours the app is built from.
///
/// Named for their role rather than their hue: "sidebar" survives a change of
/// palette, "darkPurple" does not.
abstract final class AppColors {
  /// Behind the message list.
  static const Color chatBackground = Color(0xFF3B3B54);

  /// The channel sidebar.
  static const Color sidebar = Color(0xFF454567);

  /// A selected channel or server row.
  static const Color sidebarSelected = Color(0xFF55557A);

  /// A row under the pointer.
  static const Color sidebarHover = Color(0xFF4D4D72);

  /// The top bar above the channel name.
  static const Color header = Color(0xFF3F3F5C);

  /// The message composer.
  static const Color composer = Color(0xFF464666);

  /// Hairlines between regions.
  static const Color divider = Color(0xFF2F2F45);

  /// The brand accent: the server mark, links, focus rings.
  static const Color accent = Color(0xFF8B7BD8);

  /// A speaking or active indicator.
  static const Color live = Color(0xFF4ADE80);

  /// Away or muted.
  static const Color idle = Color(0xFFF0B429);

  /// Something failed.
  static const Color danger = Color(0xFFE5484D);

  /// Primary text on any of the surfaces above.
  static const Color textPrimary = Color(0xFFF2F2F7);

  /// Secondary text: timestamps, counts, hints.
  static const Color textSecondary = Color(0xFFB0B0C8);

  /// Text for someone offline.
  static const Color textMuted = Color(0xFF7E7E96);
}

/// Builds the app's theme.
ThemeData buildAppTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: Colors.white,
    surface: AppColors.chatBackground,
    onSurface: AppColors.textPrimary,
    error: AppColors.danger,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.chatBackground,
    // The reference is dense; Material's defaults are roomier than it looks.
    visualDensity: VisualDensity.compact,
    dividerColor: AppColors.divider,
    splashFactory: NoSplash.splashFactory,
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: AppColors.textPrimary),
      bodySmall: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      titleSmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
        color: AppColors.textSecondary,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.composer,
      hintStyle: const TextStyle(color: AppColors.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 400),
      decoration: BoxDecoration(
        color: Color(0xFF23233A),
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
    ),
  );
}
