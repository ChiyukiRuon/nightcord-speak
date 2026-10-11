import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../../models/bookmarks.dart';
import '../../models/connect_request.dart';
import '../../models/domain.dart';
import '../../models/events.dart';
import '../../models/settings.dart';
import '../voice/voice_backend.dart';
import 'client_transport.dart';
import '../../models/shortcuts.dart';
import 'remote_socket.dart';
import 'device_store.dart';
import 'bookmark_store.dart';

enum GatewayState { disconnected, connecting, ready }

/// The same command/event vocabulary as FFI, carried over an authenticated socket.
class RemoteTransport implements ClientTransport {
  RemoteTransport({
    required this.socketFactory,
    required this.voice,
    DeviceStore? deviceStore,
    this.bookmarkStore,
  }) : deviceStore = deviceStore ?? MemoryDeviceStore() {
    _bookmarkChanges = bookmarkStore?.changes.listen((_) => requestBookmarks());
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
  final BookmarkStore? bookmarkStore;
  StreamSubscription<void>? _bookmarkChanges;
  String? _migrationGateway;
  final _bookmarkRequests = <String, Timer>{};
  final _bookmarkPrefix = List.generate(
    4,
    (_) =>
        Random.secure().nextInt(0x100000000).toRadixString(16).padLeft(8, '0'),
  ).join();
  int _bookmarkSequence = 0;
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
    _migrationGateway = null;
    for (final timer in _bookmarkRequests.values) {
      timer.cancel();
      _result('bookmark_add', error: 'gateway_connect_first');
    }
    _bookmarkRequests.clear();
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
          _migrateBookmarks();
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
            _result('gateway', error: 'gateway_command_rejected');
          }
        default:
          if (state == GatewayState.ready) {
            var event = FfiEvent.fromJson(json);
            if (event is CommandResultEvent &&
                _receiveBookmarks(event.result)) {
              return;
            }
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
      _result('gateway', error: 'gateway_invalid_response');
    }
  }

  void _send(String command, [Object? payload]) {
    if (_disposed) throw StateError('Transport disposed');
    if (state != GatewayState.ready) {
      _result(command, error: 'gateway_connect_first');
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
            error: error == null ? null : ClientError(kind: error),
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
  void getAvatar(int session, int clientId) =>
      _send('get_avatar', {'session': session, 'client_id': clientId});

  @override
  void setNickname(int session, String nickname) =>
      _send('set_nickname', {'session': session, 'nickname': nickname});

  @override
  void setAvatar(int session, String? image, {Map<String, dynamic>? edit}) =>
      _send('set_avatar', {'session': session, 'image': image, 'edit': edit});

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
              error: 'browser_audio_devices_unavailable',
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
              _result('voice_start', error: 'browser_microphone_unavailable');
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
  void resetShortcut(ShortcutAction action) =>
      _send('reset_shortcuts', {'action': action.wire});
  @override
  void updateSettings(Settings settings) {
    _mode = settings.audio.mode;
    voice.setOutputVolume(settings.audio.outputVolume);
    _send('settings_update', settings.toJson());
  }

  @override
  void requestBookmarks() {
    if (_disposed) throw StateError('Transport disposed');
    final store = bookmarkStore;
    if (store == null) {
      _send('bookmarks');
      return;
    }
    try {
      _result('bookmarks', data: StoredBookmarks.read(store).list.toJson());
    } catch (_) {
      _result('bookmarks', error: 'browser_bookmarks_unavailable');
    }
  }

  @override
  void updateBookmarks(BookmarkList bookmarks) {
    if (_disposed) throw StateError('Transport disposed');
    final store = bookmarkStore;
    if (store == null) {
      _send('bookmarks_update', bookmarks.toJson());
      return;
    }
    try {
      final saved = StoredBookmarks.read(store);
      StoredBookmarks(list: bookmarks, migrated: saved.migrated).save(store);
      _result('bookmarks_update');
      requestBookmarks();
    } catch (_) {
      _result('bookmarks_update', error: 'browser_bookmarks_unavailable');
      // Undo the provider's optimistic edit with the last persisted list.
      requestBookmarks();
    }
  }

  @override
  void addBookmark(NewBookmark bookmark) {
    if (_disposed) throw StateError('Transport disposed');
    if (bookmarkStore == null) {
      _send('bookmark_add', bookmark.toJson());
      return;
    }
    if (state != GatewayState.ready) {
      _result('bookmark_add', error: 'gateway_connect_first');
      return;
    }
    final id = '$_bookmarkPrefix.${++_bookmarkSequence}';
    _bookmarkRequests[id] = Timer(const Duration(seconds: 15), () {
      _bookmarkRequests.remove(id);
      _result('bookmark_add', error: 'timeout');
    });
    _send('bookmark_prepare', {
      'request_id': id,
      'bookmark': bookmark.toJson(),
    });
  }

  void _migrateBookmarks() {
    final store = bookmarkStore;
    if (store == null) return;
    try {
      final gateway = _gateway.toString();
      if (!StoredBookmarks.read(store).migrated.contains(gateway)) {
        _migrationGateway = gateway;
        _send('bookmarks');
      }
    } catch (_) {
      _result('bookmarks', error: 'browser_bookmarks_unavailable');
    }
  }

  bool _receiveBookmarks(CommandResult result) {
    final store = bookmarkStore;
    if (store == null) return false;
    if (result.command == 'bookmarks') {
      final gateway = _migrationGateway;
      _migrationGateway = null;
      if (gateway != null && result.ok && result.data != null) {
        try {
          final saved = StoredBookmarks.read(store);
          if (!saved.migrated.contains(gateway)) {
            var list = saved.list;
            for (final bookmark in BookmarkList.fromJson(
              result.data!,
            ).bookmarks) {
              if (!list.bookmarks.any(
                (entry) =>
                    entry.host == bookmark.host && entry.port == bookmark.port,
              )) {
                list = list.upsert(bookmark);
              }
            }
            StoredBookmarks(
              list: list,
              migrated: {...saved.migrated, gateway},
            ).save(store);
          }
          requestBookmarks();
        } catch (_) {
          _result('bookmarks', error: 'browser_bookmarks_unavailable');
        }
      }
      // Gateway snapshots must never replace browser-owned bookmarks.
      return true;
    }
    if (result.command == 'bookmark_add' ||
        result.command == 'bookmarks_update') {
      return true;
    }
    if (result.command != 'bookmark_prepare') return false;
    final timer = _bookmarkRequests.remove(result.data?['request_id']);
    if (timer == null) return true;
    timer.cancel();
    if (!result.ok) {
      _emit(
        CommandResultEvent(
          CommandResult(
            command: 'bookmark_add',
            session: null,
            outcome: result.outcome,
          ),
        ),
      );
      return true;
    }
    try {
      final saved = StoredBookmarks.read(store);
      final data = result.data!;
      final bookmark = Bookmark.fromJson(
        (data['bookmark'] as Map).cast<String, dynamic>(),
      );
      final replaces = data['replaces'] as Map?;
      var list = saved.list;
      if (replaces != null &&
          (replaces['host'] != bookmark.host ||
              replaces['port'] != bookmark.port)) {
        list = BookmarkList(
          bookmarks: list.bookmarks
              .where(
                (entry) =>
                    entry.host != replaces['host'] ||
                    entry.port != replaces['port'],
              )
              .toList(),
        );
      }
      list = list.upsert(bookmark);
      StoredBookmarks(list: list, migrated: saved.migrated).save(store);
      _result('bookmark_add', data: list.toJson());
    } catch (_) {
      _result('bookmark_add', error: 'browser_bookmarks_unavailable');
    }
    return true;
  }

  @override
  void dispose() {
    if (_disposed) return;
    closeGateway();
    _disposed = true;
    _bookmarkChanges?.cancel();
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
