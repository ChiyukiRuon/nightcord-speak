// The macOS menu bar, as far as this app is concerned.

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'dart:ui' show Locale;

import '../core/platform/services.dart';

/// Commands the runner sends in when a menu item is chosen.
///
/// The other end is `macos/Runner/MainFlutterWindow.swift`, which wires the
/// template's Preferences... item — already bound to Command+comma, but shipped
/// with no action — to this channel. The menu bar is the runner's, not
/// Flutter's; this is the seam where it reaches Dart.
const MethodChannel _channel = MethodChannel('nightcord/shell');

String? _menuLanguage;

/// Native resources use the same resolved locale as the Flutter widget tree.
Future<void> updateAppMenuLocale(Locale locale) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
  final tag = locale.toLanguageTag();
  if (_menuLanguage == tag) return;
  _menuLanguage = tag;
  try {
    await _channel.invokeMethod<void>('setLanguage', tag);
  } on MissingPluginException {
    // Older runners and non-native test hosts may not implement this command.
    if (_menuLanguage == tag) _menuLanguage = null;
  } on PlatformException catch (error) {
    if (_menuLanguage == tag) _menuLanguage = null;
    logToCore('warn', 'could not localize the native menu: ${error.code}');
  }
}

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
