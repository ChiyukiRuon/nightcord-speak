import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/core/avatar/avatar_repository.dart';
import 'package:nightcord_client/core/avatar/avatar_cache.dart';
import 'package:nightcord_client/core/transport/client_transport.dart';
import 'package:nightcord_client/models/domain.dart';
import 'package:nightcord_client/models/events.dart';
import 'package:nightcord_client/design/components/app_avatar.dart';
import 'package:nightcord_client/features/avatar/client_avatar.dart';
import 'package:nightcord_client/providers/providers.dart';
import 'package:nightcord_client/state/server_view.dart';

class _Transport implements ClientTransport {
  final incoming = StreamController<FfiEvent>.broadcast(sync: true);
  final calls = <(int, int)>[];
  @override
  Stream<FfiEvent> get events => incoming.stream;
  @override
  void getAvatar(int session, int clientId) => calls.add((session, clientId));
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  void answer(AvatarKey key, {String? version, bool ok = true}) {
    incoming.add(
      FfiEvent.fromJson({
        'kind': 'command_result',
        'command': 'get_avatar',
        'session': key.session,
        'outcome': ok
            ? {'status': 'ok'}
            : {
                'status': 'failed',
                'error': {'kind': 'timeout'},
              },
        'data': {
          'client_id': key.clientId,
          'version': version ?? key.version,
          'image': base64Encode([1, 2, 3]),
        },
      }),
    );
  }
}

AvatarKey key(
  int id, {
  int session = 1,
  String identity = 'alice',
  String version = 'one',
}) => (session: session, clientId: id, identity: identity, version: version);

class _Storage implements AvatarCacheStorage {
  String? data;
  @override
  Future<String?> read() async => data;
  @override
  Future<void> write(String value) async => data = value;
}

class _Sessions extends SessionsNotifier {
  @override
  Map<int, ServerView> build() => {
    1: ServerView(session: 1)
      ..server = const Server(
        id: 1,
        name: 'Server',
        address: 'server',
        protocol: ProtocolKind.ts3,
      ),
  };
}

void main() {
  late _Transport transport;
  late AvatarRepository repository;
  setUp(() {
    transport = _Transport();
    repository = AvatarRepository(transport);
  });
  tearDown(() async {
    repository.dispose();
    await transport.incoming.close();
  });

  test('chat and tree share one load; revisions and identities invalidate the cache', () async {
    final first = repository.fetch(key(2));
    final duplicate = repository.fetch(key(2));
    expect(transport.calls, [(1, 2)]);
    transport.answer(key(2));
    expect(await first, [1, 2, 3]);
    expect(await duplicate, [1, 2, 3]);
    expect(await repository.fetch(key(2)), [1, 2, 3]);
    final changed = repository.fetch(key(2, version: 'two'));
    transport.answer(key(2, version: 'two'));
    expect(await changed, [1, 2, 3]);
    // The server can hand the departed client's numeric id to someone else.
    final reused = repository.fetch(key(2, identity: 'bob', version: 'two'));
    expect(transport.calls.length, 3);
    transport.answer(key(2, identity: 'bob', version: 'two'));
    expect(await reused, [1, 2, 3]);
  });

  test(
    'stale answers and errors fall back, without poisoning another session',
    () async {
      final first = repository.fetch(key(2));
      final second = repository.fetch(key(2, session: 2));
      transport.answer(key(2), version: 'superseded');
      transport.answer(key(2, session: 2));
      expect(await first, isNull);
      expect(await second, isA<Uint8List>());
      final denied = repository.fetch(key(3));
      transport.answer(key(3), ok: false);
      expect(await denied, isNull);
      expect(await repository.fetch(key(3)), isNull);
      expect(transport.calls.where((call) => call == (1, 3)).length, 1);
    },
  );

  test(
    'large channel trees load three images at a time and release queued work',
    () async {
      final futures = [
        for (var id = 1; id <= 7; id++) repository.fetch(key(id)),
      ];
      expect(transport.calls.length, 3);
      for (var id = 1; id <= 7; id++) {
        transport.answer(key(id));
      }
      expect(transport.calls.length, 7);
      expect(await Future.wait(futures), everyElement([1, 2, 3]));
    },
  );

  test('disposing completes active and queued requests', () async {
    final futures = [for (var id = 1; id <= 7; id++) repository.fetch(key(id))];
    repository.dispose();
    expect(await Future.wait(futures), everyElement(isNull));
  });

  test(
    'a new session displays the persisted avatar before its server reply',
    () async {
      // Previously a restart left chat and tree avatars blank until download.
      final storage = _Storage();
      await AvatarCache(storage)
          .save('server:9987', 'alice', Uint8List.fromList([9]));
      repository.dispose();
      repository = AvatarRepository(
        transport,
        persistentCache: AvatarCache(storage),
      );
      final images = <Uint8List?>[];
      final ready = Completer<void>();
      final done = Completer<void>();
      repository
          .watch(key(8, session: 3, version: 'new'), server: 'server:9987')
          .listen((image) {
            images.add(image);
            if (!ready.isCompleted) ready.complete();
          }, onDone: done.complete);
      await ready.future;
      expect(images, [
        [9],
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(transport.calls, [(3, 8)]);
      transport.answer(key(8, session: 3, version: 'new'));
      await done.future;
      expect(images, [
        [9],
        [1, 2, 3],
      ]);
      expect(await AvatarCache(storage).read('server:9987', 'alice'), [
        1,
        2,
        3,
      ]);
    },
  );

  test('failed refresh retains the previous avatar without crossing identities or servers', () async {
    // Cached images must not leak when a numeric client id is reused.
    final storage = _Storage();
    final cache = AvatarCache(storage);
    await cache.save('server', 'alice', Uint8List.fromList([9]));
    repository.dispose();
    repository = AvatarRepository(transport, persistentCache: cache);
    final images = <Uint8List?>[];
    final done = Completer<void>();
    repository
        .watch(key(2), server: 'server')
        .listen(images.add, onDone: done.complete);
    await Future<void>.delayed(Duration.zero);
    transport.answer(key(2), ok: false);
    await done.future;
    expect(images, [
      [9],
      [9],
    ]);
    expect(await cache.read('other', 'alice'), isNull);
    expect(await cache.read('server', 'bob'), isNull);
    expect(await cache.read('server', null), isNull);
  });

  test('unsubscribing after a fresh image still persists it', () async {
    // Leaving the page as an image arrives must not cancel its cache write.
    final storage = _Storage();
    repository.dispose();
    repository = AvatarRepository(
      transport,
      persistentCache: AvatarCache(storage),
    );
    final image = repository.watch(key(2), server: 'server').first;
    await Future<void>.delayed(Duration.zero);
    transport.answer(key(2));
    expect(await image, [1, 2, 3]);
    await Future<void>.delayed(Duration.zero);
    expect(await AvatarCache(storage).read('server', 'alice'), [1, 2, 3]);
  });

  test('old snapshots still parse and moves preserve the image revision', () {
    final client = Client.fromJson({
      'id': 1,
      'name': 'Alice',
      'channel_id': 2,
      'avatar_version': 'image-v1',
    });
    expect(client.movedTo(3).avatarVersion, 'image-v1');
    expect(Client.fromJson({'id': 1}).avatarVersion, isNull);
  });

  testWidgets(
    'client avatar shows cached and refreshed images, then hides a removed avatar',
    (tester) async {
      // The shared widget must retain the cache until a fresh image arrives.
      final cache = AvatarCache(_Storage());
      await cache.save('server', 'alice', Uint8List.fromList([9]));
      repository.dispose();
      repository = AvatarRepository(transport, persistentCache: cache);
      final container = ProviderContainer.test(
        overrides: [
          clientTransportProvider.overrideWithValue(transport),
          avatarRepositoryProvider.overrideWithValue(repository),
          sessionsProvider.overrideWith(_Sessions.new),
        ],
      );
      Future<void> render(String? version) => tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: ClientAvatar(
              session: 1,
              client: Client(
                id: 2,
                name: 'Alice',
                channelId: 1,
                uniqueId: 'alice',
                avatarVersion: version,
              ),
            ),
          ),
        ),
      );
      await render('one');
      await tester.pumpAndSettle();
      expect(tester.widget<Avatar>(find.byType(Avatar)).image, [9]);
      expect(transport.calls, [(1, 2)]);
      transport.answer(key(2));
      await tester.pumpAndSettle();
      expect(tester.widget<Avatar>(find.byType(Avatar)).image, [1, 2, 3]);
      await render(null);
      await tester.pumpAndSettle();
      expect(tester.widget<Avatar>(find.byType(Avatar)).image, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    },
  );
}
