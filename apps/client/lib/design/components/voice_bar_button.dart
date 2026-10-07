import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One round control in the voice bar.
///
/// Size, icon size and hover all come from the theme's `iconButtonTheme` (§33),
/// so this only decides the *tint* — which is the part that carries meaning.
///
/// Lives in the design layer rather than beside the voice bar because the bar
/// is not the only thing that puts a control in it: the screen-sharing entry
/// sits here too, and it comes from another feature.
class VoiceBarButton extends StatelessWidget {
  const VoiceBarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.onSecondaryTap,
    this.onLongPress,
    this.active = false,
    this.colour,
    this.enabled = true,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  /// A second action behind the right mouse button, when the control has one.
  final VoidCallback? onSecondaryTap;

  /// The same second action for a finger, which has no right button.
  final VoidCallback? onLongPress;

  final bool active;
  final Color? colour;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    final tint = !enabled
        ? tokens.textDisabled
        : active
        ? (colour ?? tokens.primary)
        : tokens.textSecondary;

    if (onSecondaryTap == null && onLongPress == null) {
      return IconButton(
        onPressed: enabled ? onPressed : null,
        tooltip: tooltip,
        icon: Icon(icon, color: tint),
      );
    }

    // A button with a second action keeps the tooltip, but *outside* itself and
    // *outside* the gesture detector. An `IconButton`'s tooltip is a `Tooltip`
    // sitting below the button, and `Tooltip` claims a long press on touch
    // platforms — which is exactly the gesture that has to open the away
    // message, on exactly the platforms that have no right button. Nested the
    // other way round, the inner detector is hit-tested first and wins.
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        // Wrapped rather than folded in: an `IconButton` has no secondary tap,
        // so without this the away message would be reachable only on a machine
        // with a right button.
        onSecondaryTap: enabled ? onSecondaryTap : null,
        onLongPress: enabled ? onLongPress : null,
        child: IconButton(
          onPressed: enabled ? onPressed : null,
          icon: Icon(icon, color: tint),
        ),
      ),
    );
  }
}
