// The colour palettes, one per theme.
//
// `docs/UI设计与配色规范.md` describes **one** palette — the purple one, v2.0.
// That is `AppPalette.nightcord`, transcribed from §42 value for value, and it
// is the default. The other two are this client's own: `black` and `white` are
// neutral, near-black and light, and **nothing in the specification defines
// them**. They keep the specification's *structure* — the same token names, the
// same layer ladder, the same semantic families — because that structure is the
// design language; only the colours are new. `docs/ui.md` records the split.
//
// A palette is a value rather than a bag of constants so a theme can be chosen
// at runtime. Widgets do not hold one: they read `DesignTokens.of(context)`,
// which is the only thing that changes when the theme does.

import 'package:flutter/material.dart' show Brightness, Color;
import 'package:flutter/foundation.dart' show immutable;

/// Every colour a theme needs, as one immutable value.
///
/// The field order follows §3–§10, so this file can be read against the
/// specification top to bottom.
@immutable
class AppPalette {
  const AppPalette({
    required this.name,
    required this.brightness,
    required this.bgDeep,
    required this.bgSidebar,
    required this.bgMain,
    required this.bgElevated,
    required this.surface1,
    required this.surface2,
    required this.surface3,
    required this.primary,
    required this.primaryHover,
    required this.primaryPressed,
    required this.primaryFocus,
    required this.primaryDisabled,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.textOnPrimary,
    required this.borderSubtle,
    required this.borderDefault,
    required this.borderStrong,
    required this.success,
    required this.successBg,
    required this.warning,
    required this.warningBg,
    required this.error,
    required this.errorBg,
    required this.info,
    required this.infoBg,
    required this.online,
    required this.idle,
    required this.busy,
    required this.offline,
    required this.channelHoverBg,
    required this.inputBg,
  });

  /// Which theme this is, as the settings file spells it.
  ///
  /// The wire spelling, not a display name — the label comes from the strings
  /// file so it can be translated.
  final String name;

  /// Whether this is a dark theme.
  ///
  /// Not decoration: it is what tells the light theme's *inverted* layer
  /// direction from the dark ones', for anything that has to reason about the
  /// ladder rather than just draw it.
  final Brightness brightness;

  // --- Background (§3.1) ---------------------------------------------------

  /// Modals, context menus, deep popups.
  final Color bgDeep;

  /// Sidebars and navigation.
  final Color bgSidebar;

  /// The chat and the page behind everything else.
  final Color bgMain;

  /// Floating panels.
  final Color bgElevated;

  // --- Surface (§4) --------------------------------------------------------

  /// Selection, hover, ordinary cards.
  final Color surface1;

  /// Attachments, tooltips, elevated cards.
  final Color surface2;

  /// Emphasised surfaces.
  final Color surface3;

  // --- Primary (§5) --------------------------------------------------------

  final Color primary;
  final Color primaryHover;
  final Color primaryPressed;
  final Color primaryFocus;
  final Color primaryDisabled;

  // --- Text (§6) -----------------------------------------------------------

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textDisabled;

  /// Text drawn on a `primary` fill.
  ///
  /// **Flips with the theme.** Nightcord and Black fill a primary button with
  /// the *light* end of the palette, so this is white on one and near-black on
  /// the other; the light theme's primary is dark, so white again.
  final Color textOnPrimary;

  // --- Border (§7) ---------------------------------------------------------

  final Color borderSubtle;
  final Color borderDefault;
  final Color borderStrong;

  // --- Semantic (§8) -------------------------------------------------------
  //
  // These keep their meaning in every theme — green is success, red is error —
  // and only their *lightness* changes, because §27's toasts put `textPrimary`
  // on `*Bg` and that pair has to stay readable. See `docs/ui.md`.

  final Color success;
  final Color successBg;
  final Color warning;
  final Color warningBg;
  final Color error;
  final Color errorBg;
  final Color info;
  final Color infoBg;

  // --- Presence (§9) -------------------------------------------------------

  final Color online;
  final Color idle;
  final Color busy;
  final Color offline;

  // --- Named by a component section, not by §11 -----------------------------

  /// A channel row under the pointer (§19).
  final Color channelHoverBg;

  /// The message composer and every other text field (§18).
  final Color inputBg;

  /// Nightcord: the specification's palette, §42 verbatim, and the default.
  static const AppPalette nightcord = AppPalette(
    name: 'nightcord',
    brightness: Brightness.dark,
    bgDeep: Color(0xFF302850),
    bgSidebar: Color(0xFF3F3661),
    bgMain: Color(0xFF4F486E),
    bgElevated: Color(0xFF554C75),
    surface1: Color(0xFF5A5278),
    surface2: Color(0xFF696180),
    surface3: Color(0xFF7A7190),
    primary: Color(0xFF8C82C2),
    primaryHover: Color(0xFF9A90CF),
    primaryPressed: Color(0xFF786EAD),
    primaryFocus: Color(0xFFAEA6D6),
    primaryDisabled: Color(0xFF625A78),
    textPrimary: Color(0xFFF8F7FA),
    textSecondary: Color(0xFFD2CCDE),
    textTertiary: Color(0xFFAAA3BB),
    textDisabled: Color(0xFF7C758E),
    textOnPrimary: Color(0xFFFFFFFF),
    borderSubtle: Color(0xFF575071),
    borderDefault: Color(0xFF625A7C),
    borderStrong: Color(0xFF766D8D),
    success: Color(0xFF7FB89A),
    successBg: Color(0xFF344F48),
    warning: Color(0xFFD0B071),
    warningBg: Color(0xFF554B3A),
    error: Color(0xFFCF858D),
    errorBg: Color(0xFF533C48),
    info: Color(0xFF82AFC5),
    infoBg: Color(0xFF394B5C),
    online: Color(0xFF8CC9A3),
    idle: Color(0xFFD0B978),
    busy: Color(0xFFC9828C),
    offline: Color(0xFF7C758E),
    channelHoverBg: Color(0xFF51496F),
    inputBg: Color(0xFF3A3260),
  );

  /// Black: the same ladder, neutral and near-black.
  ///
  /// **Not `#000000`.** §41 禁止 1 forbids pure black as a large background,
  /// and it is not only a rule to obey — a pure black page leaves nothing below
  /// it for a modal to be *deeper* than, which is how §2.2 expresses hierarchy.
  /// These values are close enough to read as black and far enough apart to
  /// keep the layers telling themselves apart.
  ///
  /// The primary is a light neutral rather than the brand purple, which is why
  /// `textOnPrimary` is dark here and light in the other two.
  static const AppPalette black = AppPalette(
    name: 'black',
    brightness: Brightness.dark,
    bgDeep: Color(0xFF0A0A0C),
    bgSidebar: Color(0xFF121214),
    bgMain: Color(0xFF17171A),
    bgElevated: Color(0xFF1D1D21),
    surface1: Color(0xFF232328),
    surface2: Color(0xFF2C2C32),
    surface3: Color(0xFF3A3A41),
    primary: Color(0xFFDCDCE2),
    primaryHover: Color(0xFFEBEBF0),
    primaryPressed: Color(0xFFC4C4CB),
    primaryFocus: Color(0xFFF2F2F5),
    primaryDisabled: Color(0xFF4A4A52),
    textPrimary: Color(0xFFF5F5F7),
    textSecondary: Color(0xFFC6C6CC),
    textTertiary: Color(0xFF96969E),
    textDisabled: Color(0xFF6A6A72),
    textOnPrimary: Color(0xFF17171A),
    borderSubtle: Color(0xFF26262B),
    borderDefault: Color(0xFF33333A),
    borderStrong: Color(0xFF45454D),
    // The semantic family is shared with Nightcord on purpose: green means
    // success, and these were chosen for a dark background anyway.
    success: Color(0xFF7FB89A),
    successBg: Color(0xFF344F48),
    warning: Color(0xFFD0B071),
    warningBg: Color(0xFF554B3A),
    error: Color(0xFFCF858D),
    errorBg: Color(0xFF533C48),
    info: Color(0xFF82AFC5),
    infoBg: Color(0xFF394B5C),
    online: Color(0xFF8CC9A3),
    idle: Color(0xFFD0B978),
    busy: Color(0xFFC9828C),
    offline: Color(0xFF6A6A72),
    channelHoverBg: Color(0xFF1F1F24),
    // §18's "cut into the window": the field is deeper than the sidebar, which
    // is already deeper than the page.
    inputBg: Color(0xFF101012),
  );

  /// White: neutral and light.
  ///
  /// The layer ladder **inverts**, and that is the one thing to know about this
  /// palette. In a dark theme "further up" means lighter, so a modal is the
  /// deepest-looking colour. On a light background there is nothing above
  /// white, so a modal is the *brightest* surface and the recessed things —
  /// sidebar, hover, selected — are grey. §37 says a light theme must be
  /// designed rather than derived, and this is exactly the part that cannot be
  /// derived.
  ///
  /// §27's toasts made the same demand from the other side: their fills are
  /// dark in the specification, and `textPrimary` here is dark, so a dark fill
  /// would have been unreadable. The semantic pair is therefore re-cut as a
  /// pale tint with a saturated foreground.
  static const AppPalette white = AppPalette(
    name: 'white',
    brightness: Brightness.light,
    bgDeep: Color(0xFFFFFFFF),
    bgSidebar: Color(0xFFEDEDF1),
    bgMain: Color(0xFFF4F4F7),
    bgElevated: Color(0xFFFAFAFC),
    surface1: Color(0xFFE5E5EA),
    surface2: Color(0xFFDBDBE2),
    surface3: Color(0xFFCDCDD6),
    primary: Color(0xFF2E2E36),
    primaryHover: Color(0xFF45454F),
    primaryPressed: Color(0xFF1C1C22),
    primaryFocus: Color(0xFF5A5A66),
    primaryDisabled: Color(0xFFC7C7CE),
    textPrimary: Color(0xFF1A1A1F),
    textSecondary: Color(0xFF4E4E58),
    textTertiary: Color(0xFF7A7A85),
    textDisabled: Color(0xFFADADB5),
    textOnPrimary: Color(0xFFFFFFFF),
    borderSubtle: Color(0xFFE6E6EA),
    borderDefault: Color(0xFFD8D8DE),
    borderStrong: Color(0xFFC2C2CB),
    success: Color(0xFF2F6B4F),
    successBg: Color(0xFFDDEFE4),
    warning: Color(0xFF7A5A16),
    warningBg: Color(0xFFF5EAD2),
    error: Color(0xFF9C3B48),
    errorBg: Color(0xFFF7DFE3),
    info: Color(0xFF2F5E78),
    infoBg: Color(0xFFDCEAF2),
    online: Color(0xFF2F7D5A),
    idle: Color(0xFF8A6D1F),
    busy: Color(0xFFA84452),
    offline: Color(0xFF8A8A93),
    channelHoverBg: Color(0xFFECECF0),
    // §18 asks a field to sit *out* of its surroundings. On a light theme that
    // means lighter than the page, not darker.
    inputBg: Color(0xFFFFFFFF),
  );

  /// Every theme, in the order the settings dropdown lists them.
  static const List<AppPalette> all = <AppPalette>[nightcord, black, white];

  /// The palette `name` refers to, or null when nothing matches.
  static AppPalette? byName(String name) {
    for (final palette in all) {
      if (palette.name == name) return palette;
    }
    return null;
  }

  /// Blends two palettes, field by field.
  ///
  /// Used by `DesignTokens.lerp`, which Material's `AnimatedTheme` calls while
  /// a `ThemeData` swap is in flight — so switching themes cross-fades over the
  /// usual 200 ms instead of snapping. The blend is a plain `Color.lerp` per
  /// field: between two neutrals it is invisible, and between Nightcord and a
  /// neutral it passes briefly through a desaturated middle, which is what a
  /// cross-fade of two palettes looks like.
  static AppPalette lerp(AppPalette a, AppPalette b, double t) {
    Color mix(Color x, Color y) => Color.lerp(x, y, t)!;
    return AppPalette(
      // Not blended: a name is not a colour, and half way through an animation
      // there is no honest answer. The target wins, so anything reading it
      // during the fade sees where the theme is going.
      name: t < 0.5 ? a.name : b.name,
      brightness: t < 0.5 ? a.brightness : b.brightness,
      bgDeep: mix(a.bgDeep, b.bgDeep),
      bgSidebar: mix(a.bgSidebar, b.bgSidebar),
      bgMain: mix(a.bgMain, b.bgMain),
      bgElevated: mix(a.bgElevated, b.bgElevated),
      surface1: mix(a.surface1, b.surface1),
      surface2: mix(a.surface2, b.surface2),
      surface3: mix(a.surface3, b.surface3),
      primary: mix(a.primary, b.primary),
      primaryHover: mix(a.primaryHover, b.primaryHover),
      primaryPressed: mix(a.primaryPressed, b.primaryPressed),
      primaryFocus: mix(a.primaryFocus, b.primaryFocus),
      primaryDisabled: mix(a.primaryDisabled, b.primaryDisabled),
      textPrimary: mix(a.textPrimary, b.textPrimary),
      textSecondary: mix(a.textSecondary, b.textSecondary),
      textTertiary: mix(a.textTertiary, b.textTertiary),
      textDisabled: mix(a.textDisabled, b.textDisabled),
      textOnPrimary: mix(a.textOnPrimary, b.textOnPrimary),
      borderSubtle: mix(a.borderSubtle, b.borderSubtle),
      borderDefault: mix(a.borderDefault, b.borderDefault),
      borderStrong: mix(a.borderStrong, b.borderStrong),
      success: mix(a.success, b.success),
      successBg: mix(a.successBg, b.successBg),
      warning: mix(a.warning, b.warning),
      warningBg: mix(a.warningBg, b.warningBg),
      error: mix(a.error, b.error),
      errorBg: mix(a.errorBg, b.errorBg),
      info: mix(a.info, b.info),
      infoBg: mix(a.infoBg, b.infoBg),
      online: mix(a.online, b.online),
      idle: mix(a.idle, b.idle),
      busy: mix(a.busy, b.busy),
      offline: mix(a.offline, b.offline),
      channelHoverBg: mix(a.channelHoverBg, b.channelHoverBg),
      inputBg: mix(a.inputBg, b.inputBg),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppPalette && other.name == name && other.bgMain == bgMain;

  @override
  int get hashCode => Object.hash(name, bgMain);
}
