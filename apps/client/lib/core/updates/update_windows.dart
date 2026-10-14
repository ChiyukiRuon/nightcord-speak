import 'package:flutter/services.dart';

const _channel = MethodChannel('nightcord/lifecycle');

/// 由 Windows 原生启动助手，避免 PowerShell 依赖 Dart 进程的控制台句柄。
Future<int> launchWindowsUpdateHelper(
  String script,
  String configuration,
) async {
  final helperPid = await _channel.invokeMethod<int>('startUpdateHelper', {
    'script': script,
    'configuration': configuration,
  });
  if (helperPid == null || helperPid <= 0) {
    throw StateError('Windows did not return an update helper PID');
  }
  return helperPid;
}
