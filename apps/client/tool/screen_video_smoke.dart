// Exercises the production detached-window signaling and real local video.
// Defaults to local video. NIGHTCORD_SCREEN_SMOKE_REAL=1 tests a TS6 publisher.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nightcord_client/core/screen/screen_controller.dart';
import 'package:nightcord_client/core/screen/screen_share_backend.dart';
import 'package:nightcord_client/core/screen/webrtc_screen_backend.dart';
import 'package:nightcord_client/core/transport/client_transport.dart';
import 'package:nightcord_client/features/screen/detached/detached_screen.dart';
import 'package:nightcord_client/features/screen/detached/screen_window.dart';
import 'package:nightcord_client/ffi/rust_client.dart';
import 'package:nightcord_client/models/events.dart';
import 'package:nightcord_client/models/screen_options.dart';
import 'package:nightcord_client/models/connect_request.dart';
import 'package:nightcord_client/models/domain.dart';

const _options = ScreenOptions(
  source: ScreenSourceKind.screen,
  height: 720,
  fps: 10,
  videoBitrateKbps: 1500,
  audio: false,
  audioBitrateKbps: 128,
  access: ScreenAccess.public,
  viewerLimit: 4,
  mode: ScreenMode.p2p,
  detail: false,
);

class _Publisher implements ClientTransport {
  _Publisher(this.backend, this.media, this.output);
  final WebRtcScreenBackend backend;
  final ScreenMedia media;
  final File output;
  final incoming = StreamController<FfiEvent>.broadcast(sync: true);
  ScreenPeer? peer;
  Future<void> work = Future<void>.value();
  @override
  Stream<FfiEvent> get events => incoming.stream;
  void emit(String type, [Map<String, dynamic> more = const {}]) {
    incoming.add(
      DomainEvent(
        session: 1,
        event: ScreenEvent({
          'type': type,
          'stream_id': 'smoke',
          'client_id': 2,
          ...more,
        }),
      ),
    );
  }

  @override
  void screen(int session, Map<String, dynamic> command) {
    output.writeAsStringSync(
      'command ${command['action']}\n',
      mode: FileMode.append,
    );
    work = work
        .then((_) async {
          switch (command['action']) {
            case 'discover':
              emit('available', {'name': 'smoke'});
            case 'join':
              await peer?.close();
              peer = await backend.peer(
                options: _options,
                onCandidate: (c) => emit('signal', {'signal': c}),
                onMedia: (_) {},
                onFailed: () => throw StateError('publisher failed'),
              );
              final offer = await peer!.offer(media);
              emit('join_answered', {'accepted': true, 'sdp': offer});
            case 'signal':
              final signal = (command['signal'] as Map).cast<String, dynamic>();
              if (signal['type'] == 'answer') {
                await peer?.acceptAnswer(signal['sdp'] as String);
              } else {
                await peer?.candidate(signal);
              }
            case 'leave':
              await peer?.close();
              peer = null;
          }
        })
        .catchError((Object error, StackTrace stack) {
          output.writeAsStringSync(
            'publisher error $error\n$stack\n',
            mode: FileMode.append,
          );
        });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final args = await detachedScreenArgs();
  if (args != null) {
    await runScreenWindow(args);
    return;
  }
  final core = RustClient.start();
  final output = File('${Directory.current.path}/run/screen-video-smoke.log');
  output.writeAsStringSync('start\n');
  try {
    if (Platform.environment['NIGHTCORD_SCREEN_SMOKE_REAL'] == '1') {
      await _realServer(core, output);
      core.dispose();
      output.writeAsStringSync('PASS\n', mode: FileMode.append);
      exit(0);
    }
    final backend = WebRtcScreenBackend();
    final source = (await backend.sources()).firstWhere(
      (s) => s.kind == ScreenSourceKind.screen,
    );
    final capture = await backend.capture(source, _options);
    final host = _Publisher(backend, capture, output);
    final controller = ScreenController(
      backend: backend,
      send: (c) => host.screen(1, c),
    );
    controller.contextChanged(
      online: true,
      client: 1,
      channel: 1,
      clients: {1, 2},
    );
    final subscription = host.events.listen((event) {
      if (event is DomainEvent) {
        unawaited(controller.receive(event.event as ScreenEvent));
      }
    });
    runApp(
      MaterialApp(
        home: ListenableBuilder(
          listenable: controller,
          builder: (_, _) => controller.remote?.view() ?? const SizedBox(),
        ),
      ),
    );
    await controller.watch(2);
    for (var i = 0; controller.remote == null && i < 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (controller.remote == null) {
      throw StateError('main viewer did not receive media');
    }
    await Future<void>.delayed(const Duration(seconds: 1));
    output.writeAsStringSync('main video received\n', mode: FileMode.append);
    for (var cycle = 1; cycle <= 2; cycle++) {
      if (cycle > 1) {
        await controller.watch(2);
        for (var i = 0; controller.remote == null && i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      final child = await controller.transferWatch(
        (client) => openDetachedScreen(
          transport: host,
          session: 1,
          args: const ScreenWindowArgs(
            session: 1,
            clientId: 2,
            title: 'Video smoke',
          ),
        ),
      );
      await Future<void>.delayed(const Duration(seconds: 3));
      final stats = await host.peer?.stats();
      output.writeAsStringSync(
        'cycle $cycle sending $stats\n',
        mode: FileMode.append,
      );
      if (stats == null || stats.fps <= 0) {
        throw StateError('child $cycle received no video');
      }
      await child.close();
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    await capture.close();
    await subscription.cancel();
    await host.incoming.close();
    controller.dispose();
    core.dispose();
    output.writeAsStringSync('PASS\n', mode: FileMode.append);
    exit(0);
  } catch (error, stack) {
    output.writeAsStringSync('FAIL $error\n$stack\n', mode: FileMode.append);
    exit(1);
  }
}

Future<void> _realServer(RustClient core, File output) async {
  final connected = Completer<int>();
  var session = 0;
  final backend = WebRtcScreenBackend();
  final controller = ScreenController(
    backend: backend,
    send: (c) {
      output.writeAsStringSync(
        'real send ${c['action']}\n',
        mode: FileMode.append,
      );
      core.screen(session, c);
    },
  );
  final subscription = core.events.listen((event) {
    if (event is DomainEvent) {
      if (event.event is ConnectedEvent && !connected.isCompleted) {
        session = event.session;
        connected.complete(session);
      }
      if (event.event is ScreenEvent) {
        output.writeAsStringSync(
          'real recv ${(event.event as ScreenEvent).data['type']}\n',
          mode: FileMode.append,
        );
        unawaited(controller.receive(event.event as ScreenEvent));
      }
    }
  });
  core.connect(
    const ConnectRequest(
      address: '192.168.31.128:9988',
      nickname: 'Screen window diagnostic',
      profile: 'screen-window-check',
      protocol: ProtocolKind.ts6,
    ),
  );
  await connected.future.timeout(const Duration(seconds: 10));
  controller.contextChanged(online: true, client: 0, channel: 1, clients: {44});
  runApp(
    MaterialApp(
      home: ListenableBuilder(
        listenable: controller,
        builder: (_, _) => controller.remote?.view() ?? const SizedBox(),
      ),
    ),
  );
  for (var cycle = 1; cycle <= 3; cycle++) {
    await controller.watch(44);
    for (var i = 0; !controller.receiving && i < 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!controller.receiving) {
      throw StateError('real main viewer failed: ${controller.error}');
    }
    output.writeAsStringSync(
      'real main media received\n',
      mode: FileMode.append,
    );
    await Future<void>.delayed(const Duration(seconds: 1));
    final child = await controller.transferWatch(
      (client) => openDetachedScreen(
        transport: core,
        session: session,
        onReturn: () => controller.watch(44),
        args: ScreenWindowArgs(
          session: session,
          clientId: 44,
          title: 'Real TS6 video',
        ),
      ),
    );
    await Future<void>.delayed(const Duration(seconds: 1));
    final status = await child.status();
    output.writeAsStringSync(
      'real cycle $cycle child status $status\n',
      mode: FileMode.append,
    );
    if (status?['media'] != true) {
      throw StateError('real detached viewer failed');
    }
    await child.requestClose(returnInline: cycle == 3);
    for (var i = 0; !child.closed && i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!child.closed) throw StateError('native close did not finish');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (cycle == 3) {
      for (var i = 0; !controller.receiving && i < 200; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (!controller.receiving) throw StateError('inline return failed');
      await Future<void>.delayed(const Duration(seconds: 1));
      output.writeAsStringSync(
        'inline video restored\n',
        mode: FileMode.append,
      );
      await controller.leave();
    }
  }
  core.disconnect(session);
  await subscription.cancel();
  controller.dispose();
}
