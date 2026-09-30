// A heading above a group of rows.
//
// Two private copies of this existed — `_SectionTitle` in the settings dialog
// and `_SheetHeading` in the channel sidebar — identical in type and different
// only in padding, which is the caller's business anyway.

import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

/// The label above a section.
class SectionTitle extends StatelessWidget {
  /// Shows `text` as a section heading.
  const SectionTitle(this.text, {super.key});

  /// What the section is called.
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    // `label` (13/500) is §12.2's level for labels. The two copies this
    // replaces drew it in what the old theme called `titleSmall` — 12/700 with
    // letter spacing — which is a size below the scale's `label` and a weight
    // nothing else in the app uses. A section heading is a label; this is the
    // level that says so.
    style: Theme.of(context).textTheme.labelLarge?.copyWith(
      color: DesignTokens.of(context).textSecondary,
    ),
  );
}
