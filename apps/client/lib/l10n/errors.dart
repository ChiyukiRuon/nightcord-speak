// The sentence the UI shows for a [ClientError].
//
// Here rather than on the model for the same reason as the enum labels in
// `labels.dart`: the model stays data, and turning data into a sentence needs
// the current language.

import '../models/events.dart';
import 'app_localizations.dart';

extension ClientErrorText on ClientError {
  /// The user-facing sentence, in [l10n]'s language.
  ///
  /// The payloads are shaped differently per variant — a struct with a
  /// `message`, a bare string, or nothing at all for unit variants — so this is
  /// where that irregularity is absorbed rather than at every call site.
  ///
  /// Free text the core sent is passed through: it is already the most
  /// specific thing anyone wrote, and this build has no better words for a
  /// payload it does not recognize.
  String describe(AppLocalizations l10n) {
    final detail = this.detail;

    // The Dart-side kinds that carry data rather than a payload from the core.
    if (kind == 'lagged' && detail is Map && detail['missed'] is int) {
      return l10n.errorLagged(detail['missed'] as int);
    }
    if (kind == 'unparsable' && detail is Map && detail['message'] is String) {
      return l10n.errorUnparsable(detail['message'] as String);
    }

    if (detail == null) {
      return switch (kind) {
        'avatar_image' => l10n.avatarInvalidImage,
        'timeout' => l10n.errorTimeout,
        'command_failed' => l10n.errorCommandFailed,
        'join_denied' => l10n.errorJoinDenied,
        'core_gone' => l10n.errorCoreGone,
        // A variant this build does not know: its name is all there is.
        _ => kind,
      };
    }
    if (detail is String) return detail;
    if (detail is Map) {
      final message = detail['message'];
      if (message is String) return message;
      // Some variants carry no free-text message, only a code or a name.
      final code = detail['server_code'];
      if (code != null) return l10n.errorServerCode('$code');
      // `PermissionError` is an enum *inside* the enum, and serde tags the
      // inner variant too: a missing permission arrives as
      // `{"missing_permission": {"permission": 203}}`, not flat. Reading it as
      // flat is why every refused action said only "permission" — the category,
      // and nothing a person could act on.
      final permission = detail['missing_permission'] ?? detail['denied_for'];
      if (permission is Map) {
        final action = permission['action'];
        if (action != null) return l10n.errorPermissionAction('$action');
        final id = permission['permission'];
        if (id != null) return l10n.errorMissingPermission('$id');
      }
      final name = detail['name'];
      if (name != null) return l10n.errorDeviceMissing('$name');
    }
    return kind;
  }
}
