// Desktop notifications, behind one file.
//
// Two implementations, and this is the only file that knows which is which:
//
//   Windows   `local_notifier`
//   macOS     the runner's `nightcord/notifications` channel
//             (`macos/Runner/MainFlutterWindow.swift`)
//
// Full coverage of either appears here and nowhere else, so swapping one
// touches this file alone.
//
// Why macOS is not the plugin: `local_notifier` 0.1.6 builds its macOS side on
// `NSUserNotificationCenter`, deprecated since macOS 11 and inert on current
// ones -- and it reports success regardless. Its Dart `setup` does not call into
// native code at all on macOS, its `deliver` is fire-and-forget, and it answers
// `true` unconditionally, so a client whose notifications never worked is
// indistinguishable from a working one and nothing reaches the log.
//
// This was established twice, in the only order that settles it: first by
// reading the plugin, and then -- after the replacement was reverted on the
// strength of a test that turned out to have been run against the replacement
// itself -- by watching notifications stop. Do not undo it again without a test
// on a build that does not contain it.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:local_notifier/local_notifier.dart';

import '../ffi/rust_client.dart';

/// The runner's notification channel. See `macos/Runner/MainFlutterWindow.swift`.
const MethodChannel _channel = MethodChannel('nightcord/notifications');

/// Whether this platform goes through the runner rather than the plugin.
///
/// `Platform` rather than `defaultTargetPlatform`: the question is which native
/// implementation exists, not how anything should be laid out.
bool get _viaRunner => Platform.isMacOS;

/// Whether notifications were set up successfully.
///
/// Starts optimistic so a notification arriving before `initSystemNotifications`
/// finishes is not silently dropped; the setup reports failure itself.
bool _ready = false;

/// Whether notifications have been set up.
bool _attempted = false;

/// Whether a refusal has already been written to the log on this run.
///
/// See [showSystemNotification]: the first refusal is worth a line, the two
/// hundredth is not.
bool _reportedRefusal = false;

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

  if (_viaRunner) {
    // Not an assumption: ask the runner what macOS thinks. `_ready = true`
    // here would be the same unconditional "yes" that made `local_notifier`
    // impossible to diagnose on macOS — a runner too old to serve the channel
    // would look exactly like one that works.
    try {
      final status = await _channel.invokeMethod<String>('status');
      if (status == null) {
        logToCore('warn', 'the runner did not say whether notifications are allowed');
        return;
      }
      _ready = true;
      // Said out loud because it is the one state with an answer the user has
      // to act on: once refused, macOS never asks again.
      if (status == 'denied') {
        logToCore(
          'warn',
          'macOS notifications are denied for this app; they stay off until '
          'they are switched on in System Settings > Notifications',
        );
      } else {
        logToCore('info', 'desktop notifications are $status');
      }
    } catch (error) {
      logToCore('warn', 'the runner does not serve desktop notifications: $error');
    }
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
    if (_viaRunner) {
      // The answer is *what happened*, not whether the call was made. A
      // refusal used to be recorded at debug level, which meant the log said
      // nothing at all about a notification the user asked for and did not
      // get — the same silent-failure shape this channel replaced.
      final status = await _channel.invokeMethod<String>('show', {
        'title': title,
        'body': body,
      });
      if (status == 'shown') {
        // Anything that works later clears the memory, so a refusal after it
        // is reported again rather than swallowed.
        _reportedRefusal = false;
        // Recorded, because a desktop notification is user-visible and this
        // codebase's rule is that what the user can see, the log can account
        // for. It is also the only way to tell "no notification was asked for"
        // from "one was asked for and did not appear" — the two look identical
        // from outside, and only one of them is a bug here.
        //
        // The title is deliberately not included: for a private message it is
        // the sender and for a channel message it can be the message itself,
        // and the log does not carry user content.
        logToCore('info', 'showed a desktop notification');
        return;
      }

      // Once per run: a refused notification is refused for every message that
      // follows, and the reason is a switch the user has to find, not
      // something each event needs to repeat.
      if (!_reportedRefusal) {
        _reportedRefusal = true;
        logToCore(
          'warn',
          status == 'denied'
              ? 'macOS refused to show "$title": notifications are off for this '
                    'app in System Settings > Notifications'
              : 'macOS answered "$status" instead of showing "$title"',
        );
      }
      return;
    }

    await LocalNotification(title: title, body: body).show();
    // See the macOS branch: the same record for the same reason. The plugin
    // cannot say whether Windows actually drew it, so this records the request
    // rather than the result.
    logToCore('info', 'asked for a desktop notification');
  } catch (error) {
    logToCore('warn', 'could not show a desktop notification: $error');
  }
}
