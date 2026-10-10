import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/core/avatar/avatar_cache.dart';
import 'package:nightcord_client/core/avatar/avatar_cache_storage_native.dart';

void main() {
  late Directory directory;
  late FileAvatarCacheStorage storage;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'nightcord-avatar-cache-',
    );
    storage = FileAvatarCacheStorage(
      File('${directory.path}/cache/avatars.json'),
    );
  });
  tearDown(() async => directory.delete(recursive: true));

  test('cache survives restart and replaces existing files', () async {
    final cache = AvatarCache(storage);
    await cache.save('server', 'alice', Uint8List.fromList([1]));
    await cache.save('server', 'alice', Uint8List.fromList([2]));
    expect(await AvatarCache(storage).read('server', 'alice'), [2]);
  });

  test(
    'invalid files and entries fall back without breaking valid images',
    () async {
      await storage.write('broken');
      expect(await AvatarCache(storage).read('server', 'alice'), isNull);
      await storage.write(
        r'{"[\"server\",\"bob\"]":"!","[\"server\",\"alice\"]":"AQ=="}',
      );
      expect(await AvatarCache(storage).read('server', 'alice'), [1]);
    },
  );

  test(
    'persistent cache evicts old entries and bounds stored image bytes',
    () async {
      final cache = AvatarCache(storage);
      for (var id = 0; id < 65; id++) {
        await cache.save('server', '$id', Uint8List.fromList([id]));
      }
      expect(await cache.read('server', '0'), isNull);
      expect(await cache.read('server', '64'), [64]);
      await cache.save('server', 'large', Uint8List(AvatarCache.maxBytes));
      expect(await cache.read('server', '64'), isNull);
      expect(
        (await AvatarCache(storage).read('server', 'large'))?.length,
        AvatarCache.maxBytes,
      );
    },
  );
}
