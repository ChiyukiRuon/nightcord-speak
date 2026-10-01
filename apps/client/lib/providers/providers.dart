// The bridge between the Rust core's event stream and the widget tree.
//
// This is the chain from §18: events arrive, a store accumulates them, and
// widgets read the store. Nothing here touches FFI directly except through
// `RustClient`.

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart' show Locale, basicLocaleListResolution;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/transport/client_transport.dart';
import '../design/tokens/app_palette.dart';
import '../ffi/rust_client.dart';
import '../l10n/app_localizations.dart';
import '../models/domain.dart';
import '../models/events.dart';
import '../models/bookmarks.dart';
import '../models/settings.dart';
import '../models/voice_status.dart';
import '../state/notifications.dart';
import '../state/server_view.dart';
import '../util/system_notifications.dart';

/// The running Rust core, started once for the app.
///
/// Starting it can fail — the shared library may be missing from the build —
/// and that is a hard failure rather than something to paper over, so it is
/// allowed to throw. `main` catches it and shows the reason.
final rustClientProvider = Provider<RustClient>((ref) {
  final client = RustClient.start();
  ref.onDispose(client.dispose);
  return client;
});

/// The one protocol boundary the rest of the app talks through.
///
/// Today it hands back the embedded (FFI) transport; when the web build
/// arrives this is where a remote (WebSocket) transport will be chosen, and
/// nothing above it changes. See `core/transport/client_transport.dart`.
final clientTransportProvider = Provider<ClientTransport>((ref) {
  return ref.watch(rustClientProvider);
});

/// Every envelope the core publishes.
final eventStreamProvider = StreamProvider<FfiEvent>((ref) {
  return ref.watch(clientTransportProvider).events;
});

/// One accumulated view per session.
final sessionsProvider =
    NotifierProvider<SessionsNotifier, Map<int, ServerView>>(SessionsNotifier.new);

/// Which session the UI is showing.
final activeSessionProvider =
    NotifierProvider<ActiveSessionNotifier, int?>(ActiveSessionNotifier.new);

/// The view the UI should render, or null before anything is connected.
final activeViewProvider = Provider<ServerView?>((ref) {
  final sessions = ref.watch(sessionsProvider);
  final active = ref.watch(activeSessionProvider);
  if (active == null) return null;
  return sessions[active];
});

/// The most recent failure worth telling the user about, if any.
final lastErrorProvider =
    NotifierProvider<LastErrorNotifier, ClientError?>(LastErrorNotifier.new);

/// Accumulates events into per-session views.
class SessionsNotifier extends Notifier<Map<int, ServerView>> {
  /// Sessions whose voice engine has already been opened.
  ///
  /// The engine follows the connection, not a button, and it opens once: a
  /// reconnect republishes `connected`, and reopening a microphone that is
  /// already running would tear down a working stream mid-sentence.
  final Set<int> _voiceStarted = {};

  /// Sessions the user has closed, whose later events are no longer wanted.
  ///
  /// Without this, [forget] does not stick: closing a connection makes the core
  /// publish `disconnected` for that very session, and the rule that a session
  /// can publish before `connect` answers — the view is created on first sight
  /// — would build the view again a moment after the user dismissed it. The
  /// window then sits on a dead server page whose only way out is the server
  /// switcher, which reads as the disconnect button having failed.
  ///
  /// Session ids are handed out by `SessionManager::reserve_id` from a counter
  /// that only ever goes up, so an id is not reused by a later connection; the
  /// clear in [_applyCommandResult] is there so that this stays true by
  /// construction rather than by that argument.
  final Set<int> _closed = {};

  @override
  Map<int, ServerView> build() {
    // `listen` rather than `watch`: this must react to each event without
    // rebuilding, and a rebuild would re-subscribe and drop the accumulated
    // state.
    ref.listen(eventStreamProvider, (_, next) {
      final event = next.value;
      if (event != null) _apply(event);
    });
    return const {};
  }

  void _apply(FfiEvent envelope) {
    switch (envelope) {
      case DomainEvent(:final session, :final event):
        // A session the user closed is over, and the core still has a few
        // words to say about it — the `disconnected` event for the connection
        // it was just told to close, at least. Letting those through would
        // rebuild the view the user dismissed; see `_closed`.
        if (_closed.contains(session)) return;

        // A session can publish before `connect` reports back, so the view is
        // created on first sight rather than waiting for the command result.
        final view = state[session] ?? ServerView(session: session);

        // **Before** the event lands, and deliberately not as a second listener
        // on the same stream: which of two listeners runs first is not
        // something to leave to luck. The rules need the view as it was — a
        // client on their way out is still in it, and that is the only place
        // their name can still be read.
        ref.read(noticesProvider.notifier).consider(session, event, view);

        view.apply(event);
        state = {...state, session: view};

        // The engine opens when the session does.
        //
        // There is no "start voice" in TeamSpeak: joining a channel *is*
        // joining the conversation, and a client that stays silent until a
        // control inside the settings page is found reads as a broken
        // microphone and a broken speaker at once — with nothing on screen
        // saying which. The web front-end opens its engine on connect for the
        // same reason; this is the desktop half of that.
        if (view.isConnected && _voiceStarted.add(session)) {
          ref.read(clientTransportProvider).voiceStart(session);
        }

        // The core's own errors — a failed handshake, a dropped connection, a
        // refused reconnect — used to stop here: `ServerView` keeps no error
        // state, so nothing was drawn and nothing was said. The channel tree
        // simply froze. They are not tied to a command the user issued, so
        // they have to be surfaced from here rather than from a command result.
        if (event is ErrorEvent) {
          ref.read(lastErrorProvider.notifier).report(event.error);
        }

      case CommandResultEvent(:final result):
        _applyCommandResult(result);

      case LaggedEvent(:final missed):
        // The core dropped events, so what is on screen may be stale. Saying so
        // is the honest option; silently rendering a wrong tree is not.
        ref.read(lastErrorProvider.notifier).report(
          ClientError(kind: 'lagged', detail: {'missed': missed}),
        );

      case UnknownFfiEvent():
        break;
    }
  }

  void _applyCommandResult(CommandResult result) {
    if (result.ok) {
      // `connect` is the one command whose *result* is a value: the new
      // session's handle, which everything else is addressed by.
      if (result.command == 'connect' && result.session != null) {
        final session = result.session!;
        // A successful connection is what makes a handle live again, so this
        // is where the closed mark is lifted — not on any event, which is the
        // whole thing `_closed` exists to stop.
        _closed.remove(session);
        state = {...state, session: state[session] ?? ServerView(session: session)};
        ref.read(activeSessionProvider.notifier).select(session);
      }
      return;
    }

    ref.read(lastErrorProvider.notifier).report(
      result.error ?? const ClientError(kind: 'command_failed'),
    );
  }

  /// Flips the microphone for [session].
  ///
  /// The voice bar's button and the mute shortcut both come through here, so
  /// there is one definition of what muting does: tell the core, and reflect it
  /// locally at once so the control does not appear stuck for the round trip.
  void toggleInputMuted(int session) => _toggleMute(session, input: true);

  /// Flips the speakers for [session]. See [toggleInputMuted].
  void toggleOutputMuted(int session) => _toggleMute(session, input: false);

  void _toggleMute(int session, {required bool input}) {
    final view = state[session];
    // Nothing to mute without a live session; a shortcut pressed on the wrong
    // screen should do nothing rather than queue a command the core refuses.
    if (view == null || !view.isConnected) return;

    final voice = view.voice;
    if (input) {
      final muted = !voice.inputMuted;
      ref.read(clientTransportProvider).setInputMuted(muted);
      reportVoiceState(session, voice.copyWith(inputMuted: muted));
    } else {
      final muted = !voice.outputMuted;
      ref.read(clientTransportProvider).setOutputMuted(muted);
      reportVoiceState(session, voice.copyWith(outputMuted: muted));
    }
  }

  /// Marks us away, or back at the keyboard.
  ///
  /// Unlike muting there is nothing to apply optimistically: the core's own
  /// view of our client changes the moment the command is queued, so
  /// `ownClient.flags.away` is already right by the time the event lands. A
  /// second copy here would only be a second thing to disagree with.
  void setAway(int session, {required bool away, String? message}) {
    final view = state[session];
    // No live session, nothing to tell — same rule as the mute buttons.
    if (view == null || !view.isConnected) return;

    ref.read(clientTransportProvider).setAway(session, away: away, message: message);
  }

  /// Flips our away state without saying anything about it.
  ///
  /// The voice bar's button comes through here, and it never carries a message
  /// — not even the one the settings remember. Going away and *announcing* why
  /// are two different acts: the button does the first, the dialog does both.
  /// What is stored is what the dialog starts from, not what this button means.
  void toggleAway(int session) {
    final view = state[session];
    if (view == null || !view.isConnected) return;

    setAway(session, away: !(view.ownClient?.flags.away ?? false));
  }

  /// Goes away saying [message], and remembers it for next time.
  ///
  /// One method for the two halves because they belong together: a message the
  /// user typed and we did not keep would have to be typed again this evening.
  /// The write goes down the same path the settings page uses.
  void goAwayWith(int session, String message) {
    final settings = ref.read(settingsProvider);
    if (settings != null) {
      ref
          .read(settingsProvider.notifier)
          .update(settings.copyWith(presence: settings.presence.copyWith(awayMessage: message)));
    }
    setAway(session, away: true, message: message);
  }

  /// Asks the core to close a session, and stops showing it.
  ///
  /// Optimistic: the view goes as soon as the user asks, rather than when the
  /// core confirms, because sitting on a dead session while a command round
  /// trips is exactly the wait they were trying to end. A failure still arrives
  /// as a command result and is reported like any other.
  ///
  /// The one caller is the reconnect banner's 「断开」: retrying forever is the
  /// right default for a dropped connection, but only if the user can stop it.
  void disconnect(int session) {
    ref.read(clientTransportProvider).disconnect(session);
    forget(session);
  }

  /// Forgets a session, as after a clean disconnect.
  void forget(int session) {
    _closed.add(session);
    final next = {...state}..remove(session);
    state = next;
    ref.read(activeSessionProvider.notifier).forget(session);
  }

  /// Opens a conversation, and tells whoever is drawing it.
  ///
  /// Through the notifier rather than by mutating the view from the tap
  /// handler: a `ServerView` is a plain object, and mutating one is invisible
  /// until something republishes it. `view.open(...)` called straight from
  /// `onTap` left the chat panel showing the previous thread until the *next*
  /// unrelated event arrived — which is what made opening a private
  /// conversation, and going back, feel slow.
  void openConversation(int session, String conversation) {
    final view = state[session];
    if (view == null) return;
    view.open(conversation);
    state = {...state, session: view};
  }

  /// Goes back to following the channel we are in. See [openConversation].
  void closeConversation(int session) {
    final view = state[session];
    if (view == null) return;
    view.closeConversation();
    state = {...state, session: view};
  }

  /// Applies a voice-state change optimistically.
  ///
  /// The core is authoritative and will confirm with a `voice_state_changed`
  /// event; this only exists so a button does not appear stuck for the round
  /// trip. If the core disagrees, its event overwrites this.
  void reportVoiceState(int session, VoiceState voice) {
    final view = state[session];
    if (view == null) return;
    view.voice = voice;
    state = {...state, session: view};
  }
}

/// The audio devices the core last reported, by direction.
final voiceStatusProvider = NotifierProvider<VoiceStatusNotifier, VoiceStatus?>(
  VoiceStatusNotifier.new,
);

final bookmarksProvider = NotifierProvider<BookmarksNotifier, BookmarkList?>(
  BookmarksNotifier.new,
);

final windowFocusProvider = NotifierProvider<WindowFocusNotifier, bool>(
  WindowFocusNotifier.new,
);

final noticesProvider = NotifierProvider<NoticesNotifier, List<Notice>>(
  NoticesNotifier.new,
);

final settingsProvider = NotifierProvider<SettingsNotifier, Settings?>(
  SettingsNotifier.new,
);

/// What the operating system says the user prefers.
///
/// Behind a provider so that "what does the system think" can be answered by a
/// test without a platform.
final systemLocalesProvider = Provider<List<Locale>>(
  (ref) => PlatformDispatcher.instance.locales,
);

/// The language the UI renders in, always resolved to a supported locale.
///
/// Deliberately concrete rather than "null means the system": the same answer
/// is needed outside the widget tree — the notification rules compose
/// sentences without a `BuildContext` — and resolving it in two places is how
/// the toast and the window end up in different languages.
///
/// The setting belongs to the core, so null covers both "not answered yet" and
/// "follow the system"; both resolve the same way, which keeps the first frame
/// in the system's language instead of flashing a default.
final localeProvider = Provider<Locale>((ref) {
  final requested = ref.watch(settingsProvider)?.ui.requestedLanguage;
  final preferred = requested == null
      ? ref.watch(systemLocalesProvider).map(_withChineseScript).toList()
      : <Locale>[_withChineseScript(_parse(requested))];
  return basicLocaleListResolution(preferred, AppLocalizations.supportedLocales);
});

/// Reads a stored language tag, which may name a script: `zh_Hant`.
///
/// Not `Locale(code)`: that constructor takes a *language* code, so `"zh_Hant"`
/// would arrive as a language called `zh_Hant` and match nothing.
Locale _parse(String code) {
  final parts = code.split('_');
  return parts.length < 2
      ? Locale(parts.first)
      : Locale.fromSubtags(languageCode: parts.first, scriptCode: parts[1]);
}

/// Names the script of a Chinese locale that does not name one.
///
/// `basicLocaleListResolution` matches on language code before it considers the
/// script, so a `zh_TW` system locale finds our plain `zh` — Simplified — and
/// stops there. A Traditional reader would then be handed Simplified glyph
/// shapes for a great many characters, which is the one thing the separate
/// font exists to prevent. Spelling the script out here is what gives the
/// resolution something to match.
///
/// The three regions are the ones that write Traditional Chinese; everywhere
/// else that speaks it writes Simplified.
Locale _withChineseScript(Locale locale) {
  if (locale.languageCode != 'zh') return locale;

  final script =
      locale.scriptCode ??
      (const {'TW', 'HK', 'MO'}.contains(locale.countryCode) ? 'Hant' : 'Hans');

  return Locale.fromSubtags(
    languageCode: 'zh',
    scriptCode: script,
    // Kept even though no ARB is region-specific: dropping it would make
    // `zh_TW` and `zh_CN` the same value to anything downstream.
    countryCode: locale.countryCode,
  );
}

/// The two themes to hand `MaterialApp`, resolved from the setting.
///
/// **Two**, because "follow the system" is a pair here rather than a mode: the
/// light half is White and the dark half is Black, and which one is in force is
/// the platform's business. Naming a theme explicitly puts it in *both* slots,
/// which is what makes the system's brightness irrelevant to that choice — one
/// mechanism covering both cases instead of a branch.
///
/// Deliberately concrete, like [localeProvider]: null covers both "the core has
/// not answered yet" and "the file predates the key", and both mean the default
/// theme, so the first frame is drawn in Nightcord rather than flashing
/// something else. An unrecognised value resolves the same way.
///
/// Using `MaterialApp`'s own slots rather than listening for a brightness
/// change is also what makes "follow the system" live: `AnimatedTheme` inside
/// `MaterialApp` already rebuilds on `didChangePlatformBrightness`, so a user
/// who flips their system theme sees the client follow without a restart.
final themeChoiceProvider = Provider<({AppPalette light, AppPalette dark})>((ref) {
  final requested = ref.watch(settingsProvider)?.ui.requestedTheme;

  if (requested == null || requested == 'nightcord') {
    return (light: AppPalette.nightcord, dark: AppPalette.nightcord);
  }
  if (requested != 'system') {
    // `requestedTheme` only lets through the four it knows, so this is one of
    // black or white.
    final palette = AppPalette.byName(requested) ?? AppPalette.nightcord;
    return (light: palette, dark: palette);
  }

  return (light: AppPalette.white, dark: AppPalette.black);
});

final audioDevicesProvider =
    NotifierProvider<AudioDevicesNotifier, Map<String, List<AudioDevice>>>(
  AudioDevicesNotifier.new,
);

/// Collects device lists out of the event stream.
///
/// Enumeration happens on the core's thread, so results arrive as
/// `audio_devices` command results rather than as a return value. This is the
/// only place that correlation happens.
class AudioDevicesNotifier extends Notifier<Map<String, List<AudioDevice>>> {
  @override
  Map<String, List<AudioDevice>> build() {
    ref.listen(eventStreamProvider, (_, next) {
      final event = next.value;
      if (event is CommandResultEvent) _collect(event.result);
    });
    return const {};
  }

  void _collect(CommandResult result) {
    if (result.command != 'audio_devices' || !result.ok) return;

    final data = result.data;
    if (data == null) return;

    final direction = data['direction'] as String?;
    final raw = data['devices'];
    if (direction == null || raw is! List) return;

    final devices = raw
        .map((e) => AudioDevice.fromJson((e as Map).cast<String, dynamic>()))
        .toList(growable: false);

    state = {...state, direction: devices};
  }
}

/// The user's preferences.
///
/// Null until the core has answered once. The UI renders its defaults until
/// then rather than blocking: the settings live on disk and take a round trip to
/// fetch, and a settings page that refuses to draw for a frame is worse than
/// one that fills in.
///
/// The core is the owner. Nothing is cached here that the core has not said —
/// an edit goes to `updateSettings` and comes back as the result, so the two
/// cannot end up disagreeing about what is stored.
class SettingsNotifier extends Notifier<Settings?> {
  @override
  Settings? build() {
    ref.listen(eventStreamProvider, (_, next) {
      final event = next.value;
      if (event is CommandResultEvent) _collect(event.result);
    });
    return null;
  }

  /// Asks the core for the current settings.
  void refresh() => ref.read(clientTransportProvider).requestSettings();

  /// Records an edit, and sends it to the core to be stored and applied.
  ///
  /// Applied locally first so the control the user just moved does not spring
  /// back while the round trip happens. If the write fails the failure is
  /// reported like any other command failure, and the next `settings` result
  /// puts the truth back.
  void update(Settings settings) {
    state = settings;
    ref.read(clientTransportProvider).updateSettings(settings);
  }

  void _collect(CommandResult result) {
    if (result.command != 'settings' || !result.ok) return;

    final data = result.data;
    if (data == null) return;

    state = Settings.fromJson(data);
  }
}

/// What the audio engine is doing, as of the last time it was asked.
///
/// Null until the first answer. Everything that draws a meter asks for a fresh
/// one on its own timer — this only holds what came back, the same way
/// `AudioDevicesNotifier` does.
class VoiceStatusNotifier extends Notifier<VoiceStatus?> {
  @override
  VoiceStatus? build() {
    ref.listen(eventStreamProvider, (_, next) {
      final event = next.value;
      if (event is CommandResultEvent) _collect(event.result);
    });
    return null;
  }

  /// Asks the core what the engine is doing.
  void refresh() => ref.read(clientTransportProvider).requestVoiceStatus();

  /// Plays a test tone through the speakers.
  void testOutput() => ref.read(clientTransportProvider).testOutput();

  void _collect(CommandResult result) {
    if (result.command != 'voice_status' || !result.ok) return;

    final data = result.data;
    if (data == null) return;

    state = VoiceStatus.fromJson(data);
  }
}

/// The saved servers (§40).
///
/// Null until the core has answered once, like [settingsProvider] and for the
/// same reason: the core owns the file, and a list drawn from anything else
/// could disagree with what is stored.
class BookmarksNotifier extends Notifier<BookmarkList?> {
  @override
  BookmarkList? build() {
    ref.listen(eventStreamProvider, (_, next) {
      final event = next.value;
      if (event is CommandResultEvent) _collect(event.result);
    });
    return null;
  }

  /// Asks the core for the address book.
  void refresh() => ref.read(clientTransportProvider).requestBookmarks();

  /// Records an edit, and sends it to the core to be stored.
  ///
  /// Applied locally first so the list does not flicker while the round trip
  /// happens; a failed write is reported like any other command failure, and
  /// the next `bookmarks` result puts the truth back.
  void update(BookmarkList bookmarks) {
    state = bookmarks;
    ref.read(clientTransportProvider).updateBookmarks(bookmarks);
  }

  /// Saves a server from what the connect screen collected.
  ///
  /// Sent rather than applied locally, unlike [update]: the core parses the
  /// address, so it — not this class — decides what the entry becomes. The
  /// answer carries the list as it now stands.
  void add(NewBookmark bookmark) => ref.read(clientTransportProvider).addBookmark(bookmark);

  void _collect(CommandResult result) {
    // `bookmark_add` answers with the same payload as a plain request, so the
    // screen that just saved something gets the list without asking again.
    if (result.command != 'bookmarks' && result.command != 'bookmark_add') return;
    if (!result.ok) return;

    final data = result.data;
    if (data == null) return;

    state = BookmarkList.fromJson(data);
  }
}

/// Whether the window is in front.
///
/// The only thing the app knows about being away, and the only reason a desktop
/// notification is ever sent: while the window is in front, a toast inside it is
/// both visible and less intrusive.
class WindowFocusNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  /// Records what the platform reported.
  void set(bool focused) => state = focused;
}

/// What happened that is worth telling the user about.
///
/// Holds the notices currently on screen. The deciding is in
/// `state/notifications.dart`, which is pure Dart and tested directly; this only
/// wires it to the event stream and routes the answer.
class NoticesNotifier extends Notifier<List<Notice>> {
  /// Built once the settings arrive: the switches are what the rules run on,
  /// and guessing at them before then would either announce everything or
  /// nothing.
  NotificationPolicy? _policy;

  @override
  List<Notice> build() {
    ref.listen(settingsProvider, (_, settings) {
      if (settings != null) {
        _policy = NotificationPolicy(
          settings: settings.notifications,
          // Read at the moment a sentence is needed, so a language switch
          // needs no rebuild of the policy — see `NotificationPolicy.strings`.
          strings: () => lookupAppLocalizations(ref.read(localeProvider)),
        );
      }
    });
    return const [];
  }

  /// Considers one event against the view it is about to be applied to.
  ///
  /// Called from `SessionsNotifier` rather than subscribing separately — see the
  /// note there.
  void consider(int session, ClientEvent event, ServerView view) {
    final policy = _policy;
    if (policy == null) return;

    final attention = _attention(session, view);
    final notice = policy.observe(session, event, view, attention);
    if (notice == null) return;

    // Recorded whatever happens next: an unread marker is for when the user
    // looks back, and that is true whether or not the window is in front.
    final conversation = notice.conversation;
    if (conversation != null) view.markUnread(conversation);

    if (attention.focused) {
      if (notice.toast) _show(notice);
    } else if (_systemEnabled) {
      showSystemNotification(title: notice.title, body: notice.body);
    }
  }

  /// Dismisses a toast the user clicked or that has been up long enough.
  void dismiss(Notice notice) => state = [...state]..remove(notice);

  /// What the user is looking at right now.
  Attention _attention(int session, ServerView view) {
    // The shell falls back to the newest session when nothing is selected, so
    // "which server is on screen" is not `activeSessionProvider` on its own —
    // mirroring that here is what keeps the rule from being wrong for the first
    // few frames after a connect.
    final requested = ref.read(activeSessionProvider);
    final sessions = ref.read(sessionsProvider);
    final active = requested ?? (sessions.isEmpty ? null : sessions.keys.last);

    return Attention(
      session: active,
      conversation: active == session ? view.shownConversation : null,
      focused: ref.read(windowFocusProvider),
    );
  }

  bool get _systemEnabled => ref.read(settingsProvider)?.notifications.system ?? true;

  void _show(Notice notice) {
    // Oldest first: three is what fits without covering the conversation, and a
    // fourth would push one out before it could be read.
    final next = [...state, notice];
    state = next.length > 3 ? next.sublist(next.length - 3) : next;
  }
}

/// Tracks which session the UI is showing.
class ActiveSessionNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  /// Shows `session`.
  void select(int session) => state = session;

  /// Stops showing `session`, if it was the active one.
  void forget(int session) {
    if (state == session) state = null;
  }
}

/// Holds the most recent error, so a snack bar can show it once.
class LastErrorNotifier extends Notifier<ClientError?> {
  @override
  ClientError? build() => null;

  /// Records a failure.
  void report(ClientError error) => state = error;

  /// Clears it, once it has been shown.
  void clear() => state = null;
}

/// Convenience for widgets: the connection state of the active session.
final activeConnectionProvider = Provider<ConnectionState>((ref) {
  return ref.watch(activeViewProvider)?.connection ?? ConnectionState.disconnected;
});

/// Convenience for widgets: the capabilities of the active session.
final activeCapabilitiesProvider = Provider<Capabilities>((ref) {
  return ref.watch(activeViewProvider)?.capabilities ?? const Capabilities();
});

/// Convenience for widgets: the permissions of the active session.
final activePermissionsProvider = Provider<Permissions>((ref) {
  return ref.watch(activeViewProvider)?.permissions ?? const Permissions();
});
