// The voice controls pinned to the bottom of the sidebar (§19).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/components/app_text_prompt.dart';
import '../../design/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/domain.dart';
import '../../providers/providers.dart';
import '../settings/settings_dialog.dart';
import 'mic_gain_flyout.dart';

/// How far the glyphs sit below the middle of their own line box, in logical
/// pixels.
///
/// A line box is centred on the font's ascent and descent together, and Noto
/// Sans's ascent is nearly four times its descent — most of that ascent is the
/// empty space above the capitals. So a *box* that is perfectly centred still
/// draws its glyphs low.
///
/// Measured on screen at 150%: the name's ink centred 4.5 physical pixels (3
/// logical) under the middle of the bar, while the disconnect button beside it
/// — an icon, whose ink really is centred on its box — sat on it. That 3px gap
/// is what reads as "the name is not centred".
///
/// No line height fixes this: the lever is weak and pointing the wrong way, and
/// every value between 1.0 and 1.5 moved the ink by about a pixel. A `Row`
/// centres the box it is given, so a *bottom inset of twice this* is what lifts
/// the glyphs by it.
const double _opticalLift = 3;

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
    // Read from the server's own answer rather than kept beside it: the core's
    // book changes the moment our command leaves, so this is already right by
    // the time the event arrives — see `SessionsNotifier.setAway`.
    final away = view?.ownClient?.flags.away ?? false;

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
                  child: Padding(
                    // The label sitting on the bar's centre, rather than the
                    // line box that contains it — see `_opticalLift`.
                    padding: const EdgeInsets.only(bottom: _opticalLift * 2),
                    child: Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      // §12.2's `bodyMedium` — 14/500, the level it names for
                      // emphasised body text. One's own name in a control bar
                      // is exactly that.
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
                SizedBox(width: tokens.space1),
                // Ends the session, so it asks first — `disconnect` also
                // forgets the view, and the channel tree and the conversation
                // go with it. That is more than a stray click should cost, even
                // beside a button this deliberately placed.
                _VoiceButton(
                  // A door with an arrow out of it: the same 「leaving」 a
                  // sign-in screen draws, rather than a broken chain, which
                  // reads as "this link is broken" — a fault, not a choice.
                  icon: Icons.logout,
                  tooltip: l10n.voiceDisconnect,
                  // Nothing to disconnect from while the core is still
                  // retrying, and the banner already offers it for that case.
                  enabled: online,
                  onPressed: () => _confirmDisconnect(context, ref),
                ),
              ],
            ),
          ),
          // Away sits to the left of the microphone because it is about us
          // rather than about sound: it says whether we are here at all. The
          // glyph is the one the member list already draws for an away client,
          // so the button and the badge read as the same fact.
          _VoiceButton(
            // An alarm clock with a Z on its face — the closest the Material
            // set comes to the ZZZ of falling asleep, and the reason the away
            // button no longer looks like a clock you could set.
            icon: away ? Icons.snooze : Icons.snooze_outlined,
            tooltip: away ? l10n.voiceBackOnline : l10n.voiceAway,
            active: away,
            colour: tokens.idle,
            enabled: online,
            onPressed: () => ref.read(sessionsProvider.notifier).toggleAway(session),
            // The message is set once and then reused, so it lives behind a
            // secondary gesture rather than in a control of its own: a
            // permanent button for it would spend a slot in a 288px bar on
            // something nobody presses twice.
            onSecondaryTap: () => _editAwayMessage(context, ref),
            onLongPress: () => _editAwayMessage(context, ref),
          ),
          // The microphone keeps its click (mute) and gains a hover panel on
          // top: how loud we are is the microphone's business, and the button
          // is where a hand already is when someone wants to change it.
          MicGainFlyout(
            child: _VoiceButton(
              icon: voice.inputMuted ? Icons.mic_off : Icons.mic,
              tooltip: voice.inputMuted ? l10n.voiceUnmuteMic : l10n.voiceMuteMic,
              active: voice.inputMuted,
              colour: tokens.error,
              enabled: online,
              // The shortcut system calls the same method, so there is one
              // definition of what muting does.
              onPressed: () => ref.read(sessionsProvider.notifier).toggleInputMuted(session),
            ),
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

  /// Asks for the away message, remembers it, and goes away saying it.
  ///
  /// Dismissing changes nothing — neither the status nor the remembered text —
  /// which is why an empty field is a different answer from a cancel.
  Future<void> _editAwayMessage(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);

    // Both read before the await, not after: the answer arrives an arbitrary
    // number of frames later, and `ref` belongs to a widget that may be gone
    // by then.
    final sessions = ref.read(sessionsProvider.notifier);
    final saved = ref.read(settingsProvider)?.presence.awayMessage ?? '';

    final message = await showTextPrompt(
      context,
      title: l10n.awayMessageTitle,
      label: l10n.awayMessageLabel,
      confirm: l10n.saveButton,
      initial: saved,
      note: l10n.awayMessageNote,
    );
    if (message == null) return;

    sessions.goAwayWith(session, message.trim());
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
    this.onSecondaryTap,
    this.onLongPress,
    this.active = false,
    this.colour,
    this.enabled = true,
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
