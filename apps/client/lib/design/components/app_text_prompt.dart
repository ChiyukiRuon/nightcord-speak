// Asking for one line of text.
//
// Lifted from `_TextPromptDialog` in the channel sidebar, which is the poke
// dialog. The away message wants the same box with two additions — something to
// start from, and a line explaining where the text goes — and a second
// near-identical dialog would have been a second place for a "type something"
// box to live and drift.

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// Asks for one line of text, and returns what was typed.
///
/// An empty string is a real answer and is *not* the same as `null`: null means
/// the dialog was dismissed, and a caller like the away message has a use for
/// "nothing to say" that a caller like the poke does not.
Future<String?> showTextPrompt(
  BuildContext context, {
  required String title,
  required String label,
  required String confirm,
  String initial = '',
  String? note,
}) => showDialog<String>(
  context: context,
  builder: (context) => _TextPromptDialog(
    title: title,
    label: label,
    confirm: confirm,
    initial: initial,
    note: note,
  ),
);

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.label,
    required this.confirm,
    required this.initial,
    required this.note,
  });

  final String title;
  final String label;
  final String confirm;

  /// What the field starts with, so the common edit is a change rather than
  /// retyping yesterday's sentence.
  final String initial;

  /// One line of explanation under the field, when there is something the user
  /// could not work out from the title.
  final String? note;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    final note = widget.note;

    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(labelText: widget.label),
            // Enter sends, because the field is one line and there is nothing
            // else it could mean.
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          if (note != null) ...[
            SizedBox(height: tokens.space3),
            Text(
              note,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: tokens.textSecondary,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancelButton),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(widget.confirm),
        ),
      ],
    );
  }
}
