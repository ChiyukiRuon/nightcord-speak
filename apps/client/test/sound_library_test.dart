import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/core/sounds/sound_library_native.dart';
import 'package:nightcord_client/core/sounds/sound_pack.dart';
import 'package:nightcord_client/models/settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late NativeSoundLibrary library;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('nightcord-sounds-');
    library = NativeSoundLibrary(root);
  });
  tearDown(() async => root.delete(recursive: true));

  test('directory handed to the opener is absolute and uses native separators', () async {
    final path = await library.directory();
    expect(path, root.absolute.path.replaceAll('/', Platform.pathSeparator));
    if (Platform.isWindows) expect(path, isNot(contains('/')));
  });

  test('extracts defaults and discovers only supported regular audio files', () async {
    final custom = await Directory('${root.path}/custom').create();
    for (final name in ['hello.WAV', 'mute.mp3', 'message.flac', 'ignored.txt']) {
      await File('${custom.path}/$name').writeAsString('fixture');
    }
    final packs = await library.scan();
    expect(packs.map((pack) => pack.name), ['custom', 'nightcord']);
    expect(packs.first.files, ['hello.WAV', 'message.flac', 'mute.mp3']);
    expect(await File('${custom.path}/config.json').exists(), isTrue);
    expect(await File('${root.path}/nightcord/config.json').exists(), isTrue);
  });

  test('mapping lives inside each pack and survives scanning and missing audio', () async {
    await library.scan();
    await library.save('nightcord', {SoundAction.message: 'chat.mp3'});
    final packs = await library.scan();
    expect(packs.single.mapping[SoundAction.message], 'chat.mp3');
    final config = jsonDecode(await File('${root.path}/nightcord/config.json').readAsString());
    expect(config['actions']['message'], 'chat.mp3');
    await expectLater(library.play('nightcord', 'chat.mp3'), throwsA(isA<FileSystemException>()));
  });

  test('unsafe mappings are refused without damaging saved configuration', () async {
    await library.scan();
    final config = File('${root.path}/nightcord/config.json');
    final original = await config.readAsString();
    await expectLater(library.save('../other', {}), throwsFormatException);
    await expectLater(
      library.save('nightcord', {SoundAction.message: '../secret.wav'}),
      throwsFormatException,
    );
    expect(await config.readAsString(), original);
  });

  test('malformed configuration is reported and preserved', () async {
    await library.scan();
    final config = File('${root.path}/nightcord/config.json');
    await config.writeAsString('invalid json');
    await expectLater(library.scan(), throwsFormatException);
    expect(await config.readAsString(), 'invalid json');
  });

  test('notification sound preference retains defaults and custom selection', () {
    final defaults = Settings.fromJson({});
    expect(defaults.notifications.sounds, isTrue);
    expect(defaults.notifications.soundPack, 'nightcord');
    final updated = defaults.copyWith(
      notifications: defaults.notifications.copyWith(sounds: false, soundPack: 'custom'),
    );
    final restored = Settings.fromJson(updated.toJson());
    expect(restored.notifications.sounds, isFalse);
    expect(restored.notifications.soundPack, 'custom');
  });
}
