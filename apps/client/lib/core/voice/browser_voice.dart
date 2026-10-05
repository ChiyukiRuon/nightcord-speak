import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'voice_backend.dart';

@JS('NightcordAudio')
extension type _Audio._(JSObject _) implements JSObject {
  external factory _Audio(JSFunction onFrame);
  external JSPromise<JSAny?> start(JSString? input, JSString? output);
  external void stop();
  external void play(JSUint8Array frame);
  external void mute(JSBoolean muted);
  external void inputMute(JSBoolean muted);
  external void volume(JSNumber value);
  external void test();
  external JSString status();
  external JSPromise<JSString> devices(JSString direction);
}

/// Web Audio runs on the browser's render clock; only framed PCM reaches Dart.
class BrowserVoice implements VoiceBackend {
  BrowserVoice() {
    _audio = _Audio(
      ((JSUint8Array frame) {
        _frames.add(frame.toDart);
      }).toJS,
    );
  }
  late final _Audio _audio;
  final _frames = StreamController<Uint8List>.broadcast();
  @override
  Stream<Uint8List> get captured => _frames.stream;
  @override
  Future<void> start({String? inputDevice, String? outputDevice}) async {
    await _audio.start(inputDevice?.toJS, outputDevice?.toJS).toDart;
  }

  @override
  void stop() => _audio.stop();
  @override
  void play(Uint8List frame) => _audio.play(frame.toJS);
  @override
  void setOutputMuted(bool muted) => _audio.mute(muted.toJS);
  @override
  void setInputMuted(bool muted) => _audio.inputMute(muted.toJS);
  @override
  void setOutputVolume(double volume) => _audio.volume(volume.toJS);
  @override
  void testOutput() => _audio.test();
  @override
  Map<String, dynamic> get status =>
      (jsonDecode(_audio.status().toDart) as Map).cast<String, dynamic>();
  @override
  Future<List<Map<String, dynamic>>> devices(String direction) async {
    final json = await _audio.devices(direction.toJS).toDart;
    return (jsonDecode(json.toDart) as List)
        .map((entry) => (entry as Map).cast<String, dynamic>())
        .toList();
  }
}
