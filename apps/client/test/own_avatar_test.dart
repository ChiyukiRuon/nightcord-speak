import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/core/avatar/own_avatar.dart';
import 'package:nightcord_client/core/transport/client_transport.dart';
import 'package:nightcord_client/design/components/app_avatar.dart';
import 'package:nightcord_client/features/avatar/client_avatar.dart';
import 'package:nightcord_client/features/avatar/own_avatar_button.dart';
import 'package:nightcord_client/features/avatar/avatar_editor.dart';
import 'package:nightcord_client/l10n/app_localizations.dart';
import 'package:nightcord_client/state/server_view.dart';
import 'package:nightcord_client/models/domain.dart';
import 'package:nightcord_client/models/events.dart';
import 'package:nightcord_client/providers/providers.dart';

class _Transport implements ClientTransport {
  final incoming = StreamController<FfiEvent>.broadcast();
  int requests = 0;
  @override
  Stream<FfiEvent> get events => incoming.stream;
  @override
  void requestSettings() => requests++;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Sessions extends SessionsNotifier {
  @override
  Map<int, ServerView> build() => {
    1: ServerView(session: 1)
      ..connection = ConnectionState.connected
      ..ownClientId = 1
      ..apply(
        const ClientJoinedEvent(
          Client(id: 1, name: 'Self', channelId: 1, isSelf: true),
        ),
      ),
  };
}

void main() {
  testWidgets(
    'the bottom bar edit action opens the original instead of its square export',
    (tester) async {
      // The visible avatar is deliberately square, while the original is wide:
      // opening the export here used to make the excluded pixels unrecoverable.
      Future<String> png(int width, int height) async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawColor(Colors.blue, ui.BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(width, height);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final encoded = base64Encode(data!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
        return encoded;
      }

      final original = (await tester.runAsync(() => png(400, 200)))!;
      final square = (await tester.runAsync(() => png(32, 32)))!;
      final transport = _Transport();
      final container = ProviderContainer.test(
        overrides: [
          clientTransportProvider.overrideWithValue(transport),
          sessionsProvider.overrideWith(_Sessions.new),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            locale: Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: OwnAvatarButton(session: 1)),
          ),
        ),
      );
      transport.incoming.add(
        DomainEvent(
          session: 1,
          event: OwnAvatarChangedEvent({
            'configured': true,
            'revision': 1,
            'image': square,
            'edit': {
              'source': original,
              'turns': 1,
              'zoom': 2.0,
              'x': .3,
              'y': .6,
            },
          }),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('own-avatar-button')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('编辑头像'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      final editor = tester.widget<AvatarEditor>(find.byType(AvatarEditor));
      expect(editor.image.width, 400);
      expect(editor.image.height, 200);
      expect(editor.initialCrop.turns, 1);
      expect(tester.widget<Slider>(find.byType(Slider)).value, 2);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await transport.incoming.close();
    },
  );
  testWidgets(
    'startup restores the original and crop, removal clears editing data',
    (tester) async {
      // The displayed square is not an editable replacement for the original.
      final transport = _Transport();
      final container = ProviderContainer.test(
        overrides: [clientTransportProvider.overrideWithValue(transport)],
      );
      container.listen(ownAvatarProvider, (_, _) {});
      await tester.pump();
      transport.incoming.add(
        FfiEvent.fromJson({
          'kind': 'command_result',
          'command': 'settings',
          'outcome': {'status': 'ok'},
          'data': {
            'own_avatar': {
              'configured': true,
              'revision': 1,
              'image': base64Encode([1, 2]),
              'edit': {
                'source': base64Encode([7, 8, 9]),
                'turns': 1,
                'zoom': 2.0,
                'x': .3,
                'y': .6,
              },
            },
          },
        }),
      );
      await tester.pump();
      final own = container.read(ownAvatarProvider);
      expect(own.source, [7, 8, 9]);
      expect(own.image, [1, 2]);
      expect(own.crop.toJson(), {'turns': 1, 'zoom': 2.0, 'x': .3, 'y': .6});
      transport.incoming.add(
        const DomainEvent(
          session: 1,
          event: OwnAvatarChangedEvent({
            'configured': true,
            'revision': 2,
            'image': null,
          }),
        ),
      );
      await tester.pump();
      expect(container.read(ownAvatarProvider).source, isNull);
      container.dispose();
      await transport.incoming.close();
    },
  );
  testWidgets(
    'an old startup response cannot undo a newer global avatar change',
    (tester) async {
      final transport = _Transport();
      final container = ProviderContainer.test(
        overrides: [clientTransportProvider.overrideWithValue(transport)],
      );
      container.listen(ownAvatarProvider, (_, _) {});
      await tester.pump();
      transport.incoming.add(
        DomainEvent(
          session: 2,
          event: OwnAvatarChangedEvent({
            'configured': true,
            'revision': 7,
            'image': base64Encode([9, 10]),
          }),
        ),
      );
      await tester.pump();
      transport.incoming.add(
        FfiEvent.fromJson({
          'kind': 'command_result',
          'command': 'settings',
          'outcome': {'status': 'ok'},
          'data': {
            'own_avatar': {'configured': true, 'revision': 6, 'image': null},
          },
        }),
      );
      await tester.pump();
      expect(container.read(ownAvatarProvider).image, [9, 10]);
      expect(container.read(ownAvatarProvider).revision, 7);
      container.dispose();
      await transport.incoming.close();
    },
  );
  testWidgets('self avatars on different servers share one image and removal', (
    tester,
  ) async {
    final transport = _Transport();
    final container = ProviderContainer.test(
      overrides: [clientTransportProvider.overrideWithValue(transport)],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                ClientAvatar(
                  session: 1,
                  client: Client(
                    id: 1,
                    name: 'Alice',
                    channelId: 1,
                    isSelf: true,
                  ),
                ),
                ClientAvatar(
                  session: 2,
                  client: Client(
                    id: 9,
                    name: 'Other nickname',
                    channelId: 2,
                    isSelf: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(transport.requests, 1);
    transport.incoming.add(
      DomainEvent(
        session: 2,
        event: OwnAvatarChangedEvent({
          'configured': true,
          'image': base64Encode([1, 2, 3]),
        }),
      ),
    );
    await tester.pumpAndSettle();
    final avatars = tester.widgetList<Avatar>(find.byType(Avatar)).toList();
    expect(avatars.map((avatar) => avatar.image), [
      [1, 2, 3],
      [1, 2, 3],
    ]);
    // Origin is a closed or unknown session: a global change must not rebuild
    // a forgotten session just to show its avatar everywhere else.
    container.read(sessionsProvider);
    transport.incoming.add(
      const DomainEvent(
        session: 99,
        event: OwnAvatarChangedEvent({'configured': true, 'image': null}),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widgetList<Avatar>(find.byType(Avatar)).map((a) => a.image), [
      null,
      null,
    ]);
    expect(container.read(sessionsProvider), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await transport.incoming.close();
  });

  testWidgets('startup settings restore the saved global image', (
    tester,
  ) async {
    final transport = _Transport();
    final container = ProviderContainer.test(
      overrides: [clientTransportProvider.overrideWithValue(transport)],
    );
    container.listen(ownAvatarProvider, (_, _) {});
    await tester.pump();
    transport.incoming.add(
      FfiEvent.fromJson({
        'kind': 'command_result',
        'command': 'settings',
        'outcome': {'status': 'ok'},
        'data': {
          'own_avatar': {
            'configured': true,
            'image': base64Encode([7, 8]),
          },
        },
      }),
    );
    await tester.pump();
    expect(container.read(ownAvatarProvider).image, [7, 8]);
    expect(container.read(ownAvatarProvider).configured, isTrue);
    container.dispose();
    await transport.incoming.close();
  });

  testWidgets(
    'malformed global images safely fall back without losing removal state',
    (tester) async {
      final transport = _Transport();
      final container = ProviderContainer.test(
        overrides: [clientTransportProvider.overrideWithValue(transport)],
      );
      container.listen(ownAvatarProvider, (_, _) {});
      await tester.pump();
      transport.incoming.add(
        const DomainEvent(
          session: 1,
          event: OwnAvatarChangedEvent({'configured': true, 'image': '%%%'}),
        ),
      );
      await tester.pump();
      expect(container.read(ownAvatarProvider).image, isNull);
      expect(container.read(ownAvatarProvider).configured, isTrue);
      container.dispose();
      await transport.incoming.close();
    },
  );
}
