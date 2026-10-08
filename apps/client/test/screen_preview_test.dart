import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/core/screen/screen_share_backend.dart';
import 'package:nightcord_client/core/screen/webrtc_screen_backend.dart';
import 'package:nightcord_client/design/theme/app_theme.dart';
import 'package:nightcord_client/design/tokens/app_palette.dart';
import 'package:nightcord_client/features/screen/setup/screen_setup.dart';
import 'package:nightcord_client/l10n/app_localizations.dart';
import 'package:nightcord_client/models/screen_options.dart';
import 'package:nightcord_client/models/settings.dart';

class _Backend implements ScreenShareBackend {
  final requests = <Completer<ScreenMedia>>[];
  @override
  Future<ScreenMedia> preview(ScreenSource source) {
    final result = Completer<ScreenMedia>();
    requests.add(result);
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Media implements ScreenMedia {
  int closes = 0;
  @override
  Future<void> close() async {
    closes++;
  }

  @override
  set onEnded(void Function() callback) {}
  @override
  bool get hasAudio => false;
  @override
  Widget view() => const Text('preview-image');
}

const _sources = [
  ScreenSource('1', 'window-one', kind: ScreenSourceKind.window),
  ScreenSource('2', 'window-two', kind: ScreenSourceKind.window),
  ScreenSource('3', 'camera-one', kind: ScreenSourceKind.camera),
];

Future<void> _open(WidgetTester tester, _Backend backend) async {
  await tester.binding.setSurfaceSize(const Size(1000, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(AppPalette.nightcord, const Locale('en')),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showScreenSetup(
            context,
            backend: backend,
            sources: _sources,
            settings: const ScreenSettings(),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('unavailable thumbnail does not fall back to video capture', (
    tester,
  ) async {
    // A fallback would reintroduce the foreground activation on failure.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    const channel = MethodChannel('FlutterWebRTC.Method');
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      return Uint8List(0);
    });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });
    final result = expectLater(
      WebRtcScreenBackend().preview(_sources.first),
      throwsStateError,
    );
    for (var i = 0; i < 11; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await result;
    expect(calls, List.filled(10, 'getDesktopSourceThumbnail'));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('leaving the source step discards an outstanding preview', (
    tester,
  ) async {
    // A completed open used to restore a hidden capture on the settings step.
    final backend = _Backend();
    await _open(tester, backend);
    await tester.tap(find.text('window-one'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    final media = _Media();
    backend.requests.single.complete(media);
    await tester.pumpAndSettle();
    expect(media.closes, 1);
    expect(find.text('preview-image'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'desktop preview uses thumbnails and never starts video capture',
    (tester) async {
      // Video capture used to focus the chosen window even before sharing.
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel('FlutterWebRTC.Method');
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        expectSync(call.arguments['sourceId'], '1');
        return calls.length == 1 ? Uint8List(0) : Uint8List.fromList([1, 2, 3]);
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final pending = WebRtcScreenBackend().preview(_sources.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final media = await pending;
      expect(calls, ['getDesktopSourceThumbnail', 'getDesktopSourceThumbnail']);
      await media.close();
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('late preview is closed after the dialog is dismissed', (
    tester,
  ) async {
    // An outstanding native request used to survive dialog teardown.
    final backend = _Backend();
    await _open(tester, backend);
    expect(backend.requests, isEmpty);
    await tester.tap(find.text('window-one'));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    final media = _Media();
    backend.requests.single.complete(media);
    await tester.pumpAndSettle();
    expect(media.closes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching sources waits for and releases the old preview', (
    tester,
  ) async {
    // Repeated selection used to overwrite the media without closing it.
    final backend = _Backend();
    await _open(tester, backend);
    await tester.tap(find.text('window-one'));
    await tester.pump();
    await tester.tap(find.text('window-two'));
    await tester.pump();
    expect(backend.requests.length, 1);
    final first = _Media();
    backend.requests.first.complete(first);
    await tester.pump();
    expect(first.closes, 1);
    expect(backend.requests.length, 2);
    final second = _Media();
    backend.requests.last.complete(second);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(second.closes, 1);
    expect(tester.takeException(), isNull);
  });
}
