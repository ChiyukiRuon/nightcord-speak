// The main window's half of a detached share.
//
// The detached window owns its own media, but not the connection: the session,
// the server and the trust all live here. So this carries messages across —
// commands out to the connection, events back to the window — and keeps the
// main window's own copy of the picture out of the way, because two joins to
// one stream would deliver it twice.
//
// Every message across that boundary is a channel call into another engine, and
// an engine that has not started yet, or has just been destroyed, does not
// answer. So the two sides *shake hands* before either says anything that
// matters, and nothing here waits on a call without a deadline.

import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';

import '../../../core/transport/client_transport.dart';
import '../../../core/platform/services.dart';
import '../../../models/events.dart';
import 'screen_window.dart';

/// Whether this platform can open a second window at all.
///
/// The plugin covers the three desktops and nothing else; on the web a share is
/// watched in the page, and on a phone there is no second window to open — so
/// the entry point is absent there rather than present and failing.
final bool detachedWindowsAvailable =
    !kIsWeb &&
    const {
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    }.contains(defaultTargetPlatform);

/// How long the other engine has to say it is up.
const _handshake = Duration(seconds: 5);

/// How long a goodbye may take before it is given up on.
///
/// Short on purpose. A call to a window that is already gone never comes back,
/// and waiting for it forever is what made the pop-out button stop working
/// after the first window was closed.
const _courtesy = Duration(seconds: 2);

/// A detached window, while it is open.
class DetachedScreen {
  DetachedScreen._(
    this._window,
    this._transport,
    this._session,
    this.clientId,
    this._channel,
    this._onReturn,
  );

  final WindowController _window;
  final ClientTransport _transport;
  final int _session;
  final WindowMethodChannel _channel;
  final Future<void> Function()? _onReturn;

  /// Whose stream this window is here for.
  final int clientId;

  StreamSubscription<FfiEvent>? _events;
  StreamSubscription<void>? _windows;

  /// The stream the other window joined, learned from the events passing
  /// through here. Needed to give the viewer entry back when it goes away.
  String? _streamId;

  bool _closed = false;
  bool get closed => _closed;

  /// Exercise the same close request as the child window's own controls.
  Future<void> requestClose({bool returnInline = false}) => _window
      .invokeMethod<void>(
        returnInline ? 'window_return_inline' : 'window_request_close',
      )
      .timeout(_courtesy);

  Future<Map<dynamic, dynamic>?> status() =>
      _channel.invokeMethod<Map<dynamic, dynamic>>('status').timeout(_courtesy);

  /// Opens a window and hands it the connection it will work through.
  ///
  /// Waits for remote media so a failed connection can restore inline watching.
  static Future<DetachedScreen> open({
    required ClientTransport transport,
    required int session,
    required ScreenWindowArgs args,
    Future<void> Function()? onReturn,
  }) async {
    final channel = WindowMethodChannel(args.channelName);
    DetachedScreen? opened;

    // Registered *before* the window exists. The other side's first message can
    // otherwise arrive while nobody is listening, and the channel throws at it
    // — which reads, from over there, as "the connection is gone".
    final ready = Completer<void>();
    WindowController? controller;
    await channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'ready':
          // The answer to "I am up" is "this is what I am for" — the second
          // half of the handshake, and the point at which the other side may
          // start talking to the server.
          if (!ready.isCompleted) ready.complete();
        case 'command':
          final command = call.arguments;
          if (command is Map) {
            transport.screen(session, command.cast<String, dynamic>());
          }
        case 'close':
          unawaited(opened?.close());
        case 'return_inline':
          unawaited(opened?.returnToInline());
      }
      return null;
    });

    try {
      controller = await WindowController.create(
        WindowConfiguration(arguments: jsonEncode(args.toJson())),
      );
    } catch (_) {
      await channel.setMethodCallHandler(null);
      rethrow;
    }
    final screen = DetachedScreen._(
      controller,
      transport,
      session,
      args.clientId,
      channel,
      onReturn,
    );
    opened = screen;

    try {
      await ready.future.timeout(_handshake);
    } on TimeoutException {
      await screen.close();
      throw StateError('the detached window did not come up');
    }

    // The answers go back.
    screen._events = transport.events.listen((event) {
      if (event is CommandResultEvent &&
          event.result.session == session &&
          event.result.command == 'screen' &&
          !event.result.ok) {
        unawaited(
          channel
              .invokeMethod<void>('command_failed')
              .catchError((Object _) {}),
        );
        return;
      }
      if (event is! DomainEvent || event.session != session) return;
      if (event.event is! ScreenEvent) return;
      final data = (event.event as ScreenEvent).data;
      if (data['client_id'] == args.clientId && data['stream_id'] is String) {
        screen._streamId = data['stream_id'] as String;
      }
      unawaited(
        channel.invokeMethod<void>('event', data).catchError((Object _) {}),
      );
    });

    // A window can be closed by the system, which gives its engine no chance to
    // say goodbye — so the *list* of windows is what says it is gone.
    try {
      screen._windows = onWindowsChanged.listen((_) {
        unawaited(screen._closeIfGone());
      });
    } catch (_) {
      // Not every platform offers the stream; without it the window is still
      // closed, and only the bookkeeping is lost.
    }

    // Subscribe before starting: discover can be answered before the start
    // invocation itself returns, especially over a local server connection.
    try {
      await channel.invokeMethod<void>('start').timeout(_handshake);
      await controller.show();
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (true) {
        if (screen._closed) throw StateError('the detached window was closed');
        final state = await screen.status();
        if (state?['error'] != null) {
          throw StateError('detached stream failed: ${state!['error']}');
        }
        if (state?['media'] == true) break;
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('the detached stream did not connect');
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    } catch (_) {
      await screen.close();
      rethrow;
    }
    return screen;
  }

  Future<void> _closeIfGone() async {
    if (_closed) return;
    final open = await WindowController.getAll();
    if (open.any((other) => other.windowId == _window.windowId)) return;
    await close(windowGone: true);
  }

  Future<void> returnToInline() async {
    if (_closed) return;
    await close();
    await _onReturn?.call();
  }

  /// Closes the window, if it is still open, and stops carrying its messages.
  ///
  /// It also gives the viewer entry back. Both windows are the same TeamSpeak
  /// client, so the publisher cannot tell them apart: without this it would go
  /// on sending to a viewer that no longer exists, which is exactly the shape
  /// of leak that keeps a stream alive after everyone stopped watching.
  Future<void> close({bool windowGone = false}) async {
    if (_closed) return;
    _closed = true;
    if (identical(detachedWindow, this)) detachedWindow = null;

    if (_streamId case final id?) {
      _transport.screen(_session, {
        'action': 'leave',
        'stream_id': id,
        'client_id': clientId,
      });
    }
    await _events?.cancel();
    await _windows?.cancel();
    try {
      // The plugin has no close of its own: the window closes itself, on a
      // method its own side registered.
      if (!windowGone) {
        await _window.invokeMethod<void>('window_close').timeout(_courtesy);
      }
    } catch (_) {
      // Already gone, which is the same outcome.
    }
    await _channel.setMethodCallHandler(null);
  }
}

/// The one detached window this client allows at a time.
///
/// One rather than many: the picture is one stream, and a second window would
/// be a second join to it.
DetachedScreen? detachedWindow;
Future<void> _opening = Future<void>.value();

/// Opens one, replacing whatever was open before.
Future<DetachedScreen> openDetachedScreen({
  required ClientTransport transport,
  required int session,
  required ScreenWindowArgs args,
  Future<void> Function()? onReturn,
}) {
  final result = Completer<DetachedScreen>();
  _opening = _opening.then((_) async {
    try {
      result.complete(
        await _replaceDetachedScreen(
          transport: transport,
          session: session,
          args: args,
          onReturn: onReturn,
        ),
      );
    } catch (error, stack) {
      logToCore('error', 'screen: detached window failed: $error\n$stack');
      result.completeError(error, stack);
    }
  });
  return result.future;
}

Future<DetachedScreen> _replaceDetachedScreen({
  required ClientTransport transport,
  required int session,
  required ScreenWindowArgs args,
  Future<void> Function()? onReturn,
}) async {
  final previous = detachedWindow;
  // Cleared first: whatever happens below, the next attempt must not find a
  // window that is on its way out and wait for it.
  detachedWindow = null;
  await previous?.close();
  final screen = await DetachedScreen.open(
    transport: transport,
    session: session,
    args: ScreenWindowArgs(
      session: args.session,
      clientId: args.clientId,
      title: args.title,
      channelName:
          'nightcord/screen-window/${DateTime.now().microsecondsSinceEpoch}',
    ),
    onReturn: onReturn,
  );
  detachedWindow = screen;
  return screen;
}
