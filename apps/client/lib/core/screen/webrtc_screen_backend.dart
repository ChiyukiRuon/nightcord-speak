import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../models/screen_options.dart';
import '../platform/services.dart';
import 'screen_share_backend.dart';
import 'screen_sdp.dart';

/// How often the publisher says what it is actually sending.
///
/// Frame rate and resolution are what the other side is looking at, and
/// `qualityLimitationReason` is what is holding them back — `bandwidth`, `cpu`
/// or nothing at all. Without this line, "it looks choppy" has no answer in the
/// log at all, which is the same gap the audio pipeline had before it grew one.
const Duration _statsEvery = Duration(seconds: 10);

class WebRtcScreenBackend implements ScreenShareBackend {
  WebRtcScreenBackend({
    Future<RTCPeerConnection> Function(Map<String, dynamic>)? createConnection,
    Future<MediaStream> Function(String)? createStream,
    Future<MediaStream> Function(Map<String, dynamic>)? getDisplayMedia,
    this.iceGatherTimeout = const Duration(seconds: 2),
  }) : _createConnection = createConnection ?? createPeerConnection,
       _createStream = createStream ?? createLocalMediaStream,
       _getDisplayMedia = getDisplayMedia ?? _platformDisplayMedia;

  final Future<RTCPeerConnection> Function(Map<String, dynamic>)
  _createConnection;
  final Future<MediaStream> Function(String) _createStream;

  /// The platform's own picker. A seam like the other two injections.
  final Future<MediaStream> Function(Map<String, dynamic>) _getDisplayMedia;
  final Duration iceGatherTimeout;
  bool get _desktop =>
      !kIsWeb &&
      const {
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      }.contains(defaultTargetPlatform);

  @override
  Future<List<ScreenSource>> sources() async {
    final sources = <ScreenSource>[];

    if (_desktop) {
      final desktop = await desktopCapturer.getSources(
        types: [SourceType.Screen, SourceType.Window],
      );
      sources.addAll([
        for (final source in desktop)
          ScreenSource(
            source.id,
            source.name,
            kind: source.type == SourceType.Window
                ? ScreenSourceKind.window
                : ScreenSourceKind.screen,
            thumbnail: source.thumbnail,
          ),
      ]);
    }

    // Cameras come from the device list rather than the desktop capturer,
    // because they are a different kind of thing: a device the platform opens
    // for us, not a surface we point at. No camera — or no permission to see
    // their names yet — is an empty tab, not a failure.
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      for (final device in devices) {
        if (device.kind != 'videoinput') continue;
        sources.add(
          ScreenSource(
            device.deviceId,
            device.label,
            kind: ScreenSourceKind.camera,
          ),
        );
      }
    } catch (_) {
      // Listing what cannot be listed costs the camera tab and nothing else.
    }

    return sources;
  }

  @override
  Future<ScreenMedia> preview(ScreenSource source) async {
    // Starting a desktop video capturer explicitly focuses the selected window.
    // The thumbnail API uses the media-list capturer without that Start path.
    if (_desktop && source.kind != ScreenSourceKind.camera) {
      const channel = MethodChannel('FlutterWebRTC.Method');
      for (var attempt = 0; attempt < 10; attempt++) {
        final bytes = await channel.invokeMethod<Uint8List>(
          'getDesktopSourceThumbnail',
          {
            'sourceId': source.id,
            'thumbnailSize': {'width': 640, 'height': 360},
          },
        );
        if (bytes != null && bytes.isNotEmpty) return _ThumbnailMedia(bytes);
        // Native code schedules the capture and returns the previous cache.
        // Retry an empty cache, but never fall back to a focusing video capture.
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      throw StateError('No thumbnail available for this source');
    }
    // Ten a second: enough that moving a window shows up in the chooser, and
    // a tenth of what a real share costs — this one runs for as long as the
    // dialog is open, over every source the user clicks through.
    final stream = source.kind == ScreenSourceKind.camera
        ? await navigator.mediaDevices.getUserMedia({
            'audio': false,
            'video': {
              'deviceId': {'exact': source.id},
              'frameRate': {'ideal': 10},
            },
          })
        : await navigator.mediaDevices.getDisplayMedia({
            'audio': false,
            'video': {
              'deviceId': {'exact': source.id},
              'frameRate': {'ideal': 10},
              'mandatory': {'frameRate': 10.0},
            },
          });
    if (stream.getVideoTracks().isEmpty) {
      await stream.dispose();
      throw StateError('No video track for this source');
    }
    return _Media(stream);
  }

  @override
  Future<ScreenMedia> capture(
    ScreenSource? source,
    ScreenOptions options,
  ) async {
    if (_desktop && source == null) throw StateError('Select a screen source');

    // A camera is a different call, not a different constraint: it is a device
    // the browser already knows how to open, with permission of its own.
    final stream = source?.kind == ScreenSourceKind.camera
        ? await navigator.mediaDevices.getUserMedia({
            'audio': options.audio,
            'video': _video(options, deviceId: source!.id),
          })
        : await _getDisplayMedia({
            'audio': options.audio,
            'video': _video(options, deviceId: source?.id),
          });

    if (stream.getVideoTracks().isEmpty) {
      await stream.dispose();
      throw StateError('No screen video track');
    }
    // macOS's screen path is video-only inside the plugin — its
    // ScreenCaptureKit capturer never captures audio — so the sound track
    // comes from the audio device instead: the runner installs a custom
    // device whose "microphone" is the shared screen's sound, and this is
    // what opens a track onto it. Windows captures its own loopback inside
    // getDisplayMedia, so its stream already has the track.
    if (options.audio &&
        stream.getAudioTracks().isEmpty &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.macOS &&
        source?.kind != ScreenSourceKind.camera) {
      await _addSystemAudioTrack(stream);
    }
    return _Media(stream);
  }

  /// Opens the custom audio device as a track and adds it to the capture.
  ///
  /// A failure here is a share without sound, not a failed share: the device
  /// has sound only while the system picker's filter is set, and the
  /// permission it needs is the one voice already holds.
  Future<void> _addSystemAudioTrack(MediaStream stream) async {
    try {
      final audio = await navigator.mediaDevices.getUserMedia({'audio': true});
      for (final track in audio.getAudioTracks()) {
        await stream.addTrack(track);
      }
    } catch (error) {
      logToCore('warn', 'screen: no system audio track: $error');
    }
  }

  /// The video half of a capture request.
  ///
  /// Frame rate is asked for twice on purpose. The standard `ideal` is what the
  /// browser reads, and the legacy `mandatory` block is the *only* thing the
  /// Windows screen capturer looks at — `flutter_screen_capture.cc` reads
  /// `deviceId`, `mandatory.frameRate` and `cursor` and nothing else. Sending
  /// one form gets a frame rate on one platform and not the other.
  ///
  /// Resolution is deliberately absent: that capturer ignores a size constraint
  /// too, so the height the user chose is applied to the encoder instead — see
  /// `_Peer._steer`.
  Map<String, dynamic> _video(ScreenOptions options, {String? deviceId}) => {
    if (deviceId != null) 'deviceId': {'exact': deviceId},
    if (options.fps > 0) 'frameRate': {'ideal': options.fps},
    if (options.fps > 0) 'mandatory': {'frameRate': options.fps.toDouble()},
  };

  @override
  Future<ScreenPeer> peer({
    required void Function(Map<String, dynamic>) onCandidate,
    required void Function(ScreenMedia) onMedia,
    required void Function() onFailed,
    required ScreenOptions? options,
  }) async {
    logToCore('info', 'screen: creating media peer');
    final pc = await _createConnection({
      'sdpSemantics': 'unified-plan',
      'iceServers': [
        {'urls': 'stun:turn.teamspeak.com:3478'},
        {'urls': 'stun:turn2.teamspeak.com:3478'},
      ],
    });
    logToCore('info', 'screen: media peer created');
    final peer = _Peer(pc, options, onCandidate, iceGatherTimeout);
    pc.onIceGatheringState = (state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          peer.gathering?.isCompleted == false) {
        peer.gathering!.complete();
      }
    };
    pc.onIceCandidate = (c) {
      if (!peer.closed && c.candidate?.isNotEmpty == true) {
        peer.localCandidate({
          'type': 'candidate',
          'candidate': c.candidate,
          'mid': c.sdpMid ?? '0',
          'line': c.sdpMLineIndex ?? 0,
        });
      }
    };
    pc.onTrack = (event) {
      // onTrack cannot await our work. Serialize it explicitly so simultaneous
      // audio/video events cannot replace or leak one another's media.
      peer.tracks = peer.tracks
          .then((_) async {
            if (peer.closed || !peer.remoteTracks.add(event.track.id!)) return;
            var media = peer.remote;
            if (media == null) {
              final synthetic = event.streams.isEmpty;
              final stream = synthetic
                  ? await _createStream('screen')
                  : event.streams.first;
              media = _Media(stream, ownsTracks: false, ownsStream: synthetic);
              if (peer.closed) {
                await media.close();
                return;
              }
              peer.remote = media;
            }
            // A supplied remote stream already owns its native tracks. Adding
            // them again invokes a local-only lookup and fails with "stream null".
            if (!media.stream.getTracks().any(
              (track) => track.id == event.track.id,
            )) {
              await media.stream.addTrack(
                event.track,
                addToNative: media.ownsStream,
              );
            }
            if (!peer.closed) onMedia(media);
          })
          .catchError((Object error, StackTrace stack) {
            logToCore('error', 'screen: remote track failed: $error\n$stack');
            if (!peer.closed) onFailed();
          });
    };
    pc.onConnectionState = (state) {
      if (!peer.closed &&
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        onFailed();
      }
    };
    return peer;
  }
}

/// The real picker, resolved when it is called rather than when it is named.
///
/// A tear-off of this function instead of `navigator.mediaDevices.getDisplayMedia`
/// written inline: the inline form reaches for the navigator while the backend
/// is being constructed, and that registers event channels, which a plain
/// `test()` has no binding for — a test that never captures anything should not
/// need one.
Future<MediaStream> _platformDisplayMedia(Map<String, dynamic> constraints) =>
    navigator.mediaDevices.getDisplayMedia(constraints);

class _ThumbnailMedia implements ScreenMedia {
  _ThumbnailMedia(this.bytes);
  final Uint8List bytes;

  @override
  Widget view() =>
      Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true);
  @override
  set onEnded(void Function() callback) {}
  @override
  Future<void> close() async {}
  // A still has no sound, and never pretends to be a share to begin with.
  @override
  bool get hasAudio => false;
}

class _Media implements ScreenMedia {
  _Media(this.stream, {this.ownsTracks = true, this.ownsStream = true});
  final MediaStream stream;
  final bool ownsTracks;
  final bool ownsStream;
  bool closed = false;
  @override
  bool get hasAudio => stream.getAudioTracks().isNotEmpty;
  @override
  Widget view() => _Video(media: this);
  @override
  set onEnded(void Function() callback) {
    for (final track in stream.getVideoTracks()) {
      track.onEnded = callback;
    }
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    if (ownsTracks) {
      for (final track in stream.getTracks()) {
        track.onEnded = null;
        try {
          await track.stop();
        } catch (_) {
          // Continue releasing the remaining tracks and the stream.
        }
      }
    }
    // The native stream can already be gone — the publisher's teardown and
    // ours race, and losing that race is not a failure worth reporting.
    try {
      if (ownsStream) await stream.dispose();
    } catch (_) {}
  }
}

class _Peer implements ScreenPeer {
  _Peer(this.pc, this.options, this.onCandidate, this.iceGatherTimeout);
  final RTCPeerConnection pc;
  final void Function(Map<String, dynamic>) onCandidate;
  final Duration iceGatherTimeout;
  Completer<void>? gathering;
  bool bufferingCandidates = false;
  final localCandidates = <Map<String, dynamic>>[];
  final candidateKeys = <String>{};

  void localCandidate(Map<String, dynamic> candidate) {
    final key =
        '${candidate['mid']}:${candidate['line']}:${candidate['candidate']}';
    if (closed || !candidateKeys.add(key)) return;
    if (bufferingCandidates) {
      localCandidates.add(candidate);
    } else {
      onCandidate(candidate);
    }
  }

  /// Bundle gathered routes into SDP to avoid a command per network interface.
  /// Slow STUN routes remain trickled, preserving cross-network connectivity.
  Future<String> localDescription(RTCSessionDescription description) async {
    bufferingCandidates = true;
    gathering = Completer<void>();
    try {
      await pc.setLocalDescription(description);
      if (pc.iceGatheringState !=
          RTCIceGatheringState.RTCIceGatheringStateComplete) {
        await gathering!.future.timeout(iceGatherTimeout, onTimeout: () {});
      }
      if (closed) throw StateError('screen peer closed during ICE gathering');
      final sdp = withScreenCandidates(
        (await pc.getLocalDescription())?.sdp ?? description.sdp!,
        localCandidates,
      );
      for (final candidate in localCandidates) {
        if (!sdp.contains('a=${candidate['candidate']}')) {
          onCandidate(candidate);
        }
      }
      return sdp;
    } finally {
      bufferingCandidates = false;
      localCandidates.clear();
      gathering = null;
    }
  }

  /// What this publisher chose. The encoder is the only thing left that reads
  /// it here — the capture was configured separately, and the wire has already
  /// been told.
  final ScreenOptions? options;
  _Media? remote;

  /// The remote track already handed to the window, so a re-offer does not
  /// build a second one.
  final remoteTracks = <String>{};
  Future<void> tracks = Future<void>.value();
  bool closed = false;
  bool described = false;
  final List<Map<String, dynamic>> pending = [];

  /// Runs only while publishing — a viewer has nothing of its own to report.
  Timer? _stats;

  @override
  Future<String> offer(ScreenMedia media) async {
    final stream = (media as _Media).stream;
    final senders = <RTCRtpSender>[];
    // Everything the capture produced goes on the wire — video first, then
    // sound when the platform gave us any. Adding only the video half is what
    // "capture audio" silently did before: the setting reached the capture and
    // the server but never the connection between them.
    for (final track in stream.getVideoTracks()) {
      senders.add(await pc.addTrack(track, stream));
    }
    for (final track in stream.getAudioTracks()) {
      senders.add(await pc.addTrack(track, stream));
    }
    await _trimCodecs();
    final description = await pc.createOffer({
      'offerToReceiveAudio': false,
      'offerToReceiveVideo': false,
    });
    final sdp = await localDescription(description);
    for (final sender in senders) {
      await _steer(sender);
    }
    _stats ??= Timer.periodic(_statsEvery, (_) => unawaited(_logStats()));
    return sdp;
  }

  /// Keeps the offer small enough for the server to carry it.
  ///
  /// There is a ceiling on how long a single TS6 command may be — probed on
  /// 2026-10-08 to sit between 7.7 KB (delivered) and 8.3 KB (silently
  /// dropped). libwebrtc's default offer advertises every codec it knows:
  /// video alone measured 7.7 KB on the test machine, and one audio m-line
  /// pushed it past the ceiling — at which point the whole `respond` vanished:
  /// no acknowledgement, no offer, no viewer, no error anywhere. Every client
  /// this project talks to negotiates VP8 and opus, so the rest of the list
  /// was never earning its bytes.
  Future<void> _trimCodecs() async {
    try {
      for (final transceiver in await pc.getTransceivers()) {
        final kind = transceiver.sender.track?.kind;
        if (kind == 'video') {
          await transceiver.setCodecPreferences(_videoCodecs);
        } else if (kind == 'audio') {
          await transceiver.setCodecPreferences(_audioCodecs);
        }
      }
    } catch (error) {
      // A platform that cannot reorder codecs keeps its default offer — the
      // browser's own picker is lean enough that the ceiling is not in play.
      logToCore('warn', 'screen: could not trim the codec list: $error');
    }
  }

  static final List<RTCRtpCodecCapability> _videoCodecs = [
    RTCRtpCodecCapability(clockRate: 90000, mimeType: 'video/VP8'),
    // Retransmission for the same codec: without it a lost packet is lost.
    RTCRtpCodecCapability(clockRate: 90000, mimeType: 'video/rtx'),
  ];
  static final List<RTCRtpCodecCapability> _audioCodecs = [
    RTCRtpCodecCapability(clockRate: 48000, mimeType: 'audio/opus', channels: 2),
  ];

  @override
  Future<ScreenStats?> stats() async {
    if (closed) return null;
    try {
      for (final report in await pc.getStats()) {
        final values = report.values;
        if (report.type != 'outbound-rtp') continue;
        if (values['kind'] != 'video' && values['mediaType'] != 'video') {
          continue;
        }
        return ScreenStats(
          (values['frameWidth'] as num?)?.toInt() ?? 0,
          (values['frameHeight'] as num?)?.toInt() ?? 0,
          (values['framesPerSecond'] as num?)?.toDouble() ?? 0,
          values['qualityLimitationReason'] as String?,
        );
      }
    } catch (_) {
      // Statistics are diagnostics; failing to read them is not a share
      // failure and must not become one.
    }
    return null;
  }

  /// Puts [`ScreenPeer.stats`] in the log, where it survives the session.
  ///
  /// Once every ten seconds at `info`, because the default filter keeps only
  /// `info` and up — a line nobody can read without setting `RUST_LOG` would
  /// answer nothing.
  Future<void> _logStats() async {
    final rate = await stats();
    if (rate != null) logToCore('info', 'screen: sending $rate');
    await _logTransport();
  }

  /// What the connection is actually carrying, both directions.
  ///
  /// "The sound is choppy and the pitch is wrong" with a clean capture means
  /// loss and PLC on the receiving end — or playback trouble after it — and
  /// nothing in the UI can tell those apart. These are the numbers that can:
  /// packet counts and loss both ways, the receiver's jitter, and how many
  /// audio samples Opus had to invent (`concealedSamples` is the choppiness
  /// itself).
  Future<void> _logTransport() async {
    if (closed) return;
    try {
      final lines = <String>[];
      for (final report in await pc.getStats()) {
        final values = report.values;
        final kind = values['kind'] ?? values['mediaType'];
        if (report.type == 'outbound-rtp' && kind == 'audio') {
          lines.add(
            'out-audio ${values['packetsSent']}p ${values['bytesSent']}B',
          );
        } else if (report.type == 'inbound-rtp' && kind == 'audio') {
          lines.add(
            'in-audio ${values['packetsReceived']}p '
            '${values['bytesReceived']}B lost=${values['packetsLost']} '
            'jitter=${values['jitter']} concealed=${values['concealedSamples']}',
          );
        } else if (report.type == 'inbound-rtp' && kind == 'video') {
          lines.add(
            'in-video decoded=${values['framesDecoded']} '
            'dropped=${values['framesDropped']} lost=${values['packetsLost']}',
          );
        }
      }
      if (lines.isNotEmpty) {
        logToCore('info', 'screen: media ${lines.join(' | ')}');
      }
    } catch (_) {
      // Statistics are diagnostics; failing to read them is not a failure.
    }
  }

  /// Caps and steers the encoders.
  ///
  /// **After `setLocalDescription`, not before.** A sender reports no encodings
  /// until a local description exists, so an earlier call is silently a no-op —
  /// which is what this was: the cap and the preference were both being written
  /// into an empty list, and the stream ran on libwebrtc's own defaults.
  ///
  /// `maintain-framerate` is the opposite of what the reference implementation
  /// picks (it protects resolution, because a screen share is usually text).
  /// This one is set the other way round on purpose: the complaint that started
  /// this was frame rate. Flipping it is one word.
  ///
  /// Video and sound get different fields. Only the picture has a resolution to
  /// scale and a side to give way on, so an audio sender is handed nothing but
  /// its bitrate — the same split the reference implementation makes.
  Future<void> _steer(RTCRtpSender sender) async {
    final parameters = sender.parameters;
    final encodings = parameters.encodings;
    if (encodings == null || encodings.isEmpty) {
      // The whole point of doing this after `setLocalDescription` is that this
      // cannot happen. If it ever does, say so rather than shrugging: the
      // share still runs, but uncapped and free to shrink, and the difference
      // is invisible from the picture alone.
      logToCore(
        'warn',
        'screen: the sender reported no encodings, so the bitrate cap and the '
            'degradation preference were not applied',
      );
      return;
    }
    final options = this.options;
    if (options == null) {
      // Only a publisher steers an encoder, and a publisher always has
      // options. Reaching here means an offer was made for a stream nobody
      // configured, which is worth a line rather than a silent default.
      logToCore(
        'warn',
        'screen: offering with no encoder settings; left at the defaults',
      );
      return;
    }
    final audio = sender.track?.kind == 'audio';
    if (audio) {
      for (final encoding in encodings) {
        encoding.maxBitrate = options.audioBitrateKbps * 1000;
      }
    } else {
      // What to give up when there is not enough room. "Detail" is slides and
      // code — the reference client hints the track the same way — and the rest
      // is movement, where a smooth picture matters more than a sharp one.
      parameters.degradationPreference = options.detail
          ? RTCDegradationPreference.MAINTAIN_RESOLUTION
          : RTCDegradationPreference.MAINTAIN_FRAMERATE;

      final scale = _scaleFor(sender.track, options.height);
      for (final encoding in encodings) {
        encoding.maxBitrate = options.videoBitrateKbps * 1000;
        if (scale != null) encoding.scaleResolutionDownBy = scale;
      }
    }

    final applied = await sender.setParameters(parameters);
    // Logged either way, and read back rather than assumed: `setParameters`
    // can refuse a field it does not know, and a refusal that leaves no trace
    // is how this went unnoticed the first time.
    final after = sender.parameters;
    final shape = audio
        ? ''
        : ' scale=${after.encodings?.map((e) => e.scaleResolutionDownBy).toList()}'
              ' preference=${after.degradationPreference}';
    logToCore(
      applied ? 'info' : 'warn',
      'screen: send parameters ${audio ? 'audio' : 'video'} applied=$applied '
      'encodings=${after.encodings?.length} '
      'cap=${after.encodings?.map((e) => e.maxBitrate).toList()}$shape',
    );
  }

  /// How much to shrink before encoding, so the height asked for is the height
  /// that goes out.
  ///
  /// The capture cannot be asked to do it: the Windows screen capturer reads no
  /// size constraint at all, so a 4K screen arrives as 4K whatever was
  /// requested, and every bit of it would be encoded. Scaling on the encoder
  /// makes the setting mean the same thing on every platform — and null means
  /// "leave it alone", either because the source resolution was wanted or
  /// because the capture is already at or below it.
  static double? _scaleFor(MediaStreamTrack? track, int wantedHeight) {
    if (wantedHeight <= 0 || track == null) return null;
    final height = _trackHeight(track);
    if (height == null || height <= wantedHeight) return null;
    return height / wantedHeight;
  }

  static double? _trackHeight(MediaStreamTrack track) {
    try {
      return (track.getSettings()['height'] as num?)?.toDouble();
    } catch (_) {
      // Not every platform answers, and not answering costs the downscale
      // rather than the stream.
      return null;
    }
  }

  Future<void> _remote(String sdp, String type) async {
    await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
    described = true;
    for (final c in pending) {
      await _candidate(c);
    }
    pending.clear();
  }

  @override
  Future<String> answer(String sdp) async {
    await _remote(sdp, 'offer');
    final description = await pc.createAnswer();
    final local = await localDescription(description);
    // A viewer has no encoder to report, so without this the receiving side
    // of a share would log nothing at all.
    _stats ??= Timer.periodic(_statsEvery, (_) => unawaited(_logStats()));
    return local;
  }

  @override
  Future<void> acceptAnswer(String sdp) => _remote(sdp, 'answer');
  @override
  Future<void> candidate(Map<String, dynamic> c) async {
    if (!described) {
      if (pending.length < 128) pending.add(c);
    } else {
      await _candidate(c);
    }
  }

  Future<void> _candidate(Map<String, dynamic> c) async {
    // One unusable route must not discard the other working ICE candidates.
    try {
      await pc.addCandidate(
        RTCIceCandidate(
          c['candidate'] as String,
          c['mid'] as String,
          c['line'] as int,
        ),
      );
    } catch (_) {
      /* ICE can succeed through another candidate. */
    }
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    _stats?.cancel();
    _stats = null;
    pc.onTrack = null;
    pc.onIceCandidate = null;
    pc.onIceGatheringState = null;
    if (gathering?.isCompleted == false) gathering!.complete();
    pc.onConnectionState = null;
    await tracks;
    await remote?.close();
    try {
      await pc.close();
    } finally {
      await pc.dispose();
    }
  }
}

class _Video extends StatefulWidget {
  const _Video({required this.media});
  final _Media media;
  @override
  State<_Video> createState() => _VideoState();
}

class _VideoState extends State<_Video> {
  final renderer = RTCVideoRenderer();
  bool ready = false;
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await renderer.initialize();
    if (!mounted) {
      await renderer.dispose();
      return;
    }
    // Deliberately not touching `renderer.muted`, which reads like "do not
    // play my own audio back" and is nothing of the sort: it reaches for the
    // stream's first *audio* track and mutes the microphone behind it. It
    // throws when there is no source object yet, again when the stream is
    // remote, and again when the capture carries no audio — all three of which
    // are our cases. The share is video-only, so there is nothing to echo
    // anyway. Reaching for it cost every picture on screen: the exception
    // aborted this method before `srcObject`, so the renderer never got one.
    renderer.onFirstFrameRendered = () {
      logToCore('info', 'screen: first video frame rendered');
    };
    renderer.srcObject = widget.media.stream;
    setState(() => ready = true);
  }

  @override
  void didUpdateWidget(_Video old) {
    super.didUpdateWidget(old);
    if (identical(old.media, widget.media)) return;
    // The renderer is made once and lives as long as this element does, and
    // Flutter reuses an element for a widget of the same type in the same
    // place — so a different stream arriving here does *not* re-run
    // `initState`. Without this the picture stays on whatever was showing when
    // the element was built, which is exactly what "I picked another window
    // and the preview did not change" looks like.
    if (ready) renderer.srcObject = widget.media.stream;
  }

  @override
  void dispose() {
    if (ready) {
      renderer.srcObject = null;
      renderer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ready ? RTCVideoView(renderer) : const SizedBox.shrink();
}
