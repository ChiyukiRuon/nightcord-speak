// A full-width strip above the content that has something to say.
//
// The app grew three of these independently — the crash banner, the reconnect
// banner, and the chat header — each rebuilding "a band in `header` colour with
// a hairline under it". Only the first two are the same widget; the chat header
// carries a topic and a count and is a different thing wearing similar clothes.
//
// What is shared is the shell: a band, a hairline, an icon, a message, and room
// for actions on the right.

import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

/// A strip across the top of a view.
class AppBanner extends StatelessWidget {
  /// Builds a banner.
  const AppBanner({
    required this.icon,
    required this.iconColour,
    required this.child,
    this.actions = const <Widget>[],
    super.key,
  });

  /// The glyph at the left.
  final IconData icon;

  /// What the glyph is drawn in — §8's warning or error, in practice.
  final Color iconColour;

  /// The message. Usually a `Column` of a line and an optional second one.
  final Widget child;

  /// Buttons for the right-hand end, laid out in a row.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);

    return Material(
      // §2.2 puts a secondary area — a band between the page and its content —
      // at `#3F3661`, which is the same step as the sidebar.
      color: tokens.bgSidebar,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: tokens.borderSubtle)),
        ),
        padding: EdgeInsets.fromLTRB(
          tokens.space3,
          tokens.space1,
          tokens.space1,
          tokens.space1,
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: iconColour),
            SizedBox(width: tokens.space2),
            Expanded(child: child),
            ...actions,
          ],
        ),
      ),
    );
  }
}
