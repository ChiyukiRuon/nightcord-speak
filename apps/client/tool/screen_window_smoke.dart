// Run with `flutter build windows --debug -t tool/screen_window_smoke.dart`.
// Exercises real secondary-engine creation and destruction without a server.
import 'dart:async';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:window_manager/window_manager.dart';

Future<RTCPeerConnection> _peer() async {
  final pc = await createPeerConnection({'iceServers': []});
  await pc.createDataChannel('smoke', RTCDataChannelInit());
  await pc.setLocalDescription(await pc.createOffer());
  return pc;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final window = await WindowController.fromCurrentEngine();
  runApp(const MaterialApp(home: SizedBox()));
  if (window.arguments == 'screen-smoke') {
    await windowManager.ensureInitialized();
    final pc = await _peer();
    await window.setWindowMethodHandler((call) async {
      if (call.method == 'ping') return 'ready';
      if (call.method == 'close') {
        await pc.close();
        await pc.dispose();
        // Reply first so the caller knows cleanup completed before destruction.
        Timer(const Duration(milliseconds: 50), () => windowManager.close());
      }
      return null;
    });
    return;
  }
  final output = File('${Directory.current.path}/run/screen-window-smoke.log');
  await output.writeAsString('start\n');
  try {
    final mainPeer = await _peer();
    for (var cycle = 1; cycle <= 3; cycle++) {
      final child = await WindowController.create(
        const WindowConfiguration(arguments: 'screen-smoke'),
      );
      var ready = false;
      for (var attempt = 0; attempt < 40 && !ready; attempt++) {
        try {
          ready =
              await child
                  .invokeMethod<String>('ping')
                  .timeout(const Duration(milliseconds: 250)) ==
              'ready';
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      if (!ready) throw StateError('child $cycle did not initialize');
      await child
          .invokeMethod<void>('close')
          .timeout(const Duration(seconds: 2));
      var gone = false;
      for (var attempt = 0; attempt < 40 && !gone; attempt++) {
        gone = !(await WindowController.getAll()).any(
          (w) => w.windowId == child.windowId,
        );
        if (!gone) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      if (!gone) throw StateError('child $cycle did not close');
      // The main engine remains usable after another plugin instance is freed.
      await mainPeer.createOffer();
      final next = await _peer();
      await next.close();
      await next.dispose();
      await output.writeAsString(
        'cycle $cycle passed\n',
        mode: FileMode.append,
      );
    }
    await mainPeer.close();
    await mainPeer.dispose();
    await output.writeAsString('PASS\n', mode: FileMode.append);
    exit(0);
  } catch (error, stack) {
    await output.writeAsString('FAIL $error\n$stack\n', mode: FileMode.append);
    exit(1);
  }
}
