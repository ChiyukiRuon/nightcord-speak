// The screen share, in a window of its own.
//
// A second window is a second Flutter engine, and **an engine cannot use the
// first one's textures** — `Texture` ids come from the engine that registered
// them, and an unknown id renders as a blank rectangle. So the detached window
// does not show the main window's picture; it owns its own media:
//
//   * watching somebody else means opening its own peer connection, and
//   * looking at your own share means capturing it a second time.
//
// That is why the two windows talk at all. The session, the server connection
// and the publishing all stay in the main window; the detached one sends it the
// commands that need the connection and receives the events that come back —
// SDP and ICE included, which is why the channel carries those and nothing
// else worth caring about.

import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall;
import 'package:window_manager/window_manager.dart';

import '../../../core/screen/screen_controller.dart';
import '../../../core/screen/webrtc_screen_backend.dart';
import '../../../core/platform/services.dart';

import 'dart:ui' show PlatformDispatcher;

import '../../../design/theme/app_theme.dart';
import '../../../design/tokens/app_palette.dart';
import '../../../models/events.dart';
import '../../../l10n/app_localizations.dart';

/// The channel the pair talk over.
///
/// `bidirectional` pairs the two engines: only they can call each other, and
/// only each other — which is what "the window that opened me" means here.
/// A detached window holds no credentials of its own; everything it can do, it
/// does by asking the window that opened it.
const screenWindowChannel = WindowMethodChannel(
  'nightcord/screen-window',
  mode: ChannelMode.bidirectional,
);

/// What a detached window was asked to show.
///
/// Only watching, for now. Showing your *own* share in its own window would
/// mean capturing the same source a second time — and on this platform a
/// capture of a window brings that window to the front, which is the one thing
/// a detached window must never do to somebody's desktop.
class ScreenWindowArgs {
  const ScreenWindowArgs({
    required this.session,
    required this.clientId,
    required this.title,
    this.channelName = 'nightcord/screen-window',
  });

  final int session;

  /// Whose stream to watch.
  final int clientId;

  /// What to put in the window's own title bar.
  final String title;
  final String channelName;

  Map<String, dynamic> toJson() => {
    'screen': true,
    'session': session,
    'client_id': clientId,
    'title': title,
    'channel': channelName,
  };

  /// Parses the arguments of the engine this is running in, or null when this
  /// is the main window and there are none.
  static ScreenWindowArgs? parse(String? arguments) {
    if (arguments == null || arguments.isEmpty) return null;
    try {
      final json = jsonDecode(arguments);
      if (json is! Map || json['screen'] != true) return null;
      return ScreenWindowArgs(
        session: (json['session'] as num?)?.toInt() ?? 0,
        clientId: (json['client_id'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? 'Screen share',
        channelName: json['channel'] as String? ?? 'nightcord/screen-window',
      );
    } catch (_) {
      // Anything unparsable is the main window: it is the one case that must
      // never fail to start.
      return null;
    }
  }
}

/// Asks the plugin which window this engine is, and what it was opened for.
///
/// Null means the main window — including when the plugin is not there at all,
/// which is every platform except the two desktops.
Future<ScreenWindowArgs?> detachedScreenArgs() async {
  try {
    final controller = await WindowController.fromCurrentEngine();
    return ScreenWindowArgs.parse(controller.arguments);
  } catch (_) {
    return null;
  }
}

/// Runs the detached window's app. Does not return.
Future<void> runScreenWindow(ScreenWindowArgs args) async {
  runApp(DetachedScreenApp(args: args));
}

/// The detached window itself.
class DetachedScreenApp extends StatelessWidget {
  const DetachedScreenApp({required this.args, super.key});

  final ScreenWindowArgs args;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildAppTheme(
      AppPalette.nightcord,
      PlatformDispatcher.instance.locale,
    ),
    home: DetachedScreenView(args: args),
  );
}

/// Owns this window's `ScreenController` and keeps it fed from the main window.
class DetachedScreenView extends StatefulWidget {
  const DetachedScreenView({required this.args, super.key});

  final ScreenWindowArgs args;

  @override
  State<DetachedScreenView> createState() => _DetachedScreenViewState();
}

class _DetachedScreenViewState extends State<DetachedScreenView>
    with WindowListener {
  bool _closing = false;
  bool _requestingClose = false;
  late final _channel = WindowMethodChannel(widget.args.channelName);
  late final ScreenController _controller = ScreenController(
    backend: WebRtcScreenBackend(),
    send: _sendToHost,
    onError: (reason) =>
        logToCore('error', 'screen window: failed reason=$reason'),
  );

  /// Set when the opener has subscribed to our signaling events.
  final _started = Completer<void>();

  @override
  void initState() {
    super.initState();
    _controller.contextChanged(
      online: true,
      client: 0,
      channel: 0,
      clients: const {},
    );
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _ownTheWindow();
      if (!mounted) return;
      await _channel.setMethodCallHandler((call) async {
        switch (call.method) {
          case 'start':
            if (!_started.isCompleted) _started.complete();
          case 'event':
            final data = call.arguments;
            if (data is Map) {
              logToCore('info', 'screen window: recv ${data['type']}');
              await _controller.receive(
                ScreenEvent(data.cast<String, dynamic>()),
              );
            }
          case 'status':
            return {
              'media': _controller.receiving,
              'error': _controller.error,
            };
          case 'command_failed':
            _controller.fail('connection');
        }
        return null;
      });
      await _begin();
    } catch (error, stack) {
      logToCore(
        'error',
        'screen window: initialization failed: $error\n$stack',
      );
      if (mounted) _controller.fail('connection');
    }
  }

  /// Says hello, and waits to be told what to do.
  ///
  /// The handshake exists because the opener cannot know when an engine is
  /// ready to be spoken to. Saying  before it is listening is not an
  /// error, though — it simply arrives too early — so it is repeated until
  /// somebody answers, rather than treated as a broken connection.
  Future<void> _begin() async {
    for (
      var attempt = 0;
      mounted && attempt < 20 && !_started.isCompleted;
      attempt++
    ) {
      try {
        await _channel
            .invokeMethod<void>('ready', widget.args.clientId)
            .timeout(const Duration(milliseconds: 500));
        await _started.future.timeout(const Duration(milliseconds: 500));
      } on TimeoutException {
        // No answer yet; try again.
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
    if (!mounted) return;
    if (!_started.isCompleted) {
      _controller.fail('connection');
      return;
    }
    await _controller.watch(widget.args.clientId);
  }

  /// Intercept native close so media is released while this engine is alive.
  Future<void> _ownTheWindow() async {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    await windowManager.setTitle(widget.args.title);
    await windowManager.setSize(const Size(960, 600));
    final controller = await WindowController.fromCurrentEngine();
    await controller.setWindowMethodHandler((MethodCall call) async {
      if (call.method == 'window_close') {
        if (_closing) return null;
        _closing = true;
        // Release the peer before destroying the engine that owns its callbacks.
        await _controller.abandon();
        await WidgetsBinding.instance.endOfFrame;
        await _channel.setMethodCallHandler(null);
        // Reply before posting native close; destroying an engine inside its
        // own method callback can invalidate the pending response.
        Timer(const Duration(milliseconds: 50), () async {
          await windowManager.setPreventClose(false);
          await windowManager.close();
        });
      } else if (call.method == 'window_request_close') {
        await windowManager.close();
      } else if (call.method == 'window_return_inline') {
        await _requestHostClose(returnInline: true);
      }
      return null;
    });
  }

  @override
  void onWindowClose() {
    if (!_closing) unawaited(_requestHostClose());
  }

  Future<void> _requestHostClose({bool returnInline = false}) async {
    if (_closing || _requestingClose) return;
    _requestingClose = true;
    try {
      await _channel
          .invokeMethod<void>(returnInline ? 'return_inline' : 'close')
          .timeout(const Duration(seconds: 2));
    } catch (error, stack) {
      _requestingClose = false;
      logToCore('error', 'screen window: close request failed: $error\n$stack');
    }
  }

  /// Every command goes to the window that owns the connection.
  void _sendToHost(Map<String, dynamic> command) {
    logToCore('info', 'screen window: send ${command['action']}');
    unawaited(
      _channel
          .invokeMethod<void>('command', command)
          .timeout(const Duration(seconds: 2))
          .catchError((Object _) {
            // The main window is gone, so this one has nothing left to be.
            if (mounted && !_controller.disposed) {
              _controller.fail('connection');
            }
          }),
    );
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final media = _controller.remote ?? _controller.preview;
        return Scaffold(
          backgroundColor: tokens.bgDeep,
          body: Stack(
            fit: StackFit.expand,
            children: [
              if (media != null) media.view(),
              if (media == null)
                Center(
                  child: Text(
                    _controller.error != null
                        ? 'Screen sharing failed'
                        : 'Connecting…',
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: tokens.textSecondary),
                  ),
                ),
              Positioned(
                top: tokens.space2,
                right: tokens.space2,
                child: FilledButton.icon(
                  onPressed: () => _requestHostClose(returnInline: true),
                  icon: const Icon(Icons.picture_in_picture_alt),
                  label: Text(AppLocalizations.of(context).screenReturnInline),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
