import 'dart:typed_data';

import 'package:sollapchecker/core/input/input_device.dart';
import 'package:sollapchecker/core/input/raw_input_event.dart';
import 'package:sollapchecker/core/input/raw_input_service.dart';

/// Raw Input stand-in: tests push events and can make start-up fail.
class FakeRawInput extends RawInputServiceBase {
  FakeRawInput({this.failStart});

  final String? failStart;
  bool started = false;
  int startCount = 0;

  @override
  Future<void> startNative() async {
    if (failStart != null) throw StateError(failStart!);
    started = true;
    startCount++;
  }

  @override
  void stopNative() => started = false;

  void send(InputEvent e) => emit(e);
}

const internalKeyboard = InputDevice(
  handle: 100,
  kind: InputDeviceKind.keyboard,
  path: r'\\?\ACPI#PNP0303#4&1b9a1d65&0#{884b96c3-56ef-11d1-bc8c-00a0c9014b0f}',
  bus: DeviceBus.acpi,
);

const usbKeyboard = InputDevice(
  handle: 200,
  kind: InputDeviceKind.keyboard,
  path: r'\\?\HID#VID_046D&PID_C31C#7&2c0d3e2a&0&0000#{884b96c3-56ef-11d1-bc8c-00a0c9014b0f}',
  bus: DeviceBus.usbExternal,
);

const touchpad = InputDevice(
  handle: 300,
  kind: InputDeviceKind.mouse,
  path: r'\\?\HID#ELAN0001&Col01#5&2f1d3c&0&0000#{378de44c-56ef-11d1-bc8c-00a0c9014b0f}',
  bus: DeviceBus.internalHid,
);

const usbMouse = InputDevice(
  handle: 400,
  kind: InputDeviceKind.mouse,
  path: r'\\?\HID#VID_046D&PID_C077#7&1&0&0000#{378de44c-56ef-11d1-bc8c-00a0c9014b0f}',
  bus: DeviceBus.usbExternal,
);

const synthetic = InputDevice(handle: 0, kind: InputDeviceKind.mouse, path: '', bus: DeviceBus.virtual);

/// Contact reports of the built-in precision touchpad (I2C-HID).
const precisionTouchpad = InputDevice(
  handle: 500,
  kind: InputDeviceKind.hid,
  path: r'\\?\HID#CUST0001&Col02#5&4d18aa1&0&0001#{4d1e55b2-f16f-11cf-88cb-001111000030}',
  bus: DeviceBus.internalHid,
  usagePage: hidPageDigitizer,
  usage: hidUsageTouchpad,
);

/// The built-in keyboard's media-key collection (hard-wired USB controller).
const mediaKeys = InputDevice(
  handle: 600,
  kind: InputDeviceKind.hid,
  path: r'\\?\HID#VID_1038&PID_1122&MI_01#7&2182bd82&0&0000#{4d1e55b2-f16f-11cf-88cb-001111000030}',
  bus: DeviceBus.usbInternal,
  usagePage: hidPageConsumer,
  usage: hidUsageConsumerControl,
);

/// Media keys of a plugged-in USB keyboard.
const externalMediaKeys = InputDevice(
  handle: 700,
  kind: InputDeviceKind.hid,
  path: r'\\?\HID#VID_046D&PID_C31C&MI_01&Col02#7&1&0&0001#{4d1e55b2-f16f-11cf-88cb-001111000030}',
  bus: DeviceBus.usbExternal,
  usagePage: hidPageConsumer,
  usage: hidUsageConsumerControl,
);

/// The laptop's airplane-mode button (ACPI0011 "wireless radio controls").
const airplaneButton = InputDevice(
  handle: 800,
  kind: InputDeviceKind.hid,
  path: r'\\?\HID#ACPI0011#3&30be55&0&0000#{4d1e55b2-f16f-11cf-88cb-001111000030}',
  bus: DeviceBus.internalHid,
  usagePage: hidPageGenericDesktop,
  usage: hidUsageRadioControls,
);

/// One HID report (first byte = report ID) from [device].
InputEvent hidEvent(InputDevice device, List<int> report) => InputEvent(
      device,
      RawHidPacket(deviceHandle: device.handle, inForeground: true, reports: [Uint8List.fromList(report)]),
    );

/// A key press (make) or release (break) from [device].
InputEvent keyEvent(InputDevice device, int scan, {bool extended = false, bool up = false, int vKey = 0x41}) =>
    InputEvent(
      device,
      RawKeyPacket(
        deviceHandle: device.handle,
        inForeground: true,
        makeCode: scan,
        flags: (up ? riKeyBreak : 0) | (extended ? riKeyE0 : 0),
        vKey: vKey,
      ),
    );

InputEvent mouseEvent(
  InputDevice device, {
  int dx = 0,
  int dy = 0,
  int buttons = 0,
  int data = 0,
  int flags = 0,
}) =>
    InputEvent(
      device,
      RawMousePacket(
        deviceHandle: device.handle,
        inForeground: true,
        flags: flags,
        buttonFlags: buttons,
        buttonData: data,
        dx: dx,
        dy: dy,
      ),
    );
