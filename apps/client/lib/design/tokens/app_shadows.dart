// Elevation, from `docs/UI设计与配色规范.md` §15.
//
// Four levels, and level 0 is the common case. §15's closing line — "避免使用
// 明显的发光阴影" — is the reason these are all plain black at low alpha with a
// generous blur and no spread: a shadow here says "this floats above the page",
// it is not decoration.

import 'package:flutter/painting.dart';

/// The four shadow levels.
abstract final class AppShadows {
  /// No shadow. Ordinary chat area, sidebar, anything flush with the page.
  static const List<BoxShadow> level0 = <BoxShadow>[];

  /// `0 2px 8px rgba(0, 0, 0, 0.12)` — cards and attachments.
  static const List<BoxShadow> level1 = <BoxShadow>[
    BoxShadow(color: Color(0x1F000000), offset: Offset(0, 2), blurRadius: 8),
  ];

  /// `0 4px 16px rgba(0, 0, 0, 0.18)` — dropdowns and popups.
  static const List<BoxShadow> level2 = <BoxShadow>[
    BoxShadow(color: Color(0x2E000000), offset: Offset(0, 4), blurRadius: 16),
  ];

  /// `0 8px 32px rgba(0, 0, 0, 0.24)` — dialogs and modals.
  static const List<BoxShadow> level3 = <BoxShadow>[
    BoxShadow(color: Color(0x3D000000), offset: Offset(0, 8), blurRadius: 32),
  ];

  /// The modal scrim, from §25: `rgba(10, 8, 20, 0.55)`.
  ///
  /// Not black — §3.1's ban on pure black applies to the scrim too, and a
  /// purple-tinted one keeps the page behind it in the same world as the page
  /// in front of it.
  static const Color scrim = Color(0x8C0A0814);
}
