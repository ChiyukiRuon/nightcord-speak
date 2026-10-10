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
    expect(defaults.notifications.soundDirectory, isEmpty);
    final updated = defaults.copyWith(
      notifications: defaults.notifications.copyWith(
        sounds: false,
        soundPack: 'custom',
        soundDirectory: root.path,
      ),
    );
    final restored = Settings.fromJson(updated.toJson());
    expect(restored.notifications.sounds, isFalse);
    expect(restored.notifications.soundPack, 'custom');
    expect(restored.notifications.soundDirectory, root.path);
  });

  test('bundled sounds stay immutable and mappings survive external directory changes', () async {
    // macOS previously extracted defaults beside the signed application.
    final bundle = await Directory('${root.path}/app/nightcord').create(recursive: true);
    final external = await Directory('${root.path}/music').create();
    final configuration = Directory('${root.path}/data/nightcord');
    final bundledConfig = File('${bundle.path}/config.json');
    final original = jsonEncode({
      'version': 1,
      'actions': {'message': 'message.wav'},
    });
    await bundledConfig.writeAsString(original);
    await File('${bundle.path}/message.wav').writeAsString('fixture');
    final custom = await Directory('${external.path}/custom').create();
    await File('${custom.path}/hello.mp3').writeAsString('fixture');
    final unrelated = await Directory('${external.path}/unrelated').create();
    final externalDefault = await Directory('${external.path}/nightcord').create();
    await File('${externalDefault.path}/wrong.wav').writeAsString('fixture');
    final library = NativeSoundLibrary(external, bundle, configuration);
    final packs = await library.scan();
    expect(packs.map((pack) => pack.name), ['custom', 'nightcord']);
    expect(packs.last.files, ['message.wav']);
    expect(packs.last.mapping[SoundAction.message], 'message.wav');
    expect(await File('${unrelated.path}/config.json').exists(), isFalse);
    expect(await File('${externalDefault.path}/config.json').exists(), isFalse);
    await library.save('nightcord', {SoundAction.voiceJoined: 'message.wav'});
    expect(await bundledConfig.readAsString(), original);
    expect(await File('${configuration.path}/config.json').exists(), isTrue);
    final other = await Directory('${root.path}/other').create();
    final reloaded = NativeSoundLibrary(other, bundle, configuration);
    final restored = (await reloaded.scan()).single;
    expect(restored.mapping[SoundAction.voiceJoined], 'message.wav');
    expect(restored.mapping[SoundAction.message], isNull);
    expect(await Directory('${other.path}/nightcord').exists(), isFalse);
    await expectLater(
      reloaded.play('nightcord', 'missing.wav'),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('custom directories keep pack files and mappings isolated', () async {
    final first = await Directory('${root.path}/first').create();
    final second = await Directory('${root.path}/second').create();
    for (final directory in [first, second]) {
      final pack = await Directory('${directory.path}/custom').create();
      await File('${pack.path}/chat.wav').writeAsString('fixture');
    }
    final one = NativeSoundLibrary(first);
    final two = NativeSoundLibrary(second);
    await one.scan();
    await two.scan();
    await one.save('custom', {SoundAction.message: 'chat.wav'});
    expect((await one.scan()).first.mapping[SoundAction.message], 'chat.wav');
    expect((await two.scan()).first.mapping[SoundAction.message], isNull);
    expect(await two.directory(), second.absolute.path.replaceAll('/', Platform.pathSeparator));
  });
}
