// The voice controls pinned to the bottom of the sidebar (§21).

import 'package:flutter/material.dart';
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
            // The shortcut system calls the same method, so there is one
            // definition of what muting does.
            onPressed: () => ref.read(sessionsProvider.notifier).toggleInputMuted(session),
          ),
          _VoiceButton(
            icon: voice.outputMuted ? Icons.headset_off : Icons.headset,
            tooltip: voice.outputMuted ? '取消耳聋' : '耳聋（关闭扬声器）',
            active: voice.outputMuted,
            colour: AppColors.danger,
            enabled: online,
            onPressed: () => ref.read(sessionsProvider.notifier).toggleOutputMuted(session),
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
