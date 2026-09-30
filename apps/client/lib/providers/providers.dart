// The bridge between the Rust core's event stream and the widget tree.
//
// This is the chain from §18: events arrive, a store accumulates them, and
// widgets read the store. Nothing here touches FFI directly except through
// `RustClient`.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/rust_client.dart';
import '../models/domain.dart';
import '../models/events.dart';
import '../models/bookmarks.dart';
import '../models/settings.dart';
import '../state/server_view.dart';

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

/// Every envelope the core publishes.
final eventStreamProvider = StreamProvider<FfiEvent>((ref) {
  return ref.watch(rustClientProvider).events;
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
        // A session can publish before `connect` reports back, so the view is
        // created on first sight rather than waiting for the command result.
        final view = state[session] ?? ServerView(session: session);
        view.apply(event);
        state = {...state, session: view};

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
          ClientError(kind: 'lagged', message: '界面跟不上事件速度，已丢失 $missed 个事件'),
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
        state = {...state, session: state[session] ?? ServerView(session: session)};
        ref.read(activeSessionProvider.notifier).select(session);
      }
      return;
    }

    ref.read(lastErrorProvider.notifier).report(
      result.error ?? const ClientError(kind: 'unknown', message: '命令失败'),
    );
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
    ref.read(rustClientProvider).disconnect(session);
    forget(session);
  }

  /// Forgets a session, as after a clean disconnect.
  void forget(int session) {
    final next = {...state}..remove(session);
    state = next;
    ref.read(activeSessionProvider.notifier).forget(session);
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
final bookmarksProvider = NotifierProvider<BookmarksNotifier, BookmarkList?>(
  BookmarksNotifier.new,
);

final settingsProvider = NotifierProvider<SettingsNotifier, Settings?>(
  SettingsNotifier.new,
);

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
/// fetch, and a settings screen that refuses to draw for a frame is worse than
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
  void refresh() => ref.read(rustClientProvider).requestSettings();

  /// Records an edit, and sends it to the core to be stored and applied.
  ///
  /// Applied locally first so the control the user just moved does not spring
  /// back while the round trip happens. If the write fails the failure is
  /// reported like any other command failure, and the next `settings` result
  /// puts the truth back.
  void update(Settings settings) {
    state = settings;
    ref.read(rustClientProvider).updateSettings(settings);
  }

  void _collect(CommandResult result) {
    if (result.command != 'settings' || !result.ok) return;

    final data = result.data;
    if (data == null) return;

    state = Settings.fromJson(data);
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
  void refresh() => ref.read(rustClientProvider).requestBookmarks();

  /// Records an edit, and sends it to the core to be stored.
  ///
  /// Applied locally first so the list does not flicker while the round trip
  /// happens; a failed write is reported like any other command failure, and
  /// the next `bookmarks` result puts the truth back.
  void update(BookmarkList bookmarks) {
    state = bookmarks;
    ref.read(rustClientProvider).updateBookmarks(bookmarks);
  }

  /// Saves a server from what the connect screen collected.
  ///
  /// Sent rather than applied locally, unlike [update]: the core parses the
  /// address, so it — not this class — decides what the entry becomes. The
  /// answer carries the list as it now stands.
  void add(NewBookmark bookmark) => ref.read(rustClientProvider).addBookmark(bookmark);

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
