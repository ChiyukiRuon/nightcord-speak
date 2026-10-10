enum SoundAction {
  voiceJoined('voice_joined'),
  voiceLeft('voice_left'),
  microphoneOff('microphone_off'),
  microphoneOn('microphone_on'),
  speakersOff('speakers_off'),
  speakersOn('speakers_on'),
  awayOn('away_on'),
  awayOff('away_off'),
  message('message');

  const SoundAction(this.key);
  final String key;
}

class SoundPack {
  const SoundPack({required this.name, required this.files, required this.mapping});
  final String name;
  final List<String> files;
  final Map<SoundAction, String?> mapping;
}

bool soundFileName(String name) =>
    safeSoundName(name) && RegExp(r'\.(wav|mp3|flac)$', caseSensitive: false).hasMatch(name);

bool safeSoundName(String name) =>
    name.isNotEmpty && name != '.' && name != '..' && !RegExp(r'[/\\:\x00]').hasMatch(name);

abstract interface class SoundLibrary {
  bool get available;
  Future<String> directory();
  Future<List<SoundPack>> scan();
  Future<void> save(String pack, Map<SoundAction, String?> mapping);
  Future<void> play(String pack, String file, {String? output, double volume = 1});
}
