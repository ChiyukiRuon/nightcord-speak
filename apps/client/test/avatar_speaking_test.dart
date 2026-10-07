import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/design/components/app_avatar.dart';
import 'package:nightcord_client/design/theme/design_tokens.dart';
import 'package:nightcord_client/design/tokens/app_palette.dart';

void main() {
  testWidgets('speech arcs use the theme presence color without resizing the avatar', (
    tester,
  ) async {
    Future<void> render(bool speaking) => tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: Avatar(name: '用户', speaking: speaking),
        ),
      ),
    );
    await render(false);
    final idleSize = tester.getSize(find.byType(Avatar));
    expect(
      find.byWidgetPredicate((w) => w is CustomPaint && w.foregroundPainter is SpeakingArcsPainter),
      findsNothing,
    );
    await render(true);
    final paint = tester.widget<CustomPaint>(
      find.byWidgetPredicate((w) => w is CustomPaint && w.foregroundPainter is SpeakingArcsPainter),
    );
    expect(
      (paint.foregroundPainter! as SpeakingArcsPainter).color,
      const DesignTokens(AppPalette.nightcord).online,
    );
    expect(tester.getSize(find.byType(Avatar)), idleSize);
  });
}
