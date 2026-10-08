import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/core/screen/screen_controller.dart';
import 'package:nightcord_client/core/screen/screen_share_backend.dart';
import 'package:nightcord_client/models/events.dart';
import 'package:nightcord_client/models/screen_options.dart';

class Media implements ScreenMedia {
  int closes = 0;
  void Function()? ended;

  /// What the fake capture produced, for the test that watches the wire's
  /// `audio` flag follow it rather than the request.
  @override
  bool hasAudio = false;
  @override
  set onEnded(void Function() callback) => ended = callback;
  @override
  Future<void> close() async { closes++; }
  @override
  Widget view() => const SizedBox();
}
class Peer implements ScreenPeer {
  Peer(this.candidateCallback, this.mediaCallback);
  final void Function(Map<String, dynamic>) candidateCallback;
  final void Function(ScreenMedia) mediaCallback;
  final List<String> calls = [];
  int closes = 0;
  @override
  Future<String> offer(ScreenMedia media) async {
    calls.add('offer');
    candidateCallback({'type': 'candidate', 'candidate': 'local', 'mid': '0', 'line': 0});
    return 'local-offer';
  }
  @override
  Future<String> answer(String sdp) async { calls.add('answer:$sdp'); return 'local-answer'; }
  @override
  Future<void> acceptAnswer(String sdp) async { calls.add('accepted:$sdp'); }
  @override
  Future<void> candidate(Map<String, dynamic> candidate) async { calls.add('candidate'); }
  @override
  Future<void> close() async { closes++; }
  /// What the encoder reports, for the tests that look at the readout.
  ScreenStats? reading;

  @override
  Future<ScreenStats?> stats() async => reading;
}
class Backend implements ScreenShareBackend {
  final media = Media();
  final peers = <Peer>[];
  Completer<ScreenMedia>? deferred;
  @override
  Future<List<ScreenSource>> sources() async => [];

  @override
  Future<ScreenMedia> preview(ScreenSource source) async => media;
  @override
  Future<ScreenMedia> capture(ScreenSource? source, ScreenOptions options) async =>
      deferred == null ? media : deferred!.future;
  @override
  Future<ScreenPeer> peer({required void Function(Map<String, dynamic>) onCandidate,
    required void Function(ScreenMedia) onMedia, required void Function() onFailed,
    required ScreenOptions? options}) async {
    final peer = Peer(onCandidate, onMedia);
    peers.add(peer);
    return peer;
  }
}


/// The settings a share starts with, for the tests that only care that *some*
/// were given. The numbers are the default preset's, so a test that cares about
/// one of them overrides just that one.
ScreenOptions screenOptions() => const ScreenOptions(
  source: ScreenSourceKind.screen,
  height: 720,
  fps: 30,
  videoBitrateKbps: 2500,
  audio: false,
  audioBitrateKbps: 128,
  access: ScreenAccess.public,
  viewerLimit: 0,
  mode: ScreenMode.p2p,
  detail: false,
);

void main() {
  late Backend backend;
  late ScreenController controller;
  late List<Map<String, dynamic>> commands;
  setUp(() {
    backend = Backend(); commands = [];
    controller = ScreenController(backend: backend, send: commands.add);
    controller.contextChanged(online: true, client: 1, channel: 10, clients: {1, 2, 3, 4, 5, 6});
  });
  tearDown(() => controller.dispose());
  Future<void> event(String type, {String id = 's', int client = 2, Map<String, dynamic> extra = const {}}) =>
    controller.receive(ScreenEvent({'type': type, 'stream_id': id, 'client_id': client, ...extra}));

  test('publisher sends offer before trickled ICE and accepts the answer', () async {
    await controller.start(null, 'Share', screenOptions());
    await event('available', client: 1, extra: {'name': 'Share'});
    await event('join_requested', extra: {'leaving': false});
    expect(commands.map((c) => c['action']), ['start', 'respond', 'signal']);
    expect(commands[1]['sdp'], 'local-offer');
    await event('signal', extra: {'signal': {'type': 'answer', 'sdp': 'remote-answer'}});
    expect(backend.peers.single.calls, ['offer', 'accepted:remote-answer']);
    await controller.stop();
    expect(backend.media.closes, 1);
    expect(backend.peers.single.closes, 1);
    expect(commands.last['action'], 'stop');
  });

  test('late join discovers a share and answers only its selected publisher', () async {
    await controller.watch(2);
    expect(commands.single['action'], 'discover');
    await event('available', extra: {'name': 'Remote'});
    expect(commands.last['action'], 'join');
    await event('join_answered', client: 3, extra: {'accepted': true, 'sdp': 'unrelated'});
    expect(backend.peers.single.calls, isEmpty);
    await event('join_answered', extra: {'accepted': true, 'sdp': 'offer'});
    expect(commands.last['signal'], {'type': 'answer', 'sdp': 'local-answer'});
    backend.peers.single.mediaCallback(Media());
    expect(controller.remote, isNotNull);
    // A different viewer leaving must not close our receiving connection.
    await event('peer_left', client: 3);
    expect(controller.watching, isTrue);
    await event('stopped');
    expect(controller.watching, isFalse);
    expect(backend.peers.single.closes, 1);
  });

  test('duplicate remote offer is answered once but new offers still negotiate', () async {
    // TS6 sends the join offer again through its signaling event.
    await controller.watch(2);
    await event('available', extra: {'name': 'Remote'});
    await event('join_answered', extra: {'accepted': true, 'sdp': 'offer'});
    await event('signal', extra: {'signal': {'type': 'offer', 'sdp': 'offer'}});
    expect(backend.peers.single.calls, ['answer:offer']);
    expect(commands.where((c) => c['signal']?['type'] == 'answer'), hasLength(1));
    await event('signal', extra: {'signal': {'type': 'offer', 'sdp': 'new offer'}});
    expect(backend.peers.single.calls, ['answer:offer', 'answer:new offer']);
  });

  test('handover releases the same-client viewer before opening another engine', () async {
    // Keeping the old viewer joined made TS6 ignore the new engine's join.
    await controller.watch(2);
    await event('available', extra: {'name': 'Remote'});
    final peer = backend.peers.single;
    commands.clear();
    final result = await controller.transferWatch((client) async {
      expect(client, 2);
      expect(commands.single['action'], 'leave');
      expect(peer.closes, 1);
      expect(controller.watching, isFalse);
      return 'opened';
    });
    expect(result, 'opened');
    expect(commands, hasLength(1));
  });

  test('failed handover restores the inline viewer', () async {
    // A failed pop-out must allow watching and trying again.
    await controller.watch(2);
    await event('available', extra: {'name': 'Remote'});
    commands.clear();
    await expectLater(
      controller.transferWatch<void>((_) async => throw StateError('failed')),
      throwsStateError,
    );
    expect(commands.map((c) => c['action']), ['leave', 'discover']);
    expect(controller.watches(2), isTrue);
  });

  test('cancelled capture is closed even when the platform picker finishes late', () async {
    // A delayed capture used to be able to start after disconnect/stop.
    backend.deferred = Completer<ScreenMedia>();
    final starting = controller.start(null, 'Share', screenOptions());
    await controller.stop();
    backend.deferred!.complete(backend.media);
    await starting;
    expect(backend.media.closes, 1);
    expect(commands, isEmpty);
    expect(controller.active, isFalse);
  });

  test('late server acknowledgement after stop is stopped immediately', () async {
    await controller.start(null, 'Share', screenOptions());
    await controller.stop();
    await event('available', client: 1, extra: {'name': 'Share'});
    expect(commands.last, {'action': 'stop', 'stream_id': 's'});
    expect(controller.active, isFalse);
  });

  test('channel change releases capture and all peer connections', () async {
    await controller.start(null, 'Share', screenOptions());
    await event('available', client: 1, extra: {'name': 'Share'});
    await event('join_requested', extra: {'leaving': false});
    controller.contextChanged(online: true, client: 1, channel: 20, clients: {1});
    await Future<void>.delayed(Duration.zero);
    expect(controller.active, isFalse);
    expect(backend.media.closes, 1);
    expect(backend.peers.single.closes, 1);
  });

  test('the publisher reads back what it is sending while a viewer is on', () async {
    // The readout is the only place the publisher's own numbers are visible,
    // and it is polled rather than pushed — so what this pins is that the poll
    // starts with the share, finds the connection, and stops with it.
    await controller.start(null, 'Share', screenOptions());
    await event('available', client: 1, extra: {'name': 'Share'});
    await event('join_requested', extra: {'leaving': false});
    expect(controller.rate, isNull);

    backend.peers.single.reading = const ScreenStats(1920, 1080, 29.6, null);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(controller.rate, const ScreenStats(1920, 1080, 29.6, null));

    // A reading that has not changed must not wake the window up again.
    var notified = 0;
    controller.addListener(() => notified++);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(notified, 0);

    await controller.stop();
    expect(controller.rate, isNull);

    // And again from scratch: a cancelled timer is not a null one, so a second
    // share has to get a new poll rather than the corpse of the first.
    await controller.start(null, 'Share', screenOptions());
    await event('available', client: 1, extra: {'name': 'Share'});
    await event('join_requested', extra: {'leaving': false});
    backend.peers.last.reading = const ScreenStats(1280, 720, 12.0, 'cpu');
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(controller.rate, const ScreenStats(1280, 720, 12.0, 'cpu'));
  });

  test('publisher enforces viewer limit locally', () async {
    await controller.start(null, 'Share', screenOptions().copyWith(viewerLimit: 4));
    await event('available', client: 1, extra: {'name': 'Share'});
    for (var id = 2; id <= 6; id++) { await event('join_requested', client: id, extra: {'leaving': false}); }
    expect(backend.peers.length, 4);
    expect(commands.last['accept'], isFalse);
    expect(commands.last['client_id'], 6);
  });

  test('zero is no limit, not a limit of zero', () async {
    // The wire says "as many as the server will carry" with a zero, so a
    // publisher who chose no limit must not refuse everybody — which is what
    // reading it as a number would do.
    await controller.start(null, 'Share', screenOptions());
    await event('available', client: 1, extra: {'name': 'Share'});
    for (var id = 2; id <= 6; id++) { await event('join_requested', client: id, extra: {'leaving': false}); }
    expect(backend.peers.length, 5);
    expect(commands.where((c) => c['action'] == 'respond').every((c) => c['accept'] == true), isTrue);
  });

  test('capture ending through the system stops publication', () async {
    await controller.start(null, 'Share', screenOptions());
    await event('available', client: 1, extra: {'name': 'Share'});
    backend.media.ended!();
    await Future<void>.delayed(Duration.zero);
    expect(controller.active, isFalse);
    expect(commands.last['action'], 'stop');
  });

  test('a stream the server already ended is released without telling it', () async {
    // A stop for a stream the server has ended goes unanswered, and the
    // command deadline turns that silence into a failure — which is how a
    // stale command tore down the next share (2026-10-08 logs).
    await controller.start(null, 'Share', screenOptions());
    await event('available', client: 1, extra: {'name': 'Share'});
    commands.clear();
    await event('stopped');
    expect(commands, isEmpty);
    expect(controller.active, isFalse);
    expect(backend.media.closes, 1);
  });

  test('watching a stream the server ended releases without a leave', () async {
    await controller.watch(2);
    await event('available', extra: {'name': 'Share'});
    await event('join_answered', extra: {'accepted': true, 'sdp': 'offer'});
    commands.clear();
    await event('stopped');
    expect(commands, isEmpty);
    expect(controller.watching, isFalse);
    expect(backend.peers.single.closes, 1);
  });

  test('refusal closes receiver and exposes an actionable state', () async {
    await controller.watch(2);
    await event('available', extra: {'name': 'Share'});
    await event('join_answered', extra: {'accepted': false, 'sdp': ''});
    expect(controller.error, 'refused');
    expect(controller.watching, isFalse);
    expect(backend.peers.single.closes, 1);
    // A refusal is not sticky server-side, so no leave goes out either — one
    // for a request that no longer exists would only earn the same silent
    // drop and a 15-second timeout.
    expect(commands.any((c) => c['action'] == 'leave'), isFalse);
  });

  test('the wire claims audio only when the capture produced a track', () async {
    // "Capture audio" used to reach the capture and the server but never the
    // offer — and on platforms whose capture has no loopback it claimed sound
    // that could not exist. The flag follows the capture now.
    backend.media.hasAudio = true;
    await controller.start(null, 'Share', screenOptions().copyWith(audio: true));
    expect((commands.single['options'] as Map)['audio'], isTrue);
    await controller.stop();

    backend.media.hasAudio = false;
    await controller.start(null, 'Share', screenOptions().copyWith(audio: true));
    expect((commands.last['options'] as Map)['audio'], isFalse);
  });

  test('a private share holds requests until the publisher answers', () async {
    await controller.start(
      null,
      'Share',
      screenOptions().copyWith(access: ScreenAccess.private),
    );
    await event('available', client: 1, extra: {'name': 'Share'});
    await event('join_requested', extra: {'leaving': false});
    // Waiting is the whole enforcement: nothing answered, nothing opened.
    expect(controller.pendingViewers, [2]);
    expect(backend.peers, isEmpty);
    expect(commands.map((c) => c['action']), ['start']);

    await controller.approveViewer(2);
    expect(controller.pendingViewers, isEmpty);
    expect(controller.viewers, 1);
    expect(backend.peers.single.calls, ['offer']);
    final respond = commands.where((c) => c['action'] == 'respond').single;
    expect(respond['accept'], isTrue);
    expect(respond['sdp'], 'local-offer');
  });

  test('contacts waits like private, and denying answers without connecting', () async {
    // This client has no contact list to check against, so contacts behaves
    // as private — the help text has said so all along; this is the behaviour
    // catching up to it.
    await controller.start(
      null,
      'Share',
      screenOptions().copyWith(access: ScreenAccess.contacts),
    );
    await event('available', client: 1, extra: {'name': 'Share'});
    await event('join_requested', extra: {'leaving': false});
    expect(controller.pendingViewers, [2]);

    await controller.denyViewer(2);
    expect(controller.pendingViewers, isEmpty);
    expect(backend.peers, isEmpty);
    expect(commands.last, {
      'action': 'respond',
      'stream_id': 's',
      'client_id': 2,
      'accept': false,
      'sdp': '',
    });
  });

  test('a withdrawn request leaves nothing behind and cannot be approved', () async {
    await controller.start(
      null,
      'Share',
      screenOptions().copyWith(access: ScreenAccess.private),
    );
    await event('available', client: 1, extra: {'name': 'Share'});
    await event('join_requested', extra: {'leaving': false});
    await event('join_requested', extra: {'leaving': true});
    expect(controller.pendingViewers, isEmpty);
    // The viewer gave up (its side waits about twenty-five seconds);
    // approving the dead request must not open a connection.
    await controller.approveViewer(2);
    expect(backend.peers, isEmpty);
    expect(commands.any((c) => c['action'] == 'respond'), isFalse);
  });

  test('stopping the share drops everything still waiting', () async {
    await controller.start(
      null,
      'Share',
      screenOptions().copyWith(access: ScreenAccess.private),
    );
    await event('available', client: 1, extra: {'name': 'Share'});
    await event('join_requested', extra: {'leaving': false});
    await controller.stop();
    expect(controller.pendingViewers, isEmpty);
  });

  test('someone who leaves the server takes their request with them', () async {
    await controller.start(
      null,
      'Share',
      screenOptions().copyWith(access: ScreenAccess.private),
    );
    await event('available', client: 1, extra: {'name': 'Share'});
    await event('join_requested', extra: {'leaving': false});
    controller.contextChanged(
      online: true,
      client: 1,
      channel: 10,
      clients: {1, 3, 4, 5, 6},
    );
    expect(controller.pendingViewers, isEmpty);
  });

  test('an explicit approval admits past the viewer limit', () async {
    // The limit suppresses *automatic* admission; a publisher who read the
    // request and said yes has said yes (the reference implementation reads
    // it the same way).
    await controller.start(
      null,
      'Share',
      screenOptions().copyWith(access: ScreenAccess.private, viewerLimit: 1),
    );
    await event('available', client: 1, extra: {'name': 'Share'});
    await event('join_requested', client: 2, extra: {'leaving': false});
    await event('join_requested', client: 3, extra: {'leaving': false});
    await controller.approveViewer(2);
    await controller.approveViewer(3);
    expect(controller.viewers, 2);
    expect(backend.peers.length, 2);
  });
}
