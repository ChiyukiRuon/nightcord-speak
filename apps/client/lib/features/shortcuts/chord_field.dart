// A field that records a key combination.
//
// Its own widget rather than the plugin's `HotKeyRecorder`, for two reasons: it
// reports a `Chord` (so the plugin stays inside `shortcut_host.dart` rather than
// leaking into the settings page), and it can *clear* a binding — a shortcut
// someone wants gone should not require choosing some other key to get rid of
// it.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/shortcuts.dart';

/// Shows a shortcut and lets the user replace it.
///
/// Click, press the keys you want, let go. `Esc` cancels, `Delete` or
/// `Backspace` clears.
class ChordField extends StatefulWidget {
  /// Shows [chord] for [label].
  const ChordField({
    required this.label,
    required this.chord,
    required this.onChanged,
    this.trailing,
    super.key,
  });

  /// What the shortcut does.
  final String label;

  /// The current binding, or null when it is unbound.
  final Chord? chord;

  /// Called when the binding changes. Null means cleared.
  final ValueChanged<Chord?> onChanged;

  /// Something after the recorder — the settings page puts this row's
  /// "restore the default" here.
  ///
  /// A slot rather than a callback: the recorder knows nothing about defaults,
  /// and the page that owns the row is the one that knows what else belongs on
  /// it.
  final Widget? trailing;

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
    final tokens = DesignTokens.of(context);
    final text = Theme.of(context).textTheme;
    final shown = _recording ? _pending : widget.chord;
    final label = _recording
        ? (shown?.format() ?? l10n.chordFieldIdle)
        : (shown?.format() ?? l10n.chordFieldUnset);

    return Padding(
      padding: EdgeInsets.only(bottom: tokens.space2),
      child: Row(
        children: [
          Expanded(child: Text(widget.label, style: text.labelLarge)),
          Focus(
            focusNode: _focus,
            onKeyEvent: (_, event) => _onKey(event),
            child: InkWell(
              onTap: _recording ? _stopRecording : _startRecording,
              borderRadius: AppRadius.smAll,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: tokens.space3,
                  vertical: tokens.space2,
                ),
                constraints: const BoxConstraints(minWidth: 170),
                decoration: BoxDecoration(
                  // §18's input colours: this is a field, even though it takes
                  // keystrokes rather than characters.
                  color: tokens.bgSidebar,
                  borderRadius: AppRadius.smAll,
                  border: Border.all(
                    // §18: the border turns primary on focus, which is exactly
                    // what recording is.
                    color: _recording ? tokens.primary : tokens.borderSubtle,
                  ),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(
                    // A key combination lines up better in a fixed pitch, like
                    // the log paths. `AppTypography` owns the family name
                    // (`docs/UI字体规范.md` §7).
                    fontFamily: AppTypography.monospaceFamily,
                    color: shown == null || _recording
                        ? tokens.textTertiary
                        : tokens.textPrimary,
                  ),
                ),
              ),
            ),
          ),
          // After the recorder, where the page's own row of controls sits.
          if (widget.trailing case final trailing?) ...[
            SizedBox(width: tokens.space2),
            trailing,
          ],
        ],
      ),
    );
  }
}
