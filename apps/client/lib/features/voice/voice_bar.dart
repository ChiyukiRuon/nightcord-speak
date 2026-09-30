// The voice controls pinned to the bottom of the sidebar (§19).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/domain.dart';
import '../../providers/providers.dart';
import '../settings/settings_dialog.dart';

/// How tall the bar is.
///
/// Unchanged from before the design system: §20's desktop diagram has an
/// "optional status / input" band and gives no height for it, and 56 fits a
/// 36px control (§33) with room around it.
///
/// Public because anything floating above the bottom of the window has to clear
/// it — see `notice_stack.dart`.
const double voiceBarHeight = 56;

/// Who we are, and the buttons that control our microphone and speakers.
class VoiceBar extends ConsumerWidget {
  /// Controls voice on `session`.
  const VoiceBar({required this.session, super.key});

  /// The session the engine feeds.
  final int session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    final view = ref.watch(sessionsProvider)[session];
    final voice = view?.voice ?? const VoiceState();
    final name = view?.ownClient?.name ?? l10n.connectionStateDisconnected;
    final online = view?.isConnected ?? false;

    return Container(
      height: voiceBarHeight,
      decoration: BoxDecoration(
        // §2.2: a secondary area, the same step as the sidebar this bar sits at
        // the bottom of.
        color: tokens.bgSidebar,
        border: Border(top: BorderSide(color: tokens.borderSubtle)),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space3,
        vertical: tokens.space2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              // §12.2's `bodyMedium` — 14/500, the level it names for emphasised
              // body text. One's own name in a control bar is exactly that.
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          // Sits between the name and the microphone on purpose: it ends the
          // session, so it should not be the thing next to the button pressed
          // twenty times an hour. The same call the reconnect banner's 「断开」
          // makes — there is one definition of what disconnecting does.
          //
          // No confirmation. `disconnect` also forgets the session, so the
          // channel tree and the conversation go with it, and that is a heavier
          // consequence than the one click suggests. It is left unguarded to
          // match the banner, which has asked for no confirmation since it was
          // written; a dialog here is a one-line change if it turns out to be
          // too easy to hit.
          _VoiceButton(
            icon: Icons.link_off,
            tooltip: l10n.voiceDisconnect,
            // Nothing to disconnect from while the core is still retrying —
            // and the banner already offers it for that case.
            enabled: online,
            onPressed: () => ref.read(sessionsProvider.notifier).disconnect(session),
          ),
          _VoiceButton(
            icon: voice.inputMuted ? Icons.mic_off : Icons.mic,
            tooltip: voice.inputMuted ? l10n.voiceUnmuteMic : l10n.voiceMuteMic,
            active: voice.inputMuted,
            colour: tokens.error,
            enabled: online,
            // The shortcut system calls the same method, so there is one
            // definition of what muting does.
            onPressed: () => ref.read(sessionsProvider.notifier).toggleInputMuted(session),
          ),
          _VoiceButton(
            icon: voice.outputMuted ? Icons.headset_off : Icons.headset,
            tooltip: voice.outputMuted ? l10n.voiceUndeafen : l10n.voiceDeafen,
            active: voice.outputMuted,
            colour: tokens.error,
            enabled: online,
            onPressed: () => ref.read(sessionsProvider.notifier).toggleOutputMuted(session),
          ),
          _VoiceButton(
            icon: Icons.settings,
            tooltip: l10n.settingsTitle,
            // Unlike the two buttons above, settings do not need a live
            // connection — and the log folder it offers is most wanted exactly
            // when the connection is not working.
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => SettingsDialog(session: session),
            ),
          ),
        ],
      ),
    );
  }
}

/// One round control in the voice bar.
///
/// Size, icon size and hover all come from the theme's `iconButtonTheme` (§33),
/// so this only decides the *tint* — which is the part that carries meaning.
class _VoiceButton extends StatelessWidget {
  const _VoiceButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.colour,
    this.enabled = true,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
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

    return IconButton(
      onPressed: enabled ? onPressed : null,
      tooltip: tooltip,
      icon: Icon(icon, color: tint),
    );
  }
}
