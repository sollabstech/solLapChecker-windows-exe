import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sollapchecker/core/input/input_device.dart';
import 'package:sollapchecker/core/input/raw_input_event.dart';

/// Builds a 64-bit RAWINPUT with the given payload at offset 24.
Uint8List raw(int type, int handle, void Function(ByteData d) payload, {int size = 24 + 24}) {
  final b = Uint8List(size);
  final d = ByteData.sublistView(b);
  d.setUint32(0, type, Endian.little);
  d.setUint32(4, size, Endian.little);
  d.setUint64(8, handle, Endian.little);
  payload(d);
  return b;
}

void main() {
  group('parseRawInput', () {
    test('keyboard: scan code, extended flag and break', () {
      final bytes = raw(rimTypeKeyboard, 0x1234, (d) {
        d.setUint16(24, 0x4D, Endian.little); // MakeCode: right arrow
        d.setUint16(26, riKeyE0 | riKeyBreak, Endian.little);
        d.setUint16(30, 0x27, Endian.little); // VK_RIGHT
      });
      final p = parseRawInput(bytes, inForeground: true) as RawKeyPacket;

      expect(p.deviceHandle, 0x1234);
      expect(p.makeCode, 0x4D);
      expect(p.isExtended, isTrue);
      expect(p.isBreak, isTrue);
      expect(p.isE1, isFalse);
      expect(p.vKey, 0x27);
      expect(p.inForeground, isTrue);
    });

    test('mouse: relative move, buttons, wheel and negative values', () {
      final bytes = raw(rimTypeMouse, 0x99, (d) {
        d.setUint16(24, 0, Endian.little); // relative
        d.setUint16(28, riMouseLeftDown | riMouseWheel, Endian.little);
        d.setInt16(30, -120, Endian.little); // one notch down
        d.setInt32(36, -7, Endian.little);
        d.setInt32(40, 12, Endian.little);
      });
      final p = parseRawInput(bytes, inForeground: true) as RawMousePacket;

      expect(p.dx, -7);
      expect(p.dy, 12);
      expect(p.leftDown, isTrue);
      expect(p.rightDown, isFalse);
      expect(p.wheel, isTrue);
      expect(p.buttonData, -120);
      expect(p.moved, isTrue);
      expect(p.isAbsolute, isFalse);
    });

    test('a button-only mouse packet is not movement; absolute always is', () {
      final click = parseRawInput(
        raw(rimTypeMouse, 1, (d) => d.setUint16(28, riMouseRightDown, Endian.little)),
        inForeground: true,
      ) as RawMousePacket;
      expect(click.moved, isFalse);
      expect(click.rightDown, isTrue);

      final abs = parseRawInput(
        raw(rimTypeMouse, 1, (d) => d.setUint16(24, mouseMoveAbsolute, Endian.little)),
        inForeground: true,
      ) as RawMousePacket;
      expect(abs.moved, isTrue);
    });

    test('32-bit layout (16-byte header)', () {
      final b = Uint8List(16 + 16);
      final d = ByteData.sublistView(b);
      d.setUint32(0, rimTypeKeyboard, Endian.little);
      d.setUint32(8, 0xBEEF, Endian.little);
      d.setUint16(16, 0x1E, Endian.little);
      final p = parseRawInput(b, inForeground: false, headerSize: 16) as RawKeyPacket;
      expect(p.deviceHandle, 0xBEEF);
      expect(p.makeCode, 0x1E);
      expect(p.inForeground, isFalse);
    });

    test('short buffers and HID packets are ignored', () {
      expect(parseRawInput(Uint8List(10), inForeground: true), isNull);
      expect(parseRawInput(raw(rimTypeKeyboard, 1, (_) {}, size: 30), inForeground: true), isNull);
      expect(parseRawInput(raw(2, 1, (_) {}), inForeground: true), isNull); // RIM_TYPEHID
    });
  });

  group('classifyDevicePath', () {
    test('PS/2 (i8042) built-in keyboard and touchpad', () {
      expect(classifyDevicePath(r'\\?\ACPI#PNP0303#4&1b9a1d65&0#{884b96c3-56ef-11d1-bc8c-00a0c9014b0f}'), DeviceBus.acpi);
      expect(classifyDevicePath(r'\\?\ACPI#SYN1B7F#4&2&0#{378de44c-56ef-11d1-bc8c-00a0c9014b0f}'), DeviceBus.acpi);
    });

    test('I2C-HID built-in devices (ACPI-style ids, no VID/PID)', () {
      expect(classifyDevicePath(r'\\?\HID#ELAN0001&Col01#5&2f1d3c&0&0000#{378de44c-56ef-11d1-bc8c-00a0c9014b0f}'), DeviceBus.internalHid);
      expect(classifyDevicePath(r'\\?\HID#MSHW0029&Col02#5&abc&0&0001#{378de44c-56ef-11d1-bc8c-00a0c9014b0f}'), DeviceBus.internalHid);
      expect(classifyDevicePath(r'\\?\HID#DLL07E6&Col01#5&1&0&0000#{378de44c-56ef-11d1-bc8c-00a0c9014b0f}'), DeviceBus.internalHid);
    });

    test('USB without device-tree info is "unknown", not assumed internal', () {
      const usb = r'\\?\HID#VID_046D&PID_C31C#7&2c0d3e2a&0&0000#{884b96c3-56ef-11d1-bc8c-00a0c9014b0f}';
      expect(classifyDevicePath(usb), DeviceBus.usbUnknown);
    });

    test('USB with device-tree info: removable is external, hard-wired is internal', () {
      const usb = r'\\?\HID#VID_046D&PID_C31C#7&2c0d3e2a&0&0000#{884b96c3-56ef-11d1-bc8c-00a0c9014b0f}';
      const ext = NativeBusInfo(enumerators: ['HID', 'USB', 'USB', 'USB'], removable: true);
      const wired = NativeBusInfo(enumerators: ['HID', 'USB', 'USB', 'USB'], removable: false);
      expect(classifyDevicePath(usb, native: ext), DeviceBus.usbExternal);
      expect(classifyDevicePath(usb, native: wired), DeviceBus.usbInternal);
    });

    test('Bluetooth and virtual devices are never internal', () {
      expect(
        classifyDevicePath(r'\\?\HID#{00001124-0000-1000-8000-00805f9b34fb}_VID&0002045e_PID&0916#9&1&0&0000#{884b96c3-56ef-11d1-bc8c-00a0c9014b0f}'),
        DeviceBus.bluetooth,
      );
      expect(
        classifyDevicePath(r'\\?\HID#VID_045E&PID_0916#a#{x}', native: const NativeBusInfo(enumerators: ['HID', 'BTHENUM'], removable: false)),
        DeviceBus.bluetooth,
      );
      expect(classifyDevicePath(r'\\?\ROOT#RDP_KBD#0000#{884b96c3-56ef-11d1-bc8c-00a0c9014b0f}'), DeviceBus.virtual);
    });

    test('isInternal', () {
      InputDevice d(DeviceBus b) => InputDevice(handle: 1, kind: InputDeviceKind.keyboard, path: 'x', bus: b);
      expect(d(DeviceBus.acpi).isInternal, isTrue);
      expect(d(DeviceBus.internalHid).isInternal, isTrue);
      expect(d(DeviceBus.usbInternal).isInternal, isTrue);
      expect(d(DeviceBus.usbExternal).isInternal, isFalse);
      expect(d(DeviceBus.usbUnknown).isInternal, isFalse);
      expect(d(DeviceBus.bluetooth).isInternal, isFalse);
      expect(d(DeviceBus.unknown).isInternal, isFalse);
    });
  });

  test('device instance id for cfgmgr32', () {
    expect(
      deviceInstanceIdFromPath(r'\\?\HID#VID_046D&PID_C31C#7&2c0d3e2a&0&0000#{884b96c3-56ef-11d1-bc8c-00a0c9014b0f}'),
      r'HID\VID_046D&PID_C31C\7&2c0d3e2a&0&0000',
    );
    expect(
      deviceInstanceIdFromPath(r'\\?\ACPI#PNP0303#4&1b9a1d65&0#{884b96c3-56ef-11d1-bc8c-00a0c9014b0f}'),
      r'ACPI\PNP0303\4&1b9a1d65&0',
    );
    expect(deviceInstanceIdFromPath('garbage'), isNull);
  });

  test('device descriptions', () {
    expect(describeDevicePath(r'\\?\HID#VID_046D&PID_C31C#7&2c#{x}'), 'USB 046D:C31C');
    expect(describeDevicePath(r'\\?\ACPI#PNP0303#4&1b#{x}'), 'ACPI PNP0303');
    expect(describeDevicePath(''), 'Synthesized input');
  });
}
