import 'package:flutter/material.dart';

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightcord_client/core/updates/update_service.dart';
import 'package:nightcord_client/core/updates/update_controller.dart';
import 'package:nightcord_client/design/theme/app_theme.dart';
import 'package:nightcord_client/design/tokens/app_palette.dart';
import 'package:nightcord_client/features/settings/sections/update_check.dart';
import 'package:nightcord_client/l10n/app_localizations.dart';

Map<String, dynamic> release(
  String tag,
  String platform, {
  bool draft = false,
  String arch = 'x64',
}) => {
  'tag_name': tag,
  'draft': draft,
  'prerelease': true,
  'assets': [
    for (final name in [
      'Nightcord-Speak-${tag.substring(1)}-$platform-$arch${platform == 'windows' ? '-setup.exe' : '.zip'}',
      'Nightcord-Speak-${tag.substring(1)}-$platform-$arch${platform == 'windows' ? '-setup' : ''}.json',
    ])
      {
        'name': name,
        'state': 'uploaded',
        'size': 100,
        'browser_download_url':
            'https://github.com/ChiyukiRuon/nightcord-speak/releases/download/$tag/$name',
      },
  ],
};

class FakeUpdates implements UpdateService {
  @override
  bool available = true;
  bool fail = false;
  bool failInstall = false;
  bool cancelInstall = false;
  DesktopUpdate? result;
  PreparedUpdate? installed;
  Completer<PreparedUpdate>? pending;
  Completer<void>? pendingInstall;
  int downloads = 0;
  int installations = 0;
  int cancellations = 0;
  @override
  Future<DesktopUpdate?> check() async {
    if (fail) throw Exception('offline');
    return result;
  }

  @override
  Future<PreparedUpdate> download(
    DesktopUpdate update,
    void Function(double) progress,
  ) async {
    downloads++;
    progress(0.5);
    if (pending != null) return pending!.future;
    return PreparedUpdate(update, 'temporary', 'package', 'hash');
  }

  @override
  void cancelDownload() {
    cancellations++;
    if (pending != null && !pending!.isCompleted) {
      pending!.completeError(UpdateCancelled());
    }
  }

  @override
  Future<void> install(PreparedUpdate update, String language) async {
    installations++;
    if (cancelInstall) throw UpdateInstallCancelled();
    if (failInstall) throw Exception('helper not ready');
    if (pendingInstall != null) await pendingInstall!.future;
    installed = update;
  }
}

void main() {
  test('committed update stays busy even when exit request returns', () async {
    final service = FakeUpdates()
      ..result = selectDesktopUpdate(
        [release('v0.2.0', 'windows')],
        '0.1.0',
        'windows',
      );
    final controller = UpdateController(service);
    await controller.check();
    await controller.download();
    var exits = 0;
    await controller.install('en', () async {
      exits++;
    });
    expect(controller.busy, isTrue);
    expect(controller.failed, isFalse);
    await controller.install('en', () async {
      exits++;
    });
    expect(service.installations, 1);
    expect(exits, 1);
    controller.dispose();
  });

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

  Future<void> pump(
    WidgetTester tester,
    FakeUpdates service, {
    Future<void> Function()? exit,
    bool visible = true,
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildAppTheme(AppPalette.nightcord, const Locale('en')),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: visible
                ? UpdateCheck(service: service, exitApplication: exit)
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  testWidgets(
    'download stays in the client and installation precedes clean exit',
    (tester) async {
      final service = FakeUpdates()..fail = true;
      var exited = false;
      await pump(
        tester,
        service,
        exit: () async {
          expect(service.installed, isNotNull);
          exited = true;
        },
      );
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Update failed.'), findsOneWidget);
      service.fail = false;
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(find.text('You are using the latest version.'), findsOneWidget);
      service.result = selectDesktopUpdate(
        [release('v0.2.0', 'windows')],
        '0.1.0',
        'windows',
      );
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(find.text('Version 0.2.0 is available'), findsOneWidget);
      await tester.tap(find.text('Download update'));
      await tester.pumpAndSettle();
      expect(find.text('Install update'), findsOneWidget);
      expect(exited, isFalse);
      await tester.tap(find.text('Install update'));
      await tester.pumpAndSettle();
      expect(service.installed!.update, same(service.result));
      expect(exited, isTrue);
    },
  );

  testWidgets(
    'verified download survives leaving settings without downloading again',
    (tester) async {
      final service = FakeUpdates()
        ..result = selectDesktopUpdate(
          [release('v0.2.0', 'windows')],
          '0.1.0',
          'windows',
        );
      await pump(tester, service);
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(find.byType(OutlinedButton), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
      await tester.tap(find.text('Download update'));
      await tester.pumpAndSettle();
      await pump(tester, service, visible: false);
      expect(service.cancellations, 0);
      await pump(tester, service);
      expect(find.text('Install update'), findsOneWidget);
      expect(find.text('Download update'), findsNothing);
      expect(find.text('Check for updates'), findsNothing);
      expect(
        find.text('Download verified and ready to install.'),
        findsNothing,
      );
      expect(service.downloads, 1);
    },
  );

  testWidgets('download continues outside settings and restores progress', (
    tester,
  ) async {
    final service = FakeUpdates()
      ..result = selectDesktopUpdate(
        [release('v0.2.0', 'windows')],
        '0.1.0',
        'windows',
      )
      ..pending = Completer<PreparedUpdate>();
    await pump(tester, service);
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download update'));
    await tester.pump();
    await pump(tester, service, visible: false);
    expect(service.cancellations, 0);
    await pump(tester, service, settle: false);
    expect(find.text('Downloading: 50%'), findsOneWidget);
    expect(find.text('Checking for updates…'), findsNothing);
    service.pending!.complete(
      PreparedUpdate(service.result!, 'temporary', 'package', 'hash'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Install update'), findsOneWidget);
    expect(service.downloads, 1);
  });

  testWidgets(
    'installation displays preparation and exits after settings closes',
    (tester) async {
      final service = FakeUpdates()
        ..result = selectDesktopUpdate(
          [release('v0.2.0', 'windows')],
          '0.1.0',
          'windows',
        )
        ..pendingInstall = Completer<void>();
      var exited = false;
      Future<void> exit() async {
        exited = true;
      }

      await pump(tester, service, exit: exit);
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download update'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Install update'));
      await tester.pump();
      expect(find.text('Preparing update…'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      expect(exited, isFalse);
      await tester.tap(find.text('Preparing update…'));
      expect(service.installations, 1);
      await pump(tester, service, visible: false);
      expect(service.cancellations, 0);
      service.pendingInstall!.complete();
      await tester.pumpAndSettle();
      expect(exited, isTrue);
    },
  );

  testWidgets(
    'cancelled UAC keeps the install button and allows retry without downloading',
    (tester) async {
      final service = FakeUpdates()
        ..result = selectDesktopUpdate(
          [release('v0.2.0', 'windows')],
          '0.1.0',
          'windows',
        )
        ..cancelInstall = true;
      var exited = false;
      await pump(
        tester,
        service,
        exit: () async {
          exited = true;
        },
      );
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download update'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Install update'));
      await tester.pumpAndSettle();
      expect(exited, isFalse);
      expect(find.textContaining('Update failed.'), findsNothing);
      expect(find.text('Install update'), findsOneWidget);
      service.cancelInstall = false;
      await tester.tap(find.text('Install update'));
      await tester.pumpAndSettle();
      expect(exited, isTrue);
      expect(service.downloads, 1);
      expect(service.installations, 2);
    },
  );

  testWidgets('unsupported backends hide the desktop update control', (
    tester,
  ) async {
    await pump(tester, FakeUpdates()..available = false);
    expect(find.text('Check for updates'), findsNothing);
  });

  testWidgets('failed helper preparation keeps the client open for retry', (
    tester,
  ) async {
    final service = FakeUpdates()
      ..result = selectDesktopUpdate(
        [release('v0.2.0', 'windows')],
        '0.1.0',
        'windows',
      )
      ..failInstall = true;
    var exited = false;
    await pump(
      tester,
      service,
      exit: () async {
        exited = true;
      },
    );
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download update'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Install update'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Update failed.'), findsOneWidget);
    expect(exited, isFalse);
    expect(service.installed, isNull);
    service.failInstall = false;
    await tester.tap(find.text('Install update'));
    await tester.pumpAndSettle();
    expect(exited, isTrue);
  });

  test(
    'mac architecture and paired manifest determine the selected artifact',
    () {
      final builds = [
        release('v0.3.0', 'macos', arch: 'x64'),
        release('v0.2.0', 'macos', arch: 'arm64'),
      ];
      expect(
        selectDesktopUpdate(builds, '0.1.0', 'macos', arch: 'arm64')!.version,
        '0.2.0',
      );
      final missing = release('v0.4.0', 'macos', arch: 'arm64');
      (missing['assets'] as List).removeLast();
      expect(
        selectDesktopUpdate([missing], '0.1.0', 'macos', arch: 'arm64'),
        isNull,
      );
    },
  );

  test('release-controlled external URLs are not trusted for execution', () {
    final item = release('v0.2.0', 'windows');
    (item['assets'] as List).first['browser_download_url'] =
        'https://example.com/setup.exe';
    expect(selectDesktopUpdate([item], '0.1.0', 'windows'), isNull);
  });

  testWidgets(
    'download progress can be cancelled without an error or exiting',
    (tester) async {
      final service = FakeUpdates()
        ..result = selectDesktopUpdate(
          [release('v0.2.0', 'windows')],
          '0.1.0',
          'windows',
        )
        ..pending = Completer<PreparedUpdate>();
      await pump(tester, service);
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download update'));
      await tester.pump();
      expect(find.text('Downloading: 50%'), findsOneWidget);
      await tester.tap(find.text('Cancel download'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Update failed.'), findsNothing);
      expect(find.text('Install update'), findsNothing);
      expect(service.cancellations, 1);
    },
  );
}
