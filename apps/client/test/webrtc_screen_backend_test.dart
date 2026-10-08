import 'dart:async';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:nightcord_client/core/screen/screen_share_backend.dart';
import 'package:nightcord_client/core/screen/webrtc_screen_backend.dart';
import 'package:nightcord_client/models/screen_options.dart';

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
  @override
  void Function()? onEnded;
  int stops = 0;
  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WgcTrack extends _Track {
  _WgcTrack() : super('wgc-track', 'video');
  @override
  Map<String, dynamic> getSettings() => {
    'captureBackend': 'windows-graphics-capture',
  };
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
  List<MediaStreamTrack> getVideoTracks() => [
    for (final track in tracks)
      if (track.kind == 'video') track,
  ];
  @override
  List<MediaStreamTrack> getAudioTracks() => [
    for (final track in tracks)
      if (track.kind == 'audio') track,
  ];
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
  for (final closeBeforeReply in [false, true]) {
    testWidgets('WGC failure ends capture once; late=$closeBeforeReply', (
      tester,
    ) async {
      // A native capture failure must end the share rather than leave a frozen
      // last frame. A health reply after disposal must not end a newer share.
      const channel = MethodChannel('FlutterWebRTC.Method');
      final reply = Completer<Map<String, dynamic>>();
      var reads = 0;
      MethodCall? request;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) {
        request = call;
        reads++;
        return reply.future;
      });
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
      });
      final track = _WgcTrack();
      final stream = _Stream()..tracks.add(track);
      final backend = WebRtcScreenBackend(getDisplayMedia: (_) async => stream);
      const options = ScreenOptions(
        source: ScreenSourceKind.screen,
        height: 0,
        fps: 60,
        videoBitrateKbps: 10000,
        audio: false,
        audioBitrateKbps: 128,
        access: ScreenAccess.public,
        viewerLimit: 0,
        mode: ScreenMode.p2p,
        detail: false,
      );
      final media = await backend.capture(null, options);
      var ended = 0;
      media.onEnded = () => ended++;
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(reads, 1);
      expect(request?.method, 'getScreenCaptureStats');
      expect(request?.arguments, {'trackId': 'wgc-track'});
      if (closeBeforeReply) await media.close();
      reply.complete({
        'running': false,
        'freshFrames': 10,
        'deliveredFrames': 20,
        'error': -1,
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
      expect(ended, closeBeforeReply ? 0 : 1);
      expect(reads, 1);
      await media.close();
      expect(track.stops, 1);
      expect(stream.disposes, 1);
    });
  }
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

  test('unknown capture size fails and releases all captured tracks', () async {
    // A missing source height must not silently bypass the selected 1080p cap.
    final stream = _Stream();
    final video = _Track('video-1', 'video');
    stream.tracks.add(video);
    final backend = WebRtcScreenBackend(
      getDisplayMedia: (_) async => stream,
      measureCaptureHeight: (_) async => null,
    );
    const options = ScreenOptions(
      source: ScreenSourceKind.screen,
      height: 1080,
      fps: 30,
      videoBitrateKbps: 4000,
      audio: false,
      audioBitrateKbps: 128,
      access: ScreenAccess.public,
      viewerLimit: 0,
      mode: ScreenMode.p2p,
      detail: false,
    );
    await expectLater(backend.capture(null, options), throwsStateError);
    expect(video.stops, 1);
    expect(stream.disposes, 1);
  });

  test(
    'the offer carries the capture sound and steers it apart from the picture',
    () async {
      // The offer used to add only video tracks: "capture audio" reached the
      // capture and the server and never the connection between them. The
      // audio sender gets a bitrate cap and nothing else — a degradation
      // preference is the picture's business.
      final pc = _OfferConnection();
      final stream = _Stream();
      final video = _Track('video-1', 'video');
      final audio = _Track('audio-1', 'audio');
      stream.tracks.addAll([video, audio]);
      const options = ScreenOptions(
        source: ScreenSourceKind.screen,
        height: 1080,
        fps: 30,
        videoBitrateKbps: 2500,
        audio: true,
        audioBitrateKbps: 96,
        access: ScreenAccess.public,
        viewerLimit: 0,
        mode: ScreenMode.p2p,
        detail: false,
      );
      final backend = WebRtcScreenBackend(
        createConnection: (_) async => pc,
        getDisplayMedia: (_) async => stream,
        // Native desktop track settings omit height. Without measuring the
        // source before the offer, a 1080p selection sent the full 4K screen.
        measureCaptureHeight: (_) async => 2160,
      );
      final media = await backend.capture(null, options);
      expect(media.hasAudio, isTrue);
      final peer = await backend.peer(
        options: options,
        onCandidate: (_) {},
        onMedia: (_) {},
        onFailed: () {},
      );
      await peer.offer(media);
      expect(pc.added, [video, audio]);
      final picture = pc.made[0].parameters.encodings!.single;
      final sound = pc.made[1].parameters.encodings!.single;
      expect(picture.maxBitrate, 2500 * 1000);
      expect(picture.scaleResolutionDownBy, 2.0);
      expect(sound.maxBitrate, 96 * 1000);
      expect(
        pc.made[0].parameters.degradationPreference,
        RTCDegradationPreference.MAINTAIN_RESOLUTION,
      );
      expect(pc.made[1].parameters.degradationPreference, isNull);
      // The codec list is trimmed before the offer is built: the untrimmed one
      // is what pushed a two-track offer past the server's command ceiling and
      // made the whole respond vanish (2026-10-08).
      expect(pc.codecTargets[0].preferences?.map((c) => c.mimeType), [
        'video/VP8',
        'video/rtx',
      ]);
      expect(pc.codecTargets[1].preferences?.map((c) => c.mimeType), [
        'audio/opus',
      ]);
      await peer.close();
    },
  );

  for (final source in ScreenSourceKind.values) {
    test('30 fps $source uses the appropriate adaptation preference', () async {
      // Screen sharing stayed at 378x244 after bandwidth recovered. Preserve
      // its resolution without changing the user's 30 fps / 6 Mbps settings.
      final pc = _OfferConnection();
      final stream = _Stream()..tracks.add(_Track('video-1', 'video'));
      final backend = WebRtcScreenBackend(
        createConnection: (_) async => pc,
        getDisplayMedia: (_) async => stream,
        measureCaptureHeight: (_) async => 982,
      );
      final options = ScreenOptions(
        source: source,
        height: 1440,
        fps: 30,
        videoBitrateKbps: 6000,
        audio: false,
        audioBitrateKbps: 128,
        access: ScreenAccess.public,
        viewerLimit: 0,
        mode: ScreenMode.p2p,
        detail: false,
      );
      // Reuse a captured video track to test sender configuration independently
      // of platform camera permissions and display pickers.
      final media = await backend.capture(
        null,
        options.copyWith(source: ScreenSourceKind.screen),
      );
      final peer = await backend.peer(
        options: options,
        onCandidate: (_) {},
        onMedia: (_) {},
        onFailed: () {},
      );
      await peer.offer(media);
      expect(
        pc.made.single.parameters.degradationPreference,
        source == ScreenSourceKind.camera
            ? RTCDegradationPreference.MAINTAIN_FRAMERATE
            : RTCDegradationPreference.MAINTAIN_RESOLUTION,
      );
      expect(pc.made.single.parameters.encodings!.single.maxBitrate, 6000000);
      expect(
        pc.made.single.parameters.encodings!.single.scaleResolutionDownBy,
        1.0,
      );
      await peer.close();
      await media.close();
    });
  }
}

class _NativeDescriptionConnection extends _NegotiatingConnection {
  @override
  Future<RTCSessionDescription?> getLocalDescription() async =>
      RTCSessionDescription(
        'v=0\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\na=mid:0\r\n',
        'answer',
      );
}

class _Sender implements RTCRtpSender {
  _Sender(this.track);

  @override
  String get senderId => track!.id!;

  @override
  final MediaStreamTrack? track;

  @override
  RTCRtpParameters parameters = RTCRtpParameters(encodings: [RTCRtpEncoding()]);

  @override
  Future<bool> setParameters(RTCRtpParameters params) async {
    parameters = params;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Transceiver implements RTCRtpTransceiver {
  _Transceiver(this.sender);

  @override
  final RTCRtpSender sender;

  List<RTCRtpCodecCapability>? preferences;

  @override
  Future<void> setCodecPreferences(List<RTCRtpCodecCapability> codecs) async {
    preferences = codecs;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A connection that hands back a sender per added track, so what the offer
/// does to each of them can be read back.
class _OfferConnection extends _NegotiatingConnection {
  final added = <MediaStreamTrack>[];
  final made = <_Sender>[];
  final codecTargets = <_Transceiver>[];

  @override
  Future<List<RTCRtpSender>> getSenders() async => made;

  @override
  Future<RTCRtpSender> addTrack(
    MediaStreamTrack track, [
    MediaStream? stream,
  ]) async {
    added.add(track);
    final sender = _Sender(track);
    made.add(sender);
    codecTargets.add(_Transceiver(sender));
    return sender;
  }

  @override
  Future<List<RTCRtpTransceiver>> getTransceivers() async => codecTargets;

  @override
  Future<RTCSessionDescription> createOffer([
    Map<String, dynamic>? constraints,
  ]) async => RTCSessionDescription('v=0\r\n', 'offer');
}
