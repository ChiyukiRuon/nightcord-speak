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
import 'package:nightcord_client/models/domain.dart';
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
    throw StateError(
      'the core refused to report settings: ${result.error?.debugMessage}',
    );
  }
  return Settings.fromJson((result.data as Map).cast<String, dynamic>());
}

/// Asks the core for its address book and parses it.
Future<BookmarkList> readBookmarks(RustClient client) async {
  final pending = awaitCommand(client, 'bookmarks');
  client.requestBookmarks();
  final result = await pending;
  if (!result.ok) {
    throw StateError(
      'the core refused to report bookmarks: ${result.error?.debugMessage}',
    );
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
      //
      // Spelled out per platform rather than read back from
      // `libraryFileName`, which would only assert that the getter equals
      // itself. These are Cargo's rules for a `cdylib` named `nightcord_ffi`:
      // a `lib` prefix and `.dylib`/`.so` on the unixes, neither on Windows.
      //
      // This used to hardcode `.dll`, so it passed only on the one platform it
      // was written on — and the name it guards is exactly the thing that has
      // to be right on every platform.
      final expected = switch (Platform.operatingSystem) {
        'windows' => 'nightcord_ffi.dll',
        'macos' => 'libnightcord_ffi.dylib',
        _ => 'libnightcord_ffi.so',
      };
      expect(NativeLibrary.libraryFileName, expected);
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

    test('the moderation commands reach the core', () async {
      // A session that does not exist, so every one of them fails — which is
      // the point: it proves the C symbols exist, the arguments cross the ABI
      // in the right order, and each call comes back as a named result rather
      // than as silence or a crash. What they do against a real server is a
      // server test, not this one.
      final client = RustClient.start();
      addTearDown(client.dispose);

      final calls = <String, void Function()>{
        'set_nickname': () => client.setNickname(99, 'New Name'),
        'poke': () => client.poke(99, 2, 'hello'),
        'kick': () => client.kick(99, 2, KickScope.server, null),
        'ban': () => client.ban(99, 2, BanDuration.seconds(60), 'because'),
        'voice_set_client_volume': () => client.setClientVolume(99, 2, 0.5),
        'set_away': () => client.setAway(99, away: true, message: 'brb'),
      };

      for (final entry in calls.entries) {
        final pending = awaitCommand(client, entry.key);
        entry.value();
        final result = await pending;
        expect(
          result.ok,
          isFalse,
          reason:
              '${entry.key} against a missing session should report failure',
        );
      }
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
      expect(
        result.session,
        isNull,
        reason: 'device queries are not session-scoped',
      );
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
      expect(
        directory,
        isNotNull,
        reason: 'no log directory on a desktop platform',
      );
      expect(
        Directory(directory!).existsSync(),
        isTrue,
        reason: 'the core should have created the directory it reports',
      );
    });

    test(
      'a line forwarded from Dart reaches the file the UI points at',
      () async {
        // The whole chain, across the ABI. Without it the UI could offer a path
        // to a file that never receives anything the app forwards to it — which
        // is worse than no path at all, because it looks like an answer.
        final directory = coreLogDirectory();
        expect(directory, isNotNull);

        final marker =
            'dart-forwarded-${DateTime.now().microsecondsSinceEpoch}';
        logToCore('error', marker);

        final found = await _pollUntil(
          () => _logFilesContain(Directory(directory!), marker),
        );
        expect(found, isTrue, reason: '$marker never reached $directory');
      },
    );

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
      expect(
        back.notifications.directMessage,
        isTrue,
        reason: 'one switch, not all',
      );
      expect(
        back.ui.language,
        'en',
        reason: 'the language must not vanish on the way back',
      );
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

    test('editing a server moves it rather than leaving the old one behind', () async {
      // An address is an entry's identity, so changing it is not an update at
      // all unless the core is told which row the edit supersedes. Without
      // `replaces` the old address stays and a second entry appears beside it.
      final client = RustClient.start();
      addTearDown(client.dispose);

      final original = await readBookmarks(client);
      addTearDown(() => client.updateBookmarks(original));

      var pending = awaitCommand(client, 'bookmark_add');
      client.addBookmark(
        const NewBookmark(
          name: 'Before',
          address: '192.168.31.128:9999',
          nickname: 'Someone',
        ),
      );
      await pending;

      pending = awaitCommand(client, 'bookmark_add');
      client.addBookmark(
        const NewBookmark(
          name: 'After',
          address: '192.168.31.129:9999',
          nickname: 'Someone',
          replaces: '192.168.31.128:9999',
        ),
      );
      final result = await pending;
      expect(result.ok, isTrue, reason: result.error?.debugMessage);

      // Matched on the port as well as the host: the developer's real address
      // book has other servers on that same address, and a filter that caught
      // them would fail for a reason that has nothing to do with the edit.
      final saved = (await readBookmarks(client)).bookmarks;
      expect(
        saved.where((b) => b.host == '192.168.31.128' && b.port == 9999),
        isEmpty,
        reason: 'the entry the edit superseded is gone',
      );

      final moved = saved.where(
        (b) => b.host == '192.168.31.129' && b.port == 9999,
      );
      expect(moved, hasLength(1));
      expect(moved.single.name, 'After');
      expect(
        moved.single.nickname,
        'Someone',
        reason: 'the rest of the edit came with it',
      );
    });

    test('editing without moving the address does not reorder the list', () async {
      // `replaces` and the new address being equal is an ordinary save. Handled
      // by the same code path, and getting it wrong would silently push the
      // entry to the end of the list every time its name was changed.
      final client = RustClient.start();
      addTearDown(client.dispose);

      final original = await readBookmarks(client);
      addTearDown(() => client.updateBookmarks(original));

      var pending = awaitCommand(client, 'bookmark_add');
      client.addBookmark(
        const NewBookmark(name: 'First', address: '192.168.31.128:9998'),
      );
      await pending;

      final before = (await readBookmarks(client)).bookmarks;
      final at = before.indexWhere((b) => b.port == 9998);
      expect(at, isNonNegative);

      pending = awaitCommand(client, 'bookmark_add');
      client.addBookmark(
        const NewBookmark(
          name: 'Renamed',
          address: '192.168.31.128:9998',
          replaces: '192.168.31.128:9998',
        ),
      );
      await pending;

      final after = (await readBookmarks(client)).bookmarks;
      expect(after, hasLength(before.length));
      expect(
        after.indexWhere((b) => b.port == 9998),
        at,
        reason: 'same position',
      );
      expect(after[at].name, 'Renamed');
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

  group('crash evidence', () {
    test('the status answers and names the directory', () {
      // Deliberately no command and no handle on the Rust side: the question
      // is asked when the core is dead or never started, which is exactly when
      // a command could not be answered.
      final client = RustClient.start();
      addTearDown(client.dispose);

      final status = client.crashStatus();
      expect(
        status.available,
        isTrue,
        reason: 'the desktop always has a data root',
      );

      // A sibling of `logs/`, not a child of it: the first version of this
      // wiring reused the log helper, which appends `logs`, and the `contains`
      // assertion this replaces would not have noticed (docs/settings.md's
      // reasoning about the shared data root, one directory over).
      final logDir = coreLogDirectory();
      expect(logDir, isNotNull);
      final dataRoot = File(logDir!).parent.path;
      expect(status.directory, '$dataRoot${Platform.pathSeparator}crashes');
    });

    test('a live run can be marked as a clean exit, twice', () {
      final client = RustClient.start();
      addTearDown(client.dispose);

      expect(client.markCleanExit(), isTrue, reason: 'the worker is alive');
      // Idempotent: the second call has nothing left to remove and must not
      // turn into a failure.
      expect(client.markCleanExit(), isTrue);
    });

    test('a report is written, readable, and can be taken back', () {
      final client = RustClient.start();
      addTearDown(client.dispose);

      final result = client.buildCrashReport();
      expect(result.error, isNull);
      final path = result.path;
      expect(path, isNotNull);

      final file = File(path!);
      expect(file.existsSync(), isTrue);
      final text = file.readAsStringSync();
      expect(text, contains('Nightcord Speak crash report'));
      expect(text, contains('===== log tail ====='));
      expect(text, contains('Review it before sharing'));

      // The report went into the developer's real crashes directory; this test
      // puts the directory back the way it found it.
      file.deleteSync();
    });
  });
}
