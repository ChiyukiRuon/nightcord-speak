import 'package:flutter/material.dart';
import 'package:nightcord_client/core/transport/gateway_config.dart';
import 'package:nightcord_client/features/gateway/gateway_gate.dart';
import 'package:nightcord_client/l10n/app_localizations.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightcord_client/main.dart';
import 'package:nightcord_client/providers/providers.dart';
import 'package:nightcord_client/features/server/server_page.dart';
import 'package:nightcord_client/core/transport/remote_socket.dart';
import 'package:nightcord_client/core/transport/remote_transport.dart';
import 'package:nightcord_client/core/voice/voice_backend.dart';
import 'package:nightcord_client/models/connect_request.dart';
import 'package:nightcord_client/models/domain.dart';
import 'package:nightcord_client/models/events.dart';

class FakeSocket implements RemoteSocket {
  final incoming = StreamController<Object>();
  final sent = <Object>[];
  final afterWelcome = <Map<String, Object?>>[];
  bool closed = false;
  bool rejectAuth = false;
  bool noAuth = false;
  bool requireDevice = false;
  static const credential =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  @override
  int bufferedAmount = 0;
  @override
  Future<void> get opened async {
    incoming.add(
      jsonEncode({
        'kind': 'hello',
        'protocol': 1,
        'auth': noAuth ? 'none' : 'required',
        if (requireDevice) 'device': 'required',
      }),
    );
    if (noAuth && !requireDevice) {
      incoming.add(jsonEncode({'kind': 'welcome', 'protocol': 1}));
    }
  }

  @override
  Stream<Object> get messages => incoming.stream;
  @override
  void sendText(String value) {
    final frame = jsonDecode(value) as Map;
    sent.add(frame);
    if (frame['kind'] == 'auth' || frame['kind'] == 'attach') {
      if (rejectAuth) {
        incoming.add(jsonEncode({'kind': 'error', 'message': 'bad token'}));
        return;
      }
      incoming.add(
        jsonEncode({
          'kind': 'welcome',
          'protocol': 1,
          if (requireDevice) 'device': frame['device'] ?? credential,
        }),
      );
      for (final frame in afterWelcome) {
        incoming.add(jsonEncode(frame));
      }
    }
  }

  @override
  void sendBinary(Uint8List bytes) => sent.add(bytes);
  @override
  void close() {
    closed = true;
  }
}

class FakeVoice implements VoiceBackend {
  final frames = StreamController<Uint8List>.broadcast();
  final received = <Uint8List>[];
  int stops = 0;
  Completer<void>? starting;
  @override
  Stream<Uint8List> get captured => frames.stream;
  @override
  Map<String, dynamic> get status => {'healthy': true};
  @override
  Future<void> start({String? inputDevice, String? outputDevice}) =>
      starting?.future ?? Future.value();
  @override
  void stop() {
    stops++;
  }

  @override
  void play(Uint8List frame) {
    received.add(frame);
  }

  @override
  Future<List<Map<String, dynamic>>> devices(String direction) async => [
    {'id': 'browser-mic', 'name': 'Browser microphone', 'direction': direction},
  ];
  @override
  void setOutputMuted(bool muted) {}
  @override
  void setInputMuted(bool muted) {}
  @override
  void setOutputVolume(double volume) {}
  @override
  void testOutput() {}
}

void main() {
  late FakeSocket socket;
  late FakeVoice voice;
  late RemoteTransport transport;
  setUp(() {
    socket = FakeSocket();
    voice = FakeVoice();
    transport = RemoteTransport(socketFactory: (_) => socket, voice: voice);
  });
  tearDown(() async {
    transport.dispose();
    socket.incoming.close();
    await voice.frames.close();
  });
  Future<void> open() => transport.openGateway(
    Uri.parse('ws://localhost:8787/ws'),
    'test-only-token',
  );

  testWidgets(
    'refresh snapshots reach sessions before the gateway gate mounts the shell',
    (tester) async {
      // Settings subscribed first, dropping the welcome burst before AppShell
      // could subscribe. A real refreshed browser remained on the connect form.
      socket.afterWelcome.addAll([
        {
          'kind': 'event',
          'session': 7,
          'event': {
            'event': 'connected',
            'payload': {
              'server': {
                'id': 1,
                'name': 'Restored server',
                'address': 'host',
                'protocol': 'ts3',
              },
              'info': {'name': 'Restored server'},
            },
          },
        },
        {
          'kind': 'command_result',
          'command': 'connect',
          'session': 7,
          'outcome': {'status': 'ok'},
        },
      ]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [clientTransportProvider.overrideWithValue(transport)],
          child: const NightcordApp(),
        ),
      );
      await tester.pump();
      await open();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(ServerPage), findsOneWidget);
      expect(find.text('Restored server'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'configured token cannot follow a query parameter to another gateway',
    () {
      const configured = GatewayConfig(
        url: 'wss://trusted/ws',
        token: 'bundled-token',
      );
      expect(configured.autoConnect, isTrue);
      expect(
        configured.address(Uri.parse('https://app/?gw=wss://other/ws')),
        'wss://trusted/ws',
      );
      expect(const GatewayConfig(url: 'wss://trusted/ws').autoConnect, isTrue);
      expect(const GatewayConfig(token: 'token').autoConnect, isFalse);
      expect(
        const GatewayConfig().address(
          Uri.parse('http://app/?gw=ws://local/ws'),
        ),
        'ws://local/ws',
      );
    },
  );

  testWidgets(
    'deployment configuration authenticates without any form interaction',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [clientTransportProvider.overrideWithValue(transport)],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const GatewayGate(
              config: GatewayConfig(
                url: 'wss://configured/ws',
                token: 'bundled-token',
              ),
              child: Text('Automatically connected'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(socket.sent.first, {'kind': 'auth', 'token': 'bundled-token'});
      expect(find.text('Automatically connected'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'rejected deployment credentials offer a form instead of retrying forever',
    (tester) async {
      socket.rejectAuth = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [clientTransportProvider.overrideWithValue(transport)],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const GatewayGate(
              config: GatewayConfig(
                url: 'wss://configured/ws',
                token: 'bundled-token',
              ),
              child: Text('Automatically connected'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        socket.sent.where((frame) => frame is Map && frame['kind'] == 'auth'),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'address-only deployment connects to an open gateway automatically',
    (tester) async {
      socket.noAuth = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [clientTransportProvider.overrideWithValue(transport)],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const GatewayGate(
              config: GatewayConfig(url: 'wss://configured/ws'),
              child: Text('Connected without a token'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Connected without a token'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(
        socket.sent.where((frame) => frame is Map && frame['kind'] == 'auth'),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('token-free gateway sends no credential frame', () async {
    socket.noAuth = true;
    await transport.openGateway(Uri.parse('ws://localhost/ws'));
    expect(transport.state, GatewayState.ready);
    expect(socket.sent, isEmpty);
    transport.requestSettings();
    expect(socket.sent.single, {'command': 'settings'});
  });

  test('unconfigured gateway follows the page host on a phone', () {
    // A phone loading a LAN page must not connect to its own localhost.
    expect(
      const GatewayConfig().address(Uri.parse('http://192.168.31.95:5173/')),
      'ws://192.168.31.95:8787/ws',
    );
    expect(
      const GatewayConfig().address(Uri.parse('https://example.com/')),
      'wss://example.com:8787/ws',
    );
    expect(
      const GatewayConfig(url: 'ws://localhost:8787/ws')
          .address(Uri.parse('http://192.168.31.95:5173/')),
      'ws://localhost:8787/ws',
    );
  });

  test('device attachment is separate from token auth and survives transport reconnect', () async {
    socket.noAuth = true;
    socket.requireDevice = true;
    final gateway = Uri.parse('ws://localhost/ws');
    await transport.openGateway(gateway);
    expect(socket.sent.single, {'kind': 'attach', 'device': null});
    expect(transport.deviceStore.load(gateway), FakeSocket.credential);
    expect(transport.deviceStore.load(Uri.parse('ws://other/ws')), isNull);
    transport.closeGateway();
    await socket.incoming.close();
    socket = FakeSocket()
      ..noAuth = true
      ..requireDevice = true;
    await transport.openGateway(gateway);
    expect(socket.sent.last, {
      'kind': 'attach',
      'device': FakeSocket.credential,
    });
  });

  test(
    'a protected gateway receives this device credential with token auth',
    () async {
      socket.requireDevice = true;
      final gateway = Uri.parse('ws://localhost/ws');
      transport.deviceStore.save(gateway, FakeSocket.credential);
      await transport.openGateway(gateway, 'test-token');
      expect(socket.sent.single, {
        'kind': 'auth',
        'token': 'test-token',
        'device': FakeSocket.credential,
      });
    },
  );

  test(
    'protected gateway rejects a missing token without sending commands',
    () async {
      await expectLater(
        transport.openGateway(Uri.parse('ws://localhost/ws')),
        throwsStateError,
      );
      expect(transport.failure, 'Gateway token required');
      expect(socket.sent, isEmpty);
    },
  );

  test(
    'authentication is the first frame and commands cannot precede it',
    () async {
      transport.connect(
        const ConnectRequest(address: 'server', nickname: 'name'),
      );
      expect(socket.sent, isEmpty);
      await open();
      expect(socket.sent.single, {'kind': 'auth', 'token': 'test-only-token'});
      transport.connect(
        const ConnectRequest(address: 'server', nickname: 'name'),
      );
      expect((socket.sent.last as Map)['command'], 'connect');
    },
  );

  test(
    'URLs cannot leak tokens through credentials or query parameters',
    () async {
      for (final url in [
        'https://host/ws',
        'ws://user:secret@host/ws',
        'ws://host/ws?token=secret',
        'ws://host/ws#secret',
      ]) {
        await expectLater(
          transport.openGateway(Uri.parse(url), 'token'),
          throwsArgumentError,
        );
      }
      expect(socket.sent, isEmpty);
    },
  );

  test(
    'unit commands have no payload; domain commands keep their wire shape',
    () async {
      await open();
      transport.requestSettings();
      expect(socket.sent.last, {'command': 'settings'});
      transport.sendMessage(3, const ChannelTarget(4), 'hello');
      expect(socket.sent.last, {
        'command': 'send_message',
        'payload': {
          'session': 3,
          'target': {'kind': 'channel', 'id': 4},
          'text': 'hello',
        },
      });
      transport.ban(3, 5, BanDuration.seconds(60), null);
      expect(((socket.sent.last as Map)['payload'] as Map)['duration'], {
        'seconds': 60,
      });
    },
  );

  test(
    'snapshot events arriving before widgets subscribe are retained',
    () async {
      // The welcome mounts the shell on a later frame; losing this burst left
      // refreshed browsers on the connect page despite a live gateway session.
      await open();
      socket.incoming.add(
        jsonEncode({
          'kind': 'event',
          'session': 7,
          'event': {
            'event': 'own_client_identified',
            'payload': {'client_id': 2, 'channel_id': 4},
          },
        }),
      );
      await Future<void>.delayed(Duration.zero);
      final event = await transport.events.first;
      expect(event, isA<DomainEvent>());
      expect((event as DomainEvent).session, 7);
    },
  );

  test('audio is bounded and routed through the browser backend', () async {
    await open();
    final frame = Uint8List.fromList([1, 0, 0, 0, 0]);
    voice.frames.add(frame);
    await Future<void>.delayed(Duration.zero);
    expect(socket.sent.last, frame);
    socket.bufferedAmount = 65536;
    final count = socket.sent.length;
    voice.frames.add(frame);
    await Future<void>.delayed(Duration.zero);
    expect(socket.sent.length, count);
    socket.incoming.add(Uint8List.fromList([2, 0, 0, 0, 0]));
    await Future<void>.delayed(Duration.zero);
    expect(voice.received, hasLength(1));
  });

  test(
    'muting and releasing PTT stop raw microphone frames before the socket',
    () async {
      // Server-side gating alone still sent muted microphone PCM to the host,
      // and another tab holding PTT could accidentally open this tab's audio.
      await open();
      final frame = Uint8List.fromList([1, 0, 0, 0, 0]);
      transport.setInputMuted(true);
      voice.frames.add(frame);
      await Future<void>.delayed(Duration.zero);
      expect(socket.sent.whereType<Uint8List>(), isEmpty);
      transport.setInputMuted(false);
      socket.incoming.add(
        jsonEncode({
          'kind': 'event',
          'session': 1,
          'event': {
            'event': 'voice_state_changed',
            'payload': {'mode': 'push_to_talk'},
          },
        }),
      );
      await Future<void>.delayed(Duration.zero);
      voice.frames.add(frame);
      await Future<void>.delayed(Duration.zero);
      expect(socket.sent.whereType<Uint8List>(), isEmpty);
      transport.setPushToTalk(true);
      voice.frames.add(frame);
      await Future<void>.delayed(Duration.zero);
      expect(socket.sent.whereType<Uint8List>(), hasLength(1));
      transport.setPushToTalk(false);
      voice.frames.add(frame);
      await Future<void>.delayed(Duration.zero);
      expect(socket.sent.whereType<Uint8List>(), hasLength(1));
    },
  );

  test('stopping during a microphone permission prompt never starts gateway voice later', () async {
    // getUserMedia can resolve after the user stops voice or leaves the page.
    await open();
    voice.starting = Completer<void>();
    transport.voiceStart(1);
    transport.voiceStop();
    voice.starting!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(
      socket.sent.whereType<Map>().where((f) => f['command'] == 'voice_start'),
      isEmpty,
    );
  });

  test('malformed gateway data reports a failure without throwing from the event stream', () async {
    await open();
    final result = transport.events.first;
    socket.incoming.add('not json');
    expect((await result as CommandResultEvent).result.ok, isFalse);
  });

  test(
    'browser device enumeration does not ask the gateway for its hardware',
    () async {
      await open();
      final event = transport.events.first;
      transport.requestAudioDevices('input');
      final result = (await event as CommandResultEvent).result;
      expect(result.data!['devices'], isNotEmpty);
      expect(socket.sent, hasLength(1));
    },
  );

  test(
    'closing the gateway releases browser audio and rejects later commands',
    () async {
      await open();
      final stops = voice.stops;
      transport.closeGateway();
      expect(voice.stops, stops + 1);
      expect(socket.closed, isTrue);
      expect(transport.state, GatewayState.disconnected);
      transport.dispose();
      transport.dispose();
      expect(() => transport.requestSettings(), throwsStateError);
    },
  );
}
