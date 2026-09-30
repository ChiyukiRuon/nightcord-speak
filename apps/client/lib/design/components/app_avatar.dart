// A user's avatar.
//
// TeamSpeak has no avatar service for a plain client, so this is a generated
// mark: a colour derived from the name, and its first character. Deriving the
// colour from the name means the same person keeps the same colour across
// sessions and machines, which is the only thing that makes it useful.
//
// Moved here from `widgets/` when the design system was built: it is a leaf
// widget with no feature knowledge, used by both the chat and the member list,
// which is the definition of a component.
//
// **The gradient constants are not from either specification.** §14 gives the
// avatar's sizes, its shape and its presence dot, and stops there — there is no
// rule for a name-derived colour, because the specification assumes a real
// picture. The saturation and lightness below are the values this app already
// had. They are kept because the mark has to stay legible *and* distinguishable
// per person; §1.1's "avoid high saturation" is about the chrome, and a
// generated identity mark is not chrome.

import 'package:flutter/material.dart';

import '../tokens/app_colors.dart';
import '../tokens/app_typography.dart';

/// A circular mark standing in for a user's picture.
class Avatar extends StatelessWidget {
  /// Builds an avatar for `name`.
  const Avatar({required this.name, this.size = 28, this.dimmed = false, super.key});

  /// The display name the mark is derived from.
  final String name;

  /// Diameter in logical pixels. §14's sizes are 28 (compact), 36 (default),
  /// 40 (chat) and 64/96 (profile).
  final double size;

  /// Whether to mute it, for someone offline.
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    final hue = _hueFor(name);

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HSLColor.fromAHSL(1, hue, 0.45, dimmed ? 0.32 : 0.55).toColor(),
            HSLColor.fromAHSL(1, (hue + 40) % 360, 0.45, dimmed ? 0.26 : 0.42).toColor(),
          ],
        ),
      ),
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: AppTypography.semibold,
          // The initial sits *on* a saturated fill, which is the case §2.4's
          // `textOnPrimary` is for — its warning against pure white is about
          // text on a background, not text on a colour.
          color: dimmed ? AppColors.textDisabled : AppColors.textOnPrimary,
        ),
      ),
    );
  }

  /// A stable hue for a name.
  ///
  /// A simple polynomial hash. It only has to look arbitrary and be stable, so
  /// a cryptographic hash would be wasted work.
  static double _hueFor(String name) {
    var hash = 0;
    for (final unit in name.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return (hash % 360).toDouble();
  }
}
