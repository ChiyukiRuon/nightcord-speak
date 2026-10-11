import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/l10n/app_localizations.dart';
import 'package:nightcord_client/util/app_menu.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native menus and microphone descriptions cover every supported locale',
    () {
      // Native text used to be left in the template, outside the ARB guard.
      Map<String, String> readStrings(String path) => {
        for (final match in RegExp(
          r'^"([^"]+)"\s*=\s*(".*");$',
          multiLine: true,
        ).allMatches(File(path).readAsStringSync()))
          match.group(1)!: jsonDecode(match.group(2)!) as String,
      };
      const root = 'macos/Runner';
      final english = readStrings('$root/en.lproj/Menu.strings');
      final nib = File('$root/Base.lproj/MainMenu.xib').readAsStringSync();
      final identifiers = RegExp(r'identifier="(menu\.[^"]+)"')
          .allMatches(nib)
          .map((match) => match.group(1)!)
          .toSet();
      expect(identifiers, hasLength(51));
      expect(english.keys.toSet(), {...identifiers, 'menu.exitFullScreen'});
      final project = File('macos/Runner.xcodeproj/project.pbxproj')
          .readAsStringSync();
      for (final locale in AppLocalizations.supportedLocales) {
        final tag = locale.languageCode == 'zh' && locale.scriptCode != 'Hant'
            ? 'zh-Hans'
            : locale.toLanguageTag();
        final translated = readStrings('$root/$tag.lproj/Menu.strings');
        expect(translated.keys.toSet(), english.keys.toSet(), reason: tag);
        for (final key in english.keys) {
          expect(translated[key]!.trim(), isNotEmpty, reason: '$tag: $key');
          expect(
            '%@'.allMatches(translated[key]!).length,
            '%@'.allMatches(english[key]!).length,
            reason: '$tag: $key',
          );
        }
        final permissions = readStrings('$root/$tag.lproj/InfoPlist.strings');
        expect(
          permissions['NSMicrophoneUsageDescription'],
          contains('TeamSpeak'),
        );
        for (final table in ['Menu', 'InfoPlist']) {
          expect(project, contains('$tag.lproj/$table.strings'));
        }
      }
    },
  );

  test(
    'the resolved UI locale updates native menus without duplicate calls',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel('nightcord/shell');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final tags = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'setLanguage');
        tags.add(call.arguments as String);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      for (final locale in AppLocalizations.supportedLocales) {
        await updateAppMenuLocale(locale);
        await updateAppMenuLocale(locale);
      }
      expect(
        tags,
        AppLocalizations.supportedLocales
            .map((locale) => locale.toLanguageTag())
            .toList(),
      );
    },
  );

  test(
    'an older native runner does not interrupt language switching',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel('nightcord/shell');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls++;
        throw MissingPluginException();
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await updateAppMenuLocale(const Locale('en'));
      await updateAppMenuLocale(const Locale('en'));
      expect(calls, 2);
    },
  );
}
