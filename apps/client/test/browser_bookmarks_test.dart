import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/core/transport/bookmark_store.dart';
import 'package:nightcord_client/core/transport/remote_transport.dart';
import 'package:nightcord_client/models/bookmarks.dart';
import 'package:nightcord_client/models/events.dart';

import 'remote_transport_test.dart' show FakeSocket, FakeVoice;

class FailingBookmarkStore extends MemoryBookmarkStore {
  final updates = StreamController<void>.broadcast();
  @override
  Stream<void> get changes => updates.stream;
  bool fail = false;
  @override
  void write(String data) {
    if (fail) throw StateError('Storage full');
    super.write(data);
  }
}

void main() {
  late FakeSocket socket;
  late FakeVoice voice;
  late RemoteTransport transport;
  late FailingBookmarkStore store;
  late List<CommandResult> results;
  const local = Bookmark(
    host: 'local.example',
    name: 'Local',
    serverPassword: 'secret',
  );
  const old = Bookmark(host: 'old.example');
  final gateway = Uri.parse('wss://gateway.example/ws');

  Future<void> flush() => Future<void>.delayed(Duration.zero);
  void reply(String command, Map<String, dynamic> data, {bool ok = true}) {
    socket.incoming.add(
      jsonEncode({
        'kind': 'command_result',
        'command': command,
        'data': data,
        'outcome': ok
            ? {'status': 'ok'}
            : {
                'status': 'failed',
                'error': {'kind': 'timeout'},
              },
      }),
    );
  }

  setUp(() {
    socket = FakeSocket();
    voice = FakeVoice();
    store = FailingBookmarkStore();
    results = [];
    transport = RemoteTransport(
      socketFactory: (_) => socket,
      voice: voice,
      bookmarkStore: store,
    );
    final subscription = transport.events.listen((event) {
      if (event is CommandResultEvent) results.add(event.result);
    });
    addTearDown(subscription.cancel);
  });
  tearDown(() async {
    transport.dispose();
    socket.incoming.close();
    await store.updates.close();
    await voice.frames.close();
  });

  test(
    'browser bookmarks persist across transport recreation and gateway changes',
    () async {
      // Previously changing gateways selected a different server-side address book.
      transport.updateBookmarks(const BookmarkList(bookmarks: [local]));
      await flush();
      expect(socket.sent, isEmpty);
      transport.dispose();
      transport = RemoteTransport(
        socketFactory: (_) => socket,
        voice: voice,
        bookmarkStore: store,
      );
      final event = transport.events.first;
      transport.requestBookmarks();
      expect((await event as CommandResultEvent).result.data!['bookmarks'], [
        local.toJson(),
      ]);
      await transport.openGateway(
        Uri.parse('wss://another.example/ws'),
        'token',
      );
      reply('bookmarks', const BookmarkList().toJson());
      await flush();
      expect(
        StoredBookmarks.read(store).list.bookmarks.single.toJson(),
        local.toJson(),
      );
    },
  );

  test('legacy migration merges once without overwriting local edits or resurrecting deletions', () async {
    StoredBookmarks(list: const BookmarkList(bookmarks: [local])).save(store);
    await transport.openGateway(gateway, 'token');
    reply(
      'bookmarks',
      BookmarkList(
        bookmarks: [
          local.copyWith(name: 'Stale'),
          old,
        ],
      ).toJson(),
    );
    await flush();
    var saved = StoredBookmarks.read(store);
    expect(saved.list.bookmarks.map((b) => b.name), ['Local', '']);
    expect(saved.migrated, contains(gateway.toString()));
    transport.updateBookmarks(const BookmarkList());
    await flush();
    // A device-wide broadcast from an old tab must not restore the deleted list.
    reply('bookmarks', const BookmarkList(bookmarks: [old]).toJson());
    reply('bookmark_add', const BookmarkList(bookmarks: [old]).toJson());
    await flush();
    expect(StoredBookmarks.read(store).list.bookmarks, isEmpty);
    socket.sent.clear();
    transport.closeGateway();
    await socket.incoming.close();
    socket = FakeSocket();
    await transport.openGateway(gateway, 'token');
    expect(
      socket.sent.whereType<Map>().where(
        (frame) => frame['command'] == 'bookmarks',
      ),
      isEmpty,
    );
  });

  test('prepared bookmark edits are saved locally and only the requesting tab applies them', () async {
    StoredBookmarks(
      list: const BookmarkList(bookmarks: [old]),
      migrated: {gateway.toString()},
    ).save(store);
    await transport.openGateway(gateway, 'token');
    transport.addBookmark(
      const NewBookmark(
        address: 'ts3://local.example',
        replaces: 'old.example:9987',
      ),
    );
    final sent = socket.sent.last as Map;
    expect(sent['command'], 'bookmark_prepare');
    final id = (sent['payload'] as Map)['request_id'];
    reply('bookmark_prepare', {
      'request_id': 'another-tab',
      'bookmark': local.toJson(),
    });
    await flush();
    expect(StoredBookmarks.read(store).list.bookmarks.single.host, old.host);
    reply('bookmark_prepare', {
      'request_id': id,
      'bookmark': local.toJson(),
      'replaces': {'host': old.host, 'port': old.port},
    });
    await flush();
    expect(
      StoredBookmarks.read(store).list.bookmarks.single.toJson(),
      local.toJson(),
    );
    expect(results.last.command, 'bookmark_add');
    expect(results.last.ok, isTrue);
    expect(
      socket.sent.whereType<Map>().any(
        (f) =>
            f['command'] == 'bookmark_add' ||
            f['command'] == 'bookmarks_update',
      ),
      isFalse,
    );
  });

  test(
    'storage failure reports an error and restores the persisted list',
    () async {
      StoredBookmarks(list: const BookmarkList(bookmarks: [local])).save(store);
      store.fail = true;
      transport.updateBookmarks(const BookmarkList());
      await flush();
      expect(results.first.error?.kind, 'browser_bookmarks_unavailable');
      expect(results.last.command, 'bookmarks');
      expect(results.last.data!['bookmarks'], [local.toJson()]);
      expect(StoredBookmarks.read(store).list.bookmarks, hasLength(1));
    },
  );

  test('corrupt storage is reported and never silently overwritten', () async {
    store.data = 'invalid json';
    transport.requestBookmarks();
    transport.updateBookmarks(const BookmarkList());
    await flush();
    expect(results.every((result) => !result.ok), isTrue);
    expect(store.data, 'invalid json');
  });

  test(
    'storage events refresh other tabs from the latest persisted list',
    () async {
      // Gateway broadcasts no longer own the list; browser storage events do.
      StoredBookmarks(list: const BookmarkList(bookmarks: [local])).save(store);
      store.updates.add(null);
      await flush();
      expect(results.last.command, 'bookmarks');
      expect(results.last.data!['bookmarks'], [local.toJson()]);
      expect(socket.sent, isEmpty);
    },
  );

  test(
    'failed preparation keeps bookmarks intact and carries the original error',
    () async {
      StoredBookmarks(
        list: const BookmarkList(bookmarks: [local]),
        migrated: {gateway.toString()},
      ).save(store);
      await transport.openGateway(gateway, 'token');
      transport.addBookmark(const NewBookmark(address: 'bad'));
      final payload = (socket.sent.last as Map)['payload'] as Map;
      reply('bookmark_prepare', {
        'request_id': payload['request_id'],
      }, ok: false);
      await flush();
      expect(results.last.command, 'bookmark_add');
      expect(results.last.error?.kind, 'timeout');
      expect(
        StoredBookmarks.read(store).list.bookmarks.single.host,
        local.host,
      );
    },
  );
}
