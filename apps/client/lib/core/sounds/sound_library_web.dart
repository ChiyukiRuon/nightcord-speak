import 'dart:js_interop';

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

import 'bundled_sound_library.dart';
import 'sound_pack.dart';

Future<String?> chooseSoundDirectory() async => null;

SoundLibrary createSoundLibrary({String directory = ''}) =>
    BundledSoundLibrary(playAsset: _playAsset);

Future<void> _playAsset(String asset, double volume) async {
  final data = await rootBundle.load(asset);
  final blob = web.Blob(
    [data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes).toJS].toJS,
    web.BlobPropertyBag(type: 'audio/wav'),
  );
  final url = web.URL.createObjectURL(blob);
  final audio = web.HTMLAudioElement()
    ..src = url
    ..volume = volume;
  void release(web.Event _) => web.URL.revokeObjectURL(url);
  audio.addEventListener(
    'ended',
    release.toJS,
    web.AddEventListenerOptions(once: true),
  );
  audio.addEventListener(
    'error',
    release.toJS,
    web.AddEventListenerOptions(once: true),
  );
  try {
    await audio.play().toDart;
  } catch (_) {
    web.URL.revokeObjectURL(url);
    rethrow;
  }
}
