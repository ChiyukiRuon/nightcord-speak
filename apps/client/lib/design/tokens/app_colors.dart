// The raw palette, transcribed from `docs/UI设计与配色规范.md` §3–§10.
//
// That document is **v2.0**, which replaced the colours of the first version
// wholesale: it renames the background group (`bgMain` / `bgSidebar` / `bgDeep`
// / `bgElevated`), revalues every surface and the whole primary ramp, and adds
// §41's rule that the old values must not appear anywhere. The old set was
// greyer and bluer; this one is the deep purple-blue the reference UI has.
//
// This file is a copy of the specification, not an interpretation of it: the
// values are meant to be compared against that document line by line, so a
// change here that is not a change there is a bug. Anything that wants to
// *derive* a colour (a hover tint, a disabled state) belongs in the theme or in
// a component, not in this file.
//
// Widgets do not read this class directly — `DesignTokens.of(context)` is the
// one place they should touch (see `design/theme/design_tokens.dart` for why).
// The two exceptions are `app_theme.dart`, which builds the `ThemeData` from
// these constants, and components that need a palette entry with no semantic
// home of its own.

import 'package:flutter/painting.dart';

/// Every colour in the design system.
///
/// `abstract final` mirrors the specification's own declaration: the class is a
/// namespace for constants and is never instantiated or extended.
abstract final class AppColors {
  // --- Background (§3.1) ---------------------------------------------------
  //
  // Four steps of lightness rather than four kinds of widget. §4 is explicit
  // that the purple atmosphere comes from `bgSidebar` + `bgMain` — not from
  // primary — so the whole layout has to be legible from these alone.

  /// Modals, context menus, deep popups.
  static const Color bgDeep = Color(0xFF302850);

  /// Sidebars and navigation.
  static const Color bgSidebar = Color(0xFF3F3661);

  /// The chat and the page behind everything else.
  static const Color bgMain = Color(0xFF4F486E);

  /// Floating panels.
  static const Color bgElevated = Color(0xFF554C75);

  // --- Surface (§4) --------------------------------------------------------
  //
  // Selection, hover and cards. §4 repeats the rule that elevation is a
  // lightness step rather than a border.

  /// Selection, hover, ordinary cards.
  static const Color surface1 = Color(0xFF5A5278);

  /// Attachments, tooltips, elevated cards.
  static const Color surface2 = Color(0xFF696180);

  /// Emphasised surfaces.
  static const Color surface3 = Color(0xFF7A7190);

  // --- Primary (§5) --------------------------------------------------------
  //
  // Buttons, links, selection, focus, progress, sliders, badges, unread marks.
  // §5 forbids it as a large background.

  static const Color primary = Color(0xFF8C82C2);
  static const Color primaryHover = Color(0xFF9A90CF);
  static const Color primaryPressed = Color(0xFF786EAD);
  static const Color primaryFocus = Color(0xFFAEA6D6);
  static const Color primaryDisabled = Color(0xFF625A78);

  // --- Text (§6) -----------------------------------------------------------
  //
  // Three levels of emphasis, then a disabled grey. §6 warns against using pure
  // white everywhere.

  static const Color textPrimary = Color(0xFFF8F7FA);
  static const Color textSecondary = Color(0xFFD2CCDE);
  static const Color textTertiary = Color(0xFFAAA3BB);
  static const Color textDisabled = Color(0xFF7C758E);

  /// Text drawn *on* a primary-coloured fill.
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // --- Border (§7) ---------------------------------------------------------
  //
  // §7 asks for these to stay quieter than the text, and prefers translucent
  // white where a hairline is wanted at all.

  static const Color borderSubtle = Color(0xFF575071);
  static const Color borderDefault = Color(0xFF625A7C);
  static const Color borderStrong = Color(0xFF766D8D);

  // --- Semantic (§8) -------------------------------------------------------
  //
  // Each has a foreground and a background half: the `*Bg` values are the toast
  // fills from §27, dark enough to carry `textPrimary`.

  static const Color success = Color(0xFF7FB89A);
  static const Color successBg = Color(0xFF344F48);

  static const Color warning = Color(0xFFD0B071);
  static const Color warningBg = Color(0xFF554B3A);

  static const Color error = Color(0xFFCF858D);
  static const Color errorBg = Color(0xFF533C48);

  static const Color info = Color(0xFF82AFC5);
  static const Color infoBg = Color(0xFF394B5C);

  // --- Presence (§9) -------------------------------------------------------

  static const Color online = Color(0xFF8CC9A3);
  static const Color idle = Color(0xFFD0B978);
  static const Color busy = Color(0xFFC9828C);
  static const Color offline = Color(0xFF7C758E);

  // --- Window controls (§10) -----------------------------------------------
  //
  // Defined because §10 defines them, but **not wired to anything**: the window
  // still uses the platform's own title bar (the Windows runner creates an
  // ordinary `WS_OVERLAPPEDWINDOW`), so nothing draws these. §10 also warns
  // against letting them leak into ordinary UI.

  static const Color windowClose = Color(0xFFEF6F91);
  static const Color windowMinimize = Color(0xFFF1C85B);
  static const Color windowMaximize = Color(0xFF52C7D9);

  // --- Named by a component section, not by §11 -----------------------------
  //
  // §11's `AppColors` block is the token list, but two sections specify a
  // colour of their own that never made it into it. They live here so they have
  // a home and one spelling; if §11 ever grows them, rename to match rather
  // than keeping both.

  /// A channel row under the pointer (§19).
  ///
  /// Its own value rather than `surface1`: §19 measures the hover step against
  /// the *sidebar*, which is a step darker than the rest of the page, so a
  /// surface-sized jump would be twice as loud as the design intends.
  static const Color channelHoverBg = Color(0xFF51496F);

  /// The message composer and every other text field (§18).
  ///
  /// Deliberately darker than `bgSidebar` — the input reads as cut *into* the
  /// window rather than laid on top of it.
  static const Color inputBg = Color(0xFF3A3260);
}
