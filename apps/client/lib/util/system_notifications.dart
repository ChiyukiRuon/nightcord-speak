// Desktop notifications, behind one file.
//
// The plugin appears here and nowhere else, so swapping it — or adding the
// mobile one when there is something to build for — touches this file alone.
//
// The app has exactly one target today (`windows/` is the only platform
// directory), so this is deliberately the desktop-only package: adding
// `flutter_local_notifications` now would be writing code for platforms that
// cannot be built, let alone verified.

import 'dart:io';

import 'package:local_notifier/local_notifier.dart';

import '../ffi/rust_client.dart';

/// Whether the plugin was set up successfully.
///
/// Starts optimistic so a notification arriving before `initSystemNotifications`
/// finishes is not silently dropped; the setup reports failure itself.
bool _ready = false;

/// Whether notifications have been set up.
bool _attempted = false;

/// Prepares desktop notifications.
///
/// Safe to call more than once. Failure is written to the core's log rather
/// than thrown: a pop-up that does not appear is worth knowing about, but it is
/// not worth taking the app down for — and on Windows it is a real possibility,
/// since an unpackaged app needs a Start Menu shortcut carrying an
/// AppUserModelID for toasts to be shown at all.
Future<void> initSystemNotifications() async {
  if (_attempted) return;
  _attempted = true;

  // Nothing to set up on a platform with no implementation, and the plugin's
  // own `setup` would throw rather than do nothing.
  if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
    logToCore('info', 'desktop notifications are not available on this platform');
    return;
  }

  try {
    await localNotifier.setup(appName: 'Nightcord Speak');
    _ready = true;
  } catch (error) {
    logToCore('warn', 'could not start desktop notifications: $error');
  }
}

/// Shows a desktop notification, or says why it could not.
///
/// Never throws: this is called from the event path, where a failure to show a
/// pop-up must not take anything else with it.
Future<void> showSystemNotification({required String title, required String body}) async {
  if (!_ready) {
    // Once, per call, at debug level: a user who turned notifications on and
    // sees nothing needs the log to say so, without every event writing a line.
    logToCore('debug', 'desktop notifications are unavailable; dropped "$title"');
    return;
  }

  try {
    await LocalNotification(title: title, body: body).show();
  } catch (error) {
    logToCore('warn', 'could not show a desktop notification: $error');
  }
}
