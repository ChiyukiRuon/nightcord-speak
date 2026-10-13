import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/core/updates/update_log.dart';

void main() {
  test(
    'diagnostics redact signed URL credentials and bound oversized errors',
    () {
      final messages = <String>[];
      final logger = UpdateLogger(sink: (_, message) => messages.add(message));
      logger(
        'error',
        'failed https://user:password@cdn.example/update?token=secret',
      );
      expect(messages.single, contains('<url omitted>'));
      expect(messages.single, isNot(contains('password')));
      expect(messages.single, isNot(contains('secret')));
      logger('error', 'x' * 10000);
      expect(messages.last.length, lessThan(4200));
      expect(messages.last, endsWith('[truncated]'));
    },
  );

  test('an unavailable logging sink cannot break the update action', () {
    final logger = UpdateLogger(
      sink: (_, _) => throw StateError('sink unavailable'),
    );
    expect(() => logger('info', 'download completed'), returnsNormally);
  });
}
