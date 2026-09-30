// The crash status the banner acts on.

import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/models/crash.dart';

void main() {
  group('CrashStatus', () {
    test('reads the core shape', () {
      final status = CrashStatus.fromJson(const {
        'available': true,
        'abnormal': true,
        'notes': 3,
        'directory': r'C:\Users\x\AppData\Roaming\Nightcord Speak\crashes',
      });

      expect(status.available, isTrue);
      expect(status.abnormal, isTrue);
      expect(status.notes, 3);
      expect(status.directory, contains('crashes'));
    });

    test('a missing or unexpected payload falls back rather than throwing', () {
      // A platform without a crash directory answers `{"available": false}`;
      // anything stranger should be no worse.
      final unavailable = CrashStatus.fromJson(const {'available': false});
      expect(unavailable.abnormal, isFalse);
      expect(unavailable.shouldNotify, isFalse);

      final garbage = CrashStatus.fromJson(const {'abnormal': 'yes', 'notes': 'many'});
      expect(garbage.abnormal, isFalse);
      expect(garbage.notes, 0);
    });

    test('only an abnormal exit raises the banner', () {
      // Crash notes on their own do not: a worker panic already showed the
      // user an error while it happened, and the banner is for the run that
      // died without being able to say anything.
      const withNotes = CrashStatus(
        available: true,
        abnormal: false,
        notes: 2,
        directory: '/tmp',
      );
      expect(withNotes.shouldNotify, isFalse);

      const abnormal = CrashStatus(
        available: true,
        abnormal: true,
        notes: 0,
        directory: '/tmp',
      );
      expect(abnormal.shouldNotify, isTrue);

      expect(CrashStatus.none.shouldNotify, isFalse);
    });
  });
}
