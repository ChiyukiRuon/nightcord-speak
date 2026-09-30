// The voice controls pinned to the bottom of the sidebar (§21).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/domain.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../settings/settings_dialog.dart';

/// Who we are, and the buttons that control our microphone and speakers.
class VoiceBar extends ConsumerWidget {
  /// Controls voice on `session`.
  const VoiceBar({required this.session, super.key});

  /// The session the engine feeds.
  final int session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(sessionsProvider)[session];
    final voice = view?.voice ?? const VoiceState();
    final name = view?.ownClient?.name ?? '未连接';
    final online = view?.isConnected ?? false;

    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: AppColors.header,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          _VoiceButton(
            icon: voice.inputMuted ? Icons.mic_off : Icons.mic,
            tooltip: voice.inputMuted ? '取消静音' : '静音麦克风',
            active: voice.inputMuted,
            colour: AppColors.danger,
            enabled: online,
            onPressed: () {
              final muted = !voice.inputMuted;
              ref.read(rustClientProvider).setInputMuted(muted);
              // Reflected locally at once so the button feels responsive; the
              // core's `voice_state_changed` is what makes it stick.
              ref.read(sessionsProvider.notifier).reportVoiceState(
                session,
                voice.copyWith(inputMuted: muted),
              );
            },
          ),
          _VoiceButton(
            icon: voice.outputMuted ? Icons.headset_off : Icons.headset,
            tooltip: voice.outputMuted ? '取消耳聋' : '耳聋（关闭扬声器）',
            active: voice.outputMuted,
            colour: AppColors.danger,
            enabled: online,
            onPressed: () {
              final muted = !voice.outputMuted;
              ref.read(rustClientProvider).setOutputMuted(muted);
              ref.read(sessionsProvider.notifier).reportVoiceState(
                session,
                voice.copyWith(outputMuted: muted),
              );
            },
          ),
          _VoiceButton(
            icon: Icons.settings,
            tooltip: '设置',
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
    final tint = !enabled
        ? AppColors.textMuted
        : active
        ? (colour ?? AppColors.accent)
        : AppColors.textSecondary;

    return IconButton(
      onPressed: enabled ? onPressed : null,
      tooltip: tooltip,
      iconSize: 19,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: const EdgeInsets.all(6),
      icon: Icon(icon, color: tint),
    );
  }
}

/// Reads a held key as push-to-talk (§30).
///
/// A `Focus` wrapper rather than a global shortcut: registering a system-wide
/// hotkey needs a plugin, and the roadmap puts that in the polish phase. This
/// works whenever the window has focus, which is enough to use it.
class PushToTalkListener extends ConsumerStatefulWidget {
  /// Wraps `child`.
  const PushToTalkListener({required this.session, required this.child, super.key});

  /// The session the engine feeds.
  final int session;

  /// What to wrap.
  final Widget child;

  @override
  ConsumerState<PushToTalkListener> createState() => _PushToTalkListenerState();
}

class _PushToTalkListenerState extends ConsumerState<PushToTalkListener> {
  final _focus = FocusNode(debugLabel: 'push-to-talk');
  bool _held = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// Whether this key event is the push-to-talk chord.
  bool _isChord(KeyEvent event) =>
      event.logicalKey == LogicalKeyboardKey.keyP &&
      HardwareKeyboard.instance.isControlPressed &&
      HardwareKeyboard.instance.isShiftPressed;

  void _setHeld(bool held) {
    if (_held == held) return;
    _held = held;
    ref.read(rustClientProvider).setPushToTalk(held);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (_, event) {
        if (!_isChord(event)) return KeyEventResult.ignored;
        switch (event) {
          case KeyDownEvent():
            _setHeld(true);
          case KeyUpEvent():
            _setHeld(false);
          case KeyRepeatEvent():
            break; // already held
        }
        return KeyEventResult.handled;
      },
      child: widget.child,
    );
  }
}
