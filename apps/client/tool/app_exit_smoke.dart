// Build on macOS with `flutter build macos --release -t tool/app_exit_smoke.dart`.
// Exercises the native main-window close path with a pending UDP handshake and
// a live (or previously closed) secondary engine. No real server is contacted.
import 'dart:async';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'package:nightcord_client/core/platform/services.dart';
import 'package:nightcord_client/core/transport/transport_factory.dart';
import 'package:nightcord_client/models/connect_request.dart';
import 'package:nightcord_client/util/app_exit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final window = await WindowController.fromCurrentEngine();
  if (window.arguments == 'exit-smoke-child') {
    runApp(const MaterialApp(home: SizedBox()));
    await windowManager.ensureInitialized();
    await window.setWindowMethodHandler((call) async {
      if (call.method == 'ping') return 'ready';
      if (call.method == 'close') {
        Timer(const Duration(milliseconds: 50), () => windowManager.close());
      }
      return null;
    });
    return;
  }

  final mode =
      Platform.environment['NIGHTCORD_EXIT_SMOKE_MODE'] ?? 'live-child';
  final log = File('${Directory.current.path}/run/app-exit-$mode.log');
  log.parent.createSync(recursive: true);
  log.writeAsStringSync('start pid=$pid\n');
  final client = createTransport();
  final crash = readCrashStatus(client);
  final marker = File('${crash.directory}/last-run.$pid');
  if (!crash.available || !marker.existsSync()) {
    throw StateError('core did not create its run marker');
  }
  await registerMainWindowExit(() {
    client.dispose();
    if (marker.existsSync()) {
      log.writeAsStringSync(
        'FAIL: crash marker remains\n',
        mode: FileMode.append,
      );
      throw StateError('normal close left an abnormal exit marker');
    }
    log.writeAsStringSync(
      'PASS: main core cleaned up\n',
      mode: FileMode.append,
    );
  });
  runApp(const MaterialApp(home: SizedBox()));
  try {
    await windowManager.ensureInitialized();
    final child = await WindowController.create(
      const WindowConfiguration(arguments: 'exit-smoke-child'),
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
    if (!ready) throw StateError('child did not start');
    if (mode == 'closed-child') {
      await child.invokeMethod<void>('close');
      var gone = false;
      for (var attempt = 0; attempt < 40 && !gone; attempt++) {
        gone = !(await WindowController.getAll()).any(
          (window) => window.windowId == child.windowId,
        );
        if (!gone) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      if (!gone) throw StateError('child did not close');
    }
    final sink = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final received = Completer<void>();
    sink.listen((event) {
      if (event == RawSocketEvent.read &&
          sink.receive() != null &&
          !received.isCompleted) {
        received.complete();
      }
    });
    client.connect(
      ConnectRequest(
        address: '127.0.0.1:${sink.port}',
        nickname: 'exit-smoke',
        profile: 'exit-smoke',
      ),
    );
    await received.future.timeout(const Duration(seconds: 5));
    log.writeAsStringSync(
      'handshake pending; close main\n',
      mode: FileMode.append,
    );
    await windowManager.close();
  } catch (error, stack) {
    log.writeAsStringSync('FAIL: $error\n$stack\n', mode: FileMode.append);
    exit(1);
  }
}
