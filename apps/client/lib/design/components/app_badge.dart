// A small state icon beside a name.
//
// Lifted from `_StateBadge` in the channel sidebar, where it was instantiated
// four times (away, muted, deafened, recording) with a colour, an icon and a
// tooltip each. That is a component with four call sites; it was private only
// because the file it lived in was the only one that needed it so far.

import 'package:flutter/material.dart';

import '../tokens/app_spacing.dart';

/// An icon that says something about a person.
class StateBadge extends StatelessWidget {
  /// Draws `icon` in `colour`, explaining itself on hover.
  const StateBadge({
    required this.icon,
    required this.colour,
    required this.tooltip,
    super.key,
  });

  /// The glyph.
  final IconData icon;

  /// What it is drawn in. §2.6's semantic colours, in practice.
  final Color colour;

  /// What it means, for the pointer and for a screen reader.
  ///
  /// §29 is why this is not optional: colour must never be the only carrier of
  /// a state, and on a member row the tooltip is the only other channel there
  /// is. It doubles as the accessibility label through `Tooltip`'s semantics.
  final String tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
    // The only semantics on the widget: an `Icon` with its own
    // `semanticLabel` *and* a `Tooltip` above it announces the same words
    // twice, and on a row with two badges that is four.
    message: tooltip,
    child: Padding(
      padding: const EdgeInsets.only(left: AppSpacing.space1),
      child: Icon(
        icon,
        // §9's small size. The badge it replaces drew at 14, which is not on
        // §9's scale at all; 16 is the step below the 20px default.
        size: 16,
        color: colour,
      ),
    ),
  );
}
