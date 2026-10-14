import 'package:flutter/services.dart';

const _channel = MethodChannel('nightcord/lifecycle');

/// 使用 macOS 原生启动接口获取真实助手 PID，而不是仅检查 open 的返回码。
Future<int> launchMacOSUpdateHelper(String configuration) async {
  final helperPid = await _channel.invokeMethod<int>('startUpdateHelper', {
    'configuration': configuration,
  });
  if (helperPid == null || helperPid <= 0) {
    throw StateError('macOS did not return an update helper PID');
  }
  return helperPid;
}
