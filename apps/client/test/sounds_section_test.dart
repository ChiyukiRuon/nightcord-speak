import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/core/sounds/sound_pack.dart';
import 'package:nightcord_client/features/settings/sections/notifications_section.dart';
import 'package:nightcord_client/l10n/app_localizations.dart';
import 'package:nightcord_client/models/settings.dart';
import 'package:nightcord_client/providers/providers.dart';
import 'package:nightcord_client/providers/sounds.dart';

class _Settings extends SettingsNotifier {
  _Settings(this.initial);
  final Settings initial;
  @override
  Settings build() => initial;
  @override
  void update(Settings next) => state = next;
}

class _Library implements SoundLibrary {
  bool failSave = false;
  int scans = 0;
  final Map<SoundAction, String?> mapping = {SoundAction.voiceJoined: 'join.wav'};
  final List<String> played = [];
  final List<String> opened = [];
  @override
  bool get available => true;
  @override
  Future<String> directory() async => '/app/sounds';
  @override
  Future<List<SoundPack>> scan() async {
    scans++;
    return [
      SoundPack(name: 'nightcord', files: ['join.wav', 'chat.flac'], mapping: {...mapping}),
    ];
  }

  @override
  Future<void> save(String pack, Map<SoundAction, String?> next) async {
    if (failSave) throw StateError('Read only');
    mapping
      ..clear()
      ..addAll(next);
  }

  @override
  Future<void> play(String pack, String file, {String? output, double volume = 1}) async {
    played.add('$pack/$file');
  }
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    _Library library, {
    Settings settings = const Settings(),
    Future<String?> Function()? chooseDirectory,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          soundLibraryProvider.overrideWithValue(library),
          soundDirectoryOpenerProvider.overrideWithValue((path) async => library.opened.add(path)),
          if (chooseDirectory != null)
            soundDirectoryChooserProvider.overrideWithValue(chooseDirectory),
          settingsProvider.overrideWith(() => _Settings(settings)),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Consumer(
                  builder: (context, ref, child) =>
                      NotificationsSection(settings: ref.watch(settingsProvider)!),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('directory selection persists, cancellation retains it, and reset restores default', (
    tester,
  ) async {
    String? chosen = '/custom/sounds';
    await mount(tester, _Library(), chooseDirectory: () async => chosen);
    await tester.ensureVisible(find.text('Choose sound folder'));
    await tester.tap(find.text('Choose sound folder'));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(NotificationsSection));
    final container = ProviderScope.containerOf(context);
    expect(container.read(settingsProvider)!.notifications.soundDirectory, '/custom/sounds');
    chosen = null;
    await tester.tap(find.text('Choose sound folder'));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider)!.notifications.soundDirectory, '/custom/sounds');
    await tester.tap(find.text('Use default folder'));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider)!.notifications.soundDirectory, isEmpty);
    expect(container.read(settingsProvider)!.notifications.soundPack, 'nightcord');
  });

  testWidgets('disabled sounds hide configuration without scanning or losing mappings', (
    tester,
  ) async {
    final library = _Library();
    await mount(
      tester,
      library,
      settings: const Settings(notifications: NotificationSettings(sounds: false)),
    );
    expect(library.scans, 0);
    expect(find.text('Play notification sounds'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.text('Open sound folder'), findsNothing);
    expect(find.text('Refresh sound packs'), findsNothing);
    await tester.tap(find.text('Play notification sounds'));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(10));
    expect(library.scans, 1);
    await tester.tap(find.text('Play notification sounds'));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.text('/app/sounds'), findsNothing);
    expect(find.byTooltip('Preview'), findsNothing);
    await tester.tap(find.text('Play notification sounds'));
    await tester.pumpAndSettle();
    final dropdowns = find.byType(DropdownButtonFormField<String>);
    expect(
      tester.widget<DropdownButtonFormField<String>>(dropdowns.first).initialValue,
      'nightcord',
    );
    expect(
      tester.widget<DropdownButtonFormField<String>>(dropdowns.at(1)).initialValue,
      'join.wav',
    );
  });

  testWidgets('sound controls follow notification switches and preview uses selected mapping', (
    tester,
  ) async {
    final library = _Library();
    await mount(tester, library);
    expect(find.text('Sound pack'), findsOneWidget);
    expect(find.text('/app/sounds'), findsOneWidget);
    final switches = find.byType(SwitchListTile);
    expect(switches, findsNWidgets(7));
    expect(tester.widget<SwitchListTile>(switches.last).title, isA<Text>());
    expect(
      tester.getTopLeft(find.text('Play notification sounds')).dy,
      greaterThan(tester.getTopLeft(switches.at(5)).dy),
    );
    await tester.ensureVisible(find.byTooltip('Preview').first);
    await tester.tap(find.byTooltip('Preview').first);
    await tester.pumpAndSettle();
    expect(library.played, ['nightcord/join.wav']);
    await tester.ensureVisible(find.text('Open sound folder'));
    await tester.tap(find.text('Open sound folder'));
    await tester.pumpAndSettle();
    expect(library.opened, ['/app/sounds']);
  });

  testWidgets('editing mappings persists each action and write failures are visible', (
    tester,
  ) async {
    final library = _Library();
    await mount(tester, library);
    final dropdowns = find.byType(DropdownButtonFormField<String>);
    expect(dropdowns, findsNWidgets(10));
    tester.widget<DropdownButtonFormField<String>>(dropdowns.last).onChanged!('chat.flac');
    await tester.pumpAndSettle();
    expect(library.mapping[SoundAction.message], 'chat.flac');
    expect(library.mapping[SoundAction.voiceJoined], 'join.wav');
    library.failSave = true;
    tester.widget<DropdownButtonFormField<String>>(dropdowns.last).onChanged!('');
    await tester.pumpAndSettle();
    expect(library.mapping[SoundAction.message], 'chat.flac');
    expect(
      find.text('Cannot save configuration. Check that the sound pack folder is writable.'),
      findsOneWidget,
    );
  });
}
