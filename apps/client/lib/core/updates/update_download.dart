import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'update_model.dart';
import 'update_log.dart';

class UpdateResponse {
  UpdateResponse(this.status, this.body);
  final int status;
  final Stream<List<int>> body;
}

typedef UpdateFetch = Future<UpdateResponse> Function(Uri);

/// One downloader owns one transfer; cancellation closes the connection and
/// removes partial files. Fetch injection keeps regression tests offline.
class UpdateDownloader {
  UpdateDownloader({
    this._fetch,
    this._temporaryDirectory,
    this.logger = updateLogger,
  });
  final UpdateLogger logger;
  final UpdateFetch? _fetch;
  final Directory? _temporaryDirectory;
  HttpClient? _client;
  bool _cancelled = false;
  bool _active = false;

  void cancel() {
    if (_active) logger('info', 'download cancellation requested');
    _cancelled = true;
    _client?.close(force: true);
  }

  Future<UpdateResponse> _get(Uri uri) async {
    if (_cancelled) throw UpdateCancelled();
    if (_fetch != null) return _fetch(uri);
    for (var redirects = 0; redirects < 6; redirects++) {
      // GitHub release assets redirect to their own CDN; never send a request
      // to a URL chosen by an arbitrary redirect or a non-HTTPS endpoint.
      if (uri.scheme != 'https' ||
          uri.userInfo.isNotEmpty ||
          uri.port != 443 ||
          !{
            'github.com',
            'release-assets.githubusercontent.com',
            'objects.githubusercontent.com',
          }.contains(uri.host)) {
        throw const FormatException('Invalid update download origin');
      }
      final request = await _client!.getUrl(uri);
      request.followRedirects = false;
      request.headers.set('User-Agent', 'Nightcord-Speak-Updater');
      final response = await request.close();
      logger(
        'debug',
        'download response host=${uri.host} status=${response.statusCode} redirect=$redirects',
      );
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location == null) {
          throw const HttpException('Missing download redirect');
        }
        uri = uri.resolve(location);
        continue;
      }
      return UpdateResponse(
        response.statusCode,
        response.timeout(const Duration(seconds: 30)),
      );
    }
    throw const HttpException('Too many download redirects');
  }

  Future<PreparedUpdate> download(
    DesktopUpdate update,
    void Function(double) progress,
  ) async {
    if (_active) throw StateError('Update download already running');
    final tag = 'v${update.version}';
    final manifestName = update.fileName.replaceFirst(
      RegExp(r'\.(exe|zip)$'),
      '.json',
    );
    if (!isReleaseAssetUrl(update.asset, tag, update.fileName) ||
        !isReleaseAssetUrl(update.manifest, tag, manifestName) ||
        update.size <= 0 ||
        update.size > 512 * 1024 * 1024) {
      throw const FormatException('Invalid update artifact');
    }
    _active = true;
    _cancelled = false;
    _client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    Directory? directory;
    final timer = Stopwatch()..start();
    logger(
      'info',
      'download started version=${update.version} platform=${update.platform} arch=${update.arch} installer=${update.installer} expected_bytes=${update.size}',
    );
    try {
      return await (() async {
        final manifestResponse = await _get(update.manifest);
        logger('info', 'manifest response status=${manifestResponse.status}');
        if (manifestResponse.status != 200) {
          throw const HttpException('Update manifest unavailable');
        }
        final bytes = <int>[];
        await for (final chunk in manifestResponse.body) {
          if (_cancelled) throw UpdateCancelled();
          bytes.addAll(chunk);
          if (bytes.length > 64 * 1024) {
            throw const FormatException('Update manifest too large');
          }
        }
        final manifest = jsonDecode(utf8.decode(bytes));
        if (manifest is! Map ||
            manifest['version'] != update.version ||
            manifest['platform'] != update.platform ||
            manifest['arch'] != update.arch ||
            manifest['archive'] != update.fileName ||
            manifest['sha256'] is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(manifest['sha256'])) {
          throw const FormatException('Update manifest mismatch');
        }
        directory = await (_temporaryDirectory ?? Directory.systemTemp)
            .createTemp('nightcord-update-');
        final file = File('${directory!.path}/${update.fileName}');
        logger(
          'info',
          'manifest verified; package transfer starting directory=${directory!.path}',
        );
        final response = await _get(update.asset);
        logger('info', 'package response status=${response.status}');
        if (response.status != 200) {
          throw const HttpException('Update package unavailable');
        }
        var received = 0;
        var milestone = 0;
        final sink = file.openWrite();
        try {
          await for (final chunk in response.body) {
            if (_cancelled) throw UpdateCancelled();
            received += chunk.length;
            if (received > update.size) {
              throw const FormatException('Update package too large');
            }
            sink.add(chunk);
            await sink.flush();
            final reached = (received * 4 ~/ update.size) * 25;
            if (reached > milestone) {
              milestone = reached;
              logger(
                'info',
                'download progress=$milestone% bytes=$received/${update.size} elapsed_ms=${timer.elapsedMilliseconds}',
              );
            }
            progress(received / update.size);
          }
        } finally {
          await sink.close();
        }
        if (_cancelled) throw UpdateCancelled();
        if (received != update.size) {
          throw const FormatException('Incomplete update package');
        }
        logger(
          'info',
          'transfer completed bytes=$received; SHA-256 verification starting',
        );
        final digest = (await sha256.bind(file.openRead()).first).toString();
        if (_cancelled) throw UpdateCancelled();
        if (digest != manifest['sha256']) {
          logger(
            'error',
            'checksum mismatch expected=${manifest['sha256']} actual=$digest',
          );
          throw const FormatException('Update checksum mismatch');
        }
        logger(
          'info',
          'download verified elapsed_ms=${timer.elapsedMilliseconds}',
        );
        return PreparedUpdate(update, directory!.path, file.path, digest);
      })().timeout(const Duration(minutes: 15));
    } catch (error, stack) {
      final cancelled = _cancelled;
      logger(
        cancelled ? 'info' : 'error',
        'download ${cancelled ? 'cancelled' : 'failed'} elapsed_ms=${timer.elapsedMilliseconds}: $error\n$stack',
      );
      _cancelled = true;
      _client?.close(force: true);
      if (directory != null && await directory!.exists()) {
        await directory!.delete(recursive: true);
      }
      if (cancelled) throw UpdateCancelled();
      rethrow;
    } finally {
      _client?.close(force: true);
      _client = null;
      _active = false;
    }
  }
}
