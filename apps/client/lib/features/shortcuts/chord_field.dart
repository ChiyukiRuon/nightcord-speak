// A field that records a key combination.
//
// Its own widget rather than the plugin's `HotKeyRecorder`, for two reasons: it
// reports a `Chord` (so the plugin stays inside `shortcut_host.dart` rather than
// leaking into the settings dialog), and it can *clear* a binding — a shortcut
// someone wants gone should not require choosing some other key to get rid of
// it.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/shortcuts.dart';
import '../../theme/app_theme.dart';

/// Shows a shortcut and lets the user replace it.
///
/// Click, press the keys you want, let go. `Esc` cancels, `Delete` or
/// `Backspace` clears.
class ChordField extends StatefulWidget {
  /// Shows [chord] for [label].
  const ChordField({required this.label, required this.chord, required this.onChanged, super.key});

  /// What the shortcut does.
  final String label;

  /// The current binding, or null when it is unbound.
  final Chord? chord;

  /// Called when the binding changes. Null means cleared.
  final ValueChanged<Chord?> onChanged;

  @override
  State<ChordField> createState() => _ChordFieldState();
}

class _ChordFieldState extends State<ChordField> {
  final _focus = FocusNode(debugLabel: 'shortcut-recorder');

  /// Whether the field is waiting for keys.
  bool _recording = false;

  /// The combination being pressed, shown live while the keys are held.
  Chord? _pending;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _startRecording() {
    setState(() {
      _recording = true;
      _pending = null;
    });
    _focus.requestFocus();
  }

  void _stopRecording() {
    setState(() {
      _recording = false;
      _pending = null;
    });
  }

  /// Handles a key while recording.
  ///
  /// Commits on the way *up*, not down: pressing Ctrl+Shift+M fires a key-down
  /// for each of the three, and committing on the first would record Ctrl
  /// alone. Waiting for the release means the combination is complete — the
  /// same discipline as the slider that only writes on `onChangeEnd`.
  KeyEventResult _onKey(KeyEvent event) {
    if (!_recording) return KeyEventResult.ignored;

    final key = event.physicalKey;

    if (event is KeyUpEvent) {
      if (key == PhysicalKeyboardKey.escape) {
        _stopRecording();
        return KeyEventResult.handled;
      }
      if (key == PhysicalKeyboardKey.delete || key == PhysicalKeyboardKey.backspace) {
        widget.onChanged(null);
        _stopRecording();
        return KeyEventResult.handled;
      }

      // The modifier that was released is not the combination; a shortcut of
      // modifiers alone would be a shortcut nobody can press.
      if (_isModifier(key)) return KeyEventResult.handled;

      final keyboard = HardwareKeyboard.instance;
      widget.onChanged(
        Chord(
          key: key,
          ctrl: keyboard.isControlPressed,
          shift: keyboard.isShiftPressed,
          alt: keyboard.isAltPressed,
          meta: keyboard.isMetaPressed,
        ),
      );
      _stopRecording();
      return KeyEventResult.handled;
    }

    // Still held: show what it would be, so the field is not blank while the
    // user is pressing four keys.
    if (event is KeyDownEvent && !_isModifier(key)) {
      final keyboard = HardwareKeyboard.instance;
      setState(() {
        _pending = Chord(
          key: key,
          ctrl: keyboard.isControlPressed,
          shift: keyboard.isShiftPressed,
          alt: keyboard.isAltPressed,
          meta: keyboard.isMetaPressed,
        );
      });
    }
    return KeyEventResult.handled;
  }

  /// Whether [key] is a modifier held down rather than the key being chosen.
  ///
  /// `PhysicalKeyboardKey` compares by identity, so this is a set of the eight
  /// modifier keys rather than a const set — the language does not allow const
  /// sets of values with their own equality.
  static bool _isModifier(PhysicalKeyboardKey key) => {
    PhysicalKeyboardKey.controlLeft,
    PhysicalKeyboardKey.controlRight,
    PhysicalKeyboardKey.shiftLeft,
    PhysicalKeyboardKey.shiftRight,
    PhysicalKeyboardKey.altLeft,
    PhysicalKeyboardKey.altRight,
    PhysicalKeyboardKey.metaLeft,
    PhysicalKeyboardKey.metaRight,
  }.contains(key);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final shown = _recording ? _pending : widget.chord;
    final text = _recording
        ? (shown?.format() ?? l10n.chordFieldIdle)
        : (shown?.format() ?? l10n.chordFieldUnset);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(widget.label, style: const TextStyle(fontSize: 13)),
          ),
          Focus(
            focusNode: _focus,
            onKeyEvent: (_, event) => _onKey(event),
            child: InkWell(
              onTap: _recording ? _stopRecording : _startRecording,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                constraints: const BoxConstraints(minWidth: 170),
                decoration: BoxDecoration(
                  color: AppColors.composer,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _recording ? AppColors.accent : Colors.transparent,
                  ),
                ),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: shown == null || _recording
                        ? AppColors.textMuted
                        : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
