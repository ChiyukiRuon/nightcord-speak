// The application settings.
//
// Audio was the first thing to need settings, so this dialog was audio-only and
// hid inside the voice bar. It is now the app's settings surface, which is why
// the sections below are peers: devices, shortcuts and notifications join them
// rather than nesting inside audio.
//
// Every control here writes through `settingsProvider`, which is what makes the
// values survive closing the dialog and restarting the app. Before that they
// lived in this widget's state and were gone the moment it was dismissed.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/rust_client.dart';
import '../../models/domain.dart';
import '../../models/settings.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../models/shortcuts.dart';
import '../../models/voice_status.dart';
import '../shortcuts/chord_field.dart';
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
  late final TextEditingController _nickname = TextEditingController();
  late final TextEditingController _profile = TextEditingController();
  bool _started = false;

  /// Asks the core for the meter reading, and — far more slowly — re-enumerates
  /// the devices so a headset plugged in while this is open shows up.
  ///
  /// Two rates because they cost very different amounts: the status is a read of
  /// numbers the engine already has, while enumeration is a synchronous
  /// round-trip to the audio host that runs on the worker and stalls every other
  /// command while it happens.
  Timer? _statusTicker;
  Timer? _devicesTicker;

  /// Where the sensitivity slider is while it is being dragged.
  ///
  /// Kept apart from the stored settings so a drag does not write the file once
  /// per pixel; the change is committed when the user lets go.
  double? _dragging;

  @override
  void initState() {
    super.initState();
    // Enumeration touches real hardware on the core's thread, so the lists
    // arrive through `audioDevicesProvider` rather than as a return value.
    // Asking again on open also picks up a headset plugged in since last time.
    final client = ref.read(rustClientProvider);
    client.requestSettings();
    client.requestAudioDevices('input');
    client.requestAudioDevices('output');

    // A dialog that is open is a dialog someone is looking at, so this is the
    // only time either timer needs to run.
    _statusTicker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) ref.read(voiceStatusProvider.notifier).refresh();
    });
    _devicesTicker = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      client.requestAudioDevices('input');
      client.requestAudioDevices('output');
    });

    // The text fields are seeded once the core answers. They cannot be filled
    // from `build`, and cannot be filled before the answer arrives — see the
    // guard in `build` for why the form is not drawn until then.
    ref.listenManual(settingsProvider, (_, settings) {
      if (settings == null || !mounted) return;
      setState(() {
        _nickname.text = settings.connection.nickname;
        _profile.text = settings.connection.profile;
      });
    });
  }

  @override
  void dispose() {
    _statusTicker?.cancel();
    _devicesTicker?.cancel();
    _nickname.dispose();
    _profile.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    // Nothing to edit until the core answers. Drawing the form first would seed
    // every control with a default the user never chose — and
    // `DropdownButtonFormField.initialValue` is read once, so it would not
    // correct itself afterwards.
    if (settings == null) {
      return const AlertDialog(
        backgroundColor: AppColors.sidebar,
        title: Text('设置'),
        content: SizedBox(
          width: 480,
          height: 80,
          child: Center(
            child: Text('正在读取设置…', style: TextStyle(color: AppColors.textSecondary)),
          ),
        ),
      );
    }

    final devices = ref.watch(audioDevicesProvider);
    final view = ref.watch(sessionsProvider)[widget.session];
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
              _DeviceDropdown(
                label: '麦克风',
                value: settings.audio.inputDevice,
                devices: devices['input'] ?? const <AudioDevice>[],
                onChanged: (id) => _audio(
                  settings,
                  settings.audio.copyWith(inputDevice: id, clearInputDevice: id == null),
                ),
              ),
              const SizedBox(height: 12),
              _DeviceDropdown(
                label: '扬声器',
                value: settings.audio.outputDevice,
                devices: devices['output'] ?? const <AudioDevice>[],
                onChanged: (id) => _audio(
                  settings,
                  settings.audio.copyWith(outputDevice: id, clearOutputDevice: id == null),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<VoiceActivationMode>(
                initialValue: settings.audio.mode,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '传输方式'),
                items: [
                  for (final mode in VoiceActivationMode.values)
                    DropdownMenuItem(value: mode, child: Text(mode.label)),
                ],
                onChanged: (mode) {
                  if (mode == null) return;
                  _audio(settings, settings.audio.copyWith(mode: mode));
                },
              ),
              const SizedBox(height: 12),
              _DeviceInUse(status: ref.watch(voiceStatusProvider)),
              const SizedBox(height: 16),
              _SensitivitySlider(
                value: _dragging ?? settings.audio.activation.sensitivity,
                enabled: settings.audio.mode == VoiceActivationMode.voiceActivation,
                onChanged: (value) => setState(() => _dragging = value),
                onChangeEnd: (value) {
                  setState(() => _dragging = null);
                  _audio(
                    settings,
                    settings.audio.copyWith(
                      activation: settings.audio.activation.copyWith(sensitivity: value),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              _LevelMeter(
                status: ref.watch(voiceStatusProvider),
                threshold: settings.audio.activation.sensitivity,
              ),
              const SizedBox(height: 12),
              // Said out loud because a device cannot be swapped under a running
              // stream: the core would have to tear it down and reopen it, which
              // is worse than waiting when someone is mid-sentence.
              Text(
                connected
                    ? '设备改动会在下次「开始语音」时生效。'
                    : '连接后可开始语音。',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
                    onPressed: (_started || !connected) ? null : _startVoice,
                    child: const Text('开始语音'),
                  ),
                  const SizedBox(width: 12),
                  // Only meaningful with an engine: it owns the output device,
                  // and a second stream on the same speakers is not something
                  // the OS allows anyway.
                  OutlinedButton.icon(
                    onPressed: (ref.watch(voiceStatusProvider)?.running ?? false)
                        ? () => ref.read(voiceStatusProvider.notifier).testOutput()
                        : null,
                    icon: const Icon(Icons.volume_up_outlined, size: 18),
                    label: const Text('测试扬声器'),
                  ),
                ],
              ),

              const Divider(height: 32),
              const _SectionTitle('连接'),
              TextField(
                controller: _nickname,
                decoration: const InputDecoration(labelText: '默认昵称'),
                onSubmitted: (_) => _commitText(settings),
                onTapOutside: (_) => _commitText(settings),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _profile,
                decoration: const InputDecoration(
                  labelText: '身份档',
                  helperText: '同一个档名在所有服务器上是同一个客户端身份',
                ),
                onSubmitted: (_) => _commitText(settings),
                onTapOutside: (_) => _commitText(settings),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: settings.connection.maxReconnectAttempts,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '断线后'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('自动重连（不限次数）')),
                  DropdownMenuItem(value: 3, child: Text('最多重试 3 次')),
                  DropdownMenuItem(value: 10, child: Text('最多重试 10 次')),
                  DropdownMenuItem(value: 0, child: Text('不自动重连')),
                ],
                onChanged: (attempts) => _connection(
                  settings,
                  settings.connection.copyWith(
                    maxReconnectAttempts: attempts,
                    clearMaxReconnectAttempts: attempts == null,
                  ),
                ),
              ),

              const Divider(height: 32),
              const _SectionTitle('通知'),
              _NotificationSection(
                settings: settings.notifications,
                onChanged: (notifications) => ref
                    .read(settingsProvider.notifier)
                    .update(settings.copyWith(notifications: notifications)),
              ),

              const Divider(height: 32),
              const _SectionTitle('快捷键'),
              for (final action in ShortcutAction.values)
                ChordField(
                  label: action.label,
                  chord: settings.shortcuts[action],
                  onChanged: (chord) => ref
                      .read(settingsProvider.notifier)
                      .update(settings.copyWith(shortcuts: settings.shortcuts.withBinding(action, chord))),
                ),
              const SizedBox(height: 4),
              const Text(
                '点一下右边的框，然后按下你想要的组合。Esc 取消，Delete 清空（清空后不再触发）。',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
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

  /// Stores an audio change.
  void _audio(Settings settings, AudioSettings audio) =>
      ref.read(settingsProvider.notifier).update(settings.copyWith(audio: audio));

  /// Stores a connection change.
  void _connection(Settings settings, ConnectionSettings connection) =>
      ref.read(settingsProvider.notifier).update(settings.copyWith(connection: connection));

  /// Stores whatever the text fields currently hold.
  ///
  /// On submit and on leaving the field rather than per keystroke: writing the
  /// file once per character would be absurd, and a half-typed nickname saved
  /// because the user paused is worse than one saved when they move on.
  void _commitText(Settings settings) {
    final nickname = _nickname.text.trim();
    final profile = _profile.text.trim();
    if (nickname.isEmpty || profile.isEmpty) return;

    final current = settings.connection;
    if (nickname == current.nickname && profile == current.profile) return;

    _connection(
      settings,
      current.copyWith(nickname: nickname, profile: profile),
    );
  }

  void _startVoice() {
    // No device arguments: the core takes them from the settings that were just
    // written, so there is one place a device is chosen rather than two that
    // can disagree.
    ref.read(rustClientProvider).voiceStart(widget.session);
    setState(() => _started = true);
  }
}

/// What the engine actually has open, and whether it is what was asked for.
///
/// The line that answers "why can nobody hear me": a saved device that has been
/// unplugged falls back to the system default silently, so without this a user
/// can spend a long time talking into a microphone that is not the one they
/// chose.
class _DeviceInUse extends StatelessWidget {
  const _DeviceInUse({required this.status});

  final VoiceStatus? status;

  @override
  Widget build(BuildContext context) {
    final status = this.status;
    final input = status?.input;

    if (status == null || !status.running) {
      return const Text(
        '尚未开始语音。开始语音后，这里会显示实际在用的设备与麦克风电平。',
        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '正在使用：${input?.displayName ?? "没有麦克风"}',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        if (input?.fellBack ?? false)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              '你选的麦克风不在了，正在使用系统默认。',
              style: TextStyle(fontSize: 12, color: AppColors.idle),
            ),
          ),
        if (!status.healthy)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              '设备在使用中断开了。重新开始语音可以恢复。',
              style: TextStyle(fontSize: 12, color: AppColors.danger),
            ),
          ),
      ],
    );
  }
}

/// A bar that moves with the microphone, with the transmission threshold drawn
/// on it.
///
/// The threshold line is the point: the sensitivity slider above it was
/// previously adjusted blind, with only a percentage as feedback.
class _LevelMeter extends StatelessWidget {
  const _LevelMeter({required this.status, required this.threshold});

  final VoiceStatus? status;
  final double threshold;

  @override
  Widget build(BuildContext context) {
    final running = status?.running ?? false;
    final level = running ? (status?.level ?? 0.0) : 0.0;
    final transmitting = running && (status?.transmitting ?? false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          alignment: Alignment.centerLeft,
          children: [
            Container(
              height: 10,
              decoration: BoxDecoration(
                color: AppColors.composer,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            // Clamped: a level can exceed the bar, and a FractionallySizedBox
            // over 1.0 throws rather than clipping.
            FractionallySizedBox(
              widthFactor: level.clamp(0.0, 1.0),
              child: Container(
                height: 10,
                decoration: BoxDecoration(
                  color: transmitting ? AppColors.live : AppColors.textSecondary,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
            FractionallySizedBox(
              widthFactor: threshold.clamp(0.0, 1.0),
              child: Align(
                alignment: Alignment.centerRight,
                child: Container(width: 2, height: 16, color: AppColors.accent),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          running
              ? (transmitting ? '正在传输' : '低于阈值，未传输')
              : '麦克风电平（开始语音后显示）',
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

/// What is worth interrupting the user for (§43).
class _NotificationSection extends StatelessWidget {
  const _NotificationSection({required this.settings, required this.onChanged});

  final NotificationSettings settings;
  final ValueChanged<NotificationSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _switch('有人加入或离开', settings.presence, (v) => onChanged(settings.copyWith(presence: v))),
        _switch('戳一下', settings.poke, (v) => onChanged(settings.copyWith(poke: v))),
        _switch(
          '频道与服务器消息',
          settings.channelMessage,
          (v) => onChanged(settings.copyWith(channelMessage: v)),
        ),
        _switch(
          '私聊消息',
          settings.directMessage,
          (v) => onChanged(settings.copyWith(directMessage: v)),
        ),
        _switch(
          '连接断开与恢复',
          settings.connection,
          (v) => onChanged(settings.copyWith(connection: v)),
        ),
        const SizedBox(height: 8),
        // Separate from the switches above because it answers a different
        // question — where the notification goes, not whether there is one.
        _switch(
          '窗口不在前台时用系统通知',
          settings.system,
          (v) => onChanged(settings.copyWith(system: v)),
        ),
        const Text(
          '不提醒你正在看的那个会话——消息已经在你眼前了。',
          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
      ],
    );
  }

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) => SwitchListTile(
    value: value,
    onChanged: onChanged,
    title: Text(label, style: const TextStyle(fontSize: 13)),
    dense: true,
    contentPadding: EdgeInsets.zero,
    activeThumbColor: AppColors.accent,
  );
}

/// The voice-activation threshold, as a slider.
class _SensitivitySlider extends StatelessWidget {
  const _SensitivitySlider({
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text('灵敏度', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const Spacer(),
            Text(
              '${(value * 100).round()}%',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
        Slider(
          value: value.clamp(0.0, 1.0),
          // Only shown while voice activation is what opens the microphone.
          onChanged: enabled ? onChanged : null,
          onChangeEnd: enabled ? onChangeEnd : null,
          activeColor: AppColors.accent,
        ),
        const Text(
          '越高越不容易被环境噪音触发，也越需要说得响一点。',
          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
      ],
    );
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
    // A saved device that is no longer plugged in is not in the list, and
    // `DropdownButtonFormField` throws if its value is not among the items.
    // Showing 「系统默认」 and letting the core fall back is both truthful and
    // what actually happens.
    final known = devices.any((device) => device.id == value) ? value : null;

    // `initialValue` is read once and `FormFieldState` never reacts to it
    // changing, so a dropdown built while the list was still empty would show
    // 「系统默认」 for the rest of the dialog's life — the items arriving would
    // not correct the selection. Keying on the list rebuilds it when one does.
    return DropdownButtonFormField<String>(
      key: ObjectKey(devices),
      initialValue: known,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        // Only once there is a list to have not found it in: an empty or
        // failed enumeration is not evidence that anything is gone, and saying
        // so would send someone looking for a device that is still plugged in.
        helperText: value != null && known == null && devices.isNotEmpty
            ? '上次选的设备不在了，将使用系统默认'
            : null,
      ),
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
