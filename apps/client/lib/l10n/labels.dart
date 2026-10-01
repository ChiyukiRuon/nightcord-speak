// UI labels for enums whose models keep only data.
//
// Here rather than on the enums themselves: `models/` is pure data and must
// not depend on the localization layer, and a label is presentation — the
// widgets already hold both the enum and the strings.

import '../models/domain.dart';
import '../models/shortcuts.dart';
import 'app_localizations.dart';

/// How the transmission modes are named in the settings page.
extension VoiceActivationModeLabels on VoiceActivationMode {
  /// The user-facing name of this mode.
  String label(AppLocalizations l10n) => switch (this) {
    VoiceActivationMode.pushToTalk => l10n.modePushToTalk,
    VoiceActivationMode.voiceActivation => l10n.modeVoiceActivation,
    VoiceActivationMode.continuous => l10n.modeContinuous,
    VoiceActivationMode.muted => l10n.modeMuted,
  };
}

/// How the shortcut actions are named in the settings page.
extension ShortcutActionLabels on ShortcutAction {
  /// The user-facing name of this action.
  String label(AppLocalizations l10n) => switch (this) {
    ShortcutAction.mute => l10n.shortcutMute,
    ShortcutAction.deafen => l10n.shortcutDeafen,
    ShortcutAction.pushToTalk => l10n.shortcutPushToTalk,
  };
}
