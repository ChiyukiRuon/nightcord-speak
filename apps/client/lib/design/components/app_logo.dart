// The Nightcord mark: a crescent with two eyes.
//
// Drawn rather than loaded. The source is a 529-byte SVG of three circles, and
// everything it needs — an even-odd path and two filled discs — a `Canvas`
// already has. A vector asset package would be a dependency, a build step and a
// generated file to keep in sync, all to draw three circles; a PNG would need
// one export per size and would soften at any size nobody exported.
//
// **The numbers below are the SVG's**, in its own `viewBox` coordinates, so the
// two can be compared side by side. `scripts/make-app-icon.py` uses the same
// ones to build the Windows icon — if the mark changes, all three move
// together:
//
//   outer disc   centre (18.45, 18.45)  r 18.45   — the crescent's outside
//   cut-out      centre (22.86, 18.45)  r 13.82   — offset right, which is what
//                                                   leaves the crescent thick on
//                                                   the left and open to the right
//   eyes         (17.84, 18.42) and (27.88, 18.42), r 2.2 — inside the cut-out,
//                                                   which is why they read as a
//                                                   face in the dark half

import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

/// The application's mark.
class AppLogo extends StatelessWidget {
  /// Draws the mark `size` logical pixels across.
  const AppLogo({this.size = 24, this.colour, super.key});

  /// The width and height. The mark is square.
  final double size;

  /// What to draw it in, or null for the theme's primary.
  ///
  /// Null by default so a logo dropped into a new place follows the theme
  /// rather than a hard-coded colour — which is also what keeps it legible in
  /// all three: the primary is a mid purple in Nightcord, a near-white in
  /// Black and a near-black in White.
  final Color? colour;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _LogoPainter(colour ?? DesignTokens.of(context).primary),
  );
}

/// Draws the mark, in the SVG's coordinate system scaled to the widget.
class _LogoPainter extends CustomPainter {
  const _LogoPainter(this.colour);

  final Color colour;

  /// The SVG's `viewBox` is `0 0 36.9 36.9`; everything below is in those
  /// units and scaled once, at the end.
  static const double _box = 36.9;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colour
      ..isAntiAlias = true;

    canvas.save();
    canvas.scale(size.shortestSide / _box);

    // `evenOdd` is what makes this a crescent: the two ovals overlap, and the
    // rule leaves the overlap *out* of the fill rather than piling it up.
    final crescent = Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(Rect.fromCircle(center: const Offset(18.45, 18.45), radius: 18.45))
      ..addOval(Rect.fromCircle(center: const Offset(22.86, 18.45), radius: 13.82));
    canvas.drawPath(crescent, paint);

    canvas.drawCircle(const Offset(17.84, 18.42), 2.2, paint);
    canvas.drawCircle(const Offset(27.88, 18.42), 2.2, paint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.colour != colour;
}
