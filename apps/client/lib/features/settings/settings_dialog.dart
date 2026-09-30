// The application settings.
//
// Audio was the first thing to need settings, so this dialog was audio-only and
// hid inside the voice bar. It is now the app's settings surface, which is why
// the sections below are peers: devices, shortcuts and notifications join them
// rather than nesting inside audio.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/rust_client.dart';
import '../../models/domain.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../util/reveal.dart';

/// Settings, opened from the voice bar.
class SettingsDialog extends ConsumerStatefulWidget {
  /// Settings that apply to `session`.
  const SettingsDialog({required this.session, super.key});

  /// The session the audio section configures.
  final int session;

  @override
  ConsumerState<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<SettingsDialog> {
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
    final view = ref.watch(sessionsProvider)[widget.session];
    final voice = view?.voice ?? const VoiceState();
    final connected = view?.isConnected ?? false;

    return AlertDialog(
      backgroundColor: AppColors.sidebar,
      title: const Text('设置'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SectionTitle('音频'),
              const Text(
                '选择后点「开始语音」才会打开设备。设备列表由 Rust 核心枚举。',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              _DeviceDropdown(
                label: '麦克风',
                value: _input,
                devices: devices['input'] ?? const <AudioDevice>[],
                onChanged: (value) => setState(() => _input = value),
              ),
              const SizedBox(height: 12),
              _DeviceDropdown(
                label: '扬声器',
                value: _output,
                devices: devices['output'] ?? const <AudioDevice>[],
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
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
                  // Starting voice needs a live session. Offering the button
                  // anyway would turn "not connected yet" into a red error,
                  // which is the same mistake the mute button used to make.
                  onPressed: (_started || !connected) ? null : _startVoice,
                  child: Text(connected ? '开始语音' : '连接后可开始语音'),
                ),
              ),
              const Divider(height: 32),
              const _SectionTitle('日志'),
              _LogSection(directory: coreLogDirectory()),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  void _startVoice() {
    ref.read(rustClientProvider).voiceStart(
      widget.session,
      inputDevice: _input,
      outputDevice: _output,
    );
    setState(() => _started = true);
  }
}

/// The "where did the log go" half of the dialog.
class _LogSection extends StatelessWidget {
  const _LogSection({required this.directory});

  /// Where the core writes, or null when records only reach stderr.
  final String? directory;

  @override
  Widget build(BuildContext context) {
    final directory = this.directory;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectableText(
          directory ??
              '这个平台没有可写的日志目录，记录只写入标准错误输出。\n'
                  '（Android 与 iOS 需要由宿主应用提供沙箱路径。）',
          style: const TextStyle(
            fontSize: 12,
            height: 1.4,
            fontFamily: 'monospace',
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: directory == null ? null : () => revealDirectory(directory),
            icon: const Icon(Icons.folder_open, size: 18),
            label: const Text('打开日志文件夹'),
          ),
        ),
      ],
    );
  }
}

/// One dropdown of audio devices, with the system default on top.
class _DeviceDropdown extends StatelessWidget {
  const _DeviceDropdown({
    required this.label,
    required this.value,
    required this.devices,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<AudioDevice> devices;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem(value: null, child: Text('系统默认')),
        ...devices.map(
          (device) => DropdownMenuItem(
            value: device.id,
            child: Text(
              device.isDefault ? '${device.name}（默认）' : device.name,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

/// A heading inside the dialog.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}
