// A typed Dart handle on the Rust core.
//
// Everything above this file works with Dart objects and a `Stream<FfiEvent>`;
// nothing else in the app touches `dart:ffi`, pointer lifetimes, or JSON.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../models/domain.dart';
import '../models/events.dart';
import 'bindings.dart';
import 'native.dart';

/// Everything needed to open a connection.
///
/// Mirrors `ts_core::ConnectRequest`. The identity is deliberately absent: the
/// core owns it, loads it from disk, and never hands key material out (§31).
class ConnectRequest {
  const ConnectRequest({
    required this.address,
    required this.nickname,
    this.profile = 'default',
    this.serverPassword,
    this.channelPassword,
    this.privilegeKey,
    this.defaultChannel,
    this.protocol = ProtocolKind.ts3,
  });

  /// `host`, `host:port`, `ts3://host` or `[::1]:9987`.
  final String address;

  final String nickname;

  /// Identity profile. The same profile presents the same client to every
  /// server, which is what a user expects of "their" identity.
  final String profile;

  final String? serverPassword;
  final String? channelPassword;
  final String? privilegeKey;
  final String? defaultChannel;
  final ProtocolKind protocol;

  Map<String, dynamic> toJson() => {
    'address': address,
    'nickname': nickname,
    'profile': profile,
    if (serverPassword != null && serverPassword!.isNotEmpty)
      'server_password': serverPassword,
    if (channelPassword != null && channelPassword!.isNotEmpty)
      'channel_password': channelPassword,
    if (privilegeKey != null && privilegeKey!.isNotEmpty) 'privilege_key': privilegeKey,
    if (defaultChannel != null && defaultChannel!.isNotEmpty)
      'default_channel': defaultChannel,
    'protocol': protocol.wire,
  };
}

/// How often the core is polled for events.
///
/// Around one frame at 60 Hz. Polling is a lock, a drain, and a JSON decode of
/// whatever accumulated, so doing it more often buys nothing.
const Duration _pollInterval = Duration(milliseconds: 16);

/// A running Rust core.
class RustClient {
  RustClient._(this._bindings, this._handle) {
    // Polling begins only once something is listening.
    //
    // The core hands events over exactly once — `poll_events` drains the queue —
    // so a timer that ran regardless would consume results into a stream nobody
    // was reading, and a caller asking the core a direct question would wait
    // forever for an answer that had already been thrown away.
    _events = StreamController<FfiEvent>.broadcast(
      onListen: _startPolling,
      onCancel: _stopPolling,
    );
  }

  /// Starts the core.
  ///
  /// Throws [NativeLibraryNotFound] if the shared library is missing, which is
  /// a build problem rather than something to recover from at runtime.
  factory RustClient.start() {
    final bindings = NativeLibrary.load();
    final handle = bindings.create();
    if (handle == nullptr) {
      throw StateError(
        'The Nightcord core refused to start. It could not determine where to '
        'store identities.',
      );
    }
    return RustClient._(bindings, handle);
  }

  final NightcordBindings _bindings;
  final Handle _handle;

  late final StreamController<FfiEvent> _events;
  Timer? _pollTimer;
  bool _disposed = false;

  /// Everything the core has to say, as it happens.
  Stream<FfiEvent> get events => _events.stream;

  /// The core's version, for the about box and for spotting a stale library
  /// next to the executable.
  String get version => _bindings.version().toDartString();

  /// Opens a connection. The session handle arrives as a `connect`
  /// [CommandResult].
  void connect(ConnectRequest request) =>
      _withJson(request.toJson(), (json) => _bindings.connect(_handle, json));

  /// Closes a connection.
  void disconnect(int session) => _bindings.disconnect(_handle, session);

  /// Moves us into a channel.
  void joinChannel(int session, int channelId) =>
      _bindings.joinChannel(_handle, session, channelId);

  /// Returns to the server's default channel.
  void leaveChannel(int session) => _bindings.leaveChannel(_handle, session);

  /// Sends a chat message.
  void sendMessage(int session, MessageTarget target, String text) {
    _withJson(
      target.toJson(),
      (json) => _withText(text, (body) => _bindings.sendMessage(_handle, session, json, body)),
    );
  }

  /// Moves another client into a channel.
  void moveClient(int session, int clientId, int channelId) =>
      _bindings.moveClient(_handle, session, clientId, channelId);

  /// Asks for the audio devices for `"input"` or `"output"`.
  ///
  /// The answer arrives as a `audio_devices` [CommandResult] whose `data` holds
  /// `{"direction": ..., "devices": [...]}`.
  void requestAudioDevices(String direction) =>
      _withText(direction, (text) => _bindings.audioDevices(_handle, text));

  /// Opens audio devices and binds voice to a session.
  ///
  /// A null device id selects the system default.
  void voiceStart(int session, {String? inputDevice, String? outputDevice}) {
    _withText(inputDevice ?? '', (input) {
      _withText(outputDevice ?? '', (output) {
        _bindings.voiceStart(_handle, session, input, output);
      });
    });
  }

  /// Closes the audio devices.
  void voiceStop() => _bindings.voiceStop(_handle);

  /// Sets how transmission is triggered.
  void setVoiceMode(VoiceActivationMode mode) =>
      _withText(mode.wire, (text) => _bindings.voiceSetMode(_handle, text));

  /// Mutes or unmutes the microphone.
  void setInputMuted(bool muted) => _bindings.voiceSetInputMuted(_handle, muted);

  /// Mutes or unmutes the speakers.
  void setOutputMuted(bool muted) => _bindings.voiceSetOutputMuted(_handle, muted);

  /// Push-to-talk key down or up (§30).
  void setPushToTalk(bool held) => _bindings.voicePushToTalk(_handle, held);

  /// Drains whatever is queued right now.
  ///
  /// Private on purpose: the core releases each event exactly once, so a second
  /// consumer would silently steal results. [events] is the only reader.
  List<FfiEvent> _poll() {
    if (_disposed) return const [];

    final raw = _bindings.pollEvents(_handle);
    try {
      final text = raw.toDartString();
      if (text == '[]' || text.isEmpty) return const [];
      final decoded = jsonDecode(text) as List<dynamic>;
      return decoded
          .map((entry) => FfiEvent.fromJson((entry as Map).cast<String, dynamic>()))
          .toList(growable: false);
    } on FormatException catch (error) {
      // The core produced something we cannot read, which is a bug in the core
      // rather than in the user's data. Surfacing it as an error event keeps a
      // single failure path.
      return [
        CommandResultEvent(
          CommandResult(
            command: 'poll_events',
            session: null,
            outcome: CommandOutcome(
              ok: false,
              error: ClientError(kind: 'protocol', message: '无法解析事件：$error'),
            ),
          ),
        ),
      ];
    } finally {
      // Always freed, including on the decode failure above: the core handed
      // ownership over and expects it back.
      _bindings.freeString(raw);
    }
  }

  /// Stops the core and releases the library handle.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stopPolling();
    _events.close();
    _bindings.destroy(_handle);
  }

  void _startPolling() {
    if (_disposed) return;
    _pollTimer ??= Timer.periodic(_pollInterval, (_) => _drain());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _drain() {
    if (_disposed || _events.isClosed) return;
    for (final event in _poll()) {
      _events.add(event);
    }
  }

  /// Passes a JSON string to `call` and frees it afterwards.
  void _withJson(Map<String, dynamic> value, void Function(Pointer<Utf8>) call) {
    _withText(jsonEncode(value), call);
  }

  /// Passes a text string to `call` and frees it afterwards.
  ///
  /// The allocation is ours until `call` returns; the core copies anything it
  /// needs, so freeing immediately is correct rather than premature.
  void _withText(String value, void Function(Pointer<Utf8>) call) {
    final pointer = value.toNativeUtf8();
    try {
      call(pointer);
    } finally {
      calloc.free(pointer);
    }
  }
}
