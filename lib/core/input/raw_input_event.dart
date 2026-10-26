import 'dart:typed_data';

/// Decoded Windows Raw Input packets (WM_INPUT payloads).
///
/// Raw Input reports which physical device produced each keystroke or mouse
/// movement, which is what lets the keyboard and touchpad tests ignore an
/// external USB keyboard or mouse.

// RAWKEYBOARD.Flags
const riKeyBreak = 0x01; // key released
const riKeyE0 = 0x02; // extended scan code prefix E0
const riKeyE1 = 0x04; // prefix E1 (Pause)

// RAWMOUSE.usButtonFlags
const riMouseLeftDown = 0x0001;
const riMouseLeftUp = 0x0002;
const riMouseRightDown = 0x0004;
const riMouseRightUp = 0x0008;
const riMouseWheel = 0x0400;
const riMouseHWheel = 0x0800;

// RAWMOUSE.usFlags
const mouseMoveAbsolute = 0x0001;

// RAWINPUTHEADER.dwType
const rimTypeMouse = 0;
const rimTypeKeyboard = 1;

sealed class RawInputPacket {
  const RawInputPacket({required this.deviceHandle, required this.inForeground});

  /// Opaque handle of the source device. 0 means synthesized input
  /// (SendInput, remote desktop, or the precision-touchpad gesture layer).
  final int deviceHandle;

  /// The app was in the foreground when this was typed (WM_INPUT's RIM_INPUT);
  /// background "sink" input is discarded so nothing is logged system-wide.
  final bool inForeground;
}

class RawKeyPacket extends RawInputPacket {
  const RawKeyPacket({
    required super.deviceHandle,
    required super.inForeground,
    required this.makeCode,
    required this.flags,
    required this.vKey,
  });

  /// Hardware scan code (set 1).
  final int makeCode;
  final int flags;

  /// Windows virtual-key code.
  final int vKey;

  bool get isBreak => flags & riKeyBreak != 0;
  bool get isExtended => flags & riKeyE0 != 0;
  bool get isE1 => flags & riKeyE1 != 0;
}

class RawMousePacket extends RawInputPacket {
  const RawMousePacket({
    required super.deviceHandle,
    required super.inForeground,
    required this.flags,
    required this.buttonFlags,
    required this.buttonData,
    required this.dx,
    required this.dy,
  });

  final int flags;
  final int buttonFlags;

  /// Signed wheel delta (120 = one notch) when [buttonFlags] has a wheel bit.
  final int buttonData;
  final int dx;
  final int dy;

  bool get isAbsolute => flags & mouseMoveAbsolute != 0;
  bool get leftDown => buttonFlags & riMouseLeftDown != 0;
  bool get leftUp => buttonFlags & riMouseLeftUp != 0;
  bool get rightDown => buttonFlags & riMouseRightDown != 0;
  bool get wheel => buttonFlags & (riMouseWheel | riMouseHWheel) != 0;
  bool get moved => isAbsolute || dx != 0 || dy != 0;
}

/// Decodes the bytes of a RAWINPUT structure.
///
/// Layout (x64): a 24-byte RAWINPUTHEADER { dwType, dwSize, hDevice, wParam }
/// followed by RAWMOUSE or RAWKEYBOARD. [headerSize] is 24 on 64-bit
/// Windows (16 on 32-bit). Returns null for other device types or short data.
RawInputPacket? parseRawInput(Uint8List bytes, {required bool inForeground, int headerSize = 24}) {
  if (bytes.length < headerSize + 4) return null;
  final d = ByteData.sublistView(bytes);
  final type = d.getUint32(0, Endian.little);
  final handle = headerSize == 24 ? d.getUint64(8, Endian.little) : d.getUint32(8, Endian.little);
  final h = headerSize;

  switch (type) {
    case rimTypeKeyboard:
      if (bytes.length < h + 16) return null;
      return RawKeyPacket(
        deviceHandle: handle,
        inForeground: inForeground,
        makeCode: d.getUint16(h, Endian.little),
        flags: d.getUint16(h + 2, Endian.little),
        vKey: d.getUint16(h + 6, Endian.little),
      );
    case rimTypeMouse:
      if (bytes.length < h + 24) return null;
      return RawMousePacket(
        deviceHandle: handle,
        inForeground: inForeground,
        flags: d.getUint16(h, Endian.little),
        buttonFlags: d.getUint16(h + 4, Endian.little),
        buttonData: d.getInt16(h + 6, Endian.little),
        dx: d.getInt32(h + 12, Endian.little),
        dy: d.getInt32(h + 16, Endian.little),
      );
    default:
      return null; // RIM_TYPEHID etc.
  }
}
