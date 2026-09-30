// The address book model, and its agreement with what the core stores.
//
// Same contract as `settings_test.dart`: the JSON here is produced and consumed
// by `ts_settings::BookmarkList`, and a field renamed on one side and not the
// other would silently lose saved servers.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/ffi/rust_client.dart';
import 'package:nightcord_client/models/bookmarks.dart';
import 'package:nightcord_client/models/domain.dart';
import 'package:nightcord_client/models/settings.dart';

Map<String, dynamic> roundTrip(BookmarkList list) =>
    jsonDecode(jsonEncode(list.toJson())) as Map<String, dynamic>;

const sample = Bookmark(
  name: '家里的服务器',
  host: '192.168.31.128',
  port: 9987,
  nickname: 'Alice',
  protocol: ProtocolKind.ts6,
  serverPassword: 'hunter2',
);

void main() {
  group('bookmarks', () {
    test('survive the JSON round trip unchanged', () {
      const list = BookmarkList(bookmarks: [sample]);
      expect(BookmarkList.fromJson(roundTrip(list)).toJson(), list.toJson());
    });

    test('an empty object is an empty book, not a crash', () {
      final list = BookmarkList.fromJson(const {});
      expect(list.bookmarks, isEmpty);
      expect(list.version, 1);
    });

    test('an entry missing its port gets the default', () {
      // A hand-written entry. The struct this replaced had no default on its
      // port, so one missing line made the whole address book unreadable.
      final list = BookmarkList.fromJson(const {
        'bookmarks': [
          {'name': 'x', 'host': '192.168.31.128'},
        ],
      });

      expect(list.bookmarks.single.port, 9987);
      expect(list.bookmarks.single.nickname, isNull);
      expect(list.bookmarks.single.serverPassword, isNull);
    });

    test('a list replaced by something else falls back to empty', () {
      final list = BookmarkList.fromJson(const {'bookmarks': 42});
      expect(list.bookmarks, isEmpty);
    });

    test('a nameless entry is shown by its host', () {
      const unnamed = Bookmark(name: '  ', host: 'example.com');
      expect(unnamed.displayName, 'example.com');
    });

    test('saving the same address twice replaces rather than duplicates', () {
      // Otherwise a list quietly fills with the same server because the user
      // saved it again under a different name.
      final list = const BookmarkList().upsert(sample).upsert(sample.copyWith(name: '改名'));

      expect(list.bookmarks, hasLength(1));
      expect(list.bookmarks.single.name, '改名');
    });

    test('a different address is a new entry', () {
      final list = const BookmarkList()
          .upsert(sample)
          .upsert(sample.copyWith(host: 'example.com'));

      expect(list.bookmarks, hasLength(2));
    });

    test('removing out of range leaves the list alone', () {
      final list = const BookmarkList().upsert(sample);

      expect(list.removeAt(7).bookmarks, hasLength(1));
      expect(list.removeAt(-1).bookmarks, hasLength(1));
      expect(list.removeAt(0).bookmarks, isEmpty);
    });

    test('the password is carried but never assumed', () {
      // It is a credential, so an entry saved without one must stay without one
      // rather than picking up a stale value from a copyWith.
      expect(sample.copyWith(clearServerPassword: true).serverPassword, isNull);
      expect(sample.copyWith().serverPassword, 'hunter2');
      expect(const Bookmark().serverPassword, isNull);
    });

    test('the protocol names are the ones the core accepts', () {
      for (final protocol in ProtocolKind.values) {
        final json = Bookmark(protocol: protocol).toJson();
        expect(ProtocolKind.fromWire(json['protocol'] as String), protocol);
      }
    });
  });

  group('connecting from a bookmark', () {
    test('the bookmark wins where it has an opinion', () {
      const settings = Settings(
        connection: ConnectionSettings(nickname: '默认昵称', profile: 'work'),
      );

      final request = ConnectRequest.fromBookmark(sample, settings);

      expect(request.address, '192.168.31.128:9987');
      expect(request.nickname, 'Alice');
      expect(request.serverPassword, 'hunter2');
      expect(request.protocol, ProtocolKind.ts6);
      // Supplied by the settings: a bookmark has no field for it.
      expect(request.profile, 'work');
    });

    test('the settings fill in what the bookmark left open', () {
      const settings = Settings(
        connection: ConnectionSettings(nickname: '默认昵称', profile: 'work'),
      );
      const bare = Bookmark(host: 'example.com', port: 9987);

      final request = ConnectRequest.fromBookmark(bare, settings);

      expect(request.nickname, '默认昵称');
      expect(request.profile, 'work');
      expect(request.serverPassword, isNull);
    });
  });
}
