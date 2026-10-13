export '../../util/system_notifications_web.dart'
    show requestNotificationPermission;

import 'package:flutter/foundation.dart';

import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../../models/crash.dart';
import '../transport/client_transport.dart';
import 'picked_screen_source.dart';
import 'device_info.dart';

final _applicationContextMenuRegions =
    <Object, bool Function(double, double)>{};
({double x, double y, bool handled})? _secondaryContextMenuPress;

/// Remember the hit before Flutter can cover it with an application popup.
Future<void> initializePlatformInteractions() async {
  web.window.addEventListener(
    'pointerdown',
    ((web.MouseEvent event) {
      _secondaryContextMenuPress = event.button == 2
          ? (
              x: event.clientX.toDouble(),
              y: event.clientY.toDouble(),
              handled: _applicationContextMenuRegions.values.any(
                (contains) => contains(
                  event.clientX.toDouble(),
                  event.clientY.toDouble(),
                ),
              ),
            )
          : null;
    }).toJS,
    web.AddEventListenerOptions(capture: true),
  );
  web.window.addEventListener(
    'contextmenu',
    ((web.MouseEvent event) {
      final press = _secondaryContextMenuPress;
      // Some browsers deliver contextmenu on press, others on release. Keep
      // the decision until the next press so either order uses the same hit.
      if (event.button == 2 &&
          press != null &&
          press.handled &&
          (press.x - event.clientX).abs() <= 1 &&
          (press.y - event.clientY).abs() <= 1) {
        event.preventDefault();
      }
    }).toJS,
    web.AddEventListenerOptions(capture: true),
  );
}

void registerApplicationContextMenuRegion(
  Object key,
  bool Function(double, double) contains,
) => _applicationContextMenuRegions[key] = contains;
void unregisterApplicationContextMenuRegion(Object key) =>
    _applicationContextMenuRegions.remove(key);

// The browser runs its own picker out of getDisplayMedia; there is no system
// one to ask for — and its audio follows the page's own output routing.
Future<bool> screenPickerAvailable() async => false;
Future<PickedScreenSource?> pickScreenSource() async => null;
Future<void> setScreenAudioOutput(String? name) async {}

String? environmentValue(String name) => null;
const bool supportsLogSettings = false;

DeviceClass platformDeviceClass() => browserDeviceClass(
  userAgent: web.window.navigator.userAgent,
  maxTouchPoints: web.window.navigator.maxTouchPoints,
);
String? coreLogDirectory() => null;
void logToCore(String level, String message) =>
    debugPrint('[nightcord:$level] $message');
CrashStatus readCrashStatus(ClientTransport client) => CrashStatus.none;
({String? path, String? error}) buildCrashReport(ClientTransport client) =>
    (path: null, error: 'Reports are on the gateway host');

bool isMissingNativeLibrary(Object error) => false;
