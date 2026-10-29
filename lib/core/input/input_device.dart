import 'raw_input_event.dart';

enum InputDeviceKind {
  keyboard,
  mouse,

  /// Another HID collection (media keys, airplane button, precision touchpad...).
  hid,
}

// HID usage page / usage pairs that Raw Input is asked for besides keyboards and mice.
const hidPageGenericDesktop = 0x01;
const hidUsageSystemControl = 0x80; // sleep / power buttons
const hidUsageRadioControls = 0x0C; // airplane-mode button
const hidPageConsumer = 0x0C;
const hidUsageConsumerControl = 0x01; // volume, mute, media, brightness keys
const hidPageDigitizer = 0x0D;
const hidUsageTouchpad = 0x05; // Windows precision touchpad

/// How a device is attached, as far as we can tell.
enum DeviceBus {
  /// ACPI / PS/2 (i8042): the classic built-in laptop keyboard and touchpad.
  acpi('Built-in (ACPI/PS2)'),

  /// I²C-HID or other firmware-described HID: modern built-in keyboards and precision touchpads.
  internalHid('Built-in (HID)'),

  /// A USB device permanently wired inside the laptop.
  usbInternal('Built-in (USB)'),

  /// A USB device plugged into a port.
  usbExternal('External USB'),

  /// Bluetooth keyboard or mouse.
  bluetooth('Bluetooth'),

  /// Remote-desktop / virtual / synthesized input.
  virtual('Virtual'),

  /// A USB device whose attachment could not be determined.
  usbUnknown('USB (unknown port)'),
  unknown('Unknown');

  const DeviceBus(this.label);
  final String label;
}

/// What the native side learned by walking the device's parents in the
/// device tree (cfgmgr32): the enumerator names ("HID", "USB", "BTHENUM", ...)
/// and whether any USB node is flagged removable.
class NativeBusInfo {
  const NativeBusInfo({required this.enumerators, required this.removable});

  final List<String> enumerators;
  final bool removable;
}

/// A keyboard or mouse as reported by Raw Input.
class InputDevice {
  const InputDevice({
    required this.handle,
    required this.kind,
    required this.path,
    required this.bus,
    this.usagePage = 0,
    this.usage = 0,
  });

  final int handle;
  final InputDeviceKind kind;

  /// Top-level HID collection, for [InputDeviceKind.hid] devices (0 otherwise).
  final int usagePage;
  final int usage;

  /// A Windows precision touchpad's contact reports.
  bool get isTouchpadDigitizer => usagePage == hidPageDigitizer && usage == hidUsageTouchpad;

  /// Media/system/airplane keys. On a laptop keyboard these are reached with
  /// Fn, so a press from a built-in one shows that Fn works.
  bool get isFunctionKeySource =>
      (usagePage == hidPageConsumer && usage == hidUsageConsumerControl) ||
      (usagePage == hidPageGenericDesktop && (usage == hidUsageSystemControl || usage == hidUsageRadioControls));

  /// Raw Input device interface path, e.g. `\\?\ACPI#PNP0303#4&1b9a1d65&0#{...}`.
  final String path;
  final DeviceBus bus;

  /// Counts as part of the laptop itself.
  bool get isInternal =>
      bus == DeviceBus.acpi || bus == DeviceBus.internalHid || bus == DeviceBus.usbInternal;

  /// A plugged-in USB, Bluetooth or virtual device: never part of the laptop,
  /// so its input is always ignored and cannot be switched on.
  bool get canBeCounted =>
      bus != DeviceBus.usbExternal && bus != DeviceBus.bluetooth && bus != DeviceBus.virtual;

  /// Whether events from this device are counted before the user overrides it.
  /// External and unidentified USB devices are ignored; anything else we
  /// cannot classify (not USB, not Bluetooth) is assumed to be built in.
  bool get countedByDefault => isInternal || bus == DeviceBus.unknown;

  /// Short name for the UI, e.g. "ACPI PNP0303", "USB 046D:C31C".
  String get description => describeDevicePath(path);

  /// Synthesized input has no device handle at all.
  static const synthetic = InputDevice(
    handle: 0,
    kind: InputDeviceKind.mouse,
    path: '',
    bus: DeviceBus.virtual,
  );
}

/// Decides how a device is attached from its Raw Input path, refined by
/// [native] bus information when available.
///
/// Rules, in order:
///  1. Bluetooth (HID service GUID in the path, or a BTH* parent) -> external.
///  2. A USB device: external if any USB node in its chain is removable,
///     internal if it is hard-wired; unknown if the device tree could not be read.
///  3. `ACPI#...` paths (PS/2 i8042) -> built-in.
///  4. `HID#<ACPI-style id>` (I²C-HID such as ELAN/SYNA/MSHW/DLL) -> built-in.
///  5. `ROOT#...` / `RDP_*` -> virtual.
DeviceBus classifyDevicePath(String path, {NativeBusInfo? native}) {
  final p = path.toUpperCase();

  final bt = p.contains('{00001124-0000-1000-8000-00805F9B34FB}') ||
      p.contains('{00001812-0000-1000-8000-00805F9B34FB}') ||
      p.contains('BTHENUM') ||
      p.contains('BTHLE');
  if (bt) return DeviceBus.bluetooth;

  final enums = native?.enumerators.map((e) => e.toUpperCase()).toList() ?? const <String>[];
  if (enums.any((e) => e.startsWith('BTH'))) return DeviceBus.bluetooth;

  final looksUsb = p.contains('VID_') && p.contains('PID_');
  final chainUsb = enums.contains('USB');
  if (looksUsb || chainUsb) {
    if (native == null) return DeviceBus.usbUnknown;
    return native.removable ? DeviceBus.usbExternal : DeviceBus.usbInternal;
  }

  if (p.startsWith(r'\\?\ACPI#') || p.startsWith(r'\??\ACPI#')) return DeviceBus.acpi;
  if (p.contains(r'\ROOT#') || p.contains('RDP_') || p.contains('TERMINPUT')) return DeviceBus.virtual;
  final hidAt = p.indexOf(r'\HID#');
  if (hidAt >= 0 && RegExp(r'^[A-Z]{3,4}[0-9A-F]{4}').hasMatch(p.substring(hidAt + 5))) {
    return DeviceBus.internalHid;
  }

  return DeviceBus.unknown;
}

/// Human-readable identity taken from the path (no registry lookup needed).
String describeDevicePath(String path) {
  if (path.isEmpty) return 'Synthesized input';
  final parts = path.split('#');
  if (parts.length < 2) return path;
  final id = parts[1];

  final vid = RegExp(r'VID_([0-9A-Fa-f]{4})').firstMatch(id)?.group(1);
  final pid = RegExp(r'PID_([0-9A-Fa-f]{4})').firstMatch(id)?.group(1);
  if (vid != null && pid != null) return 'USB ${vid.toUpperCase()}:${pid.toUpperCase()}';

  final bus = parts[0].replaceAll(r'\\?\', '').replaceAll(r'\??\', '');
  final clean = id.split('&').first;
  return '$bus $clean'.trim();
}

/// Instance ID for cfgmgr32 from a Raw Input path:
/// `\\?\HID#VID_046D&PID_C31C#7&2c0d&0&0000#{884b...}` -> `HID\VID_046D&PID_C31C\7&2c0d&0&0000`.
String? deviceInstanceIdFromPath(String path) {
  var s = path;
  if (s.startsWith(r'\\?\') || s.startsWith(r'\??\')) s = s.substring(4);
  final guid = s.lastIndexOf('#{');
  if (guid > 0) s = s.substring(0, guid);
  if (!s.contains('#')) return null;
  return s.replaceAll('#', r'\');
}

/// Everything the keyboard/touchpad controllers need from one packet.
class InputEvent {
  const InputEvent(this.device, this.packet);

  final InputDevice device;
  final RawInputPacket packet;
}
