import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/core/updates/update_service.dart';
import 'package:nightcord_client/design/theme/app_theme.dart';
import 'package:nightcord_client/design/tokens/app_palette.dart';
import 'package:nightcord_client/features/settings/sections/update_check.dart';
import 'package:nightcord_client/l10n/app_localizations.dart';

Map<String, dynamic> release(
  String tag,
  String platform, {
  bool draft = false,
}) => {
  'tag_name': tag,
  'draft': draft,
  'prerelease': true,
  'assets': [
    {
      'name': 'Nightcord-Speak-${tag.substring(1)}-$platform-x64.zip',
      'state': 'uploaded',
    },
  ],
};

class FakeUpdates implements UpdateService {
  @override
  bool available = true;
  bool fail = false;
  DesktopUpdate? result;
  DesktopUpdate? opened;
  @override
  Future<DesktopUpdate?> check() async {
    if (fail) throw Exception('offline');
    return result;
  }

  @override
  Future<void> open(DesktopUpdate update) async {
    opened = update;
  }
}

void main() {
  test(
    'versions compare numerically and order preview stages before final',
    () {
      final versions = [
        '0.1.9',
        '0.1.10-alpha.1',
        '0.1.10-alpha.2',
        '0.1.10-beta.1',
        '0.1.10-rc.1',
        '0.1.10',
        '0.2.0',
      ];
      for (var i = 1; i < versions.length; i++) {
        expect(
          ReleaseVersion.parse(versions[i])!
              .compareTo(ReleaseVersion.parse(versions[i - 1])!),
          greaterThan(0),
        );
      }
      expect(
        ReleaseVersion.parse('0.1.0+99')!
            .compareTo(ReleaseVersion.parse('0.1.0+1')!),
        0,
      );
      expect(ReleaseVersion.parse('0.01.0'), isNull);
    },
  );

  test('platform-only patches and drafts do not hide an applicable update', () {
    final releases = [
      release('v0.3.0', 'windows'),
      release('v0.2.1', 'macos', draft: true),
      release('v0.2.0', 'macos'),
    ];
    expect(selectDesktopUpdate(releases, '0.1.0+1', 'macos')!.version, '0.2.0');
    expect(selectDesktopUpdate(releases, '0.2.0', 'macos'), isNull);
  });

  test('unsuffixed 0.x previews are updates, named previews require preview client', () {
    final releases = [
      release('v0.3.0-beta.1', 'windows'),
      release('v0.2.0', 'windows'),
    ];
    expect(selectDesktopUpdate(releases, '0.1.0', 'windows')!.version, '0.2.0');
    expect(
      selectDesktopUpdate(releases, '0.2.0-beta.1', 'windows')!.version,
      '0.3.0-beta.1',
    );
  });

  test('missing or unfinished assets do not advertise an update', () {
    final item = release('v0.2.0', 'windows');
    (item['assets'] as List).first['state'] = 'new';
    expect(selectDesktopUpdate([item], '0.1.0', 'windows'), isNull);
  });

  Future<void> pump(WidgetTester tester, FakeUpdates service) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppPalette.nightcord, const Locale('en')),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(body: UpdateCheck(service: service)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'check shows current version, failures can be retried, download opens release',
    (tester) async {
      final service = FakeUpdates()..fail = true;
      await pump(tester, service);
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not check'), findsOneWidget);
      service.fail = false;
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(
        find.text('You are using the latest version.'),
        findsOneWidget,
      );
      service.result = DesktopUpdate(
        '0.2.0',
        Uri.parse(
          'https://github.com/ChiyukiRuon/nightcord-speak/releases/tag/v0.2.0',
        ),
      );
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(find.text('Version 0.2.0 is available'), findsOneWidget);
      await tester.tap(find.text('Open download page'));
      await tester.pumpAndSettle();
      expect(service.opened, same(service.result));
    },
  );

  testWidgets('unsupported backends hide the desktop update control', (
    tester,
  ) async {
    await pump(tester, FakeUpdates()..available = false);
    expect(find.text('Check for updates'), findsNothing);
  });
}
