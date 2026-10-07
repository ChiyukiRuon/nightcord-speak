import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/core/transport/client_transport.dart';
import 'package:nightcord_client/features/screen/detached/detached_screen.dart';
import 'package:nightcord_client/features/screen/detached/screen_window.dart';
import 'package:nightcord_client/models/events.dart';

class _Transport implements ClientTransport {
  final incoming = StreamController<FfiEvent>.broadcast(sync: true);
  @override
  Stream<FfiEvent> get events => incoming.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final mode in ['close', 'return', 'gone', 'failure']) {
    final fails = mode == 'failure';
    test('paired-channel handover waits for media and cleans up ($mode)', () async {
      // start was sent to the window-controller channel, while the child waited
      // on the paired signaling channel, so the window never began watching.
      const windows = MethodChannel('mixin.one/desktop_multi_window');
      const channels = MethodChannel('mixin.one/desktop_multi_window/channels');
      const args = ScreenWindowArgs(
        session: 1,
        clientId: 2,
        title: 'test',
        channelName: 'nightcord/screen-window/regression',
      );
      final transport = _Transport();
      final calls = <String>[];
      var returns = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(windows, (call) async {
        if (call.method == 'createWindow') {
          final json = jsonDecode(call.arguments['arguments'] as String);
          expectSync(json['channel'], args.channelName);
          scheduleMicrotask(
            () => messenger.handlePlatformMessage(
              channels.name,
              const StandardMethodCodec().encodeMethodCall(
                const MethodCall('methodCall', {
                  'channel': 'nightcord/screen-window/regression',
                  'method': 'ready',
                  'arguments': 2,
                }),
              ),
              (_) {},
            ),
          );
          return 'child';
        }
        return null;
      });
      messenger.setMockMethodCallHandler(channels, (call) async {
        calls.add(call.method);
        if (call.method == 'invokeMethod') {
          calls.add(call.arguments['method'] as String);
        }
        if (call.method == 'invokeMethod' &&
            call.arguments['method'] == 'status') {
          return {'media': !fails, 'error': fails ? 'connection' : null};
        }
        if (call.method == 'invokeMethod' &&
            call.arguments['method'] == 'start') {
          expectSync(call.arguments['channel'], args.channelName);
          expectSync(transport.incoming.hasListener, isTrue);
        }
        return null;
      });
      final opening = DetachedScreen.open(
        transport: transport,
        session: 1,
        args: args,
        onReturn: () async {
          // Rejoining before child cleanup would duplicate the same viewer.
          expect(calls, contains('window_close'));
          expect(transport.incoming.hasListener, isFalse);
          returns++;
        },
      );
      if (fails) {
        // A created window with a failed stream must reject the handover.
        await expectLater(opening, throwsStateError);
      } else {
        final screen = await opening;
        transport.incoming.add(
          const CommandResultEvent(
            CommandResult(
              command: 'screen',
              session: 1,
              outcome: CommandOutcome(ok: false),
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(calls, contains('command_failed'));
        if (mode == 'return') {
          await screen.returnToInline();
          await screen.returnToInline();
        } else {
          await screen.close(windowGone: mode == 'gone');
        }
      }
      // A native destruction notification must not re-enter window close.
      if (mode == 'gone') expect(calls, isNot(contains('window_close')));
      expect(returns, mode == 'return' ? 1 : 0);
      await transport.incoming.close();
      expect(calls, contains('unregisterMethodHandler'));
      messenger.setMockMethodCallHandler(windows, null);
      messenger.setMockMethodCallHandler(channels, null);
    });
  }
}
