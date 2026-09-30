// A dot meaning "there is something here you have not looked at".
//
// Lifted out of `features/notifications/notice_stack.dart`, where it was
// declared next to the toast stack even though three of its four uses are in
// the channel sidebar. A generic indicator living inside one feature is how a
// design system ends up with two of it.

import 'package:flutter/material.dart';

import '../tokens/app_colors.dart';

/// The unread indicator.
class UnreadDot extends StatelessWidget {
  /// Draws the dot.
  const UnreadDot({this.size = 8, super.key});

  /// Diameter in logical pixels.
  ///
  /// 8 is §9's desktop presence size, which this borrows because it is the
  /// same job at the same distance. `UnreadDot` is not a presence dot — it says
  /// "unread", not "online" — but it is the same size of signal beside the same
  /// kind of name.
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
  );
}
