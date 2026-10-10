// Devices, how the microphone opens, and how loud everything is.
//
// The one section that talks to hardware, and the only one whose controls stop
// meaning anything without a session. Two of its readings are polled rather
// than pushed — the meter and the device list — and both live here in the
// section's own state, so they run only while this section is the one on
// screen. They used to run for as long as the settings surface was open, which
// on a page you might sit in for minutes meant a synchronous round trip to the
// audio host every five seconds for no one's benefit.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/labels.dart';
import '../../../models/domain.dart';
import '../../../models/settings.dart';
import '../../../models/voice_status.dart';
import '../../../providers/providers.dart';
import '../../../util/gain.dart';

/// Everything about audio.
class AudioSection extends ConsumerStatefulWidget {
  /// Edits `settings`; the microphone test and the device swap act on
  /// `session`, when there is one.
  const AudioSection({
    required this.settings,
    required this.session,
    super.key,
  });

  final Settings settings;
  final int? session;

  @override
  ConsumerState<AudioSection> createState() => _AudioSectionState();
}

class _AudioSectionState extends ConsumerState<AudioSection> {
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

  /// The volume slider's position while a drag is in progress.
  double? _draggingVolume;

  /// The gain slider's position while a drag is in progress, in decibels —
  /// kept out of the stored settings for the same reason as the others.
  double? _draggingGain;

  @override
  void initState() {
    super.initState();
    // Enumeration touches real hardware on the core's thread, so the lists
    // arrive through `audioDevicesProvider` rather than as a return value.
    // Asking again on open also picks up a headset plugged in since last time.
    final client = ref.read(clientTransportProvider);
    client.requestAudioDevices('input');
    client.requestAudioDevices('output');

    // This section being on screen is what makes the polls worth paying for —
    // see the note at the top of the file.
    _statusTicker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) ref.read(voiceStatusProvider.notifier).refresh();
    });
    _devicesTicker = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      client.requestAudioDevices('input');
      client.requestAudioDevices('output');
    });
  }

  @override
  void dispose() {
    _statusTicker?.cancel();
    _devicesTicker?.cancel();
    super.dispose();
  }

  /// The session the audio controls act on, or null when there is nothing to
  /// act on: no session at all, or one that is not connected.
  ///
  /// One place decides this, so the call sites cannot disagree about whether
  /// voice can be started.
  int? get _connectedSession {
    final session = widget.session;
    if (session == null) return null;
    final view = ref.read(sessionsProvider)[session];
    return (view?.isConnected ?? false) ? session : null;
  }

  /// Stores an audio change, and applies a device change to the live stream.
  ///
  /// Changing a device used to be a promise for next time: the dropdown showed
  /// the new one while the engine kept the old, and nothing on screen said
  /// which was which. Devices cannot be swapped under a running stream, so
  /// honouring the choice means reopening the engine — done here, while the
  /// choice is being made.
  void _audio(AudioSettings audio) {
    final settings = widget.settings;
    ref.read(settingsProvider.notifier).update(settings.copyWith(audio: audio));

    final devicesChanged =
        audio.inputDevice != settings.audio.inputDevice ||
        audio.outputDevice != settings.audio.outputDevice;
    final session = _connectedSession;
    if (!devicesChanged || session == null) return;

    // Passed explicitly: the settings write above is asynchronous, and a
    // `voice_start` that raced it would open the device that was stored last.
    ref
        .read(clientTransportProvider)
        .voiceStart(
          session,
          inputDevice: audio.inputDevice,
          outputDevice: audio.outputDevice,
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
      final session = _connectedSession;
      if (session == null) return;
      final audio = widget.settings.audio;
      transport.voiceStart(
        session,
        inputDevice: audio.inputDevice,
        outputDevice: audio.outputDevice,
      );
    }
    setState(() => _testing = !_testing);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    final settings = widget.settings;
    final devices = ref.watch(audioDevicesProvider);
    final connected = _connectedSession != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DeviceDropdown(
          label: l10n.settingsMicrophoneLabel,
          value: settings.audio.inputDevice,
          devices: devices['input'] ?? const <AudioDevice>[],
          onChanged: (id) => _audio(
            settings.audio.copyWith(
              inputDevice: id,
              clearInputDevice: id == null,
            ),
          ),
        ),
        SizedBox(height: tokens.space3),
        _DeviceDropdown(
          label: l10n.settingsSpeakerLabel,
          value: settings.audio.outputDevice,
          devices: devices['output'] ?? const <AudioDevice>[],
          onChanged: (id) => _audio(
            settings.audio.copyWith(
              outputDevice: id,
              clearOutputDevice: id == null,
            ),
          ),
        ),
        SizedBox(height: tokens.space3),
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
            _audio(settings.audio.copyWith(mode: mode));
          },
        ),
        SizedBox(height: tokens.space4),
        _DeviceInUse(status: ref.watch(voiceStatusProvider)),
        SizedBox(height: tokens.space4),
        DropdownButtonFormField<VadAlgorithm>(
          initialValue: settings.audio.activation.algorithm,
          isExpanded: true,
          decoration: InputDecoration(labelText: l10n.settingsVad),
          items: [
            DropdownMenuItem(
              value: VadAlgorithm.smart,
              child: Text(l10n.settingsVadSmart),
            ),
            DropdownMenuItem(
              value: VadAlgorithm.level,
              child: Text(l10n.settingsSensitivity),
            ),
          ],
          onChanged: settings.audio.mode == VoiceActivationMode.voiceActivation
              ? (algorithm) {
                  if (algorithm == null) return;
                  setState(() => _dragging = null);
                  _audio(
                    settings.audio.copyWith(
                      activation: settings.audio.activation.copyWith(
                        algorithm: algorithm,
                      ),
                    ),
                  );
                }
              : null,
        ),
        SizedBox(height: tokens.space2),
        if (settings.audio.activation.algorithm == VadAlgorithm.smart)
          Text(
            l10n.settingsVadSmartHint,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: tokens.textTertiary),
          ),
        if (settings.audio.activation.algorithm == VadAlgorithm.level)
          _SensitivitySlider(
            value: _dragging ?? settings.audio.activation.sensitivity,
            enabled: settings.audio.mode == VoiceActivationMode.voiceActivation,
            onChanged: (value) => setState(() => _dragging = value),
            onChangeEnd: (value) {
              setState(() => _dragging = null);
              _audio(
                settings.audio.copyWith(
                  activation: settings.audio.activation.copyWith(
                    sensitivity: value,
                  ),
                ),
              );
            },
          ),
        SizedBox(height: tokens.space2),
        _LevelMeter(
          status: ref.watch(voiceStatusProvider),
          threshold: settings.audio.activation.algorithm == VadAlgorithm.level
              ? settings.audio.activation.sensitivity
              : null,
        ),
        SizedBox(height: tokens.space3),
        // Above the playback volume because it is about us rather than
        // about the room: what everyone else hears, then what we hear.
        _GainSlider(
          value: _draggingGain ?? settings.audio.inputGainDb,
          onChanged: (value) => setState(() => _draggingGain = value),
          onChangeEnd: (value) {
            setState(() => _draggingGain = null);
            _audio(settings.audio.copyWith(inputGainDb: value));
          },
        ),
        SizedBox(height: tokens.space1),
        Text(
          l10n.settingsMicBoostHint,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: tokens.textTertiary),
        ),
        SizedBox(height: tokens.space3),
        _VolumeSlider(
          value: _draggingVolume ?? settings.audio.outputVolume,
          onChanged: (value) => setState(() => _draggingVolume = value),
          onChangeEnd: (value) {
            setState(() => _draggingVolume = null);
            _audio(settings.audio.copyWith(outputVolume: value));
          },
        ),
        SizedBox(height: tokens.space3),
        // Said out loud because a device cannot be swapped under a running
        // stream: the core would have to tear it down and reopen it, which
        // is worse than waiting when someone is mid-sentence.
        // The codec profile is not in this boat — it is retuned in place —
        // so the note names only the devices.
        Text(
          connected ? l10n.settingsDeviceChangeNote : l10n.settingsConnectFirst,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: tokens.textTertiary),
        ),
        SizedBox(height: tokens.space3),
        Row(
          children: [
            FilledButton(
              onPressed: connected ? _toggleMicTest : null,
              child: Text(
                _testing ? l10n.settingsStopTest : l10n.settingsTestMicrophone,
              ),
            ),
            SizedBox(width: tokens.space3),
            // Always available, engine or not: with no engine the core
            // opens the output device on its own for the length of the
            // tone. Gating this on the engine made the speaker check
            // depend on a microphone being open first — nothing a person
            // could guess from two buttons sitting side by side.
            OutlinedButton.icon(
              onPressed: () =>
                  ref.read(voiceStatusProvider.notifier).testOutput(),
              icon: const Icon(Icons.volume_up_outlined),
              label: Text(l10n.settingsTestSpeaker),
            ),
          ],
        ),
      ],
    );
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
    final tokens = DesignTokens.of(context);
    final text = Theme.of(context).textTheme;
    final status = this.status;
    final input = status?.input;

    if (status == null || !status.running) {
      return Text(
        l10n.settingsVoiceNotStarted,
        style: text.bodySmall?.copyWith(color: tokens.textTertiary),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.settingsDeviceInUse(
            input?.displayName ?? l10n.settingsNoMicrophone,
          ),
          style: text.bodySmall?.copyWith(color: tokens.textSecondary),
        ),
        if (input?.fellBack ?? false)
          Padding(
            padding: EdgeInsets.only(top: tokens.space1),
            child: Text(
              l10n.settingsMicFellBack,
              // §8's warning: the device is not the one that was asked for,
              // but the app is still working.
              style: text.bodySmall?.copyWith(color: tokens.warning),
            ),
          ),
        if (!status.healthy)
          Padding(
            padding: EdgeInsets.only(top: tokens.space1),
            child: Text(
              l10n.settingsDeviceLost,
              style: text.bodySmall?.copyWith(color: tokens.error),
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
  final double? threshold;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
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
                // A groove has to be *lighter* than the surface it is cut
                // into: §2.2 puts the content at the page step, and `surface1`
                // is the one above it.
                color: tokens.surface1,
                borderRadius: AppRadius.xsAll,
              ),
            ),
            // Clamped: a level can exceed the bar, and a FractionallySizedBox
            // over 1.0 throws rather than clipping.
            FractionallySizedBox(
              widthFactor: level.clamp(0.0, 1.0),
              child: Container(
                height: 10,
                decoration: BoxDecoration(
                  // The same green as a talking name, because it means the same
                  // thing: audio is on its way out.
                  color: transmitting ? tokens.online : tokens.textTertiary,
                  borderRadius: AppRadius.xsAll,
                ),
              ),
            ),
            if (threshold != null)
              FractionallySizedBox(
                widthFactor: threshold!.clamp(0.0, 1.0),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Container(width: 2, height: 16, color: tokens.primary),
                ),
              ),
          ],
        ),
        SizedBox(height: tokens.space1),
        Text(
          running
              ? (transmitting
                    ? l10n.settingsTransmitting
                    : (threshold == null
                          ? l10n.settingsVadWaiting
                          : l10n.settingsBelowThreshold))
              : l10n.settingsLevelMeterHint,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: tokens.textTertiary),
        ),
      ],
    );
  }
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
    final tokens = DesignTokens.of(context);
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              l10n.settingsSensitivity,
              style: text.bodySmall?.copyWith(color: tokens.textSecondary),
            ),
            const Spacer(),
            Text(
              '${(value * 100).round()}%',
              style: text.bodySmall?.copyWith(color: tokens.textTertiary),
            ),
          ],
        ),
        // Track, thumb and overlay come from the theme's `sliderTheme` (§5
        // lists sliders as a primary-coloured control).
        Slider(
          value: value.clamp(0.0, 1.0),
          // Only shown while voice activation is what opens the microphone.
          onChanged: enabled ? onChanged : null,
          onChangeEnd: enabled ? onChangeEnd : null,
        ),
        Text(
          l10n.settingsSensitivityHint,
          style: text.bodySmall?.copyWith(color: tokens.textTertiary),
        ),
      ],
    );
  }
}

/// How loud everyone else hears us.
///
/// Its own slider rather than a second reading of the one below it: the two are
/// different controls on different ends of the pipeline, and the microphone
/// gain is the one a voice bar flyout also draws.
class _GainSlider extends StatelessWidget {
  const _GainSlider({
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  /// The stored gain, in decibels.
  final double value;

  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              l10n.settingsMicGain,
              style: text.bodySmall?.copyWith(color: tokens.textSecondary),
            ),
            const Spacer(),
            Text(
              formatGainDb(value, silentLabel: l10n.settingsMicGainSilent),
              style: text.bodySmall?.copyWith(color: tokens.textTertiary),
            ),
          ],
        ),
        Slider(
          value: gainDbToSlider(value).clamp(0.0, 1.0),
          onChanged: (position) => onChanged(gainSliderToDb(position)),
          onChangeEnd: (position) => onChangeEnd(gainSliderToDb(position)),
        ),
        Text(
          l10n.settingsMicGainHint,
          style: text.bodySmall?.copyWith(color: tokens.textTertiary),
        ),
      ],
    );
  }
}

/// The master playback gain.
class _VolumeSlider extends StatelessWidget {
  const _VolumeSlider({
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              l10n.settingsVolume,
              style: text.bodySmall?.copyWith(color: tokens.textSecondary),
            ),
            const Spacer(),
            Text(
              '${(value * 100).round()}%',
              style: text.bodySmall?.copyWith(color: tokens.textTertiary),
            ),
          ],
        ),
        Slider(
          value: value.clamp(0.0, 1.0),
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
        Text(
          l10n.settingsVolumeHint,
          style: text.bodySmall?.copyWith(color: tokens.textTertiary),
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
    // 「系统默认」 for the rest of the page's life — the items arriving would
    // not correct the selection. A key rebuilds it when one does.
    //
    // The key is the *contents*, not the list object. `ObjectKey(devices)`
    // compared by identity, and this section re-enumerates the devices every
    // five seconds to notice a headset being plugged in — so a fresh, identical
    // list arrived on a timer and swapped the dropdown out from under whoever
    // had it open. Keying on what is actually in the list means an unchanged
    // enumeration changes nothing.
    final signature = devices.map((d) => d.id).join('\u0000');
    return DropdownButtonFormField<String>(
      key: ValueKey('$signature|$known'),
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
              device.isDefault
                  ? l10n.settingsDeviceDefaultSuffix(device.name)
                  : device.name,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }
}
