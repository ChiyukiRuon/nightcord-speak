// What to call a physical key on screen.
//
// A table rather than a rule, and a file of its own because the reason it has
// to exist at all is worth one place to say — see [physicalKeyName].

/// The name a person reads for a key, e.g. `M`, `Page Up` or `Audio Volume
/// Mute`.
///
/// **Deliberately not `PhysicalKeyboardKey.debugName`**, which is what this
/// used to be. Flutter fills that one in inside an `assert`:
///
/// > The debug string to print for this keyboard key, which will be null in
/// > release mode.
///
/// so in a release build it is null — and since `Chord.format` falls back to
/// the raw code, a shipped build read `Ctrl+Shift+0x70010` where the debug
/// build and every test read `Ctrl+Shift+M`. Every test in this repository
/// runs in debug, so the suite could not see it; the first release build did.
///
/// Owning the names pins them for both builds, and the spellings are Flutter's
/// own (`Arrow Left`, `Audio Volume Mute`), so a name copied out of a log or a
/// test still means what it says on the page.
///
/// A code that is not in the table prints as hex. That is honest rather than
/// pretty — it is exactly what the settings file holds for that key — and a
/// guessed name would be worse than a code nobody recognises.
///
/// The argument is the raw usage rather than a `PhysicalKeyboardKey` so that
/// `debugName` is not within reach here: putting it back takes a change to the
/// signature, which is a thing somebody has to mean.
String physicalKeyName(int usbHidUsage) =>
    _names[usbHidUsage] ?? '0x${usbHidUsage.toRadixString(16)}';

/// Names by USB HID usage, from the HID usage tables.
///
/// The `0x0007` above every usage is the keyboard page; the consumer-page
/// entries near the bottom say `0x000c` instead.
const Map<int, String> _names = {
  // Letters, in HID order.
  0x00070004: 'A',
  0x00070005: 'B',
  0x00070006: 'C',
  0x00070007: 'D',
  0x00070008: 'E',
  0x00070009: 'F',
  0x0007000a: 'G',
  0x0007000b: 'H',
  0x0007000c: 'I',
  0x0007000d: 'J',
  0x0007000e: 'K',
  0x0007000f: 'L',
  0x00070010: 'M',
  0x00070011: 'N',
  0x00070012: 'O',
  0x00070013: 'P',
  0x00070014: 'Q',
  0x00070015: 'R',
  0x00070016: 'S',
  0x00070017: 'T',
  0x00070018: 'U',
  0x00070019: 'V',
  0x0007001a: 'W',
  0x0007001b: 'X',
  0x0007001c: 'Y',
  0x0007001d: 'Z',

  // The digits, in the order the HID table lists them: `0` is the tenth.
  0x0007001e: '1',
  0x0007001f: '2',
  0x00070020: '3',
  0x00070021: '4',
  0x00070022: '5',
  0x00070023: '6',
  0x00070024: '7',
  0x00070025: '8',
  0x00070026: '9',
  0x00070027: '0',

  // Function keys.
  0x0007003a: 'F1',
  0x0007003b: 'F2',
  0x0007003c: 'F3',
  0x0007003d: 'F4',
  0x0007003e: 'F5',
  0x0007003f: 'F6',
  0x00070040: 'F7',
  0x00070041: 'F8',
  0x00070042: 'F9',
  0x00070043: 'F10',
  0x00070044: 'F11',
  0x00070045: 'F12',
  0x00070068: 'F13',
  0x00070069: 'F14',
  0x0007006a: 'F15',
  0x0007006b: 'F16',
  0x0007006c: 'F17',
  0x0007006d: 'F18',
  0x0007006e: 'F19',
  0x0007006f: 'F20',
  0x00070070: 'F21',
  0x00070071: 'F22',
  0x00070072: 'F23',
  0x00070073: 'F24',

  // Editing and punctuation. The names are the keys' positions — which is what
  // a physical key is — so they hold on any layout.
  0x00070028: 'Enter',
  0x00070029: 'Escape',
  0x0007002a: 'Backspace',
  0x0007002b: 'Tab',
  0x0007002c: 'Space',
  0x0007002d: 'Minus',
  0x0007002e: 'Equal',
  0x0007002f: 'Bracket Left',
  0x00070030: 'Bracket Right',
  0x00070031: 'Backslash',
  0x00070033: 'Semicolon',
  0x00070034: 'Quote',
  0x00070035: 'Backquote',
  0x00070036: 'Comma',
  0x00070037: 'Period',
  0x00070038: 'Slash',
  0x00070039: 'Caps Lock',
  0x00070064: 'Intl Backslash',
  0x00070065: 'Context Menu',

  // The navigation cluster.
  0x00070046: 'Print Screen',
  0x00070047: 'Scroll Lock',
  0x00070048: 'Pause',
  0x00070049: 'Insert',
  0x0007004a: 'Home',
  0x0007004b: 'Page Up',
  0x0007004c: 'Delete',
  0x0007004d: 'End',
  0x0007004e: 'Page Down',
  0x0007004f: 'Arrow Right',
  0x00070050: 'Arrow Left',
  0x00070051: 'Arrow Down',
  0x00070052: 'Arrow Up',

  // The numpad.
  0x00070053: 'Num Lock',
  0x00070054: 'Numpad Divide',
  0x00070055: 'Numpad Multiply',
  0x00070056: 'Numpad Subtract',
  0x00070057: 'Numpad Add',
  0x00070058: 'Numpad Enter',
  0x00070059: 'Numpad 1',
  0x0007005a: 'Numpad 2',
  0x0007005b: 'Numpad 3',
  0x0007005c: 'Numpad 4',
  0x0007005d: 'Numpad 5',
  0x0007005e: 'Numpad 6',
  0x0007005f: 'Numpad 7',
  0x00070060: 'Numpad 8',
  0x00070061: 'Numpad 9',
  0x00070062: 'Numpad 0',
  0x00070063: 'Numpad Decimal',
  0x00070067: 'Numpad Equal',
  0x00070085: 'Numpad Comma',

  // What a laptop keyboard has where a full one has the cluster above: the
  // volume keys and the transport keys. A mute at hand is a shortcut people
  // reach for.
  0x0007007f: 'Audio Volume Mute',
  0x00070080: 'Audio Volume Up',
  0x00070081: 'Audio Volume Down',
  0x000c00b0: 'Media Play',
  0x000c00b1: 'Media Pause',
  0x000c00b5: 'Media Track Next',
  0x000c00b6: 'Media Track Previous',
  0x000c00b7: 'Media Stop',
  0x000c00cd: 'Media Play Pause',

  // The eight modifiers. The recorder never takes one as *the* key of a
  // combination, so these are reachable only from a hand-edited file — named
  // rather than left as hex so such a row still reads as something.
  0x000700e0: 'Control Left',
  0x000700e1: 'Shift Left',
  0x000700e2: 'Alt Left',
  0x000700e3: 'Meta Left',
  0x000700e4: 'Control Right',
  0x000700e5: 'Shift Right',
  0x000700e6: 'Alt Right',
  0x000700e7: 'Meta Right',
};
