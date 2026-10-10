import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/app_info.dart';
import 'update_model.dart';

UpdateService createUpdateService() => NativeUpdateService();

class NativeUpdateService implements UpdateService {
  @override
  bool get available => Platform.isWindows || Platform.isMacOS;

  @override
  Future<DesktopUpdate?> check() async {
    if (!available) return null;
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
  Future<void> open(DesktopUpdate update) async {
    final page = update.page;
    if (page.scheme != 'https' ||
        page.host != 'github.com' ||
        !page.path.startsWith('/ChiyukiRuon/nightcord-speak/releases/tag/')) {
      throw const FormatException('Invalid release URL');
    }
    final result = Platform.isWindows
        ? await Process.run('rundll32.exe', [
            'url.dll,FileProtocolHandler',
            page.toString(),
          ])
        : await Process.run('/usr/bin/open', [page.toString()]);
    if (result.exitCode != 0) {
      throw const ProcessException('browser', [], 'Cannot open release page');
    }
  }
}
