import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/design/tokens/app_fonts.dart';
import 'package:nightcord_client/design/theme/app_theme.dart';
import 'package:nightcord_client/design/tokens/app_palette.dart';
import 'package:nightcord_client/features/screen/detached/screen_window.dart';
import 'package:nightcord_client/l10n/app_localizations.dart';
import 'package:nightcord_client/l10n/locale.dart';
import 'package:nightcord_client/widgets/startup_failure.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('engine arguments preserve each supported language and script', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final args = ScreenWindowArgs(
        session: 1,
        clientId: 2,
        title: 'viewer',
        locale: locale,
      );
      expect(ScreenWindowArgs.parse(jsonEncode(args.toJson()))!.locale, locale);
    }
    expect(ScreenWindowArgs.parse('{"screen":true}')!.locale, isNull);
  });

  test('all app roots share script resolution and English fallback', () {
    for (final region in ['TW', 'HK', 'MO']) {
      expect(
        resolveAppLocale(systemLocales: [Locale('zh', region)]).scriptCode,
        'Hant',
      );
    }
    expect(
      resolveAppLocale(systemLocales: const [Locale('fr')]),
      const Locale('en'),
    );
    expect(
      resolveAppLocale(
        language: 'zh_Hant',
        systemLocales: const [Locale('en')],
      ).scriptCode,
      'Hant',
    );
    expect(
      resolveAppLocale(
        language: 'en',
        systemLocales: const [Locale('zh', 'HK')],
      ),
      const Locale('en'),
    );
  });

  testWidgets(
    'startup failure resolves a Hong Kong system locale to Traditional Chinese',
    (tester) async {
      // This app root previously bypassed the script normalization in providers.
      final dispatcher = tester.binding.platformDispatcher;
      dispatcher.localesTestValue = const [Locale('zh', 'HK')];
      addTearDown(dispatcher.clearLocalesTestValue);
      final locale = resolveAppLocale(systemLocales: dispatcher.locales);
      await tester.pumpWidget(
        StartupFailureApp(
          error: StateError('diagnostic'),
          theme: buildAppTheme(AppPalette.nightcord, locale),
        ),
      );
      await tester.pumpAndSettle();
      final strings = lookupAppLocalizations(locale);
      expect(find.text(strings.startupFailureTitle), findsOneWidget);
      final context = tester.element(find.text(strings.startupFailureTitle));
      expect(Localizations.localeOf(context).scriptCode, 'Hant');
      expect(
        Theme.of(context).textTheme.bodyMedium!.fontFamily,
        AppFonts.traditionalChinese,
      );
    },
  );

  testWidgets(
    'detached controls, errors and fonts follow the host and live updates',
    (tester) async {
      // The child used the system locale, ignoring the main window's setting.
      final dispatcher = tester.binding.platformDispatcher;
      dispatcher.localesTestValue = const [
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      ];
      addTearDown(dispatcher.clearLocalesTestValue);
      const channels = MethodChannel('mixin.one/desktop_multi_window/channels');
      const windows = MethodChannel('mixin.one/desktop_multi_window');
      const manager = MethodChannel('window_manager');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(manager, (_) async => null);
      messenger.setMockMethodCallHandler(
        windows,
        (_) async => {'windowId': 'child', 'windowArgument': ''},
      );
      messenger.setMockMethodCallHandler(channels, (_) async => null);
      addTearDown(() {
        messenger.setMockMethodCallHandler(manager, null);
        messenger.setMockMethodCallHandler(windows, null);
        messenger.setMockMethodCallHandler(channels, null);
      });
      const args = ScreenWindowArgs(
        session: 1,
        clientId: 2,
        title: 'viewer',
        locale: Locale('en'),
      );
      await tester.pumpWidget(const DetachedScreenApp(args: args));
      await tester.pump();
      expect(find.text('Back to small window'), findsOneWidget);
      expect(find.text('Connecting…'), findsOneWidget);

      Future<void> send(String method, [Object? argument]) async {
        await messenger.handlePlatformMessage(
          channels.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('methodCall', {
              'channel': args.channelName,
              'method': method,
              'arguments': argument,
            }),
          ),
          (_) {},
        );
        await tester.pump();
      }

      await send('command_failed');
      for (final locale in AppLocalizations.supportedLocales) {
        await send('locale', locale.toLanguageTag());
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        final strings = lookupAppLocalizations(locale);
        expect(find.text(strings.screenReturnInline), findsOneWidget);
        expect(find.text(strings.screenConnectionFailed), findsOneWidget);
        final context = tester.element(find.text(strings.screenReturnInline));
        expect(Localizations.localeOf(context), locale);
        expect(
          Theme.of(context).textTheme.bodyMedium!.fontFamily,
          AppFonts.forLocale(locale),
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );
}
