import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../models/bookmarks.dart';
import '../../models/connect_request.dart';
import '../../models/domain.dart';
import '../../models/events.dart';
import '../../models/settings.dart';
import '../voice/voice_backend.dart';
import 'client_transport.dart';
import 'remote_socket.dart';
import 'device_store.dart';

enum GatewayState { disconnected, connecting, ready }

/// The same command/event vocabulary as FFI, carried over an authenticated socket.
class RemoteTransport implements ClientTransport {
  RemoteTransport({
    required this.socketFactory,
    required this.voice,
    DeviceStore? deviceStore,
  }) : deviceStore = deviceStore ?? MemoryDeviceStore() {
    _capture = voice.captured.listen((frame) {
      final socket = _socket;
      // Old audio is less valuable than the next frame. Bound socket backlog.
      if (state == GatewayState.ready &&
          !_inputMuted &&
          !_outputMuted &&
          !_away &&
          _mode != VoiceActivationMode.muted &&
          (_mode != VoiceActivationMode.pushToTalk || _pttHeld) &&
          socket != null &&
          socket.bufferedAmount < 65536) {
        socket.sendBinary(frame);
      }
    });
  }

  final RemoteSocket Function(Uri) socketFactory;
  final VoiceBackend voice;
  final DeviceStore deviceStore;
  Uri? _gateway;
  late final _events = StreamController<FfiEvent>.broadcast(
    onListen: () {
      scheduleMicrotask(() {
        final pending = List<FfiEvent>.of(_pending);
        _pending.clear();
        for (final event in pending) {
          _emit(event);
        }
      });
    },
  );
  final _pending = <FfiEvent>[];
  void _emit(FfiEvent event) {
    if (_events.isClosed) return;
    if (_events.hasListener) {
      _events.add(event);
    } else {
      _pending.add(event);
    }
  }

  final _states = StreamController<GatewayState>.broadcast();
  Stream<GatewayState> get states => _states.stream;
  GatewayState state = GatewayState.disconnected;
  String? failure;
  RemoteSocket? _socket;
  StreamSubscription<Object>? _subscription;
  late final StreamSubscription<Uint8List> _capture;
  Completer<void>? _authenticated;
  bool _disposed = false;
  bool _inputMuted = false;
  bool _outputMuted = false;
  bool _away = false;
  bool _pttHeld = false;
  VoiceActivationMode _mode = VoiceActivationMode.voiceActivation;
  int _voiceGeneration = 0;

  @override
  Stream<FfiEvent> get events => _events.stream;

  String _token = '';

  Future<void> openGateway(Uri uri, [String token = '']) async {
    if (_disposed) throw StateError('Transport disposed');
    if (!{'ws', 'wss'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError(
        'Use a ws:// or wss:// gateway URL without credentials or query parameters',
      );
    }
    closeGateway();
    failure = null;
    _token = token.trim();
    _gateway = uri;
    _setState(GatewayState.connecting);
    final authenticated = Completer<void>();
    _authenticated = authenticated;
    authenticated.future.ignore();
    try {
      final socket = socketFactory(uri);
      _socket = socket;
      _subscription = socket.messages.listen(
        _receive,
        onError: (Object error) {
          _lost('Gateway connection failed');
        },
        onDone: () => _lost('Gateway connection closed'),
      );
      await socket.opened.timeout(const Duration(seconds: 10));
      if (_socket != socket) throw StateError('Gateway connection cancelled');
      // The hello frame decides whether a credential is required.
      await authenticated.future.timeout(const Duration(seconds: 12));
    } catch (_) {
      closeGateway();
      rethrow;
    } finally {
      if (identical(_authenticated, authenticated)) _authenticated = null;
    }
  }

  void _setState(GatewayState next) {
    if (state == next) return;
    state = next;
    if (!_states.isClosed) _states.add(next);
  }

  void _lost(String message) {
    if (_disposed || state == GatewayState.disconnected) return;
    failure = message;
    _authenticated?.completeErrorIfPending(StateError(message));
    closeGateway();
  }

  void closeGateway() {
    _voiceGeneration++;
    _pttHeld = false;
    voice.stop();
    _pending.clear();
    _subscription?.cancel();
    _subscription = null;
    _socket?.close();
    _socket = null;
    _token = '';
    _setState(GatewayState.disconnected);
  }

  void _receive(Object frame) {
    if (_disposed) return;
    if (frame is Uint8List) {
      if (state == GatewayState.ready) voice.play(frame);
      return;
    }
    try {
      final json = (jsonDecode(frame as String) as Map).cast<String, dynamic>();
      switch (json['kind']) {
        case 'hello':
          if (json['protocol'] != 1) {
            _lost('Unsupported gateway protocol');
            return;
          }
          if (json['auth'] != 'none') {
            if (_token.isEmpty) {
              _lost('Gateway token required');
              return;
            }
            _socket?.sendText(
              jsonEncode({
                'kind': 'auth',
                'token': _token,
                if (json['device'] == 'required')
                  'device': deviceStore.load(_gateway!),
              }),
            );
          } else if (json['device'] == 'required') {
            _socket?.sendText(
              jsonEncode({
                'kind': 'attach',
                'device': deviceStore.load(_gateway!),
              }),
            );
          }
        case 'welcome':
          if (json['protocol'] != 1) {
            _lost('Unsupported gateway protocol');
            return;
          }
          final credential = json['device'];
          if (credential is String && _gateway != null) {
            deviceStore.save(_gateway!, credential);
          }
          _setState(GatewayState.ready);
          if (!(_authenticated?.isCompleted ?? true)) {
            _authenticated!.complete();
          }
        case 'error':
          // Do not echo raw gateway payloads: they may contain user data.
          if (state != GatewayState.ready) {
            _lost(
              json['message'] == 'bad token'
                  ? 'Gateway token rejected'
                  : 'Gateway authentication failed',
            );
          } else {
            _result('gateway', error: 'Gateway rejected the command');
          }
        default:
          if (state == GatewayState.ready) {
            var event = FfiEvent.fromJson(json);
            if (event case CommandResultEvent(
              result: CommandResult(
                command: 'voice_status',
                :final data,
                :final outcome,
                :final session,
              ),
            )) {
              final local = voice.status;
              event = CommandResultEvent(
                CommandResult(
                  command: 'voice_status',
                  session: session,
                  outcome: outcome,
                  data: {
                    ...?data,
                    ...local,
                    'transmitting': data?['transmitting'] ?? false,
                    'healthy':
                        local['healthy'] == true && data?['healthy'] == true,
                  },
                ),
              );
            }
            if (event case CommandResultEvent(
              result: CommandResult(command: 'settings', :final data),
            )) {
              if (data != null) {
                final settings = Settings.fromJson(data);
                _mode = settings.audio.mode;
                voice.setOutputVolume(settings.audio.outputVolume);
              }
            }
            if (event case DomainEvent(
              event: VoiceStateChangedEvent(:final state),
            )) {
              _inputMuted = state.inputMuted;
              _outputMuted = state.outputMuted;
              _mode = state.mode;
              voice.setInputMuted(_inputMuted);
              voice.setOutputMuted(_outputMuted);
            }
            if (event case DomainEvent(
              event: ClientUpdatedEvent(:final client),
            )) {
              if (client.isSelf) _away = client.flags.away;
            }
            if (event case DomainEvent(
              event: ClientJoinedEvent(:final client),
            )) {
              if (client.isSelf) _away = client.flags.away;
            }
            if (event case DomainEvent(
              event: ConnectionStateChangedEvent(
                state: ConnectionState.connected,
              ),
            )) {
              _away = false;
            }
            _emit(event);
          }
      }
    } catch (_) {
      _result('gateway', error: 'Invalid gateway response');
    }
  }

  void _send(String command, [Object? payload]) {
    if (_disposed) throw StateError('Transport disposed');
    if (state != GatewayState.ready) {
      _result(command, error: 'Connect to the gateway first');
      return;
    }
    _socket!.sendText(jsonEncode({'command': command, 'payload': ?payload}));
  }

  void _result(String command, {Map<String, dynamic>? data, String? error}) {
    if (_events.isClosed) return;
    _emit(
      CommandResultEvent(
        CommandResult(
          command: command,
          session: null,
          data: data,
          outcome: CommandOutcome(
            ok: error == null,
            error: error == null
                ? null
                : ClientError(kind: 'network', detail: {'message': error}),
          ),
        ),
      ),
    );
  }

  @override
  void connect(ConnectRequest request) => _send('connect', request.toJson());
  @override
  void disconnect(int session) => _send('disconnect', {'session': session});
  @override
  void joinChannel(int session, int channelId) =>
      _send('join_channel', {'session': session, 'channel_id': channelId});
  @override
  void leaveChannel(int session) =>
      _send('leave_channel', {'session': session});
  @override
  void sendMessage(int session, MessageTarget target, String text) => _send(
    'send_message',
    {'session': session, 'target': target.toJson(), 'text': text},
  );
  @override
  void moveClient(int session, int clientId, int channelId) => _send(
    'move_client',
    {'session': session, 'client_id': clientId, 'channel_id': channelId},
  );
  @override
  void poke(int session, int clientId, String message) => _send('poke', {
    'session': session,
    'client_id': clientId,
    'message': message,
  });
  @override
  void kick(int session, int clientId, KickScope scope, String? message) =>
      _send('kick', {
        'session': session,
        'client_id': clientId,
        'scope': scope.wire,
        'message': message,
      });
  @override
  void ban(int session, int clientId, BanDuration duration, String? reason) =>
      _send('ban', {
        'session': session,
        'client_id': clientId,
        'duration': duration.encoded,
        'reason': reason,
      });
  @override
  void screen(int session, Map<String, dynamic> command) =>
      _send('screen', {'session': session, 'command': command});

  @override
  void setAway(int session, {required bool away, String? message}) {
    _send('set_away', {'session': session, 'away': away, 'message': message});
  }

  @override
  void setClientVolume(int session, int clientId, double volume) => _send(
    'voice_set_client_volume',
    {'session': session, 'client_id': clientId, 'volume': volume},
  );
  @override
  void requestAudioDevices(String direction) {
    unawaited(
      voice
          .devices(direction)
          .then((devices) {
            _result(
              'audio_devices',
              data: {'direction': direction, 'devices': devices},
            );
          })
          .catchError((Object error) {
            _result(
              'audio_devices',
              error: 'Browser audio devices unavailable',
            );
          }),
    );
  }

  @override
  void voiceStart(int session, {String? inputDevice, String? outputDevice}) {
    if (_disposed) throw StateError('Transport disposed');
    final generation = ++_voiceGeneration;
    unawaited(
      voice
          .start(inputDevice: inputDevice, outputDevice: outputDevice)
          .then((_) {
            if (_disposed || generation != _voiceGeneration) return;
            _send('voice_start', {
              'session': session,
              'input': null,
              'output': null,
            });
          })
          .catchError((Object error) {
            if (!_disposed && generation == _voiceGeneration) {
              _result(
                'voice_start',
                error: 'Microphone unavailable. Allow microphone access and enable audio again.',
              );
            }
          }),
    );
  }

  @override
  void voiceStop() {
    _voiceGeneration++;
    voice.stop();
    _send('voice_stop');
  }

  @override
  void setInputMuted(bool muted) {
    _inputMuted = muted;
    voice.setInputMuted(muted);
    _send('voice_set_input_muted', {'muted': muted});
  }

  @override
  void setOutputMuted(bool muted) {
    _outputMuted = muted;
    voice.setOutputMuted(muted);
    _send('voice_set_output_muted', {'muted': muted});
  }

  @override
  void setPushToTalk(bool held) {
    _pttHeld = held;
    _send('voice_push_to_talk', {'held': held});
  }

  @override
  void requestVoiceStatus() => _send('voice_status');
  @override
  void testOutput() => voice.testOutput();
  @override
  void requestSettings() => _send('settings');
  @override
  void updateSettings(Settings settings) {
    _mode = settings.audio.mode;
    voice.setOutputVolume(settings.audio.outputVolume);
    _send('settings_update', settings.toJson());
  }

  @override
  void requestBookmarks() => _send('bookmarks');
  @override
  void updateBookmarks(BookmarkList bookmarks) =>
      _send('bookmarks_update', bookmarks.toJson());
  @override
  void addBookmark(NewBookmark bookmark) =>
      _send('bookmark_add', bookmark.toJson());
  @override
  void dispose() {
    if (_disposed) return;
    closeGateway();
    _disposed = true;
    _capture.cancel();
    _events.close();
    _states.close();
  }
}

extension on Completer<void> {
  void completeErrorIfPending(Object error) {
    if (!isCompleted) completeError(error);
  }
}
