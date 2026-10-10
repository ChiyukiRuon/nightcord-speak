import 'sound_pack.dart';

Future<String?> chooseSoundDirectory() async => null;

SoundLibrary createSoundLibrary({String directory = ''}) => _UnavailableSoundLibrary();

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
