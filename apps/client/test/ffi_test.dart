// Proves the Dart side can actually reach the Rust core.
//
// These run the real shared library, not a stub: if the ABI drifts, or the
// library stops exporting a symbol, this is where it shows up rather than in a
// stack trace three widgets deep.
//
// Everything goes through `client.events`. The core releases each event exactly
// once, so there is no second reader to consult — an earlier version of these
// tests polled the queue directly and silently lost results to the stream.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/ffi/native.dart';
import 'package:nightcord_client/ffi/rust_client.dart';
import 'package:nightcord_client/models/bookmarks.dart';
import 'package:nightcord_client/models/events.dart';
import 'package:nightcord_client/models/settings.dart';

import 'test_support.dart';

/// Polls [check] until it holds, or gives up after a few seconds.
///
/// The log writer is asynchronous by design — that is what keeps it off the
/// audio thread — so the file is not written the instant `logToCore` returns.
Future<bool> _pollUntil(bool Function() check) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    if (check()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return false;
}

/// Asks the core for its settings and parses them.
///
/// A helper rather than inline because more than one test needs to read them,
/// and the request-and-collect dance is the part that would drift.
Future<Settings> readSettings(RustClient client) async {
  final pending = awaitCommand(client, 'settings');
  client.requestSettings();
  final result = await pending;
  if (!result.ok) {
    throw StateError('the core refused to report settings: ${result.error?.debugMessage}');
  }
  return Settings.fromJson((result.data as Map).cast<String, dynamic>());
}

/// Asks the core for its address book and parses it.
Future<BookmarkList> readBookmarks(RustClient client) async {
  final pending = awaitCommand(client, 'bookmarks');
  client.requestBookmarks();
  final result = await pending;
  if (!result.ok) {
    throw StateError('the core refused to report bookmarks: ${result.error?.debugMessage}');
  }
  return BookmarkList.fromJson((result.data as Map).cast<String, dynamic>());
}

/// Whether any file under [directory] contains [needle].
bool _logFilesContain(Directory directory, String needle) {
  if (!directory.existsSync()) return false;
  for (final entry in directory.listSync()) {
    if (entry is! File) continue;
    try {
      if (entry.readAsStringSync().contains(needle)) return true;
    } on FileSystemException {
      // Being written to as we read it; the next pass will do.
    }
  }
  return false;
}

void main() {
  group('library loading', () {
    test('the library loads and reports its version', () {
      final client = RustClient.start();
      addTearDown(client.dispose);

      // Reaching this line at all means every symbol resolved.
      expect(client.version, startsWith('nightcord '));
    });

    test('the platform name is what Cargo produces', () {
      // A mismatch here is the whole reason a library turns up "not found".
      expect(NativeLibrary.libraryFileName, endsWith('.dll'));
    });
  });

  group('lifecycle', () {
    test('a fresh client emits nothing until something happens', () async {
      final client = RustClient.start();
      addTearDown(client.dispose);

      final received = <FfiEvent>[];
      final subscription = client.events.listen(received.add);
      addTearDown(subscription.cancel);

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(received, isEmpty);
    });

    test('disposing twice is harmless', () {
      // `dispose` runs from widget teardown, which can race a rebuild.
      final client = RustClient.start();
      client.dispose();
      client.dispose();
    });

    test('the stream closes on dispose', () async {
      final client = RustClient.start();
      final subscription = client.events.listen((_) {});

      client.dispose();
      await subscription.cancel();
    });
  });

  group('command results', () {
    test('an invalid direction is reported rather than ignored', () async {
      // The UI must learn its request was rejected, not wait forever for a
      // result that will never arrive.
      final client = RustClient.start();
      addTearDown(client.dispose);

      final pending = awaitCommand(client, 'audio_devices');
      client.requestAudioDevices('sideways');
      final result = await pending;

      expect(result.ok, isFalse);
      expect(result.error?.debugMessage, contains('sideways'));
      expect(result.session, isNull, reason: 'device queries are not session-scoped');
    });

    test('a device list arrives as data on a successful result', () async {
      // Enumeration touches real hardware, so the count is whatever this
      // machine has; the shape is what is under test.
      final client = RustClient.start();
      addTearDown(client.dispose);

      final pending = awaitCommand(client, 'audio_devices');
      client.requestAudioDevices('output');
      final result = await pending;

      expect(result.ok, isTrue, reason: result.error?.debugMessage);
      expect(result.data?['direction'], 'output');
      expect(result.data?['devices'], isA<List<dynamic>>());
    });

    test('consecutive queries both answer', () async {
      // Guards the failure that started this: one request being answered and
      // the next vanishing.
      final client = RustClient.start();
      addTearDown(client.dispose);

      final first = awaitCommand(client, 'audio_devices');
      client.requestAudioDevices('input');
      expect((await first).ok, isTrue);

      final second = awaitCommand(client, 'audio_devices');
      client.requestAudioDevices('output');
      expect((await second).ok, isTrue);
    });
  });

  group('logging', () {
    test('the log directory is reported without a client', () {
      // No `RustClient` is started here on purpose: the startup-failure screen
      // has none, and it is the screen that most needs the path.
      final directory = coreLogDirectory();

      // Null is a legitimate answer where the platform gives no writable root,
      // but this build targets desktops, where there always is one — and if
      // that ever stopped being true the UI's button would silently vanish.
      expect(directory, isNotNull, reason: 'no log directory on a desktop platform');
      expect(
        Directory(directory!).existsSync(),
        isTrue,
        reason: 'the core should have created the directory it reports',
      );
    });

    test('a line forwarded from Dart reaches the file the UI points at', () async {
      // The whole chain, across the ABI. Without it the UI could offer a path
      // to a file that never receives anything the app forwards to it — which
      // is worse than no path at all, because it looks like an answer.
      final directory = coreLogDirectory();
      expect(directory, isNotNull);

      final marker = 'dart-forwarded-${DateTime.now().microsecondsSinceEpoch}';
      logToCore('error', marker);

      final found = await _pollUntil(() => _logFilesContain(Directory(directory!), marker));
      expect(found, isTrue, reason: '$marker never reached $directory');
    });

    test('an awkward line is accepted rather than thrown', () {
      // Called from error handlers, where raising a second error would replace
      // a reportable failure with a confusing one.
      expect(() => logToCore('not a level', '记录下来'), returnsNormally);
      expect(() => logToCore('error', ''), returnsNormally);
      expect(() => logToCore('error', '换行\n也要能记'), returnsNormally);
    });
  });

  group('settings', () {
    test('an edit written through the FFI comes back', () async {
      // The whole chain — Dart, the ABI, the core, the file, and back — without
      // any UI in the way.
      //
      // This writes the developer's real preferences file, so whatever was
      // there is read first and put back afterwards. A test that leaves someone
      // else's nickname rewritten is a test that gets switched off.
      final client = RustClient.start();
      addTearDown(client.dispose);

      final original = await readSettings(client);
      addTearDown(() => client.updateSettings(original));

      final edited = original.copyWith(
        connection: original.connection.copyWith(nickname: 'Round Trip'),
        // The notification switches go with it: a section the core does not
        // know about would be accepted and then silently stripped on the next
        // read, which is worse than rejecting it.
        notifications: original.notifications.copyWith(presence: false),
        ui: original.ui.copyWith(language: 'en'),
      );

      final pending = awaitCommand(client, 'settings_update');
      client.updateSettings(edited);
      final result = await pending;

      expect(result.ok, isTrue, reason: result.error?.debugMessage);

      final back = await readSettings(client);
      expect(back.connection.nickname, 'Round Trip');
      expect(back.notifications.presence, isFalse);
      expect(back.notifications.directMessage, isTrue, reason: 'one switch, not all');
      expect(back.ui.language, 'en', reason: 'the language must not vanish on the way back');
    });

    test('the core answers with settings this build can read', () async {
      // Read-only on purpose: a test that rewrote the developer's own
      // preferences would be a test that gets switched off. The write path is
      // covered where it can be undone — `crates/ts-ffi`, which restores the
      // file it found.
      final client = RustClient.start();
      addTearDown(client.dispose);

      final settings = await readSettings(client);

      expect(settings.version, 1);
      expect(settings.connection.nickname, isNotEmpty);
      expect(settings.connection.profile, isNotEmpty);
    });
  });

  group('bookmarks', () {
    test('a server saved through the FFI comes back', () async {
      // The whole chain for the address book, and the one thing the Dart model
      // cannot check: that the core's parser accepts what a user types and
      // normalises it into the stored form.
      //
      // This writes the developer's real address book, so whatever was there
      // goes back afterwards.
      final client = RustClient.start();
      addTearDown(client.dispose);

      final original = await readBookmarks(client);
      addTearDown(() => client.updateBookmarks(original));

      final pending = awaitCommand(client, 'bookmark_add');
      client.addBookmark(
        const NewBookmark(name: 'Round Trip', address: '192.168.31.128:9987'),
      );
      final result = await pending;

      expect(result.ok, isTrue, reason: result.error?.debugMessage);

      final saved = (await readBookmarks(client)).bookmarks
          .where((b) => b.name == 'Round Trip')
          .toList();
      expect(saved, hasLength(1));
      expect(saved.single.host, '192.168.31.128');
      expect(saved.single.port, 9987);
    });

    test('an address the core cannot parse is refused rather than stored', () async {
      // Pasting a browser URL is the mistake this catches. The host itself is
      // deliberately not validated — DNS is the authority on that, and guessing
      // at hostname syntax rejects addresses that work. The scheme is another
      // matter: `http://` is never going to reach a TeamSpeak server.
      final client = RustClient.start();
      addTearDown(client.dispose);

      final before = await readBookmarks(client);

      final pending = awaitCommand(client, 'bookmark_add');
      client.addBookmark(
        const NewBookmark(name: 'Bad', address: 'https://example.com/server'),
      );
      final result = await pending;

      expect(result.ok, isFalse);
      expect(result.error?.debugMessage, contains('scheme'));

      // And nothing was written. Compared as JSON because these are value
      // objects without an `==`, and the point is that the stored bytes match.
      expect((await readBookmarks(client)).toJson(), before.toJson());
    });

    test('the core answers with bookmarks this build can read', () async {
      final client = RustClient.start();
      addTearDown(client.dispose);

      final bookmarks = await readBookmarks(client);
      expect(bookmarks.version, 1);
    });
  });

  group('event stream', () {
    test('carries results to every listener', () async {
      // The stream is a broadcast: the store and a settings page may both be
      // watching, and neither should starve the other.
      final client = RustClient.start();
      addTearDown(client.dispose);

      final first = <FfiEvent>[];
      final second = <FfiEvent>[];
      final a = client.events.listen(first.add);
      final b = client.events.listen(second.add);
      addTearDown(a.cancel);
      addTearDown(b.cancel);

      final pending = awaitCommand(client, 'audio_devices');
      client.requestAudioDevices('input');
      await pending;

      expect(first, isNotEmpty);
      expect(second, isNotEmpty);
    });
  });
}
