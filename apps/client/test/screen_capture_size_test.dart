import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:nightcord_client/core/screen/screen_capture_size.dart';

class _Stream implements MediaStream {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Renderer implements RTCVideoRenderer {
  _Renderer({this.deliverFrame = true});
  final bool deliverFrame;
  @override
  Function? onResize;
  @override
  Function? onFirstFrameRendered;
  @override
  int videoHeight = 0;
  MediaStream? attached;
  bool disposed = false;
  @override
  Future<void> initialize() async {}
  @override
  set srcObject(MediaStream? stream) {
    attached = stream;
    if (stream != null && deliverFrame) {
      videoHeight = 2160;
      onResize?.call();
    }
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'reads the first raw frame and releases the temporary renderer',
    () async {
      // Desktop getSettings omitted height, leaving 1080p shares at full 4K.
      final renderer = _Renderer();
      expect(
        await screenCaptureHeight(_Stream(), createRenderer: () => renderer),
        2160,
      );
      expect(renderer.disposed, isTrue);
      expect(renderer.attached, isNull);
      expect(renderer.onResize, isNull);
    },
  );
  test(
    'a source without frames times out and still releases the renderer',
    () async {
      final renderer = _Renderer(deliverFrame: false);
      await expectLater(
        screenCaptureHeight(
          _Stream(),
          createRenderer: () => renderer,
          timeout: Duration.zero,
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(renderer.disposed, isTrue);
      expect(renderer.attached, isNull);
    },
  );
}
