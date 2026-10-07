import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:nightcord_client/core/screen/screen_share_backend.dart';
import 'package:nightcord_client/core/screen/webrtc_screen_backend.dart';

class _Connection implements RTCPeerConnection {
  @override
  void Function(RTCTrackEvent)? onTrack;
  @override
  void Function(RTCIceCandidate)? onIceCandidate;
  @override
  void Function(RTCIceGatheringState)? onIceGatheringState;
  @override
  void Function(RTCPeerConnectionState)? onConnectionState;
  int closes = 0;
  int disposes = 0;
  @override
  Future<void> close() async {
    closes++;
  }

  @override
  Future<void> dispose() async {
    disposes++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NegotiatingConnection extends _Connection {
  _NegotiatingConnection({this.bundle = true});
  final bool bundle;
  static const route = 'candidate:route';
  @override
  RTCIceGatheringState get iceGatheringState => bundle
      ? RTCIceGatheringState.RTCIceGatheringStateComplete
      : RTCIceGatheringState.RTCIceGatheringStateGathering;
  @override
  Future<void> setRemoteDescription(RTCSessionDescription description) async {}
  @override
  Future<RTCSessionDescription> createAnswer([
    Map<String, dynamic>? constraints,
  ]) async => RTCSessionDescription('v=0\r\n', 'answer');
  @override
  Future<void> setLocalDescription(RTCSessionDescription description) async {
    onIceCandidate!(RTCIceCandidate(route, '0', 0));
    if (bundle) {
      onIceGatheringState!(RTCIceGatheringState.RTCIceGatheringStateComplete);
    }
  }

  @override
  Future<RTCSessionDescription?> getLocalDescription() async =>
      RTCSessionDescription('v=0\r\n${bundle ? 'a=$route\r\n' : ''}', 'answer');
}

class _Track implements MediaStreamTrack {
  _Track(this.id, this.kind);
  @override
  final String id;
  @override
  final String kind;
  int stops = 0;
  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Stream implements MediaStream {
  final tracks = <MediaStreamTrack>[];
  final additions = <bool>[];
  Completer<void>? adding;
  bool rejectNative = false;
  int disposes = 0;
  @override
  List<MediaStreamTrack> getTracks() => tracks;
  @override
  Future<void> addTrack(
    MediaStreamTrack track, {
    bool addToNative = true,
  }) async {
    additions.add(addToNative);
    if (rejectNative && addToNative) throw StateError('remote stream is null');
    await adding?.future;
    tracks.add(track);
  }

  @override
  Future<void> dispose() async {
    disposes++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'native original SDP gains routes even when the SDK omits them',
    () async {
      // Native getLocalDescription returned the initial SDP without candidates.
      final pc = _NativeDescriptionConnection();
      final candidates = <Map<String, dynamic>>[];
      final peer = await WebRtcScreenBackend(createConnection: (_) async => pc)
          .peer(
            options: null,
            onCandidate: candidates.add,
            onMedia: (_) {},
            onFailed: () {},
          );
      expect(await peer.answer('offer'), contains('a=candidate:route\r\n'));
      expect(candidates, isEmpty);
      await peer.close();
    },
  );
  for (final bundle in [true, false]) {
    test(
      'gathered routes use SDP with safe slow-gather fallback ($bundle)',
      () async {
        // Per-route signaling flooded the server when windows were reopened.
        final pc = _NegotiatingConnection(bundle: bundle);
        final candidates = <Map<String, dynamic>>[];
        final backend = WebRtcScreenBackend(
          createConnection: (_) async => pc,
          iceGatherTimeout: Duration.zero,
        );
        final peer = await backend.peer(
          options: null,
          onCandidate: candidates.add,
          onMedia: (_) {},
          onFailed: () {},
        );
        final sdp = await peer.answer('offer');
        expect(sdp.contains('a=${_NegotiatingConnection.route}'), bundle);
        expect(candidates.length, bundle ? 0 : 1);
        pc.onIceCandidate!(
          RTCIceCandidate(_NegotiatingConnection.route, '0', 0),
        );
        expect(candidates.length, bundle ? 0 : 1);
        pc.onIceCandidate!(RTCIceCandidate('candidate:late', '0', 0));
        expect(candidates.last['candidate'], 'candidate:late');
        await peer.close();
      },
    );
  }
  test(
    'closing during ICE gathering cancels negotiation without signaling',
    () async {
      final pc = _NegotiatingConnection(bundle: false);
      final candidates = <Map<String, dynamic>>[];
      final peer = await WebRtcScreenBackend(createConnection: (_) async => pc)
          .peer(
            options: null,
            onCandidate: candidates.add,
            onMedia: (_) {},
            onFailed: () {},
          );
      final answering = peer.answer('offer');
      final rejected = expectLater(answering, throwsStateError);
      await _flush();
      await peer.close();
      await rejected;
      expect(candidates, isEmpty);
    },
  );
  test(
    'existing remote streams are never added to the native local stream map',
    () async {
      // The cascade used to call addTrack even with a supplied remote stream,
      // producing the logged MediaStreamAddTrack "stream is null" error.
      final pc = _Connection();
      final stream = _Stream()..rejectNative = true;
      final video = _Track('video', 'video');
      stream.tracks.add(video);
      final delivered = <ScreenMedia>[];
      var failures = 0;
      final backend = WebRtcScreenBackend(createConnection: (_) async => pc);
      final peer = await backend.peer(
        options: null,
        onCandidate: (_) {},
        onMedia: delivered.add,
        onFailed: () => failures++,
      );
      pc.onTrack!(RTCTrackEvent(streams: [stream], track: video));
      await _flush();
      expect(delivered.length, 1);
      expect(stream.additions, isEmpty);
      expect(failures, 0);
      pc.onTrack!(RTCTrackEvent(streams: [stream], track: video));
      await _flush();
      expect(delivered.length, 1);
      await peer.close();
      expect(video.stops, 0);
      expect(stream.disposes, 0);
      expect(pc.disposes, 1);
    },
  );

  test(
    'streamless audio and video share one stream and await native additions',
    () async {
      // Concurrent onTrack callbacks used to open two streams and publish them
      // before addTrack completed, leaving one unowned during a handover.
      final pc = _Connection();
      final stream = _Stream()..adding = Completer<void>();
      var creates = 0;
      final delivered = <ScreenMedia>[];
      final backend = WebRtcScreenBackend(
        createConnection: (_) async => pc,
        createStream: (_) async {
          creates++;
          return stream;
        },
      );
      final peer = await backend.peer(
        options: null,
        onCandidate: (_) {},
        onMedia: delivered.add,
        onFailed: () => fail('unexpected failure'),
      );
      pc.onTrack!(RTCTrackEvent(streams: [], track: _Track('audio', 'audio')));
      pc.onTrack!(RTCTrackEvent(streams: [], track: _Track('video', 'video')));
      await _flush();
      expect(creates, 1);
      expect(delivered, isEmpty);
      stream.adding!.complete();
      await _flush();
      expect(stream.tracks.length, 2);
      expect(delivered.length, 2);
      expect(identical(delivered.first, delivered.last), isTrue);
      await peer.close();
      await peer.close();
      expect(stream.disposes, 1);
      expect(pc.closes, 1);
    },
  );

  test(
    'closing a peer while its synthetic stream opens releases the late stream',
    () async {
      final pc = _Connection();
      final opening = Completer<MediaStream>();
      final backend = WebRtcScreenBackend(
        createConnection: (_) async => pc,
        createStream: (_) => opening.future,
      );
      final peer = await backend.peer(
        options: null,
        onCandidate: (_) {},
        onMedia: (_) => fail('closed peer must not deliver media'),
        onFailed: () {},
      );
      pc.onTrack!(RTCTrackEvent(streams: [], track: _Track('video', 'video')));
      await _flush();
      final closing = peer.close();
      final stream = _Stream();
      opening.complete(stream);
      await closing;
      expect(stream.disposes, 1);
      expect(stream.additions, isEmpty);
      expect(pc.disposes, 1);
    },
  );
}

class _NativeDescriptionConnection extends _NegotiatingConnection {
  @override
  Future<RTCSessionDescription?> getLocalDescription() async =>
      RTCSessionDescription(
        'v=0\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\na=mid:0\r\n',
        'answer',
      );
}
