import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/core/avatar/avatar_repository.dart';
import 'package:nightcord_client/core/transport/client_transport.dart';
import 'package:nightcord_client/models/domain.dart';
import 'package:nightcord_client/models/events.dart';

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
}
