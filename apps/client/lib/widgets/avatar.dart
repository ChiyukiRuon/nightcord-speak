// A user's avatar.
//
// TeamSpeak has no avatar service for a plain client, so this is a generated
// mark: a colour derived from the name, and its first character. Deriving the
// colour from the name means the same person keeps the same colour across
// sessions and machines, which is the only thing that makes it useful.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A circular mark standing in for a user's picture.
class Avatar extends StatelessWidget {
  /// Builds an avatar for `name`.
  const Avatar({required this.name, this.size = 28, this.dimmed = false, super.key});

  /// The display name the mark is derived from.
  final String name;

  /// Diameter in logical pixels.
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
          fontWeight: FontWeight.w600,
          color: dimmed ? AppColors.textMuted : Colors.white,
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
