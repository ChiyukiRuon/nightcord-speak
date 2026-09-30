// Corner radii, from `docs/UI设计与配色规范.md` §14.
//
// §14 closes with "整体不要使用过度圆润的组件" — the scale stops at 16 on
// purpose, and `round` is for things that are circles rather than for anything
// large and soft.

import 'package:flutter/painting.dart';

/// Corner radii.
abstract final class AppRadius {
  /// Badges and small controls.
  static const Radius xs = Radius.circular(4);

  /// Inputs.
  static const Radius sm = Radius.circular(6);

  /// Cards.
  static const Radius md = Radius.circular(8);

  /// Dialogs.
  static const Radius lg = Radius.circular(12);

  /// Large cards.
  static const Radius xl = Radius.circular(16);

  /// Avatars and pills — a circle, spelled as a radius so it can be used
  /// anywhere a `BorderRadius` is expected.
  static const Radius round = Radius.circular(999);

  // The same scale as `BorderRadius`, because most call sites want all four
  // corners and writing `BorderRadius.all(AppRadius.md)` everywhere is noise.

  static const BorderRadius xsAll = BorderRadius.all(xs);
  static const BorderRadius smAll = BorderRadius.all(sm);
  static const BorderRadius mdAll = BorderRadius.all(md);
  static const BorderRadius lgAll = BorderRadius.all(lg);
  static const BorderRadius xlAll = BorderRadius.all(xl);
  static const BorderRadius roundAll = BorderRadius.all(round);
}
