import 'dart:io';

import '../../ffi/rust_client.dart' show coreLogDirectory;
import 'avatar_cache.dart';

AvatarCacheStorage createAvatarCacheStorage() => FileAvatarCacheStorage();

class FileAvatarCacheStorage implements AvatarCacheStorage {
  FileAvatarCacheStorage([this.file]);
  final File? file;

  File? _file() {
    if (file != null) return file;
    final logs = coreLogDirectory();
    if (logs == null) return null;
    return File('${Directory(logs).parent.path}/cache/avatars.json');
  }

  @override
  Future<String?> read() async {
    final target = _file();
    if (target == null || !await target.exists()) return null;
    if (await target.length() > 3 * 1024 * 1024) return null;
    return target.readAsString();
  }

  @override
  Future<void> write(String data) async {
    final target = _file();
    if (target == null) return;
    await target.parent.create(recursive: true);
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(data, flush: true);
    await temporary.rename(target.path);
  }
}
