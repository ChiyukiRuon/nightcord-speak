import 'dart:typed_data';

/// Browser audio stays below the transport boundary, just like native PCM.
abstract interface class VoiceBackend {
  Future<void> start({String? inputDevice, String? outputDevice});
  void stop();
  void play(Uint8List frame);
  void setInputMuted(bool muted);
  void setOutputMuted(bool muted);
  void setOutputVolume(double volume);
  void testOutput();
  Future<List<Map<String, dynamic>>> devices(String direction);
  Map<String, dynamic> get status;
  Stream<Uint8List> get captured;
}
