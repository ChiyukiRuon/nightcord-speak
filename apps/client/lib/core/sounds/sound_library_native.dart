import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

import '../../ffi/native.dart';
import '../../ffi/rust_client.dart' show coreLogDirectory;
import 'sound_pack.dart';

SoundLibrary createSoundLibrary() => NativeSoundLibrary();

typedef _PlayC = Bool Function(Pointer<Utf8>, Pointer<Utf8>, Float);
typedef _PlayDart = bool Function(Pointer<Utf8>, Pointer<Utf8>, double);

/// Filesystem access and native playback are capabilities, never widget branches.
class NativeSoundLibrary implements SoundLibrary {
  NativeSoundLibrary([this._root]);
  Directory? _root;
  @override
  bool get available => true;

  @override
  Future<String> directory() async {
    if (_root == null) {
      var parent = File(Platform.resolvedExecutable).parent;
      // Keep user-editable files outside signed macOS application bundles.
      if (Platform.isMacOS && parent.parent.parent.path.endsWith('.app')) {
        parent = parent.parent.parent.parent;
      } else if (Platform.isAndroid || Platform.isIOS) {
        final logs = coreLogDirectory();
        if (logs == null) throw const FileSystemException('Application data directory unavailable');
        parent = Directory(logs).parent;
      }
      _root = Directory('${parent.path}/sounds');
    }
    await _root!.create(recursive: true);
    return _root!.absolute.path.replaceAll('/', Platform.pathSeparator);
  }

  Future<Directory> _pack(String name) async {
    if (!safeSoundName(name)) throw const FormatException('Invalid sound pack name');
    final root = await directory();
    final pack = Directory('$root/$name');
    if (await FileSystemEntity.type(pack.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FileSystemException('Sound pack is missing or is a symbolic link');
    }
    return pack;
  }

  @override
  Future<List<SoundPack>> scan() async {
    final root = await directory();
    final defaultPack = Directory('$root/nightcord');
    if (await FileSystemEntity.type(defaultPack.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      await defaultPack.create();
    }
    if (await FileSystemEntity.type(defaultPack.path, followLinks: false) ==
        FileSystemEntityType.directory) {
      // Extract shipped defaults once; upgrades must not overwrite user mappings.
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      for (final asset in manifest.listAssets().where(
        (asset) => asset.startsWith('assets/sounds/nightcord/'),
      )) {
        final name = asset.split('/').last;
        if (!safeSoundName(name)) continue;
        final destination = File('${defaultPack.path}/$name');
        if (await FileSystemEntity.type(destination.path, followLinks: false) !=
            FileSystemEntityType.notFound) {
          continue;
        }
        final data = await rootBundle.load(asset);
        await destination.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      }
    }
    final packs = <SoundPack>[];
    await for (final entity in Directory(root).list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = entity.uri.pathSegments.where((segment) => segment.isNotEmpty).last;
      if (!safeSoundName(name)) continue;
      final files = <String>[];
      await for (final file in entity.list(followLinks: false)) {
        if (file is! File) continue;
        final name = file.uri.pathSegments.last;
        if (soundFileName(name)) files.add(name);
      }
      files.sort();
      final config = File('${entity.path}/config.json');
      final mapping = <SoundAction, String?>{};
      if (await FileSystemEntity.type(config.path, followLinks: false) ==
          FileSystemEntityType.notFound) {
        // New packs start unassigned; never guess which voice line an action means.
        await save(name, {for (final action in SoundAction.values) action: null});
      } else {
        if (await FileSystemEntity.type(config.path, followLinks: false) !=
            FileSystemEntityType.file) {
          throw const FileSystemException('Sound config must be a regular file');
        }
        if (await config.length() > 65536) throw const FormatException('Sound config is too large');
        final json = jsonDecode(await config.readAsString());
        if (json is! Map || json['version'] != 1 || json['actions'] is! Map) {
          throw FormatException('Invalid sound config: $name');
        }
        final actions = json['actions'] as Map;
        for (final action in SoundAction.values) {
          final file = actions[action.key];
          if (file != null && (file is! String || !soundFileName(file))) {
            throw FormatException('Invalid sound mapping: $name');
          }
          // Retain missing filenames in the editor, so removal is visible.
          mapping[action] = file as String?;
        }
      }
      packs.add(SoundPack(name: name, files: files, mapping: mapping));
    }
    packs.sort((a, b) => a.name.compareTo(b.name));
    return packs;
  }

  @override
  Future<void> save(String pack, Map<SoundAction, String?> mapping) async {
    final directory = await _pack(pack);
    for (final file in mapping.values) {
      if (file != null && !soundFileName(file)) {
        throw const FormatException('Invalid sound filename');
      }
    }
    final config = File('${directory.path}/config.json');
    final type = await FileSystemEntity.type(config.path, followLinks: false);
    if (type != FileSystemEntityType.notFound && type != FileSystemEntityType.file) {
      throw const FileSystemException('Sound config must be a regular file');
    }
    final temporary = File(
      '${directory.path}/.config-${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temporary.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert({
          'version': 1,
          'actions': {for (final action in SoundAction.values) action.key: mapping[action]},
        })}\n',
        flush: true,
      );
      await temporary.rename(config.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  @override
  Future<void> play(String pack, String file, {String? output, double volume = 1}) async {
    if (!soundFileName(file)) throw const FormatException('Invalid sound filename');
    final directory = await _pack(pack);
    final path = '${directory.path}/$file';
    if (await FileSystemEntity.type(path, followLinks: false) != FileSystemEntityType.file) {
      throw const FileSystemException('Sound file is missing or is a symbolic link');
    }
    final native = NativeLibrary.load().library;
    final play = native.lookupFunction<_PlayC, _PlayDart>('nightcord_play_notification_sound');
    final pathPointer = path.toNativeUtf8();
    final outputPointer = output?.toNativeUtf8() ?? nullptr;
    try {
      if (!play(pathPointer, outputPointer, volume)) {
        throw StateError('Sound playback queue is full');
      }
    } finally {
      calloc.free(pathPointer);
      if (outputPointer != nullptr) calloc.free(outputPointer);
    }
  }
}
