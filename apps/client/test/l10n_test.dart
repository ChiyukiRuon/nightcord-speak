// The localized rendering of data that has no BuildContext where it is
// produced: error sentences and message timestamps.
//
// The words themselves live in `lib/l10n/*.arb`; these tests pin the logic that
// decides *which* words, in both languages.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/features/server/chat_panel.dart';
import 'package:nightcord_client/l10n/app_localizations.dart';
import 'package:nightcord_client/l10n/errors.dart';
import 'package:nightcord_client/models/events.dart';

final zh = lookupAppLocalizations(const Locale('zh'));
final en = lookupAppLocalizations(const Locale('en'));

void main() {
  group('ClientError.describe', () {
    test("the core's own message is passed through unchanged", () {
      // `detail.message` is the most specific thing anyone wrote about the
      // failure; wrapping it would only add words around it.
      const error = ClientError(
        kind: 'protocol',
        detail: {'message': 'malformed request: sideways'},
      );
      expect(error.describe(zh), 'malformed request: sideways');
      expect(error.describe(en), 'malformed request: sideways');
    });

    test('shaped payloads become sentences in the requested language', () {
      const code = ClientError(kind: 'server', detail: {'server_code': 256});
      expect(code.describe(zh), '服务器返回错误码 256');
      expect(code.describe(en), 'The server returned error code 256');

      const denied = ClientError(kind: 'permission', detail: {'action': 'join channel'});
      expect(denied.describe(zh), contains('权限不足'));
      expect(denied.describe(en), contains('Permission denied'));

      const device = ClientError(kind: 'devices', detail: {'name': 'Headset'});
      expect(device.describe(zh), '找不到设备 Headset');
      expect(device.describe(en), 'Device not found: Headset');
    });

    test('the Dart-side kinds speak both languages', () {
      expect(const ClientError(kind: 'command_failed').describe(zh), '命令失败');
      expect(const ClientError(kind: 'command_failed').describe(en), 'The command failed');
      expect(const ClientError(kind: 'join_denied').describe(en), contains('permission'));
      expect(const ClientError(kind: 'core_gone').describe(zh), contains('重启'));
      expect(const ClientError(kind: 'core_gone').describe(en), contains('Restart'));

      // The one Dart-side kind that carries data.
      const lagged = ClientError(kind: 'lagged', detail: {'missed': 3});
      expect(lagged.describe(zh), contains('3'));
      expect(lagged.describe(en), contains('3'));
    });

    test('an unknown variant with no payload falls back to its name', () {
      // A bare variant name beats invented words for a payload this build does
      // not understand.
      expect(const ClientError(kind: 'something_new').describe(en), 'something_new');
    });
  });

  group('formatTimestamp', () {
    final now = DateTime(2026, 9, 30, 14, 0);

    test('today and yesterday are words', () {
      expect(formatTimestamp(zh, DateTime(2026, 9, 30, 5, 4), now: now), '今天 5:04');
      expect(formatTimestamp(en, DateTime(2026, 9, 30, 5, 4), now: now), 'Today 5:04');
      expect(formatTimestamp(zh, DateTime(2026, 9, 29, 5, 4), now: now), '昨天 5:04');
      expect(formatTimestamp(en, DateTime(2026, 9, 29, 5, 4), now: now), 'Yesterday 5:04');
    });

    test('an earlier day this year keeps the clock', () {
      expect(formatTimestamp(zh, DateTime(2026, 9, 1, 5, 4), now: now), '9月1日 5:04');
      expect(formatTimestamp(en, DateTime(2026, 9, 1, 5, 4), now: now), '9/1 5:04');
    });

    test('another year drops the clock', () {
      expect(formatTimestamp(zh, DateTime(2025, 12, 31, 5, 4), now: now), '2025/12/31');
      expect(formatTimestamp(en, DateTime(2025, 12, 31, 5, 4), now: now), '2025/12/31');
    });
  });

  test('the two ARB files carry the same keys', () {
    // gen-l10n fails the build when a key is missing from the *template*, but
    // a key missing from a *translation* falls back to English silently — one
    // English sentence in a Chinese UI, which nobody notices until a user
    // does. Comparing the key sets turns that into a test failure.
    Set<String> keysOf(String path) =>
        (jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>)
            .keys
            .where((key) => !key.startsWith('@'))
            .toSet();

    final template = keysOf('lib/l10n/app_en.arb');
    final translated = keysOf('lib/l10n/app_zh.arb');

    expect(
      template.difference(translated),
      isEmpty,
      reason: 'untranslated in zh',
    );
    expect(
      translated.difference(template),
      isEmpty,
      reason: 'zh has keys the template does not know',
    );
  });

  test('the crash note count is pluralized in English', () {
    // The one ICU plural in the app so far: a dropped plural form would put
    // "1 crash notes" in front of a user, and only a test notices.
    expect(en.crashBannerNotes(1), contains('1 crash note'));
    expect(en.crashBannerNotes(2), contains('2 crash notes'));
    expect(en.crashBannerNotes(1), isNot(contains('notes')));
    expect(zh.crashBannerNotes(2), contains('2'));
  });
}
