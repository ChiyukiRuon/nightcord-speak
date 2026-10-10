import 'dart:convert';
import 'dart:typed_data';

/// Persistence is optional: storage failures must not stop server downloads.
abstract interface class AvatarCacheStorage {
  Future<String?> read();
  Future<void> write(String data);
}

class AvatarCache {
  AvatarCache(this.storage);
  final AvatarCacheStorage storage;
  final _images = <String, Uint8List>{};
  Future<void>? _loaded;
  Future<void> _writes = Future.value();
  static const maxBytes = 2 * 1024 * 1024;

  String? _key(String? server, String? identity) =>
      server == null || server.isEmpty || identity == null || identity.isEmpty
      ? null
      : jsonEncode([server, identity]);

  Future<void> _load() async {
    try {
      final data = await storage.read();
      if (data == null || data.length > 3 * 1024 * 1024) return;
      final decoded = jsonDecode(data);
      if (decoded is! Map) return;
      for (final entry in decoded.entries) {
        if (entry.key is! String || entry.value is! String) continue;
        try {
          final bytes = base64Decode(entry.value as String);
          if (bytes.isNotEmpty && bytes.length <= maxBytes) {
            _images[entry.key as String] = bytes;
            _trim();
          }
        } on FormatException {
          // One damaged entry must not discard the other users' pictures.
        }
      }
    } catch (_) {
      // Missing, corrupt or inaccessible cache files behave like a cold start.
    }
  }

  void _trim() {
    var bytes = _images.values.fold(0, (total, image) => total + image.length);
    while (_images.length > 64 || bytes > maxBytes) {
      bytes -= _images.remove(_images.keys.first)!.length;
    }
  }

  Future<Uint8List?> read(String? server, String? identity) async {
    final key = _key(server, identity);
    if (key == null) return null;
    await (_loaded ??= _load());
    final image = _images.remove(key);
    if (image != null) _images[key] = image;
    return image;
  }

  Future<void> save(String? server, String? identity, Uint8List image) async {
    final key = _key(server, identity);
    if (key == null || image.isEmpty || image.length > maxBytes) return;
    await (_loaded ??= _load());
    _images.remove(key);
    _images[key] = image;
    _trim();
    final data = jsonEncode(
      _images.map((key, value) => MapEntry(key, base64Encode(value))),
    );
    // Serialize writes so a slow older snapshot cannot overwrite a newer one.
    _writes = _writes.then((_) async {
      try {
        await storage.write(data);
      } catch (_) {
        // Quota and disk errors degrade to the bounded in-memory cache.
      }
    });
    await _writes;
  }
}
