// Temporary probe (2026-10-08): does a Windows-published offer that carries an
// audio track reach a viewer through the real TS6 server, where a video-only
// offer does? Two sessions in one core: A publishes, B watches. No UI.
//
//   flutter run -d windows -t tool/screen_audio_probe.dart            (audio on)
//   PROBE_AUDIO=0 flutter run -d windows -t tool/screen_audio_probe.dart  (control)
//
// Exit code: 0 when the viewer received media, 2 otherwise.
import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:nightcord_client/core/screen/screen_controller.dart';
import 'package:nightcord_client/core/screen/screen_sdp.dart';
import 'package:nightcord_client/core/screen/screen_share_backend.dart';
import 'package:nightcord_client/core/screen/webrtc_screen_backend.dart';
import 'package:nightcord_client/ffi/rust_client.dart';
import 'package:nightcord_client/models/connect_request.dart';
import 'package:nightcord_client/models/domain.dart';
import 'package:nightcord_client/models/events.dart';
import 'package:nightcord_client/models/screen_options.dart';

void log(String line) =>
    // ignore: avoid_print
    print('[probe] $line');

Future<void> pause(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

/// Reports every offer's size and can inflate it, to tell "too big" apart from
/// "the audio m-line itself" when a respond never comes back.
class _PadPeer implements ScreenPeer {
  _PadPeer(this.inner, this.pad);

  final ScreenPeer inner;
  final int pad;

  @override
  Future<String> offer(ScreenMedia media) async {
    final sdp = await inner.offer(media);
    final sections = <List<String>>[];
    for (final line in sdp.split(RegExp(r'\r?\n'))) {
      if (line.isEmpty) continue;
      if (line.startsWith('m=')) sections.add([]);
      if (sections.isNotEmpty) sections.last.add(line);
    }
    var videoBytes = 0;
    var videoCandidates = 0;
    var audioBytes = 0;
    var audioCandidates = 0;
    for (final section in sections) {
      final candidates = section
          .where((l) => l.startsWith('a=candidate'))
          .length;
      final bytes = section.fold(0, (sum, l) => sum + l.length + 2);
      if (section.first.startsWith('m=audio')) {
        audioBytes = bytes;
        audioCandidates = candidates;
      } else {
        videoBytes += bytes;
        videoCandidates += candidates;
      }
    }
    final deduped = withScreenCandidates(sdp, const []);
    String masked(String line) => line.replaceAll(RegExp(r'\d'), '#');
    String firstCandidate(List<String>? section) => section == null
        ? '-'
        : masked(
            section.firstWhere(
              (l) => l.startsWith('a=candidate'),
              orElse: () => '-',
            ),
          );
    log(
      'offer size=${sdp.length} pad=$pad m-lines=${sections.length} '
      'bundle=${sdp.contains('a=group:BUNDLE')} '
      'videoSection=$videoBytes/$videoCandidates  '
      'audioSection=$audioBytes/$audioCandidates '
      'secondPassRemoves=${sdp.length - deduped.length}',
    );
    log('video[0]=${firstCandidate(sections.isEmpty ? null : sections[0])}');
    log(
      'audio[0]=${firstCandidate(sections.length < 2 ? null : sections[1])}',
    );
    if (pad <= 0) return sdp;
    return '$sdp\r\na=x-probe-pad:${'p' * pad}\r\n';
  }

  @override
  Future<String> answer(String sdp) => inner.answer(sdp);
  @override
  Future<void> acceptAnswer(String sdp) => inner.acceptAnswer(sdp);
  @override
  Future<void> candidate(Map<String, dynamic> candidate) =>
      inner.candidate(candidate);
  @override
  Future<void> close() => inner.close();
  @override
  Future<ScreenStats?> stats() => inner.stats();
}

class _ProbeBackend extends WebRtcScreenBackend {
  _ProbeBackend(this.pad);

  final int pad;

  @override
  Future<ScreenPeer> peer({
    required void Function(Map<String, dynamic>) onCandidate,
    required void Function(ScreenMedia) onMedia,
    required void Function() onFailed,
    required ScreenOptions? options,
  }) async => _PadPeer(
    await super.peer(
      onCandidate: onCandidate,
      onMedia: onMedia,
      onFailed: onFailed,
      options: options,
    ),
    pad,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox.shrink());
  final audio = Platform.environment['PROBE_AUDIO'] != '0';
  final pad = int.tryParse(Platform.environment['PROBE_PAD'] ?? '') ?? 0;
  log('start audio=$audio pad=$pad');

  final core = RustClient.start();
  final backend = _ProbeBackend(pad);
  final aConnected = Completer<int>();
  final bConnected = Completer<int>();
  final aOwn = Completer<OwnClientIdentifiedEvent>();
  final bOwn = Completer<OwnClientIdentifiedEvent>();
  var sa = -1;
  var sb = -1;
  ScreenController? a;
  ScreenController? b;

  final subscription = core.events.listen((event) {
    if (event is! DomainEvent) return;
    final inner = event.event;
    if (inner is ConnectedEvent) {
      log('session ${event.session} connected');
      if (!aConnected.isCompleted) {
        sa = event.session;
        aConnected.complete(sa);
      } else if (!bConnected.isCompleted) {
        sb = event.session;
        bConnected.complete(sb);
      }
    } else if (inner is OwnClientIdentifiedEvent) {
      if (!aOwn.isCompleted) {
        log('A own=${inner.clientId} channel=${inner.channelId}');
        aOwn.complete(inner);
      } else if (!bOwn.isCompleted) {
        log('B own=${inner.clientId} channel=${inner.channelId}');
        bOwn.complete(inner);
      }
    } else if (inner is ScreenEvent) {
      if (event.session == sa) {
        unawaited(a?.receive(inner));
      } else if (event.session == sb) {
        unawaited(b?.receive(inner));
      }
    }
  });

  void connect(String profile) => core.connect(
    ConnectRequest(
      address: '192.168.31.128:9988',
      nickname: 'Screen audio probe',
      profile: profile,
      protocol: ProtocolKind.ts6,
    ),
  );

  try {
    connect('screen-audio-probe-a');
    await aConnected.future.timeout(const Duration(seconds: 10));
    final ownA = await aOwn.future.timeout(const Duration(seconds: 10));
    a = ScreenController(
      backend: backend,
      send: (c) => core.screen(sa, c),
      onError: (reason) => log('A error $reason'),
    );
    a.contextChanged(
      online: true,
      client: ownA.clientId,
      channel: ownA.channelId,
      clients: {ownA.clientId},
    );

    await pause(1500);
    final sources = await backend.sources();
    final source = sources.firstWhere(
      (s) => s.kind == ScreenSourceKind.screen,
      orElse: () => sources.first,
    );
    final options = ScreenOptions(
      source: ScreenSourceKind.screen,
      height: 720,
      fps: 15,
      videoBitrateKbps: 1500,
      audio: audio,
      audioBitrateKbps: 128,
      access: ScreenAccess.public,
      viewerLimit: 4,
      mode: ScreenMode.p2p,
      detail: false,
    );
    await a.start(source, 'audio probe', options);
    for (var i = 0; a.publishing == null && i < 100; i++) {
      await pause(100);
    }
    if (a.publishing == null) {
      log('FAIL publisher never got a stream id (error=${a.error})');
      exit(2);
    }
    log('publisher live stream=${a.publishing} captureAudio=$audio');

    connect('screen-audio-probe-b');
    await bConnected.future.timeout(const Duration(seconds: 10));
    final ownB = await bOwn.future.timeout(const Duration(seconds: 10));
    b = ScreenController(
      backend: backend,
      send: (c) => core.screen(sb, c),
      onError: (reason) => log('B error $reason'),
    );
    b.contextChanged(
      online: true,
      client: ownB.clientId,
      channel: ownB.channelId,
      clients: {ownA.clientId, ownB.clientId},
    );
    // The publisher's admission gate checks this set, so it must know B now.
    a.contextChanged(
      online: true,
      client: ownA.clientId,
      channel: ownA.channelId,
      clients: {ownA.clientId, ownB.clientId},
    );
    await pause(1500);

    await b.watch(ownA.clientId);
    var received = false;
    for (var i = 0; i < 60; i++) {
      if (b.receiving) {
        received = true;
        break;
      }
      if (b.error != null) break;
      await pause(500);
      if (i % 4 == 0) {
        log(
          't=${i ~/ 2}s B watching=${b.watching} remote=${b.remote != null} '
          'error=${b.error} | A viewers=${a.viewers}',
        );
      }
    }
    log(
      'RESULT audio=$audio received=$received B.error=${b.error} '
      'A.viewers=${a.viewers} remoteHasAudio=${b.remote?.hasAudio}',
    );

    await a.stop();
    await b.leave();
    await pause(500);
    subscription.cancel();
    core.disconnect(sa);
    core.disconnect(sb);
    core.dispose();
    exit(received ? 0 : 2);
  } catch (error, stack) {
    log('FAIL $error\n$stack');
    exit(2);
  }
}
