import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/sounds/sound_library.dart';
import '../models/settings.dart';
import 'providers.dart' show settingsProvider;
import '../state/sound_policy.dart';
import '../core/platform/services.dart' show logToCore;
import '../util/reveal.dart';

final soundDirectoryOpenerProvider = Provider<Future<void> Function(String)>(
  (ref) => revealDirectory,
);

final soundDirectoryChooserProvider = Provider<Future<String?> Function()>(
  (ref) => chooseSoundDirectory,
);
final soundLibraryProvider = Provider<SoundLibrary>(
  (ref) => createSoundLibrary(
    directory: ref.watch(
      settingsProvider.select((settings) => settings?.notifications.soundDirectory ?? ''),
    ),
  ),
);
final soundPacksProvider = FutureProvider<List<SoundPack>>(
  (ref) => ref.watch(soundLibraryProvider).scan(),
);
final soundPolicyProvider = Provider<SoundPolicy>((ref) => SoundPolicy());

Future<void> playSoundActions(Ref ref, List<SoundAction> actions, Settings? settings) async {
  if (actions.isEmpty || settings == null || !settings.notifications.sounds) return;
  final library = ref.read(soundLibraryProvider);
  if (!library.available) return;
  try {
    final packs = await ref.read(soundPacksProvider.future);
    final pack = packs.where((pack) => pack.name == settings.notifications.soundPack).firstOrNull;
    if (pack == null) return;
    for (final action in actions) {
      final file = pack.mapping[action];
      if (file == null || !pack.files.contains(file)) continue;
      await library.play(
        pack.name,
        file,
        output: settings.audio.outputDevice,
        volume: settings.audio.outputVolume,
      );
    }
  } catch (_) {
    logToCore('warn', 'Could not load or play notification sound');
  }
}
