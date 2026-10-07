import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/events.dart';
import '../../providers/providers.dart';
import 'screen_controller.dart';
import 'screen_share_backend.dart';
import 'webrtc_screen_backend.dart';
import '../platform/services.dart';

final screenBackendProvider = Provider<ScreenShareBackend>((ref) => WebRtcScreenBackend());

/// Names one screen-sharing message for the log.
///
/// Ids and the message kind only: an SDP or an ICE candidate carries the DTLS
/// fingerprint, the ICE credentials and the peer's addresses, and none of that
/// belongs in a file on disk (§4.5). What is left is still enough to tell "we
/// never asked" from "we asked and the answer never came", which is otherwise
/// invisible from this side of a peer connection.
String _trace(String direction, String kind, String? stream, Object? client) =>
    'screen: $direction $kind stream=${stream ?? '-'} client=${client ?? '-'}';

final screenControllerProvider = Provider.family<ScreenController, int>((ref, session) {
  final transport = ref.watch(clientTransportProvider);
  final controller = ScreenController(backend: ref.watch(screenBackendProvider),
    send: (command) {
      final signal = command['signal'];
      logToCore('info', _trace('send', '${command['action']}'
          '${signal is Map ? '/${signal['type']}' : ''}',
          command['stream_id'] as String?, command['client_id']));
      transport.screen(session, command);
    },
    onError: (reason) => logToCore('error', 'screen sharing: session=$session reason=$reason'));
  void update() {
    final view = ref.read(sessionsProvider)[session];
    controller.contextChanged(online: view?.isConnected ?? false,
      client: view?.ownClientId, channel: view?.ownChannelId,
      clients: view == null ? <int>{} : {for (final c in view.clients.values) if (c.channelId == view.ownChannelId) c.id});
  }
  ref.listen(sessionsProvider, (_, _) => update());
  update();
  final subscription = transport.events.listen((event) {
    if (event is DomainEvent && event.session == session && event.event is ScreenEvent) {
      final data = (event.event as ScreenEvent).data;
      final signal = data['signal'];
      logToCore('info', _trace('recv', '${data['type']}'
          '${signal is Map ? '/${signal['type']}' : ''}',
          data['stream_id'] as String?, data['client_id']));
      unawaited(controller.receive(event.event as ScreenEvent));
    } else if (event is CommandResultEvent && event.result.session == session && event.result.command == 'screen' && !event.result.ok) {
      if (controller.active || controller.watching) controller.fail('connection');
    } else if (event is LaggedEvent) {
      controller.fail('connection');
    }
  });
  ref.onDispose(() { subscription.cancel(); controller.dispose(); });
  return controller;
});
