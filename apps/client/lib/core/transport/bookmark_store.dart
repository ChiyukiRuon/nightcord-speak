import 'dart:convert';

import '../../models/bookmarks.dart';

/// Storage belongs to the page origin, independently of its selected gateway.
abstract interface class BookmarkStore {
  String? read();
  void write(String data);
  Stream<void> get changes;
}

class MemoryBookmarkStore implements BookmarkStore {
  String? data;
  @override
  String? read() => data;
  @override
  void write(String data) => this.data = data;
  @override
  Stream<void> get changes => const Stream.empty();
}

/// Migration markers travel with the list so deleted imports stay deleted.
class StoredBookmarks {
  StoredBookmarks({this.list = const BookmarkList(), Set<String>? migrated})
    : migrated = migrated ?? {};

  final BookmarkList list;
  final Set<String> migrated;

  factory StoredBookmarks.read(BookmarkStore store) {
    final raw = store.read();
    if (raw == null) return StoredBookmarks();
    final json = (jsonDecode(raw) as Map).cast<String, dynamic>();
    if (json['version'] != 1 || json['bookmarks'] is! List) {
      throw const FormatException('Unsupported bookmark storage');
    }
    return StoredBookmarks(
      list: BookmarkList.fromJson(json),
      migrated: (json['migrated_gateways'] as List).cast<String>().toSet(),
    );
  }

  void save(BookmarkStore store) => store.write(
    jsonEncode({...list.toJson(), 'migrated_gateways': migrated.toList()}),
  );
}
