// Points the screen-share audio at the same device the voice engine uses.
//
// The share's sound does not travel the voice pipeline: playback goes through
// WebRTC's own device handling, which knows only the system default until it
// is told otherwise. The voice engine honours the settings' speaker choice —
// so without this, one app had two answers to "where does sound come out",
// and the share was the odd one (2026-10-08).
//
// How each platform is told differs: on macOS the note goes to the app's own
// audio device (the Rust voice engine's spelling is CoreAudio's, which that
// device can resolve); on Windows the plugin has a device list of its own,
// whose ids are the raw WASAPI guids the settings' `wasapi:` ids wrap.
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../models/settings.dart';
import '../platform/services.dart';

/// True once the plugin's output list has been written to the log. The list
/// is what "back to default" is matched against, so seeing it once makes a
/// wrong pick explainable instead of a mystery.
bool _loggedPluginOutputs = false;

final _outputRouter = ScreenAudioOutputRouter(_applyScreenAudioOutput);

Future<void> applyScreenAudioOutput(Settings? settings) async {
  try {
    await _outputRouter.apply(settings);
  } catch (error) {
    logToCore('warn', 'screen: could not set the share audio output: $error');
  }
}

@visibleForTesting
class ScreenAudioOutputRouter {
  ScreenAudioOutputRouter(this._apply);
  final Future<void> Function(Settings?) _apply;
  Future<void> _queue = Future<void>.value();
  String? _appliedOutput;
  bool _hasAppliedOutput = false;

  Future<void> apply(Settings? settings) {
    final device = settings?.audio.outputDevice;
    // Settings edits and their replies can overlap. Never rebuild the native
    // output twice concurrently, or restart it for an unrelated settings edit.
    _queue = _queue.then((_) async {
      if (_hasAppliedOutput && _appliedOutput == device) return;
      try {
        await _apply(settings);
      } catch (_) {
        // A failed native restart may also have invalidated the old route.
        _hasAppliedOutput = false;
        rethrow;
      }
      _appliedOutput = device;
      _hasAppliedOutput = true;
    });
    final pending = _queue;
    _queue = pending.catchError((Object _) {});
    return pending;
  }
}

Future<void> _applyScreenAudioOutput(Settings? settings) async {
  if (kIsWeb) return;
  final device = settings?.audio.outputDevice;

  if (defaultTargetPlatform == TargetPlatform.macOS) {
    const prefix = 'coreaudio:';
    final name = device != null && device.startsWith(prefix)
        ? device.substring(prefix.length)
        : device;
    await setScreenAudioOutput(name);
    return;
  }

  if (defaultTargetPlatform != TargetPlatform.windows) return;
  final available = [
    for (final device in await navigator.mediaDevices.enumerateDevices())
      if (device.kind == 'audiooutput') device.deviceId,
  ];
  if (!_loggedPluginOutputs) {
    _loggedPluginOutputs = true;
    logToCore('info', 'screen: media plugin outputs: $available');
  }
  final id = pluginOutputDeviceId(device, available);
  if (id == null) {
    throw StateError('Screen audio output is unavailable: $device');
  }
  await Helper.selectAudioOutput(id);
  logToCore('info', 'screen: share audio output -> $id');
}

/// The plugin's name for the device the settings named, or null when its list
/// does not contain it.
///
/// The settings speak the voice engine's spelling — `wasapi:{guid}` — while
/// the plugin's list speaks the bare `{guid}` (its ids are the platform's own
/// device guids). A null or empty setting becomes the `default` sentinel,
/// resolved by the native plugin rather than by device enumeration order.
///
/// Pure on purpose: the mapping is the part that can be wrong without anyone
/// hearing it (a miss just means "stayed on the system default"), so it is
/// tested without a plugin behind it.
@visibleForTesting
String? pluginOutputDeviceId(String? settingsId, List<String> available) {
  if (settingsId == null || settingsId.isEmpty) {
    // Enumeration order cannot identify the default. The Windows plugin
    // resolves this sentinel through WASAPI at the time of selection.
    return 'default';
  }
  const prefix = 'wasapi:';
  final guid = settingsId.startsWith(prefix)
      ? settingsId.substring(prefix.length)
      : settingsId;
  if (available.contains(guid)) return guid;
  for (final id in available) {
    if (id.toLowerCase() == guid.toLowerCase()) return id;
  }
  return null;
}
