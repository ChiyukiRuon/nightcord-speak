import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/core/avatar/prepare_avatar.dart';
import 'package:nightcord_client/core/avatar/avatar_crop.dart';
import 'package:nightcord_client/design/components/app_avatar.dart';
import 'package:nightcord_client/features/avatar/avatar_editor.dart';
import 'package:nightcord_client/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Uint8List> picture(int width, int height) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..drawColor(Colors.blue, BlendMode.src);
    canvas.drawCircle(const Offset(10, 10), 5, Paint()..color = Colors.red);
    final drawing = recorder.endRecording();
    final image = await drawing.toImage(width, height);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
      drawing.dispose();
    }
  }

  test(
    'uploads produce a bounded square PNG without distorting the source',
    () async {
      final resized = await prepareAvatar(await picture(1024, 512));
      expect(resized.length, lessThanOrEqualTo(200 * 1024));
      final codec = await ui.instantiateImageCodec(resized);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 256);
      expect(frame.image.height, 256);
      frame.image.dispose();
      codec.dispose();
      expect(
        () => prepareAvatar(Uint8List.fromList(utf8.encode('broken'))),
        throwsA(anything),
      );
      expect(
        () => prepareAvatar(Uint8List(10 * 1024 * 1024 + 1)),
        throwsA(isA<FormatException>()),
      );
    },
  );

  testWidgets(
    'a real image retains speech arcs and a broken image falls back to initials',
    (tester) async {
      Future<void> show(Uint8List bytes) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Avatar(name: 'Alice', image: bytes, speaking: true),
          ),
        ),
      );
      await show((await tester.runAsync(() => picture(32, 32)))!);
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint &&
              widget.foregroundPainter is SpeakingArcsPainter,
        ),
        findsOneWidget,
      );
      await show(Uint8List.fromList([1, 2, 3]));
      await tester.pumpAndSettle();
      expect(find.text('A'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  Future<ui.Image> quadrants() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (final (rect, color) in [
      (const Rect.fromLTWH(0, 0, 200, 100), Colors.red),
      (const Rect.fromLTWH(200, 0, 200, 100), Colors.green),
      (const Rect.fromLTWH(0, 100, 200, 100), Colors.blue),
      (const Rect.fromLTWH(200, 100, 200, 100), Colors.white),
    ]) {
      canvas.drawRect(rect, Paint()..color = color);
    }
    final drawing = recorder.endRecording();
    try {
      return await drawing.toImage(400, 200);
    } finally {
      drawing.dispose();
    }
  }

  Future<List<Color>> corners(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    try {
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      return [
        for (final (x, y) in [(25, 25), (230, 25), (25, 230), (230, 230)])
          Color.fromARGB(
            data.getUint8((y * 256 + x) * 4 + 3),
            data.getUint8((y * 256 + x) * 4),
            data.getUint8((y * 256 + x) * 4 + 1),
            data.getUint8((y * 256 + x) * 4 + 2),
          ),
      ];
    } finally {
      image.dispose();
      codec.dispose();
    }
  }

  test('rotation exports the same oriented quadrants as the preview', () async {
    final image = await quadrants();
    try {
      final expected = [
        [Colors.red, Colors.green, Colors.blue, Colors.white],
        [Colors.blue, Colors.red, Colors.white, Colors.green],
        [Colors.white, Colors.blue, Colors.green, Colors.red],
        [Colors.green, Colors.white, Colors.red, Colors.blue],
      ];
      for (var turns = 0; turns < 4; turns++) {
        expect(
          await corners(
            await exportAvatarCrop(image, AvatarCrop(turns: turns)),
          ),
          expected[turns].map((color) => Color(color.toARGB32())).toList(),
        );
      }
    } finally {
      image.dispose();
    }
  });

  test('zoom and extreme drags keep the crop inside the image', () async {
    final image = await quadrants();
    try {
      final crop = const AvatarCrop(zoom: 2)
          .drag(image, const Offset(10000, -10000), 280);
      expect(crop.rect(image), const Rect.fromLTWH(0, 100, 100, 100));
      expect(
        await corners(await exportAvatarCrop(image, crop)),
        List.filled(4, Color(Colors.blue.toARGB32())),
      );
    } finally {
      image.dispose();
    }
  });

  testWidgets(
    'editor supports drag, zoom, rotation, reset and cancellation on a phone',
    (tester) async {
      tester.view.physicalSize = const Size(360, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final image = (await tester.runAsync(quadrants))!;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => AvatarEditor(
                    image: image,
                    initialCrop: const AvatarCrop(
                      turns: 1,
                      zoom: 2,
                      x: .3,
                      y: .6,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(find.byType(Slider)).value, 2);
      await tester.drag(find.byType(Slider), const Offset(60, 0));
      await tester.drag(
        find.byKey(const ValueKey('avatar-crop-preview')),
        const Offset(40, 20),
      );
      await tester.tap(find.text('旋转'));
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(find.byType(Slider)).value, greaterThan(1));
      await tester.tap(find.text('重置'));
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(find.byType(Slider)).value, 1);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byType(AvatarEditor), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      image.dispose();
    },
  );
}
