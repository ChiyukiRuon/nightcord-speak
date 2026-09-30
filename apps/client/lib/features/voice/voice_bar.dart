// The voice controls pinned to the bottom of the sidebar (§21).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/domain.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';

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
            tooltip: '音频设置',
            enabled: online,
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => _AudioSettingsDialog(session: session),
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

/// Picks the input and output devices.
class _AudioSettingsDialog extends ConsumerStatefulWidget {
  const _AudioSettingsDialog({required this.session});

  final int session;

  @override
  ConsumerState<_AudioSettingsDialog> createState() => _AudioSettingsDialogState();
}

class _AudioSettingsDialogState extends ConsumerState<_AudioSettingsDialog> {
  String? _input;
  String? _output;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // Enumeration touches real hardware on the core's thread, so the lists
    // arrive through `audioDevicesProvider` rather than as a return value.
    // Asking again on open also picks up a headset plugged in since last time.
    final client = ref.read(rustClientProvider);
    client.requestAudioDevices('input');
    client.requestAudioDevices('output');
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(audioDevicesProvider);
    final voice = ref.watch(sessionsProvider)[widget.session]?.voice ?? const VoiceState();

    return AlertDialog(
      backgroundColor: AppColors.sidebar,
      title: const Text('音频设置'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '选择后点「开始语音」才会打开设备。设备列表由 Rust 核心枚举。',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _input,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '麦克风'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('系统默认')),
                  ...(devices['input'] ?? const <AudioDevice>[]).map(
                    (d) => DropdownMenuItem(
                      value: d.id,
                      child: Text(
                        d.isDefault ? '${d.name}（默认）' : d.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _input = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _output,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '扬声器'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('系统默认')),
                  ...(devices['output'] ?? const <AudioDevice>[]).map(
                    (d) => DropdownMenuItem(
                      value: d.id,
                      child: Text(
                        d.isDefault ? '${d.name}（默认）' : d.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _output = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<VoiceActivationMode>(
                initialValue: voice.mode,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '传输方式'),
                items: [
                  for (final mode in VoiceActivationMode.values)
                    DropdownMenuItem(value: mode, child: Text(mode.label)),
                ],
                onChanged: (mode) {
                  if (mode == null) return;
                  ref.read(rustClientProvider).setVoiceMode(mode);
                },
              ),
              const SizedBox(height: 16),
              const Text(
                '按键说话：按住 Ctrl + Shift + P（全局快捷键在后续阶段加入）。',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
          onPressed: _started
              ? null
              : () {
                  ref.read(rustClientProvider).voiceStart(
                        widget.session,
                        inputDevice: _input,
                        outputDevice: _output,
                      );
                  setState(() => _started = true);
                },
          child: const Text('开始语音'),
        ),
      ],
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
