import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/events.dart';
import '../../models/screen_options.dart';
import 'screen_share_backend.dart';

class SharedScreen {
  const SharedScreen(this.id, this.clientId, this.name);
  final String id;
  final int clientId;
  final String name;
}

class _Link {
  _Link(this.streamId, this.clientId);
  final String streamId;
  final int clientId;
  ScreenPeer? peer;
  bool ready = false;
  String? answeredOffer;
  final List<Map<String, dynamic>> candidates = [];
}

/// How often the publisher re-reads what it is sending.
///
/// One reader per window that is showing them, so this is the rate someone is
/// watching at rather than a protocol rate.
const Duration _rateEvery = Duration(seconds: 1);

/// Each session owns its peers, including when another server is visible.
class ScreenController extends ChangeNotifier {
  ScreenController({required this.backend, required this.send, this.onError});
  final ScreenShareBackend backend;
  final void Function(Map<String, dynamic>) send;
  final void Function(String)? onError;
  Set<int> _clients = {};
  final Map<String, SharedScreen> available = {};
  final Map<int, _Link> _viewers = {};
  _Link? _watch;
  ScreenMedia? preview;
  ScreenMedia? remote;

  /// What the encoder is producing, while we are the one publishing.
  ScreenStats? rate;

  String? publishing;

  /// What this share was started with. The publisher's own side of the
  /// agreement: the viewer limit it enforces, and the numbers the encoder and
  /// the capture were set up from.
  ScreenOptions? options;
  int? ownClient;
  int? _channel;
  int? _requested;
  bool connected = false;
  bool starting = false;
  bool disposed = false;
  String? error;
  Timer? _startTimer;
  Timer? _watchTimer;
  Timer? _rateTimer;
  int _epoch = 0;
  Future<void> _events = Future.value();
  int get viewers => _viewers.length;
  bool get watching => _requested != null || _watch != null;
  bool get receiving => remote != null && _watch?.ready == true;

  /// Watching, but the picture has not arrived yet.
  ///
  /// Its own question rather than `watching && remote == null` written at the
  /// call site, because the window it draws is the answer to it: a stream that
  /// has been agreed on but not connected to still deserves a frame.
  bool get watchPending => watching && remote == null;

  /// Which stream is ours to stop, if any.
  bool get active => starting || publishing != null;

  /// How many viewers this share allows, or 0 for as many as the server will
  /// carry.
  ///
  /// The one place the number lives now. It used to be written three times —
  /// the wire, this gate and two pieces of UI text — and changing it meant
  /// finding all of them.
  int get viewerLimit => options?.viewerLimit ?? 0;

  /// Whose stream we are watching, once the server has named it.
  ///
  /// The stream id is the server's; the person is what the window puts in its
  /// title, and what the member row highlights.
  int? get watchingClient => _watch?.clientId;

  /// Whether this person's share is the one we asked for.
  ///
  /// True from the moment the request goes out rather than from the moment the
  /// server answers: the badge is what the user just pressed, and a button that
  /// does not react until a round trip later reads as one that did not work.
  bool watches(int clientId) => _requested == clientId || _watch?.clientId == clientId;

  void _notify() { if (!disposed) notifyListeners(); }
  void _send(Map<String, dynamic> command) { if (connected && !disposed) send(command); }

  void contextChanged({required bool online, required int? client, required int? channel, required Set<int> clients}) {
    final changed = connected && (!online || ownClient != client || _channel != channel);
    if (changed) { unawaited(stop()); unawaited(leave()); available.clear(); }
    connected = online;
    _clients = clients;
    ownClient = client;
    _channel = channel;
    available.removeWhere((_, s) => !clients.contains(s.clientId));
    for (final id in _viewers.keys.toList()) {
      if (!clients.contains(id)) unawaited(_drop(id));
    }
    if (_watch != null && !clients.contains(_watch!.clientId)) unawaited(leave());
  }

  Future<void> start(ScreenSource? source, String name, ScreenOptions options) async {
    if (!connected || active || disposed) return;
    starting = true;
    error = null;
    final epoch = ++_epoch;
    _notify();
    try {
      final media = await backend.capture(source, options);
      if (epoch != _epoch || disposed || !connected) { await media.close(); return; }
      preview = media;
      media.onEnded = () => unawaited(stop());
      this.options = options;
      _send({'action': 'start', 'name': name, 'options': options.toJson()});
      _startTimer = Timer(const Duration(seconds: 20), () => fail('timeout'));
      // Nothing to read until a viewer's connection exists; the loop simply
      // finds nothing and waits.
      _rateTimer ??= Timer.periodic(_rateEvery, (_) => unawaited(_readRate()));
      _notify();
    } catch (_) { if (epoch == _epoch) fail('capture'); }
  }

  Future<void> stop() async {
    ++_epoch;
    _startTimer?.cancel();
    // Cleared, not just cancelled: `start` reuses the field with `??=`, and a
    // cancelled timer is not null — the second share would never be read.
    _rateTimer?.cancel();
    _rateTimer = null;
    final id = publishing;
    publishing = null;
    starting = false;
    rate = null;
    options = null;
    if (id != null) _send({'action': 'stop', 'stream_id': id});
    final media = preview;
    preview = null;
    final links = _viewers.values.toList();
    _viewers.clear();
    _notify();
    await Future.wait([if (media != null) media.close(), for (final link in links) if (link.peer != null) link.peer!.close()]);
  }

  /// Keeps [rate] current while we are publishing.
  ///
  /// Polled rather than pushed, for the same reason the microphone level is
  /// (see `docs/devices.md`): the number only matters while someone is looking
  /// at it, and a `getStats()` callback that runs whether or not anyone is
  /// would be paying for itself in a session that has the window closed.
  Future<void> _readRate() async {
    if (disposed || publishing == null) return;
    final peers = _viewers.values;
    if (peers.isEmpty) return;
    final reading = await peers.first.peer?.stats();
    if (disposed || reading == null || reading == rate) return;
    rate = reading;
    _notify();
  }

  Future<void> watch(int clientId) async {
    if (!connected || clientId == ownClient || disposed) return;
    await leave();
    _requested = clientId;
    error = null;
    _watchTimer = Timer(const Duration(seconds: 25), () { _error('timeout'); unawaited(leave()); });
    _send({'action': 'discover', 'client_id': clientId});
    _notify();
  }

  Future<void> leave() => _leave(tell: true);

  /// Release the server's viewer entry before another engine claims it.
  Future<T> transferWatch<T>(Future<T> Function(int clientId) open) async {
    final client = watchingClient;
    if (client == null) throw StateError('no stream to transfer');
    await leave();
    try {
      return await open(client);
    } catch (_) {
      if (!disposed && connected) await watch(client);
      rethrow;
    }
  }

  /// Gives up the picture without telling the server.
  ///
  /// Used when the host has already removed this engine's viewer entry.
  Future<void> abandon() => _leave(tell: false);

  Future<void> _leave({required bool tell}) async {
    _watchTimer?.cancel();
    _requested = null;
    final link = _watch;
    _watch = null;
    remote = null;
    if (tell && link != null) {
      _send({'action': 'leave', 'stream_id': link.streamId, 'client_id': link.clientId});
    }
    _notify();
    await link?.peer?.close();
  }

  bool _live(_Link link) => !disposed && connected && (identical(_watch, link) || identical(_viewers[link.clientId], link));
  void _signal(_Link link, Map<String, dynamic> signal) {
    if (_live(link)) _send({'action': 'signal', 'stream_id': link.streamId, 'client_id': link.clientId, 'signal': signal});
  }
  void _ready(_Link link) {
    link.ready = true;
    for (final c in link.candidates) { _signal(link, c); }
    link.candidates.clear();
  }
  Future<void> _open(_Link link) async {
    final peer = await backend.peer(options: options, onCandidate: (c) {
      if (!_live(link)) return;
      if (link.ready) { _signal(link, c); }
      else if (link.candidates.length < 128) { link.candidates.add(c); }
    }, onMedia: (media) {
      if (identical(_watch, link) && _live(link)) {
        remote = media;
        _watchTimer?.cancel();
        _notify();
      }
    }, onFailed: () {
      if (!_live(link)) return;
      _error('connection');
      if (identical(_watch, link)) { unawaited(leave()); }
      else { unawaited(_drop(link.clientId)); }
    });
    if (!_live(link)) { await peer.close(); return; }
    link.peer = peer;
  }

  Future<void> _answer(_Link link, String offer) async {
    // TS6 repeats an offer through join_answered and streamsignaling.
    if (link.answeredOffer == offer) return;
    final answer = await link.peer!.answer(offer);
    if (!_live(link)) return;
    link.answeredOffer = offer;
    _signal(link, {'type': 'answer', 'sdp': answer});
    _ready(link);
  }
  Future<void> _drop(int client) async {
    final link = _viewers.remove(client);
    _notify();
    await link?.peer?.close();
  }

  /// Serializes negotiation; ICE and answers must not race description setup.
  Future<void> receive(ScreenEvent event) {
    _events = _events.then((_) => _receive(event.data).timeout(const Duration(seconds: 15))).catchError((Object _) { fail('connection'); });
    return _events;
  }
  Future<void> _receive(Map<String, dynamic> e) async {
    if (disposed || !connected) return;
    final id = e['stream_id'] as String;
    final client = e['client_id'] as int?;
    switch (e['type']) {
      case 'available':
        available[id] = SharedScreen(id, client!, e['name'] as String);
        if (client == ownClient) {
          if (!starting && publishing != id) {
            _send({'action': 'stop', 'stream_id': id});
          } else {
            publishing = id;
            starting = false;
            _startTimer?.cancel();
          }
        } else if (_requested == client && _watch == null) {
          final link = _Link(id, client);
          _watch = link;
          await _open(link);
          if (_live(link)) _send({'action': 'join', 'stream_id': id, 'client_id': client});
        }
      case 'stopped':
        available.remove(id);
        if (publishing == id) await stop();
        if (_watch?.streamId == id) await leave();
      case 'join_requested':
        if (id != publishing || preview == null || client == ownClient || !_clients.contains(client)) return;
        if (e['leaving'] == true) { await _drop(client!); return; }
        if (_viewers.containsKey(client)) return;
        // Zero is the wire's way of saying "as many as the server will carry",
        // so it is not a limit of zero — the gate only exists when a number
        // was actually chosen.
        final limit = options?.viewerLimit ?? 0;
        if (limit > 0 && _viewers.length >= limit) {
          _send({'action': 'respond', 'stream_id': id, 'client_id': client, 'accept': false, 'sdp': ''});
          return;
        }
        final media = preview!;
        final link = _Link(id, client!);
        _viewers[client] = link;
        await _open(link);
        if (!_live(link)) return;
        final sdp = await link.peer!.offer(media);
        if (!_live(link)) return;
        _send({'action': 'respond', 'stream_id': id, 'client_id': client, 'accept': true, 'sdp': sdp});
        _ready(link);
      case 'join_answered':
        final link = _watch;
        if (link == null || id != link.streamId || client != link.clientId) return;
        if (e['accepted'] != true || (e['sdp'] as String).isEmpty) {
          _error('refused'); await leave(); return;
        }
        await _answer(link, e['sdp'] as String);
      case 'peer_left':
        if (id == publishing) await _drop(client!);
        if (id == _watch?.streamId && (client == ownClient || client == _watch?.clientId)) await leave();
      case 'signal':
        final link = id == publishing ? _viewers[client] : _watch;
        if (link == null || link.streamId != id || link.clientId != client || link.peer == null) return;
        final s = (e['signal'] as Map).cast<String, dynamic>();
        switch (s['type']) {
          case 'candidate': await link.peer!.candidate(s);
          case 'answer':
            if (id == publishing) await link.peer!.acceptAnswer(s['sdp'] as String);
          case 'offer':
            if (identical(link, _watch)) {
              await _answer(link, s['sdp'] as String);
            }
        }
    }
    _notify();
  }

  void fail(String reason) {
    if (disposed) return;
    _error(reason);
    unawaited(stop());
    unawaited(leave());
  }
  void _error(String reason) { error = reason; onError?.call(reason); }
  @override
  void dispose() {
    if (disposed) return;
    _rateTimer?.cancel();
    unawaited(stop());
    unawaited(leave());
    disposed = true;
    super.dispose();
  }
}
