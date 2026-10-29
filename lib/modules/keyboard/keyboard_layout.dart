/// The on-screen laptop keyboard (84 keys) and the scan codes that identify
/// each key in Raw Input. Scan codes are PS/2 "set 1" make codes; keys in the
/// grey/extended block carry an E0 prefix.
class KeyDef {
  const KeyDef(this.id, this.label, {this.width = 1, this.scan, this.extended = false, this.manualOnly = false});

  final String id;
  final String label;

  /// Relative width in key units (a normal key is 1).
  final double width;

  /// Raw Input MakeCode; null for keys that send no scan code to Windows.
  final int? scan;
  final bool extended;

  /// Fn is handled inside the keyboard controller and sends nothing on its own.
  /// It is detected through what Fn + a function key sends (volume, mute,
  /// airplane mode...), or confirmed by hand.
  final bool manualOnly;
}

class KeyboardLayout {
  KeyboardLayout._();

  static const fnId = 'fn';

  static const _letters = {
    'Q': 0x10, 'W': 0x11, 'E': 0x12, 'R': 0x13, 'T': 0x14, 'Y': 0x15, 'U': 0x16, 'I': 0x17, 'O': 0x18, 'P': 0x19,
    'A': 0x1E, 'S': 0x1F, 'D': 0x20, 'F': 0x21, 'G': 0x22, 'H': 0x23, 'J': 0x24, 'K': 0x25, 'L': 0x26,
    'Z': 0x2C, 'X': 0x2D, 'C': 0x2E, 'V': 0x2F, 'B': 0x30, 'N': 0x31, 'M': 0x32,
  };

  static List<KeyDef> _row(String chars) =>
      [for (final c in chars.split('')) KeyDef('key_$c', c, scan: _letters[c]!)];

  static const _digits = [
    KeyDef('key_1', '1', scan: 0x02), KeyDef('key_2', '2', scan: 0x03), KeyDef('key_3', '3', scan: 0x04),
    KeyDef('key_4', '4', scan: 0x05), KeyDef('key_5', '5', scan: 0x06), KeyDef('key_6', '6', scan: 0x07),
    KeyDef('key_7', '7', scan: 0x08), KeyDef('key_8', '8', scan: 0x09), KeyDef('key_9', '9', scan: 0x0A),
    KeyDef('key_0', '0', scan: 0x0B),
  ];

  static final List<List<KeyDef>> rows = [
    // Function row
    const [
      KeyDef('esc', 'Esc', scan: 0x01),
      KeyDef('f1', 'F1', scan: 0x3B), KeyDef('f2', 'F2', scan: 0x3C), KeyDef('f3', 'F3', scan: 0x3D),
      KeyDef('f4', 'F4', scan: 0x3E), KeyDef('f5', 'F5', scan: 0x3F), KeyDef('f6', 'F6', scan: 0x40),
      KeyDef('f7', 'F7', scan: 0x41), KeyDef('f8', 'F8', scan: 0x42), KeyDef('f9', 'F9', scan: 0x43),
      KeyDef('f10', 'F10', scan: 0x44), KeyDef('f11', 'F11', scan: 0x57), KeyDef('f12', 'F12', scan: 0x58),
      KeyDef('prtsc', 'PrtSc', scan: 0x37, extended: true),
      KeyDef('ins', 'Ins', scan: 0x52, extended: true),
      KeyDef('del', 'Del', scan: 0x53, extended: true),
    ],
    // Number row
    [
      const KeyDef('grave', '`', scan: 0x29),
      ..._digits,
      const KeyDef('minus', '-', scan: 0x0C),
      const KeyDef('equals', '=', scan: 0x0D),
      const KeyDef('backspace', 'Backspace', width: 2, scan: 0x0E),
    ],
    // QWERTY row
    [
      const KeyDef('tab', 'Tab', width: 1.5, scan: 0x0F),
      ..._row('QWERTYUIOP'),
      const KeyDef('lbracket', '[', scan: 0x1A),
      const KeyDef('rbracket', ']', scan: 0x1B),
      const KeyDef('backslash', '\\', width: 1.5, scan: 0x2B),
    ],
    // Home row
    [
      const KeyDef('caps', 'Caps', width: 1.8, scan: 0x3A),
      ..._row('ASDFGHJKL'),
      const KeyDef('semicolon', ';', scan: 0x27),
      const KeyDef('quote', "'", scan: 0x28),
      const KeyDef('enter', 'Enter', width: 2.2, scan: 0x1C),
    ],
    // Bottom letter row
    [
      const KeyDef('lshift', 'Shift', width: 2.4, scan: 0x2A),
      ..._row('ZXCVBNM'),
      const KeyDef('comma', ',', scan: 0x33),
      const KeyDef('period', '.', scan: 0x34),
      const KeyDef('slash', '/', scan: 0x35),
      const KeyDef('rshift', 'Shift', width: 2.6, scan: 0x36),
    ],
    // Space row
    const [
      KeyDef('lctrl', 'Ctrl', width: 1.3, scan: 0x1D),
      KeyDef(fnId, 'Fn', manualOnly: true),
      KeyDef('lwin', 'Win', scan: 0x5B, extended: true),
      KeyDef('lalt', 'Alt', width: 1.2, scan: 0x38),
      KeyDef('space', 'Space', width: 5.4, scan: 0x39),
      KeyDef('ralt', 'Alt', width: 1.2, scan: 0x38, extended: true),
      KeyDef('rctrl', 'Ctrl', width: 1.3, scan: 0x1D, extended: true),
      KeyDef('left', '←', scan: 0x4B, extended: true),
      KeyDef('up', '↑', scan: 0x48, extended: true),
      KeyDef('down', '↓', scan: 0x50, extended: true),
      KeyDef('right', '→', scan: 0x4D, extended: true),
    ],
    // Navigation keys (Fn combinations on many laptops, but they still send scan codes)
    const [
      KeyDef('home', 'Home', width: 1.4, scan: 0x47, extended: true),
      KeyDef('end', 'End', width: 1.4, scan: 0x4F, extended: true),
      KeyDef('pgup', 'PgUp', width: 1.4, scan: 0x49, extended: true),
      KeyDef('pgdn', 'PgDn', width: 1.4, scan: 0x51, extended: true),
    ],
  ];

  static final List<KeyDef> all = [for (final r in rows) ...r];

  static final Map<int, KeyDef> _byScan = {
    for (final k in all)
      if (k.scan != null) _scanKey(k.scan!, k.extended): k,
  };

  static int _scanKey(int scan, bool extended) => (extended ? 0x100 : 0) | scan;

  /// The key for a Raw Input make code, or null if it is not on this layout.
  static KeyDef? find(int makeCode, {required bool extended}) => _byScan[_scanKey(makeCode, extended)];

  static int get total => all.length;

  /// Media and system keys, by virtual-key code. A laptop keyboard reaches
  /// these through Fn + a function key, so one of them proves Fn works.
  static const _fnVKeys = {
    0x5F: 'Sleep',
    0xA6: 'Browser back', 0xA7: 'Browser forward', 0xA8: 'Refresh', 0xA9: 'Browser stop',
    0xAA: 'Search', 0xAB: 'Favorites', 0xAC: 'Browser home',
    0xAD: 'Mute', 0xAE: 'Volume down', 0xAF: 'Volume up',
    0xB0: 'Next track', 0xB1: 'Previous track', 0xB2: 'Stop media', 0xB3: 'Play / pause',
    0xB4: 'Mail', 0xB5: 'Media player', 0xB6: 'App 1 (e.g. My Computer)', 0xB7: 'App 2 (e.g. Calculator)',
  };

  /// The same keys by E0-prefixed scan code, for keyboards that report no virtual key.
  static const _fnE0Scans = {
    0x10: 'Previous track', 0x19: 'Next track', 0x20: 'Mute', 0x21: 'Calculator', 0x22: 'Play / pause',
    0x24: 'Stop media', 0x2E: 'Volume down', 0x30: 'Volume up', 0x32: 'Browser home', 0x5E: 'Power',
    0x5F: 'Sleep', 0x63: 'Wake', 0x65: 'Search', 0x66: 'Favorites', 0x67: 'Refresh', 0x68: 'Browser stop',
    0x69: 'Browser forward', 0x6A: 'Browser back', 0x6B: 'My Computer', 0x6C: 'Mail', 0x6D: 'Media player',
  };

  /// Name of the Fn-layer key a keystroke came from, or null for an ordinary key.
  static String? fnSignalName(int makeCode, {required bool extended, required int vKey}) =>
      _fnVKeys[vKey] ?? (extended ? _fnE0Scans[makeCode] : null);
}
