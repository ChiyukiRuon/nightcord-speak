// The macOS menu bar, as far as this app is concerned.

import 'package:flutter/services.dart';

import '../ffi/rust_client.dart';

/// Commands the runner sends in when a menu item is chosen.
///
/// The other end is `macos/Runner/MainFlutterWindow.swift`, which wires the
/// template's Preferences... item — already bound to Command+comma, but shipped
/// with no action — to this channel. The menu bar is the runner's, not
/// Flutter's; this is the seam where it reaches Dart.
const MethodChannel _channel = MethodChannel('nightcord/shell');

/// Starts listening for menu commands.
///
/// Nothing is returned to cancel with: the handler is registered on a channel
/// that lives as long as the isolate, and the only caller is the shell, which
/// lives as long as the app.
///
/// There is no `Platform.isMacOS` guard, and no Windows or Linux counterpart.
/// Those platforms have no such menu, the channel is never spoken on, and a
/// handler that never fires costs nothing — a guard would only be a second
/// place to get the platform wrong.
void listenForAppMenu({required void Function() onOpenSettings}) {
  _channel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'openSettings':
        onOpenSettings();
      default:
        // A menu item this build does not know about. Not worth surfacing: the
        // runner can legitimately be newer than the Dart it launched.
        logToCore('debug', 'ignoring the menu command "${call.method}"');
    }
  });
}
