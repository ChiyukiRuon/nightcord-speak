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
          // The name and the disconnect button travel together: the button sits
          // immediately to the right of the name, and the rest of the expanded
          // space is empty, which is what keeps the voice controls pinned to the
          // right edge. A plain `Expanded(Text)` with the button after it would
          // put the button out at the right-hand cluster instead, a whole bar's
          // width away from the thing it belongs to.
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    // §12.2's `bodyMedium` — 14/500, the level it names for
                    // emphasised body text. One's own name in a control bar is
                    // exactly that.
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                SizedBox(width: tokens.space1),
                // Ends the session, so it asks first — `disconnect` also
                // forgets the view, and the channel tree and the conversation
                // go with it. That is more than a stray click should cost, even
                // beside a button this deliberately placed.
                _VoiceButton(
                  icon: Icons.link_off,
                  tooltip: l10n.voiceDisconnect,
                  // Nothing to disconnect from while the core is still
                  // retrying, and the banner already offers it for that case.
                  enabled: online,
                  onPressed: () => _confirmDisconnect(context, ref),
                ),
              ],
            ),
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

  /// Asks, then closes the connection.
  ///
  /// The dialog says what is actually lost rather than "are you sure": a
  /// disconnect ends the session *and* forgets it, so the channel tree and the
  /// conversation go too. Naming that is the entire reason to ask.
  ///
  /// This button is the one control in the bar that cannot be undone by
  /// pressing it again. Muting, deafening and opening settings are all
  /// reversible in place; this is not.
  Future<void> _confirmDisconnect(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);

    // Read before the await, not after: the answer arrives an arbitrary number
    // of frames later, and `ref` belongs to a widget that may be gone by then.
    final sessions = ref.read(sessionsProvider.notifier);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.voiceDisconnectConfirmTitle),
        content: Text(l10n.voiceDisconnectConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancelButton),
          ),
          // The verb the reconnect banner already uses for the same act, so
          // there is one word for it in the app.
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.bannerDisconnect),
          ),
        ],
      ),
    );

    if (confirmed ?? false) sessions.disconnect(session);
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
