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
import '../../l10n/app_localizations.dart';
import '../../l10n/labels.dart';
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
  /// Whether the microphone test is running.
  ///
  /// Not the voice state: the engine follows the connection now, so this only
  /// says whether the user asked for the meter to be opened on demand.
  bool _testing = false;

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
    final client = ref.read(clientTransportProvider);
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
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);

    // Nothing to edit until the core answers. Drawing the form first would seed
    // every control with a default the user never chose — and
    // `DropdownButtonFormField.initialValue` is read once, so it would not
    // correct itself afterwards.
    if (settings == null) {
      return AlertDialog(
        backgroundColor: AppColors.sidebar,
        title: Text(l10n.settingsTitle),
        content: SizedBox(
          width: 480,
          height: 80,
          child: Center(
            child: Text(
              l10n.settingsLoading,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
      );
    }

    final devices = ref.watch(audioDevicesProvider);
    final view = ref.watch(sessionsProvider)[widget.session];
    final connected = view?.isConnected ?? false;

    return AlertDialog(
      backgroundColor: AppColors.sidebar,
      title: Text(l10n.settingsTitle),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionTitle(l10n.settingsAudioSection),
              _DeviceDropdown(
                label: l10n.settingsMicrophoneLabel,
                value: settings.audio.inputDevice,
                devices: devices['input'] ?? const <AudioDevice>[],
                onChanged: (id) => _audio(
                  settings,
                  settings.audio.copyWith(inputDevice: id, clearInputDevice: id == null),
                ),
              ),
              const SizedBox(height: 12),
              _DeviceDropdown(
                label: l10n.settingsSpeakerLabel,
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
                decoration: InputDecoration(labelText: l10n.settingsTransmissionMode),
                items: [
                  for (final mode in VoiceActivationMode.values)
                    DropdownMenuItem(value: mode, child: Text(mode.label(l10n))),
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
                    ? l10n.settingsDeviceChangeNote
                    : l10n.settingsConnectFirst,
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
                    onPressed: connected ? _toggleMicTest : null,
                    child: Text(
                      _testing ? l10n.settingsStopTest : l10n.settingsTestMicrophone,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Always available, engine or not: with no engine the core
                  // opens the output device on its own for the length of the
                  // tone. Gating this on the engine made the speaker check
                  // depend on a microphone being open first — nothing a person
                  // could guess from two buttons sitting side by side.
                  OutlinedButton.icon(
                    onPressed: () =>
                        ref.read(voiceStatusProvider.notifier).testOutput(),
                    icon: const Icon(Icons.volume_up_outlined, size: 18),
                    label: Text(l10n.settingsTestSpeaker),
                  ),
                ],
              ),

              const Divider(height: 32),
              _SectionTitle(l10n.settingsConnectionSection),
              TextField(
                controller: _nickname,
                decoration: InputDecoration(labelText: l10n.settingsDefaultNickname),
                onSubmitted: (_) => _commitText(settings),
                onTapOutside: (_) => _commitText(settings),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _profile,
                decoration: InputDecoration(
                  labelText: l10n.settingsIdentityProfile,
                  helperText: l10n.settingsIdentityProfileHelper,
                ),
                onSubmitted: (_) => _commitText(settings),
                onTapOutside: (_) => _commitText(settings),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: settings.connection.maxReconnectAttempts,
                isExpanded: true,
                decoration: InputDecoration(labelText: l10n.settingsAfterDrop),
                items: [
                  DropdownMenuItem(value: null, child: Text(l10n.settingsReconnectUnlimited)),
                  DropdownMenuItem(value: 3, child: Text(l10n.settingsReconnectAttempts(3))),
                  DropdownMenuItem(value: 10, child: Text(l10n.settingsReconnectAttempts(10))),
                  DropdownMenuItem(value: 0, child: Text(l10n.settingsReconnectNever)),
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
              _SectionTitle(l10n.settingsNotificationsSection),
              _NotificationSection(
                settings: settings.notifications,
                onChanged: (notifications) => ref
                    .read(settingsProvider.notifier)
                    .update(settings.copyWith(notifications: notifications)),
              ),

              const Divider(height: 32),
              _SectionTitle(l10n.settingsShortcutsSection),
              for (final action in ShortcutAction.values)
                ChordField(
                  label: action.label(l10n),
                  chord: settings.shortcuts[action],
                  onChanged: (chord) => ref
                      .read(settingsProvider.notifier)
                      .update(settings.copyWith(shortcuts: settings.shortcuts.withBinding(action, chord))),
                ),
              const SizedBox(height: 4),
              Text(
                l10n.settingsShortcutsHelp,
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),

              const Divider(height: 32),
              _SectionTitle(l10n.settingsInterfaceSection),
              DropdownButtonFormField<String?>(
                // `requestedLanguage`, not `language`: a hand-edited value this
                // build does not know would match no item, and the dropdown
                // asserts on that.
                initialValue: settings.ui.requestedLanguage,
                isExpanded: true,
                decoration: InputDecoration(labelText: l10n.settingsLanguageLabel),
                items: [
                  DropdownMenuItem(value: null, child: Text(l10n.settingsLanguageSystem)),
                  DropdownMenuItem(value: 'zh', child: Text(l10n.settingsLanguageZh)),
                  DropdownMenuItem(value: 'en', child: Text(l10n.settingsLanguageEn)),
                ],
                onChanged: (language) => _ui(
                  settings,
                  settings.ui.copyWith(language: language, clearLanguage: language == null),
                ),
              ),

              const Divider(height: 32),
              _SectionTitle(l10n.logLabel),
              _LogSection(directory: coreLogDirectory()),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.closeButton),
        ),
      ],
    );
  }

  /// Stores an audio change, and applies a device change to the live stream.
  ///
  /// Changing a device used to be a promise for next time: the dropdown showed
  /// the new one while the engine kept the old, and nothing on screen said
  /// which was which. Devices cannot be swapped under a running stream, so
  /// honouring the choice means reopening the engine — done here, while the
  /// choice is being made.
  void _audio(Settings settings, AudioSettings audio) {
    ref.read(settingsProvider.notifier).update(settings.copyWith(audio: audio));

    final devicesChanged =
        audio.inputDevice != settings.audio.inputDevice ||
        audio.outputDevice != settings.audio.outputDevice;
    final connected = ref.read(sessionsProvider)[widget.session]?.isConnected ?? false;
    if (!devicesChanged || !connected) return;

    // Passed explicitly: the settings write above is asynchronous, and a
    // `voice_start` that raced it would open the device that was stored last.
    ref.read(clientTransportProvider).voiceStart(
      widget.session,
      inputDevice: audio.inputDevice,
      outputDevice: audio.outputDevice,
    );
  }

  /// Stores a connection change.
  void _connection(Settings settings, ConnectionSettings connection) =>
      ref.read(settingsProvider.notifier).update(settings.copyWith(connection: connection));

  /// Stores a front-end change — currently just the language, but the whole
  /// 「界面」 section comes through here.
  void _ui(Settings settings, UiSettings ui) =>
      ref.read(settingsProvider.notifier).update(settings.copyWith(ui: ui));

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

  /// Opens the selected microphone so its level can be watched, or closes it.
  ///
  /// The devices are passed explicitly rather than left to the core to look up.
  /// The settings write above is asynchronous, and a `voice_start` that raced
  /// it would open whichever device was stored *last* — which is the one device
  /// the user just said they did not want.
  void _toggleMicTest() {
    final transport = ref.read(clientTransportProvider);
    if (_testing) {
      transport.voiceStop();
    } else {
      final audio = ref.read(settingsProvider)?.audio;
      transport.voiceStart(
        widget.session,
        inputDevice: audio?.inputDevice,
        outputDevice: audio?.outputDevice,
      );
    }
    setState(() => _testing = !_testing);
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
    final l10n = AppLocalizations.of(context);
    final status = this.status;
    final input = status?.input;

    if (status == null || !status.running) {
      return Text(
        l10n.settingsVoiceNotStarted,
        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.settingsDeviceInUse(input?.displayName ?? l10n.settingsNoMicrophone),
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        if (input?.fellBack ?? false)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.settingsMicFellBack,
              style: const TextStyle(fontSize: 12, color: AppColors.idle),
            ),
          ),
        if (!status.healthy)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.settingsDeviceLost,
              style: const TextStyle(fontSize: 12, color: AppColors.danger),
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
    final l10n = AppLocalizations.of(context);
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
              ? (transmitting ? l10n.settingsTransmitting : l10n.settingsBelowThreshold)
              : l10n.settingsLevelMeterHint,
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
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _switch(l10n.settingsNotifyPresence, settings.presence,
            (v) => onChanged(settings.copyWith(presence: v))),
        _switch(l10n.settingsNotifyPoke, settings.poke,
            (v) => onChanged(settings.copyWith(poke: v))),
        _switch(
          l10n.settingsNotifyChannelMessage,
          settings.channelMessage,
          (v) => onChanged(settings.copyWith(channelMessage: v)),
        ),
        _switch(
          l10n.settingsNotifyDirectMessage,
          settings.directMessage,
          (v) => onChanged(settings.copyWith(directMessage: v)),
        ),
        _switch(
          l10n.settingsNotifyConnection,
          settings.connection,
          (v) => onChanged(settings.copyWith(connection: v)),
        ),
        const SizedBox(height: 8),
        // Separate from the switches above because it answers a different
        // question — where the notification goes, not whether there is one.
        _switch(
          l10n.settingsNotifySystem,
          settings.system,
          (v) => onChanged(settings.copyWith(system: v)),
        ),
        Text(
          l10n.settingsNotifyNote,
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
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
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(l10n.settingsSensitivity,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
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
        Text(
          l10n.settingsSensitivityHint,
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
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
    final l10n = AppLocalizations.of(context);
    final directory = this.directory;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectableText(
          directory ?? l10n.settingsNoLogDirectory,
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
            label: Text(l10n.openLogFolder),
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
    final l10n = AppLocalizations.of(context);
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
            ? l10n.settingsDeviceMissing
            : null,
      ),
      items: [
        DropdownMenuItem(value: null, child: Text(l10n.settingsSystemDefault)),
        ...devices.map(
          (device) => DropdownMenuItem(
            value: device.id,
            child: Text(
              device.isDefault ? l10n.settingsDeviceDefaultSuffix(device.name) : device.name,
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
