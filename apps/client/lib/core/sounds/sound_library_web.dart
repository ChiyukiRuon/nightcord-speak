import 'sound_pack.dart';

SoundLibrary createSoundLibrary() => _UnavailableSoundLibrary();

class _UnavailableSoundLibrary implements SoundLibrary {
  @override
  bool get available => false;
  @override
  Future<String> directory() async => '';
  @override
  Future<List<SoundPack>> scan() async => [];
  @override
  Future<void> save(String pack, Map<SoundAction, String?> mapping) async {}
  @override
  Future<void> play(String pack, String file, {String? output, double volume = 1}) async {}
}
