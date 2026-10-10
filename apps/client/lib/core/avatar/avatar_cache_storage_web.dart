import 'package:web/web.dart' as web;

import 'avatar_cache.dart';

AvatarCacheStorage createAvatarCacheStorage() => BrowserAvatarCacheStorage();

class BrowserAvatarCacheStorage implements AvatarCacheStorage {
  static const _key = 'nightcord.avatars.v1';

  @override
  Future<String?> read() async => web.window.localStorage.getItem(_key);

  @override
  Future<void> write(String data) async =>
      web.window.localStorage.setItem(_key, data);
}
