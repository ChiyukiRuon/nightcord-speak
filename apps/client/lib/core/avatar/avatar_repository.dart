import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/events.dart';
import '../../providers/providers.dart';
import '../transport/client_transport.dart';
import 'avatar_cache.dart';
import 'avatar_cache_storage.dart';

/// Session and stable identity prevent an id reused by another user from
/// inheriting the previous user's cached picture.
typedef AvatarKey = ({
  int session,
  int clientId,
  String? identity,
  String version,
});

final avatarRepositoryProvider = Provider<AvatarRepository>((ref) {
  final repository = AvatarRepository(
    ref.watch(clientTransportProvider),
    persistentCache: AvatarCache(createAvatarCacheStorage()),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

final avatarImageProvider = StreamProvider.autoDispose
    .family<Uint8List?, AvatarKey>((ref, key) {
      final server = ref.watch(
        sessionsProvider.select(
          (sessions) => sessions[key.session]?.server?.address,
        ),
      );
      return ref.watch(avatarRepositoryProvider).watch(key, server: server);
    });

class _Request {
  _Request(this.key);
  final AvatarKey key;
  final done = Completer<Uint8List?>();
  Timer? timer;
}

/// Bounded memory cache and three simultaneous loads shared by chat and tree.
class AvatarRepository {
  AvatarRepository(this.transport, {this.persistentCache}) {
    _subscription = transport.events.listen(_event);
  }

  final ClientTransport transport;
  final AvatarCache? persistentCache;
  late final StreamSubscription<FfiEvent> _subscription;
  final _cache = <AvatarKey, Uint8List>{};
  final _requests = <AvatarKey, _Request>{};
  final _waiting = Queue<_Request>();
  final _active = <(int, int), _Request>{};
  final _failures = <AvatarKey, DateTime>{};
  int _bytes = 0;
  bool _disposed = false;

  /// A previous connection's picture remains visible while this session refreshes.
  Stream<Uint8List?> watch(AvatarKey key, {String? server}) async* {
    final cached = await persistentCache?.read(server, key.identity);
    if (_disposed) return;
    if (cached != null) yield cached;
    final fresh = await fetch(key);
    if (_disposed) return;
    // Start persistence before yielding: a widget can unsubscribe as soon as
    // it receives the image, which cancels the remainder of an async generator.
    final saving = fresh == null
        ? null
        : persistentCache?.save(server, key.identity, fresh);
    yield fresh ?? cached;
    await saving;
  }

  Future<Uint8List?> fetch(AvatarKey key) {
    if (_disposed) return Future.value(null);
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return Future.value(cached);
    }
    final failed = _failures[key];
    if (failed != null &&
        DateTime.now().difference(failed) < const Duration(seconds: 30)) {
      return Future.value(null);
    }
    final existing = _requests[key];
    if (existing != null) return existing.done.future;
    if (_requests.length >= 64) return Future.value(null);
    final request = _Request(key);
    _requests[key] = request;
    _waiting.add(request);
    _pump();
    return request.done.future;
  }

  void _pump() {
    if (_disposed) return;
    // A second revision of the same client must wait for the previous answer:
    // failed responses carry the client id, but have no image revision.
    for (final request in _waiting.toList()) {
      if (_active.length >= 3) break;
      final key = request.key;
      final address = (key.session, key.clientId);
      if (_active.containsKey(address)) continue;
      _waiting.remove(request);
      _active[address] = request;
      request.timer = Timer(
        const Duration(seconds: 28),
        () => _finish(request, null),
      );
      try {
        transport.getAvatar(key.session, key.clientId);
      } catch (_) {
        _finish(request, null);
      }
    }
  }

  void _event(FfiEvent event) {
    if (event is! CommandResultEvent || event.result.command != 'get_avatar') {
      return;
    }
    final result = event.result;
    final request = _active[(result.session, result.data?['client_id'])];
    if (request == null) return;
    Uint8List? bytes;
    if (result.ok && result.data?['version'] == request.key.version) {
      final encoded = result.data?['image'];
      if (encoded is String && encoded.length <= 2796204) {
        try {
          final decoded = base64Decode(encoded);
          if (decoded.isNotEmpty && decoded.length <= 2 * 1024 * 1024) {
            bytes = decoded;
          }
        } on FormatException {
          // A newer or malformed core response must still fall back safely.
        }
      }
    }
    _finish(request, bytes);
  }

  void _finish(_Request request, Uint8List? bytes) {
    if (request.done.isCompleted) return;
    request.timer?.cancel();
    _active.remove((request.key.session, request.key.clientId));
    _requests.remove(request.key);
    if (bytes != null) {
      _cache[request.key] = bytes;
      _bytes += bytes.length;
      while (_cache.length > 128 || _bytes > 16 * 1024 * 1024) {
        _bytes -= _cache.remove(_cache.keys.first)!.length;
      }
    } else {
      _failures[request.key] = DateTime.now();
      while (_failures.length > 128) {
        _failures.remove(_failures.keys.first);
      }
    }
    request.done.complete(bytes);
    _pump();
  }

  void dispose() {
    _disposed = true;
    _subscription.cancel();
    for (final request in _requests.values) {
      request.timer?.cancel();
      if (!request.done.isCompleted) request.done.complete(null);
    }
    _requests.clear();
    _waiting.clear();
    _active.clear();
    _cache.clear();
  }
}
