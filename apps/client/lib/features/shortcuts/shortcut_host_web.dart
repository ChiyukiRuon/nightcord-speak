import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/shortcuts.dart';
import '../../providers/providers.dart';

/// Page-scoped shortcuts release PTT on key-up and when the page loses focus.
class ShortcutHost extends ConsumerStatefulWidget {
  const ShortcutHost({required this.child, super.key});
  final Widget child;
  @override
  ConsumerState<ShortcutHost> createState() => _ShortcutHostState();
}

class _ShortcutHostState extends ConsumerState<ShortcutHost> with WidgetsBindingObserver {
  PhysicalKeyboardKey? _held;
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handle);
    WidgetsBinding.instance.addObserver(this);
  }

  void _release() {
    if (_held == null) return;
    _held = null;
    ref.read(clientTransportProvider).setPushToTalk(false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _release();
  }

  bool _handle(KeyEvent event) {
    if (event is KeyUpEvent && event.physicalKey == _held) {
      _release();
      return true;
    }
    if (event is! KeyDownEvent) return false;
    // A chord recorder must receive the key without firing the recorded action.
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    final shortcuts = ref.read(settingsProvider)?.shortcuts;
    if (shortcuts == null) return false;
    final keyboard = HardwareKeyboard.instance;
    for (final action in ShortcutAction.values) {
      final chord = shortcuts[action];
      if (chord == null ||
          !chord.matches(
            event.physicalKey,
            ctrl: keyboard.isControlPressed,
            shift: keyboard.isShiftPressed,
            alt: keyboard.isAltPressed,
            meta: keyboard.isMetaPressed,
          )) {
        continue;
      }
      final session = ref.read(activeSessionProvider);
      if (session == null) return false;
      if (action == ShortcutAction.pushToTalk) {
        _held = event.physicalKey;
        ref.read(clientTransportProvider).setPushToTalk(true);
      } else if (action == ShortcutAction.mute) {
        ref.read(sessionsProvider.notifier).toggleInputMuted(session);
      } else {
        ref.read(sessionsProvider.notifier).toggleOutputMuted(session);
      }
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    _release();
    HardwareKeyboard.instance.removeHandler(_handle);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
