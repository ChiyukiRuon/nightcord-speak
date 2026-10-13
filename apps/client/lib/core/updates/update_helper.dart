import 'dart:async';
import 'dart:io';

import 'update_model.dart';
import 'update_log.dart';

/// Keep the client open until preparation and any UAC prompt have finished.
Future<void> waitForUpdateHelper(
  Directory directory,
  String nonce, {
  String markerPrefix = '',
  Duration preparationTimeout = const Duration(seconds: 60),
  Duration elevationTimeout = const Duration(minutes: 5),
  Duration pollInterval = const Duration(milliseconds: 100),
  UpdateLogger logger = updateLogger,
}) async {
  final clock = Stopwatch()..start();
  var timeout = preparationTimeout;
  var elevationSeen = false;
  var nextHeartbeat = const Duration(seconds: 10);
  logger(
    'info',
    'waiting for helper attempt=$nonce preparation_timeout_ms=${preparationTimeout.inMilliseconds} directory=${directory.path}',
  );
  Future<bool> acknowledged(String name) async {
    final file = File('${directory.path}/$markerPrefix$name');
    return await file.exists() && await file.readAsString() == nonce;
  }

  while (true) {
    if (await acknowledged('cancelled')) {
      logger(
        'info',
        'helper elevation cancelled attempt=$nonce elapsed_ms=${clock.elapsedMilliseconds}',
      );
      throw UpdateInstallCancelled();
    }
    if (await File('${directory.path}/${markerPrefix}error').exists()) {
      logger(
        'error',
        'helper failed attempt=$nonce elapsed_ms=${clock.elapsedMilliseconds} log=${directory.path}/${markerPrefix}updater.log',
      );
      throw FileSystemException(
        'Update helper preparation failed',
        '${directory.path}/${markerPrefix}updater.log',
      );
    }
    if (await acknowledged('ready')) {
      logger(
        'info',
        'helper ready attempt=$nonce elapsed_ms=${clock.elapsedMilliseconds}',
      );
      return;
    }
    if (!elevationSeen && await acknowledged('elevating')) {
      elevationSeen = true;
      timeout = clock.elapsed + elevationTimeout;
      logger(
        'info',
        'helper requested UAC attempt=$nonce elevation_timeout_ms=${elevationTimeout.inMilliseconds}',
      );
    }
    if (clock.elapsed >= timeout) {
      await File('${directory.path}/${markerPrefix}abort')
          .writeAsString(nonce, flush: true);
      logger(
        'error',
        'helper timed out; abort written attempt=$nonce elevation=$elevationSeen elapsed_ms=${clock.elapsedMilliseconds}',
      );
      throw const FileSystemException(
        'Update helper did not acknowledge readiness',
      );
    }
    if (clock.elapsed >= nextHeartbeat) {
      logger(
        'info',
        'helper still waiting attempt=$nonce elevation=$elevationSeen elapsed_ms=${clock.elapsedMilliseconds}',
      );
      nextHeartbeat = clock.elapsed + const Duration(seconds: 10);
    }
    await Future<void>.delayed(pollInterval);
  }
}
