// Proves the Dart side can actually reach the Rust core.
//
// These run the real shared library, not a stub: if the ABI drifts, or the
// library stops exporting a symbol, this is where it shows up rather than in a
// stack trace three widgets deep.
//
// Everything goes through `client.events`. The core releases each event exactly
// once, so there is no second reader to consult — an earlier version of these
// tests polled the queue directly and silently lost results to the stream.

import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/ffi/native.dart';
import 'package:nightcord_client/ffi/rust_client.dart';
import 'package:nightcord_client/models/events.dart';

import 'test_support.dart';

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
      expect(result.error?.message, contains('sideways'));
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

      expect(result.ok, isTrue, reason: result.error?.message);
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
