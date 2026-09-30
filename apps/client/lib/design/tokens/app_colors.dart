// The raw palette, transcribed from `docs/UI设计与配色规范.md` §2 / §3.
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
  // --- Background (§2.1) ---------------------------------------------------
  //
  // Four steps of lightness rather than four kinds of widget: the whole layout
  // is meant to be legible from the background alone, which is why §4.1 can
  // say "main content is 484868, sidebar is 383060" and mean it literally.

  /// Main content area — the chat, and the page behind everything else.
  static const Color backgroundPrimary = Color(0xFF484868);

  /// Sidebars and input areas.
  static const Color backgroundSecondary = Color(0xFF383060);

  /// Modals, context menus, and anything that sits *under* the page.
  static const Color backgroundTertiary = Color(0xFF302850);

  /// Floating panels.
  static const Color backgroundElevated = Color(0xFF50486C);

  // --- Surface (§2.2) ------------------------------------------------------
  //
  // Hover, cards and active states. §2.2 is explicit that these — not borders —
  // are how elevation is expressed; the border family exists for the few places
  // a real divider is genuinely needed.

  /// Hover, and ordinary cards.
  static const Color surface1 = Color(0xFF50486C);

  /// Attachments, tooltips, elevated cards.
  static const Color surface2 = Color(0xFF686080);

  /// Active and strong-surface states.
  static const Color surface3 = Color(0xFF78708E);

  // --- Primary (§2.3) ------------------------------------------------------
  //
  // §4.2 forbids using primary as a large fill. It is for buttons, links,
  // selection, focus, progress and unread badges — roughly the 8% of the
  // screen the ratio table in §1.2 allows.

  static const Color primary = Color(0xFF887EB4);
  static const Color primaryHover = Color(0xFF968CBD);
  static const Color primaryPressed = Color(0xFF766CA3);
  static const Color primaryFocus = Color(0xFFAAA2CB);
  static const Color primaryDisabled = Color(0xFF625A72);

  // --- Text (§2.4) ---------------------------------------------------------
  //
  // Three levels of emphasis, then a disabled grey. §2.4 warns against using
  // pure white for everything, so `textPrimary` is deliberately off-white and
  // the levels below it are further from it than the old palette's were.

  static const Color textPrimary = Color(0xFFF8F7FA);
  static const Color textSecondary = Color(0xFFD0CBDD);
  static const Color textTertiary = Color(0xFFA7A1B8);
  static const Color textDisabled = Color(0xFF77718A);

  /// Text drawn *on* a primary-coloured fill.
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // --- Border (§2.5) -------------------------------------------------------

  static const Color borderSubtle = Color(0xFF5B5678);
  static const Color borderDefault = Color(0xFF68627F);
  static const Color borderStrong = Color(0xFF79718F);

  // --- Semantic (§2.6) -----------------------------------------------------
  //
  // Each has a foreground and a background half: the `*Bg` values are the
  // toast/notice fills from §19, which is why they are dark enough to carry
  // `textPrimary` rather than the saturated colour itself.

  static const Color success = Color(0xFF7FB89A);
  static const Color successBg = Color(0xFF344F48);

  static const Color warning = Color(0xFFD0B071);
  static const Color warningBg = Color(0xFF554B3A);

  static const Color error = Color(0xFFCF858D);
  static const Color errorBg = Color(0xFF533C48);

  static const Color info = Color(0xFF82AFC5);
  static const Color infoBg = Color(0xFF394B5C);

  // --- Presence (§2.7) -----------------------------------------------------

  static const Color online = Color(0xFF8CC9A3);
  static const Color idle = Color(0xFFD0B978);
  static const Color busy = Color(0xFFC9828C);
  static const Color offline = Color(0xFF77718A);

  // --- Window controls (§2.8) ----------------------------------------------
  //
  // Defined because §3 defines them, but **not wired to anything**: the window
  // still uses the platform's own title bar (the Windows runner creates an
  // ordinary `WS_OVERLAPPEDWINDOW`), so nothing draws these. §2.8 also warns
  // against letting them leak into ordinary UI. Uncomment-or-delete is a
  // decision for whoever builds a custom chrome, not for this file.

  static const Color windowClose = Color(0xFFEF6F91);
  static const Color windowMinimize = Color(0xFFF1C85B);
  static const Color windowMaximize = Color(0xFF52C7D9);

  // --- List-row states (§12.2, §15) ----------------------------------------
  //
  // **Not in §3's token table.** §12.2 specifies these three by value for
  // channel rows, and §15 reuses `rowText` for attachment metadata, but the
  // token table never gives them names. They are named here so they have a
  // home; if §3 ever grows them, rename to match rather than keeping both.
  //
  // `rowText` sits between `textSecondary` and `textTertiary` and is *not*
  // redundant with either: §12.2 wants an unselected channel quieter than
  // normal body text but louder than metadata, and rounding it to one of the
  // two loses that on purpose.

  /// Unselected channel names, and attachment metadata.
  static const Color rowText = Color(0xFFC0BBCD);

  /// A channel row under the pointer.
  static const Color rowHoverBg = Color(0xFF443C68);

  /// A channel row's name under the pointer.
  static const Color rowHoverText = Color(0xFFE8E5F0);
}
