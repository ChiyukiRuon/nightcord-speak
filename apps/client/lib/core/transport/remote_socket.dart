import 'dart:typed_data';

/// A socket adapter that lets authentication and command mapping be tested.
abstract interface class RemoteSocket {
  Stream<Object> get messages;
  Future<void> get opened;
  int get bufferedAmount;
  void sendText(String text);
  void sendBinary(Uint8List bytes);
  void close();
}
