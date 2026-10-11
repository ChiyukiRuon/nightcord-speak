import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:nightcord_client/core/updates/update_download.dart';
import 'package:nightcord_client/core/updates/update_model.dart';

Future<void> main() async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse(
        'https://api.github.com/repos/ChiyukiRuon/nightcord-speak/releases?per_page=100',
      ),
    );
    request.headers.set('User-Agent', 'Nightcord-Update-Download-Smoke');
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('Release list HTTP ${response.statusCode}');
    }
    final releases =
        jsonDecode(await response.transform(utf8.decoder).join()) as List;
    final update = selectDesktopUpdate(
      releases,
      '0.0.0',
      'windows',
      installer: false,
    );
    if (update == null) throw StateError('No published Windows artifact');
    final prepared = await UpdateDownloader().download(update, (_) {});
    try {
      if ((await sha256.bind(File(prepared.file).openRead()).first)
              .toString() !=
          prepared.sha256) {
        throw StateError('Downloaded artifact mismatch');
      }
      stdout.writeln(
        'Verified real GitHub download: ${update.fileName} (${update.size} bytes).',
      );
    } finally {
      await Directory(prepared.directory).delete(recursive: true);
    }
  } finally {
    client.close(force: true);
  }
}
