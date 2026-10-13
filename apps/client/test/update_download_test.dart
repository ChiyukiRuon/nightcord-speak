import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/core/updates/update_download.dart';
import 'package:nightcord_client/core/updates/update_model.dart';
import 'package:nightcord_client/core/updates/update_log.dart';

void main() {
  late Directory root;
  final content = utf8.encode('verified-update-content');
  final update = DesktopUpdate(
    '0.3.0',
    Uri.parse(
      'https://github.com/ChiyukiRuon/nightcord-speak/releases/download/v0.3.0/Nightcord-Speak-0.3.0-windows-x64.zip',
    ),
    Uri.parse(
      'https://github.com/ChiyukiRuon/nightcord-speak/releases/download/v0.3.0/Nightcord-Speak-0.3.0-windows-x64.json',
    ),
    platform: 'windows',
    arch: 'x64',
    fileName: 'Nightcord-Speak-0.3.0-windows-x64.zip',
    size: content.length,
    installer: false,
  );

  Map<String, dynamic> manifest() => {
    'version': update.version,
    'platform': update.platform,
    'arch': update.arch,
    'archive': update.fileName,
    'sha256': sha256.convert(content).toString(),
  };

  UpdateDownloader downloader({
    Map<String, dynamic>? metadata,
    List<int>? payload,
    int status = 200,
  }) => UpdateDownloader(
    temporaryDirectory: root,
    fetch: (uri) async => UpdateResponse(
      status,
      Stream.value(
        uri == update.manifest
            ? utf8.encode(jsonEncode(metadata ?? manifest()))
            : payload ?? content,
      ),
    ),
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('update-regression-');
    await File('${root.path}/unrelated').writeAsString('keep');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  Future<void> expectClean() async {
    expect((await root.list().toList()).length, 1);
    expect(await File('${root.path}/unrelated').readAsString(), 'keep');
  }

  test(
    'downloads into a private directory and verifies streamed bytes',
    () async {
      final progress = <double>[];
      final prepared = await downloader().download(update, progress.add);
      expect(await File(prepared.file).readAsBytes(), content);
      expect(prepared.sha256, sha256.convert(content).toString());
      expect(progress.last, 1);
    },
  );

  test(
    'tampering and truncated or oversized transfers remove partial files',
    () async {
      // Previously there was no in-client verification before executing an update.
      for (final payload in [
        List<int>.filled(content.length, 0),
        content.sublist(1),
        [...content, 0],
      ]) {
        await expectLater(
          downloader(payload: payload).download(update, (_) {}),
          throwsFormatException,
        );
        await expectClean();
      }
    },
  );

  test(
    'mismatched version, platform, architecture and filename are rejected',
    () async {
      for (final field in [
        'version',
        'platform',
        'arch',
        'archive',
        'sha256',
      ]) {
        await expectLater(
          downloader(metadata: manifest()..[field] = 'wrong')
              .download(update, (_) {}),
          throwsFormatException,
        );
        await expectClean();
      }
    },
  );

  test('transfer diagnostics record phases and throttle progress without logging URLs', () async {
    final messages = <String>[];
    final transfer = UpdateDownloader(
      temporaryDirectory: root,
      logger: UpdateLogger(sink: (_, message) => messages.add(message)),
      fetch: (uri) async => UpdateResponse(
        200,
        uri == update.manifest
            ? Stream.value(utf8.encode(jsonEncode(manifest())))
            : Stream.fromIterable(content.map((byte) => [byte])),
      ),
    );
    final prepared = await transfer.download(update, (_) {});
    expect(await File(prepared.file).readAsBytes(), content);
    expect(messages, contains(contains('manifest verified')));
    expect(messages, contains(contains('SHA-256 verification starting')));
    expect(messages.last, contains('download verified elapsed_ms='));
    expect(
      messages.where((line) => line.contains('download progress=')).length,
      4,
    );
    expect(messages.any((line) => line.contains('https://')), isFalse);
  });

  test('HTTP errors leave no package to install', () async {
    await expectLater(
      downloader(status: 500).download(update, (_) {}),
      throwsA(isA<HttpException>()),
    );
    await expectClean();
  });

  test(
    'cancellation removes only owned partial files and allows retry',
    () async {
      late UpdateDownloader transfer;
      transfer = UpdateDownloader(
        temporaryDirectory: root,
        fetch: (uri) async => UpdateResponse(
          200,
          uri == update.manifest
              ? Stream.value(utf8.encode(jsonEncode(manifest())))
              : Stream.fromIterable([
                  content.sublist(0, 2),
                  content.sublist(2),
                ]),
        ),
      );
      await expectLater(
        transfer.download(update, (_) => transfer.cancel()),
        throwsA(isA<UpdateCancelled>()),
      );
      await expectClean();
      expect(await transfer.download(update, (_) {}), isA<PreparedUpdate>());
    },
  );
}
