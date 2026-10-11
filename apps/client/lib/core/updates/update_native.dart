import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../../models/app_info.dart';
import 'update_model.dart';
import 'update_download.dart';

UpdateService createUpdateService() => NativeUpdateService();

class NativeUpdateService implements UpdateService {
  final _downloader = UpdateDownloader();
  bool _installer = false;
  bool _handedOff = false;
  PreparedUpdate? _prepared;
  final String _arch = Abi.current() == Abi.macosArm64 ? 'arm64' : 'x64';
  @override
  bool get available => Platform.isWindows || Platform.isMacOS;

  @override
  Future<DesktopUpdate?> check() async {
    if (!available) return null;
    await _discard();
    _installer = false;
    if (Platform.isWindows &&
        await File(
          '${File(Platform.resolvedExecutable).parent.path}/unins000.exe',
        ).exists()) {
      final registry = await Process.run('reg.exe', [
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\NightcordSpeak_is1',
        '/v',
        'InstallLocation',
        '/reg:64',
      ]);
      final match = RegExp(r'InstallLocation\s+REG_SZ\s+(.+)')
          .firstMatch(registry.stdout.toString());
      if (match != null) {
        final installed = match
            .group(1)!
            .trim()
            .replaceAll(RegExp(r'[\\/]+$'), '')
            .toLowerCase();
        _installer =
            installed ==
            File(Platform.resolvedExecutable).parent.absolute.path
                .toLowerCase();
      }
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      return await (() async {
        final releases = <dynamic>[];
        // Paginate so recent patches for the other platform do not hide this one.
        for (var page = 1; page <= 10; page++) {
          final request = await client.getUrl(
            Uri.https(
              'api.github.com',
              '/repos/ChiyukiRuon/nightcord-speak/releases',
              {'per_page': '100', 'page': '$page'},
            ),
          );
          request.headers.set('Accept', 'application/vnd.github+json');
          request.headers.set('User-Agent', 'Nightcord-Speak/$appVersion');
          request.headers.set('X-GitHub-Api-Version', '2022-11-28');
          final response = await request.close();
          if (response.statusCode != 200) {
            throw HttpException('Release HTTP ${response.statusCode}');
          }
          final body = StringBuffer();
          await for (final chunk in response.transform(utf8.decoder)) {
            body.write(chunk);
            if (body.length > 8 * 1024 * 1024) {
              throw const FormatException('Release response too large');
            }
          }
          final items = jsonDecode(body.toString()) as List<dynamic>;
          releases.addAll(items);
          if (items.length < 100) {
            return selectDesktopUpdate(
              releases,
              appVersion,
              Platform.isWindows ? 'windows' : 'macos',
              arch: _arch,
              installer: _installer,
            );
          }
        }
        throw const HttpException('Release history exceeds pagination limit');
      })().timeout(const Duration(seconds: 30));
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<PreparedUpdate> download(
    DesktopUpdate update,
    void Function(double) progress,
  ) async {
    await _discard();
    return _prepared = await _downloader.download(update, progress);
  }

  Future<void> _discard() async {
    final prepared = _prepared;
    _prepared = null;
    if (prepared != null && !_handedOff) {
      final directory = Directory(prepared.directory);
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  }

  @override
  void cancelDownload() {
    _downloader.cancel();
    if (!_handedOff) unawaited(_discard().catchError((Object _) {}));
  }

  @override
  Future<void> install(PreparedUpdate prepared, String language) async {
    if (_handedOff) throw StateError('Update already handed to helper');
    final directory = Directory(prepared.directory);
    final file = File(prepared.file);
    if (!await file.exists() ||
        (await sha256.bind(file.openRead()).first).toString() !=
            prepared.sha256) {
      throw const FormatException('Downloaded update changed');
    }
    final executable = File(Platform.resolvedExecutable);
    final target = Platform.isMacOS
        ? executable.parent.parent.parent.path
        : executable.parent.path;
    if (Platform.isMacOS && !target.endsWith('.app')) {
      throw const FileSystemException('Application bundle unavailable');
    }
    final nonce = List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final configuration = File('${directory.path}/update.json');
    for (final name in ['ready', 'error', 'commit']) {
      final stale = File('${directory.path}/$name');
      if (await stale.exists()) await stale.delete();
    }
    await configuration.writeAsString(
      jsonEncode({
        'parent_pid': pid,
        'target': target,
        'package': prepared.file,
        'sha256': prepared.sha256,
        'version': prepared.update.version,
        'installer': prepared.update.installer,
        'nonce': nonce,
        'language': language,
      }),
      flush: true,
    );
    if (Platform.isWindows) {
      final script = File('${directory.path}/update.ps1');
      // Windows PowerShell 5 reads scripts without a BOM using the ANSI code page.
      await script.writeAsString(
        '\uFEFF${await rootBundle.loadString('assets/updates/windows.ps1')}',
        flush: true,
      );
      await Process.start('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-File',
        script.path,
        '-Configuration',
        configuration.path,
      ], mode: ProcessStartMode.detached);
    } else {
      final helper = '$target/Contents/Helpers/NightcordUpdater.app';
      if (!await Directory(helper).exists()) {
        throw const FileSystemException('Update helper unavailable');
      }
      final opened = await Process.run('/usr/bin/open', [
        '-n',
        '-a',
        helper,
        '--args',
        configuration.path,
      ]);
      if (opened.exitCode != 0) {
        throw const ProcessException('open', [], 'Cannot start update helper');
      }
    }
    final ready = File('${directory.path}/ready');
    for (var attempt = 0; attempt < 600; attempt++) {
      final error = File('${directory.path}/error');
      if (await error.exists()) {
        throw const FileSystemException('Update helper preparation failed');
      }
      if (await ready.exists() && await ready.readAsString() == nonce) {
        await File('${directory.path}/commit')
            .writeAsString(nonce, flush: true);
        _handedOff = true;
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    // No ready acknowledgement means the client stays open and the helper
    // never gets permission to overwrite a running application.
    throw const FileSystemException(
      'Update helper did not acknowledge readiness',
    );
  }
}
