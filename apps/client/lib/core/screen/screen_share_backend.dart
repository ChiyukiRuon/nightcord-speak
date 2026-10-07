import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../models/screen_options.dart';

class ScreenSource {
  const ScreenSource(this.id, this.name, {this.kind = ScreenSourceKind.screen, this.thumbnail});
  final String id;
  final String name;

  /// A still of this source, encoded PNG or JPEG, when the platform offers one.
  ///
  /// The picker shows these instead of opening a capture per source: a live
  /// preview means a second capture running for as long as the dialog is open,
  /// and the question being answered here is "which one of these is it", which
  /// a still answers.
  final Uint8List? thumbnail;

  /// What this endpoint is a handle on. The picker groups by it, and it is what
  /// the server is told the stream is.
  final ScreenSourceKind kind;
}

abstract interface class ScreenMedia {
  Widget view();
  set onEnded(void Function() callback);
  Future<void> close();
}

abstract interface class ScreenPeer {
  Future<String> offer(ScreenMedia media);
  Future<String> answer(String sdp);
  Future<void> acceptAnswer(String sdp);
  Future<void> candidate(Map<String, dynamic> candidate);
  Future<void> close();

  /// What the encoder is producing right now, or null when this peer is not
  /// sending anything — a viewer has nothing to report.
  ///
  /// Pulled rather than pushed, like the microphone level: the number is only
  /// wanted while someone is looking at it, and a publisher that is not on
  /// screen should not be running a statistics callback at all.
  Future<ScreenStats?> stats();
}

/// What a publisher is actually sending.
class ScreenStats {
  const ScreenStats(this.width, this.height, this.fps, this.limitedBy);

  final int width;
  final int height;
  final double fps;

  /// What is holding the picture back: `bandwidth`, `cpu`, `other`, or `none`.
  ///
  /// The whole reason this exists. "The frame rate is low" has unrelated
  /// causes — a low bandwidth estimate scales the picture down, a busy machine
  /// cannot encode what it captured, and a capture that is not producing frames
  /// shows up as neither — and this is the only thing that tells them apart.
  final String? limitedBy;

  @override
  String toString() => '${width}x$height ${fps.toStringAsFixed(1)}fps'
      '${limitedBy == null ? '' : ' ($limitedBy)'}';

  // Compared by value so the poll can tell "the reading changed" from "the
  // same reading arrived again" — it runs once a second for as long as a share
  // lasts, and rebuilding the window on an identical number is pure churn.
  @override
  bool operator ==(Object other) =>
      other is ScreenStats &&
      other.width == width &&
      other.height == height &&
      other.fps == fps &&
      other.limitedBy == limitedBy;

  @override
  int get hashCode => Object.hash(width, height, fps, limitedBy);
}

/// Owns platform media; UI and session state never inspect operating systems.
abstract interface class ScreenShareBackend {
  Future<List<ScreenSource>> sources();

  /// Opens this source for *looking* at rather than for sharing.
  ///
  /// Its own method because a preview is not a share: no encoder is configured,
  /// nothing goes on the wire, and none of the publisher's choices apply. The
  /// picker wants the picture, at whatever rate is enough to recognise a window
  /// by, and no sound — the shared window's audio coming out of the chooser's
  /// own speakers would be a strange thing for a dialog to do.
  ///
  /// Desktop implementations use thumbnails to avoid focusing the selected
  /// window. A missing thumbnail must not fall back to a focusing capture.
  Future<ScreenMedia> preview(ScreenSource source);

  Future<ScreenMedia> capture(ScreenSource? source, ScreenOptions options);
  Future<ScreenPeer> peer({
    required void Function(Map<String, dynamic>) onCandidate,
    required void Function(ScreenMedia) onMedia,
    required void Function() onFailed,
    /// Null when watching: the encoder settings belong to whoever publishes,
    /// and a viewer never offers anything for them to apply to.
    required ScreenOptions? options,
  });
}
