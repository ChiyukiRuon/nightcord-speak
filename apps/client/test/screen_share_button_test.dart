import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/core/screen/screen_controller.dart';
import 'package:nightcord_client/core/screen/screen_providers.dart';
import 'package:nightcord_client/core/screen/screen_share_backend.dart';
import 'package:nightcord_client/features/screen/screen_share_button.dart';
import 'package:nightcord_client/l10n/app_localizations.dart';
import 'package:nightcord_client/models/domain.dart' as domain;
import 'package:nightcord_client/models/screen_options.dart';
import 'package:nightcord_client/models/settings.dart';
import 'package:nightcord_client/providers/providers.dart';
import 'package:nightcord_client/state/server_view.dart';

class _Sessions extends SessionsNotifier {
  @override
  Map<int, ServerView> build() => {
    1: ServerView(session: 1)..connection = domain.ConnectionState.connected,
  };
}

class _Settings extends SettingsNotifier {
  @override
  Settings build() =>
      const Settings(screen: ScreenSettings(height: 1080, fps: 60));
}

class _Backend implements ScreenShareBackend, DirectScreenCapture {
  final pending = Completer<ScreenMedia>();
  ScreenOptions? requested;
  @override
  bool get directScreenCapture => true;
  @override
  Future<ScreenMedia> capture(ScreenSource? source, ScreenOptions options) {
    expect(source, isNull);
    requested = options;
    return pending.future;
  }

  @override
  Future<List<ScreenSource>> sources() =>
      throw StateError('Direct capture must not enumerate first');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Media implements ScreenMedia {
  int closes = 0;
  @override
  bool get hasAudio => false;
  @override
  set onEnded(void Function() callback) {}
  @override
  Future<void> close() async {
    closes++;
  }

  @override
  Widget view() => const SizedBox.shrink();
}

void main() {
  testWidgets(
    'direct screen sharing invokes capture inside the click without a setup dialog',
    (tester) async {
      // Awaiting source enumeration or opening our wizard loses browser activation.
      final backend = _Backend();
      final commands = <Map<String, dynamic>>[];
      final controller = ScreenController(backend: backend, send: commands.add)
        ..contextChanged(online: true, client: 1, channel: 1, clients: {1});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionsProvider.overrideWith(_Sessions.new),
            settingsProvider.overrideWith(_Settings.new),
            screenControllerProvider(1).overrideWithValue(controller),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: ScreenShareButton(session: 1)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Share screen'));
      expect(backend.requested?.height, 1080);
      expect(backend.requested?.fps, 60);
      expect(backend.requested?.source, ScreenSourceKind.screen);
      await tester.pump();
      expect(find.byType(Dialog), findsNothing);
      expect(controller.starting, isTrue);
      final media = _Media();
      backend.pending.complete(media);
      await tester.pump();
      expect(commands.single['action'], 'start');
      await controller.stop();
      expect(media.closes, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
}
