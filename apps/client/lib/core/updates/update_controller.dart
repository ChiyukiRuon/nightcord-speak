import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'update_log.dart';
import 'update_service.dart';

// Keep the task alive when the settings route is removed.
final updateControllerProvider =
    Provider.family<UpdateController, UpdateService?>((ref, service) {
      final controller = UpdateController(service ?? createUpdateService());
      ref.onDispose(controller.dispose);
      return controller;
    });

enum UpdateActivity { idle, checking, downloading, installing }

class UpdateController extends ChangeNotifier {
  UpdateController(this.service);

  final UpdateService service;
  UpdateActivity activity = UpdateActivity.idle;
  bool checked = false;
  bool failed = false;
  DesktopUpdate? update;
  PreparedUpdate? prepared;
  double? progress;
  bool _disposed = false;

  bool get busy => activity != UpdateActivity.idle;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _run(UpdateActivity next, Future<void> Function() action) async {
    if (busy || _disposed) {
      updateLogger(
        'debug',
        '${next.name} ignored: busy=$busy disposed=$_disposed',
      );
      return;
    }
    final timer = Stopwatch()..start();
    updateLogger('info', '${next.name} started');
    activity = next;
    failed = false;
    _notify();
    try {
      await action();
      updateLogger(
        'info',
        '${next.name} completed elapsed_ms=${timer.elapsedMilliseconds}',
      );
    } on UpdateCancelled {
      // Cancellation is a user action, not a failed update.
      updateLogger(
        'info',
        '${next.name} cancelled elapsed_ms=${timer.elapsedMilliseconds}',
      );
    } on UpdateInstallCancelled {
      updateLogger(
        'info',
        'elevation cancelled; package retained elapsed_ms=${timer.elapsedMilliseconds}',
      );
    } catch (error, stack) {
      failed = true;
      updateLogger(
        'error',
        '${next.name} failed elapsed_ms=${timer.elapsedMilliseconds}: $error\n$stack',
      );
    } finally {
      activity = UpdateActivity.idle;
      progress = null;
      _notify();
    }
  }

  Future<void> check() => _run(UpdateActivity.checking, () async {
    // A verified package remains installable even if a later check fails.
    if (prepared != null) return;
    update = await service.check();
    checked = true;
  });

  Future<void> download() => _run(UpdateActivity.downloading, () async {
    final candidate = update;
    if (candidate == null || prepared != null) return;
    progress = 0;
    _notify();
    prepared = await service.download(candidate, (value) {
      progress = value;
      _notify();
    });
  });

  Future<void> install(String language, Future<void> Function() exit) =>
      _run(UpdateActivity.installing, () async {
        final package = prepared;
        if (package == null) return;
        await service.install(package, language);
        updateLogger(
          'info',
          'helper committed; requesting clean application exit',
        );
        await exit();
        updateLogger('info', 'application exit request returned');
      });

  void cancelDownload() {
    if (activity == UpdateActivity.downloading) service.cancelDownload();
  }

  @override
  void dispose() {
    _disposed = true;
    service.cancelDownload();
    super.dispose();
  }
}
