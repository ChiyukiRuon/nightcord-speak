// Durations and curves, from `docs/UI设计与配色规范.md` §34.
//
// §34 gives ranges ("Hover 100~150ms") rather than single values, because the
// right point inside a range depends on what is moving. These are the points
// chosen for this app: the low end for anything under the pointer, since a
// hover that lags reads as a dropped frame, and the middle of the range for
// surfaces that appear, since those are noticed rather than followed.
//
// §34 also lists what to avoid — bounce, long animations, big scale changes,
// flashing. Nothing here is over 240 ms.

import 'package:flutter/animation.dart';

/// How long things take, and how they get there.
abstract final class AppMotion {
  /// A row or button under the pointer: 120 ms, the middle of §34's 100–150.
  static const Duration hover = Duration(milliseconds: 120);

  /// A press: 100 ms, the top of §34's 80–120. Press feedback has to feel
  /// instantaneous, so it sits at the fast end.
  static const Duration press = Duration(milliseconds: 100);

  /// A colour or opacity cross-fade: 180 ms, the middle of §34's 150–200.
  static const Duration fade = Duration(milliseconds: 180);

  /// A panel sliding or expanding: 220 ms, the middle of §34's 200–250.
  static const Duration panel = Duration(milliseconds: 220);

  /// A dialog: 240 ms, the middle of §34's 200–280.
  static const Duration modal = Duration(milliseconds: 240);

  /// §34's two recommended curves. `easeOut` for things arriving (fast then
  /// settling), `easeInOut` for things that were already on screen and move.
  static const Curve enter = Curves.easeOut;
  static const Curve move = Curves.easeInOut;
}
