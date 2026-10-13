import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/core/updates/update_helper.dart';
import 'package:nightcord_client/core/updates/update_model.dart';

void main() {
  late Directory root;
  const nonce = '0123456789abcdef0123456789abcdef';

  setUp(() async {
    root = await Directory.systemTemp.createTemp('update-helper-test-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  Future<void> signal(String name, String value) =>
      File('${root.path}/$name').writeAsString(value).then((_) {});

  test('only the active attempt can acknowledge helper readiness', () async {
    await signal('old-error', 'failed');
    await signal('old-ready', nonce);
    await signal('$nonce-ready', nonce);
    await waitForUpdateHelper(root, nonce, markerPrefix: '$nonce-');
    expect(await File('${root.path}/$nonce-abort').exists(), isFalse);
  });

  test(
    'cancelled UAC retains the package without committing or exiting',
    () async {
      await signal('package.zip', 'verified package');
      await signal('$nonce-cancelled', nonce);
      await expectLater(
        waitForUpdateHelper(root, nonce, markerPrefix: '$nonce-'),
        throwsA(isA<UpdateInstallCancelled>()),
      );
      expect(
        await File('${root.path}/package.zip').readAsString(),
        'verified package',
      );
      expect(await File('${root.path}/$nonce-commit').exists(), isFalse);
      expect(await File('${root.path}/$nonce-abort').exists(), isFalse);
    },
  );

  test('UAC has a separate waiting budget and can finish after the preparation deadline', () async {
    await signal('elevating', nonce);
    final waiting = waitForUpdateHelper(
      root,
      nonce,
      preparationTimeout: Duration.zero,
      elevationTimeout: const Duration(seconds: 2),
      pollInterval: const Duration(milliseconds: 1),
    );
    await signal('ready', nonce);
    await waiting;
    expect(await File('${root.path}/abort').exists(), isFalse);
  });

  test(
    'expired readiness writes an abort token for a delayed elevated worker',
    () async {
      await signal('ready', 'old attempt');
      await expectLater(
        waitForUpdateHelper(root, nonce, preparationTimeout: Duration.zero),
        throwsA(isA<FileSystemException>()),
      );
      expect(await File('${root.path}/abort').readAsString(), nonce);
    },
  );

  test(
    'elevation budget is bounded even when the prompt never finishes',
    () async {
      await signal('elevating', nonce);
      await expectLater(
        waitForUpdateHelper(root, nonce, elevationTimeout: Duration.zero),
        throwsA(isA<FileSystemException>()),
      );
      expect(await File('${root.path}/abort').readAsString(), nonce);
    },
  );

  test('helper preparation errors point to the attempt log', () async {
    await signal('$nonce-error', 'failed');
    await expectLater(
      waitForUpdateHelper(root, nonce, markerPrefix: '$nonce-'),
      throwsA(
        isA<FileSystemException>().having(
          (error) => error.path,
          'log path',
          '${root.path}/$nonce-updater.log',
        ),
      ),
    );
  });
}
