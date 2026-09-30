// The bridge between the Rust core's event stream and the widget tree.
//
// This is the chain from §18: events arrive, a store accumulates them, and
// widgets read the store. Nothing here touches FFI directly except through
// `RustClient`.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/rust_client.dart';
import '../models/domain.dart';
import '../models/events.dart';
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
