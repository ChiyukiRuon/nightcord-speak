// The bridge from the core's event stream to the stores (§18).
//
// The stores themselves are pure Dart and tested directly — see
// `server_view_test.dart` and `notification_test.dart`. What cannot be covered
// there is the wiring: whether an event that arrives from Rust actually reaches
// the provider the UI reads.

import 'dart:async';
import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/core/transport/client_transport.dart';
import 'package:nightcord_client/design/tokens/app_palette.dart';
import 'package:nightcord_client/models/connect_request.dart';
import 'package:nightcord_client/models/domain.dart';
import 'package:nightcord_client/models/events.dart';
import 'package:nightcord_client/models/settings.dart';
import 'package:nightcord_client/providers/providers.dart';

/// A transport that only records, so a test can prove the app talks to the
/// interface and not to a particular implementation.
///
/// Only the members a test exercises are implemented; the rest throw, which is
/// also a statement: nothing else may be needed to run the stores.
class _RecordingTransport implements ClientTransport {
  final List<String> calls = [];
  final StreamController<FfiEvent> _events = StreamController<FfiEvent>.broadcast();

  @override
  Stream<FfiEvent> get events => _events.stream;

  @override
  void voiceStart(int session, {String? inputDevice, String? outputDevice}) =>
      calls.add('voiceStart:$session');

  @override
  void setInputMuted(bool muted) => calls.add('setInputMuted:$muted');

  @override
  void setOutputMuted(bool muted) => calls.add('setOutputMuted:$muted');

  @override
  void connect(ConnectRequest request) => calls.add('connect:${request.address}');

  @override
  void dispose() => calls.add('dispose');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not part of this test');
}

/// A [SettingsNotifier] that answers with a fixed object, without a core.
class _FixedSettings extends SettingsNotifier {
  _FixedSettings(this.settings);

  final Settings? settings;

  @override
  Settings? build() => settings;
}

/// A container whose settings and "system" the test controls.
ProviderContainer containerWith({
  Settings? settings,
  List<Locale> system = const [Locale('en')],
}) => ProviderContainer.test(
  overrides: [
    settingsProvider.overrideWith(() => _FixedSettings(settings)),
    systemLocalesProvider.overrideWithValue(system),
  ],
);

void main() {
  test('a core error reaches the error channel', () async {
    // Regression: an `ErrorEvent` used to stop at the view — and `ServerView`
    // keeps no error state, so a failed handshake or a dropped connection drew
    // nothing and said nothing; the channel tree simply froze. It has to be
    // reported from the envelope handler, because it is not tied to a command
    // the user issued and so has no command result to arrive in.
    //
    // The controller is deliberately left unclosed: with Riverpod holding the
    // source subscription, `close()` never completes and a teardown awaiting it
    // would hang until the test's timeout. Nothing outlives the test.
    final events = StreamController<FfiEvent>();
    final container = ProviderContainer.test(
      overrides: [eventStreamProvider.overrideWith((_) => events.stream)],
    );

    // `ref.listen` inside the notifier's `build` is what reacts to the stream,
    // so the provider has to exist before the event is pushed.
    final subscription = container.listen(sessionsProvider, (_, _) {});
    addTearDown(subscription.close);

    const error = ClientError(kind: 'timeout', detail: '握手超时');
    events.add(const DomainEvent(session: 7, event: ErrorEvent(error)));
    await pumpEventQueue();

    expect(container.read(lastErrorProvider), same(error));
  });

  test('the stores speak to the transport interface, not to the FFI', () async {
    // The seam's whole point: everything above `clientTransportProvider` works
    // against the interface, whichever core is below it. A fake transport that
    // records calls proves the stores never reach past it.
    final transport = _RecordingTransport();
    final container = ProviderContainer.test(
      overrides: [clientTransportProvider.overrideWithValue(transport)],
    );
    final subscription = container.listen(sessionsProvider, (_, _) {});
    addTearDown(subscription.close);

    // A connected session, so the mute toggle has something to act on.
    container.read(activeSessionProvider.notifier).select(7);
    transport._events.add(const DomainEvent(
      session: 7,
      event: ConnectionStateChangedEvent(ConnectionState.connected),
    ));
    await pumpEventQueue();

    container.read(sessionsProvider.notifier).toggleInputMuted(7);
    container.read(sessionsProvider.notifier).toggleOutputMuted(7);

    // `voiceStart` comes first because connecting opens the engine — see the
    // test below for why.
    expect(transport.calls, [
      'voiceStart:7',
      'setInputMuted:true',
      'setOutputMuted:true',
    ]);
  });

  test('connecting opens the voice engine', () async {
    // Regression: voice was started only from a button inside the settings
    // dialog, so a client that had connected and joined a channel both heard
    // nothing and said nothing — with no error, no log line and nothing on
    // screen to say why. There is no "start voice" in TeamSpeak: the
    // connection is the switch.
    final transport = _RecordingTransport();
    final container = ProviderContainer.test(
      overrides: [clientTransportProvider.overrideWithValue(transport)],
    );
    final subscription = container.listen(sessionsProvider, (_, _) {});
    addTearDown(subscription.close);

    transport._events.add(const DomainEvent(
      session: 3,
      event: ConnectionStateChangedEvent(ConnectionState.connected),
    ));
    await pumpEventQueue();

    expect(transport.calls, ['voiceStart:3']);
  });

  test('a reconnect does not reopen a microphone that is already running', () async {
    // The engine outlives a dropped connection: reopening the devices would
    // cut off a stream that had recovered on its own.
    final transport = _RecordingTransport();
    final container = ProviderContainer.test(
      overrides: [clientTransportProvider.overrideWithValue(transport)],
    );
    final subscription = container.listen(sessionsProvider, (_, _) {});
    addTearDown(subscription.close);

    for (final state in [
      ConnectionState.connected,
      ConnectionState.reconnecting,
      ConnectionState.connected,
    ]) {
      transport._events.add(
        DomainEvent(session: 3, event: ConnectionStateChangedEvent(state)),
      );
      await pumpEventQueue();
    }

    expect(transport.calls, ['voiceStart:3']);
  });

  group('localeProvider', () {
    test('an explicit language wins over the system', () {
      final container = containerWith(
        settings: const Settings(ui: UiSettings(language: 'en')),
        system: const [Locale('zh')],
      );

      expect(container.read(localeProvider), const Locale('en'));
    });

    test('without a setting the system decides', () {
      final container = containerWith(system: const [Locale('zh', 'CN')]);

      // The *supported* locale comes back, not the system's exact tag.
      expect(container.read(localeProvider), const Locale('zh'));
    });

    test('before the core has answered, the system decides', () {
      // Settings are null while the round trip is in flight; the first frame
      // must not sit in some default language the user never chose.
      final container = containerWith(system: const [Locale('zh')]);

      expect(container.read(localeProvider), const Locale('zh'));
    });

    test('a system language this build does not have falls back to English', () {
      final container = containerWith(system: const [Locale('fr')]);

      expect(container.read(localeProvider), const Locale('en'));
    });

    test('an unrecognized stored language follows the system', () {
      // A hand-edited file, or a language a newer build supports. The stored
      // value stays in the file — see `settings_test` — but the UI falls back
      // rather than matching nothing.
      final container = containerWith(
        settings: const Settings(ui: UiSettings(language: 'fr')),
        system: const [Locale('zh')],
      );

      expect(container.read(localeProvider), const Locale('zh'));
    });
  });

  group('themeChoiceProvider', () {
    test('an explicit theme fills both slots', () {
      // Which is what makes the system's brightness irrelevant to an explicit
      // choice: `MaterialApp` has nothing to switch between.
      for (final name in ['nightcord', 'black', 'white']) {
        final container = containerWith(settings: Settings(ui: UiSettings(theme: name)));
        final choice = container.read(themeChoiceProvider);

        expect(choice.light.name, name);
        expect(choice.dark.name, name);
      }
    });

    test('following the system is White by day and Black by night', () {
      final container = containerWith(
        settings: const Settings(ui: UiSettings(theme: 'system')),
      );
      final choice = container.read(themeChoiceProvider);

      expect(choice.light, AppPalette.white);
      expect(choice.dark, AppPalette.black);
    });

    test('before the core has answered, the default theme is drawn', () {
      // Settings are null while the round trip is in flight. The first frame
      // must not flash a theme the user did not choose — and the default is
      // Nightcord, not "follow the system".
      final container = containerWith();
      final choice = container.read(themeChoiceProvider);

      expect(choice.light, AppPalette.nightcord);
      expect(choice.dark, AppPalette.nightcord);
    });

    test('an unrecognized stored theme falls back to the default', () {
      final container = containerWith(
        settings: const Settings(ui: UiSettings(theme: 'solarized')),
      );
      final choice = container.read(themeChoiceProvider);

      expect(choice.light, AppPalette.nightcord);
      expect(choice.dark, AppPalette.nightcord);
    });

    test('the two halves are always a real pair', () {
      // Whatever the setting says, neither slot may be "nothing" — the widget
      // that draws them does not handle a null theme.
      for (final theme in [null, 'nightcord', 'black', 'white', 'system', 'nonsense']) {
        final container = containerWith(settings: Settings(ui: UiSettings(theme: theme)));
        final choice = container.read(themeChoiceProvider);

        expect(AppPalette.all, contains(choice.light));
        expect(AppPalette.all, contains(choice.dark));
      }
    });
  });
}
