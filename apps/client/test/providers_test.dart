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
import 'package:nightcord_client/models/events.dart';
import 'package:nightcord_client/models/settings.dart';
import 'package:nightcord_client/providers/providers.dart';

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
}
