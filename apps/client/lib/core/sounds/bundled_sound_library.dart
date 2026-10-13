import 'dart:convert';

import 'package:flutter/services.dart';

import 'sound_pack.dart';

/// Browser sounds always follow the shipped mapping, regardless of host settings.
class BundledSoundLibrary implements SoundLibrary {
  BundledSoundLibrary({required this.playAsset, AssetBundle? bundle})
    : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  final Future<void> Function(String asset, double volume) playAsset;
  Future<List<SoundPack>>? _packs;
  static const assetDirectory = 'assets/sounds/nightcord';

  @override
  bool get available => true;
  @override
  bool get supportsCustomPacks => false;
  @override
  Future<String> directory() async => '';
  @override
  Future<List<SoundPack>> scan() => _packs ??= _load();

  Future<List<SoundPack>> _load() async {
    final json = jsonDecode(
      await _bundle.loadString('$assetDirectory/config.json'),
    ) as Map;
    final actions = json['actions'] as Map;
    final mapping = <SoundAction, String?>{
      for (final action in SoundAction.values)
        action: actions[action.key] as String?,
    };
    return [
      SoundPack(
        name: 'nightcord',
        files: mapping.values.nonNulls.toSet().toList(),
        mapping: mapping,
      ),
    ];
  }

  @override
  Future<void> save(String pack, Map<SoundAction, String?> mapping) async {
    throw UnsupportedError('Bundled notification sounds are read-only');
  }

  @override
  Future<void> play(
    String pack,
    String file, {
    String? output,
    double volume = 1,
  }) async {
    final bundled = (await scan()).single;
    if (pack != bundled.name || !bundled.files.contains(file)) {
      throw const FormatException('Unknown bundled notification sound');
    }
    await playAsset('$assetDirectory/$file', volume.clamp(0.0, 1.0));
  }
}
