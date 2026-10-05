import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'remote_socket.dart';

class BrowserSocket implements RemoteSocket {
  BrowserSocket(Uri uri) : _socket = web.WebSocket(uri.toString()) {
    _socket.binaryType = 'arraybuffer';
    _socket.onopen = ((web.Event event) {
      if (!_opened.isCompleted) _opened.complete();
    }).toJS;
    _socket.onmessage = ((web.MessageEvent event) {
      final data = event.data;
      if (data.isA<JSString>()) {
        _messages.add((data as JSString).toDart);
      } else if (data.isA<JSArrayBuffer>()) {
        _messages.add((data as JSArrayBuffer).toDart.asUint8List());
      }
    }).toJS;
    _socket.onerror = ((web.Event event) {
      if (!_opened.isCompleted) {
        _opened.completeError(StateError('Gateway unreachable'));
      }
      _messages.addError(StateError('Gateway unreachable'));
    }).toJS;
    _socket.onclose = ((web.CloseEvent event) {
      if (!_opened.isCompleted) {
        _opened.completeError(StateError('Gateway closed'));
      }
      _messages.close();
    }).toJS;
  }

  final web.WebSocket _socket;
  final _messages = StreamController<Object>();
  final _opened = Completer<void>();
  @override
  Stream<Object> get messages => _messages.stream;
  @override
  Future<void> get opened => _opened.future;
  @override
  int get bufferedAmount => _socket.bufferedAmount;
  @override
  void sendText(String text) => _socket.send(text.toJS);
  @override
  void sendBinary(Uint8List bytes) => _socket.send(bytes.toJS);
  @override
  void close() => _socket.close();
}
