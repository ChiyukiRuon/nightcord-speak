import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/core/sounds/bundled_sound_library.dart';
import 'package:nightcord_client/core/sounds/sound_pack.dart';
import 'package:nightcord_client/models/settings.dart';
import 'package:nightcord_client/providers/sounds.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'browser uses shipped mappings even when gateway selected a custom pack',
    () async {
      // The browser cannot read custom paths or packs selected by its host.
      final played = <(String, double)>[];
      final library = BundledSoundLibrary(
        playAsset: (asset, volume) async => played.add((asset, volume)),
      );
      final container = ProviderContainer(
        overrides: [soundLibraryProvider.overrideWithValue(library)],
      );
      addTearDown(container.dispose);
      const settings = Settings(
        notifications: NotificationSettings(
          soundPack: 'custom',
          soundDirectory: '/host/music',
        ),
      );
      final play = Provider(
        (ref) => playSoundActions(ref, [
          SoundAction.voiceJoined,
          SoundAction.message,
        ], settings),
      );
      await container.read(play);
      expect(played.map((entry) => entry.$1), [
        'assets/sounds/nightcord/connected.wav',
        'assets/sounds/nightcord/new_message.wav',
      ]);
      final disabled = Provider(
        (ref) => playSoundActions(
          ref,
          [SoundAction.message],
          settings.copyWith(
            notifications: settings.notifications.copyWith(sounds: false),
          ),
        ),
      );
      await container.read(disabled);
      expect(played, hasLength(2));
      expect(library.available, isTrue);
      expect(library.supportsCustomPacks, isFalse);
      expect(await library.directory(), isEmpty);
    },
  );

  test(
    'bundled playback rejects custom assets and clamps browser volume',
    () async {
      final volumes = <double>[];
      final library = BundledSoundLibrary(
        playAsset: (_, volume) async => volumes.add(volume),
      );
      await library.play('nightcord', 'connected.wav', volume: 2);
      await library.play('nightcord', 'connected.wav', volume: -1);
      expect(volumes, [1, 0]);
      await expectLater(
        library.play('custom', 'connected.wav'),
        throwsFormatException,
      );
      await expectLater(
        library.play('nightcord', '../connected.wav'),
        throwsFormatException,
      );
      await expectLater(library.save('nightcord', {}), throwsUnsupportedError);
    },
  );
}
