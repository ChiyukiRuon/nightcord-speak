import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'bookmark_store.dart';

class BrowserBookmarkStore implements BookmarkStore {
  static const key = 'nightcord.bookmarks.v1';

  late final JSFunction _listener = ((web.Event event) {
    final change = event as web.StorageEvent;
    if (change.storageArea == web.window.localStorage &&
        (change.key == key || change.key == null)) {
      _changes.add(null);
    }
  }).toJS;
  late final StreamController<void> _changes = StreamController<void>.broadcast(
    onListen: () => web.window.addEventListener('storage', _listener),
    onCancel: () => web.window.removeEventListener('storage', _listener),
  );

  @override
  String? read() => web.window.localStorage.getItem(key);
  @override
  void write(String data) => web.window.localStorage.setItem(key, data);
  @override
  Stream<void> get changes => _changes.stream;
}
