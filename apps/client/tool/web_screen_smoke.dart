import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web/web.dart' as web;

import 'package:nightcord_client/core/screen/screen_share_backend.dart';
import 'package:nightcord_client/core/screen/webrtc_screen_backend.dart';
import 'package:nightcord_client/models/screen_options.dart';
import 'package:nightcord_client/models/connect_request.dart';
import 'package:nightcord_client/models/domain.dart';
import 'package:nightcord_client/models/events.dart';
import 'package:nightcord_client/core/transport/remote_transport.dart';
import 'package:nightcord_client/core/transport/socket_web.dart';
import 'package:nightcord_client/core/voice/browser_voice.dart';
import 'package:nightcord_client/core/screen/screen_controller.dart';

const options = ScreenOptions(
  source: ScreenSourceKind.screen,
  height: 720,
  fps: 30,
  videoBitrateKbps: 4000,
  audio: false,
  audioBitrateKbps: 128,
  access: ScreenAccess.public,
  viewerLimit: 0,
  mode: ScreenMode.p2p,
  detail: true,
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox.shrink());
  final button = web.HTMLButtonElement()..textContent = 'Capture and negotiate';
  button.style.cssText = 'position:fixed;top:20px;left:20px;z-index:999999';
  web.document.body!.append(button);
  button.addEventListener(
    'click',
    ((web.Event _) {
      unawaited(
        Uri.base.queryParameters.containsKey('server')
            ? checkRemote()
            : check(),
      );
    }).toJS,
  );
  web.document.title = 'ready';
}

Future<void> checkRemote() async {
  final transport = RemoteTransport(
    socketFactory: BrowserSocket.new,
    voice: BrowserVoice(),
  );
  final clients = <int, Client>{};
  final own = Completer<OwnClientIdentifiedEvent>();
  final peers = <RTCPeerConnection>[];
  int? session;
  ScreenController? controller;
  final subscription = transport.events.listen((event) {
    if (event is CommandResultEvent) {
      debugPrint(
        'command ${event.result.command}: ${event.result.ok ? 'ok' : event.result.error?.kind}',
      );
    }
    if (event is! DomainEvent) return;
    session = event.session;
    final inner = event.event;
    if (inner is ClientJoinedEvent) clients[inner.client.id] = inner.client;
    if (inner is ClientUpdatedEvent) clients[inner.client.id] = inner.client;
    if (inner is OwnClientIdentifiedEvent && !own.isCompleted) {
      own.complete(inner);
    }
    if (inner is ScreenEvent) {
      debugPrint(
        'screen event: ${inner.data['type']} ${inner.data['signal'] is Map ? inner.data['signal']['type'] : ''}',
      );
      unawaited(controller?.receive(inner));
    }
  });
  try {
    await transport.openGateway(
      Uri.parse(Uri.base.queryParameters['gw'] ?? 'ws://localhost:8787/ws'),
    );
    transport.connect(
      ConnectRequest(
        address: Uri.base.queryParameters['server']!,
        nickname: 'Web screen diagnostic',
        protocol: ProtocolKind.ts6,
      ),
    );
    final me = await own.future.timeout(const Duration(seconds: 15));
    await Future<void>.delayed(const Duration(seconds: 2));
    final publisher = clients.values
        .where((c) => c.flags.streaming && c.id != me.clientId)
        .firstOrNull;
    if (publisher == null) {
      throw StateError('No publisher is currently sharing');
    }
    controller = ScreenController(
      backend: WebRtcScreenBackend(
        createConnection: (config) async {
          final pc = await createPeerConnection(config);
          peers.add(pc);
          return pc;
        },
      ),
      send: (command) => transport.screen(session!, command),
      onError: (reason) => debugPrint('watch error: $reason'),
    );
    controller.contextChanged(
      online: true,
      client: me.clientId,
      channel: me.channelId,
      clients: clients.keys.toSet(),
    );
    await controller.watch(publisher.id);
    for (var i = 0; i < 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (controller.error != null) throw StateError(controller.error!);
      for (final pc in peers) {
        for (final stat in await pc.getStats()) {
          if (stat.type == 'inbound-rtp' &&
              (stat.values['framesDecoded'] as num? ?? 0) > 0) {
            debugPrint('received video frames=${stat.values['framesDecoded']}');
            web.document.title = 'PASS';
            return;
          }
        }
      }
    }
    throw StateError('No decoded video before deadline');
  } catch (error) {
    debugPrint('FAIL: $error');
    web.document.title = 'FAIL: $error';
  } finally {
    await controller?.leave();
    controller?.dispose();
    if (session != null) transport.disconnect(session!);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await subscription.cancel();
    transport.dispose();
  }
}

Future<void> check() async {
  ScreenMedia? capture;
  ScreenPeer? publisher;
  ScreenPeer? viewer;
  try {
    final backend = WebRtcScreenBackend();
    final sources = await backend.sources();
    debugPrint(
      'sources: ${sources.map((s) => '${s.kind}:${s.id}:${s.name}').join(', ')}',
    );
    final camera = Uri.base.queryParameters['camera'] == '1';
    final source = camera
        ? sources.firstWhere((source) => source.kind == ScreenSourceKind.camera)
        : sources.first;
    final configured = options.copyWith(source: source.kind);
    capture = await backend.capture(source, configured);
    debugPrint('capture passed');
    final rendered = Completer<void>();
    publisher = await backend.peer(
      options: configured,
      onCandidate: (c) {
        unawaited(viewer?.candidate(c));
      },
      onMedia: (_) {},
      onFailed: () => debugPrint('publisher failed'),
    );
    viewer = await backend.peer(
      options: null,
      onCandidate: (c) {
        unawaited(publisher?.candidate(c));
      },
      onMedia: (media) {
        if (!rendered.isCompleted) rendered.complete();
      },
      onFailed: () => debugPrint('viewer failed'),
    );
    final offer = await publisher.offer(capture);
    debugPrint('offer passed (${offer.length} bytes)');
    final answer = await viewer.answer(offer);
    await publisher.acceptAnswer(answer);
    await rendered.future.timeout(const Duration(seconds: 10));
    web.document.title = 'PASS';
  } catch (error, stack) {
    debugPrint('FAIL: $error\n$stack');
    web.document.title = 'FAIL: $error';
  } finally {
    await publisher?.close();
    await viewer?.close();
    await capture?.close();
  }
}
