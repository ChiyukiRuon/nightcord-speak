import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Reads a frame before any sender can adapt its size. Desktop track settings
/// omit dimensions, and outbound statistics have already been downscaled.
Future<int?> screenCaptureHeight(
  MediaStream stream, {
  RTCVideoRenderer Function()? createRenderer,
  Duration timeout = const Duration(seconds: 3),
}) async {
  final renderer = (createRenderer ?? RTCVideoRenderer.new)();
  final measured = Completer<int>();
  var initialized = false;
  void readSize() {
    if (!measured.isCompleted && renderer.videoHeight > 0) {
      measured.complete(renderer.videoHeight);
    }
  }

  try {
    await renderer.initialize();
    initialized = true;
    renderer.onResize = readSize;
    renderer.onFirstFrameRendered = readSize;
    renderer.srcObject = stream;
    readSize();
    return await measured.future.timeout(timeout);
  } finally {
    renderer.onResize = null;
    renderer.onFirstFrameRendered = null;
    if (initialized) {
      renderer.srcObject = null;
      await renderer.dispose();
    }
  }
}
