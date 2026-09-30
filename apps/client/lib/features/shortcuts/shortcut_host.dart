// The shortcut system (§42).
//
// Standalone, as the design doc asks: one place registers the bindings, one
// place turns a press into an action. Nothing else in the app reads the
// keyboard, and the only file that knows the plugin exists is this one — the
// rest of the app talks about `Chord` and `ShortcutAction`.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../../ffi/rust_client.dart';
import '../../models/shortcuts.dart';
import '../../providers/providers.dart';

/// Registers the user's shortcuts and carries them out.
///
/// Wraps the whole shell rather than the server page: a mute shortcut should
/// work on the connect screen too, and a *global* hotkey does not care what is
/// on screen at all.
class ShortcutHost extends ConsumerStatefulWidget {
  /// Wraps [child].
  const ShortcutHost({required this.child, super.key});

  /// What to wrap.
  final Widget child;

  @override
  ConsumerState<ShortcutHost> createState() => _ShortcutHostState();
}

class _ShortcutHostState extends ConsumerState<ShortcutHost> {
  /// What is currently registered, so a settings change that moved nothing
  /// does not tear the registrations down and build them again.
  ShortcutSettings? _registered;

  @override
  void initState() {
    super.initState();
    ref.listenManual(settingsProvider, (_, settings) {
      if (settings != null) unawaited(_apply(settings.shortcuts));
    });
    final settings = ref.read(settingsProvider);
    if (settings != null) unawaited(_apply(settings.shortcuts));
  }

  @override
  void dispose() {
    // Best effort: the process may be going away, and a failed unregister has
    // nothing left to report to.
    unawaited(hotKeyManager.unregisterAll());
    super.dispose();
  }

  /// Replaces every registration with the ones [shortcuts] describes.
  Future<void> _apply(ShortcutSettings shortcuts) async {
    if (shortcuts == _registered) return;
    _registered = shortcuts;

    await hotKeyManager.unregisterAll();

    for (final action in ShortcutAction.values) {
      final chord = shortcuts[action];
      if (chord != null) await _register(action, chord);
    }
  }

  Future<void> _register(ShortcutAction action, Chord chord) async {
    final hotKey = HotKey(
      key: chord.key,
      modifiers: [
        if (chord.ctrl) HotKeyModifier.control,
        if (chord.shift) HotKeyModifier.shift,
        if (chord.alt) HotKeyModifier.alt,
        if (chord.meta) HotKeyModifier.meta,
      ],
      // System-wide, because the whole point of push-to-talk is pressing it
      // while some other window — a game, usually — has the keyboard. Mute and
      // deafen follow it, which is what every other voice client does.
      scope: HotKeyScope.system,
    );

    try {
      await hotKeyManager.register(
        hotKey,
        keyDownHandler: (_) => _fire(action, held: true),
        // Registered per *combination*, so this arrives whether or not the
        // modifiers are still held. The window-scoped handler this replaced read
        // live modifier state, which meant releasing Ctrl before P made the
        // release look like a different chord — and transmission never stopped.
        keyUpHandler: action == ShortcutAction.pushToTalk
            ? (_) => _fire(action, held: false)
            : null,
      );
    } catch (error) {
      // Another program already owns the combination. Said out loud rather than
      // silently doing nothing: a shortcut that does not work is otherwise
      // indistinguishable from one that is not bound, and the user has no way
      // to tell which.
      logToCore('warn', 'could not register the ${action.name} shortcut: $error');
    }
  }

  /// Carries out one action.
  ///
  /// `held` is the key going down or coming up. Mute and deafen are toggles, so
  /// they act once, on the way down.
  void _fire(ShortcutAction action, {required bool held}) {
    if (action == ShortcutAction.pushToTalk) {
      // Momentary, and to the engine rather than to a session: there is one
      // engine, and it does not care which server is on screen.
      ref.read(rustClientProvider).setPushToTalk(held);
      return;
    }

    if (!held) return;
    final session = _activeSession();
    if (session == null) return;

    final sessions = ref.read(sessionsProvider.notifier);
    if (action == ShortcutAction.mute) {
      sessions.toggleInputMuted(session);
    } else {
      sessions.toggleOutputMuted(session);
    }
  }

  /// The session the shell is showing, or the newest one.
  ///
  /// The same fallback `AppShell` makes: `activeSessionProvider` is null until a
  /// connect result arrives, so on its own it would make the first shortcut
  /// after connecting do nothing.
  int? _activeSession() {
    final requested = ref.read(activeSessionProvider);
    if (requested != null) return requested;
    final sessions = ref.read(sessionsProvider);
    return sessions.isEmpty ? null : sessions.keys.last;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
