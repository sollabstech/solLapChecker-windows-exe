import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show protected;

import 'input_device.dart';
import 'raw_input_event.dart';

/// Source of keyboard and mouse events tagged with the device that produced them.
abstract class RawInputService {
  /// Events from every keyboard and mouse (the consumer filters by device).
  Stream<InputEvent> get events;

  /// Starts listening (reference counted; call [release] when done).
  /// Throws if Raw Input cannot be set up.
  Future<void> acquire();

  void release();
}

/// Reference counting and the event stream; subclasses supply the native part.
abstract class RawInputServiceBase implements RawInputService {
  final _controller = StreamController<InputEvent>.broadcast();
  int _users = 0;

  @override
  Stream<InputEvent> get events => _controller.stream;

  @protected
  void emit(InputEvent e) => _controller.add(e);

  Future<void> startNative();

  void stopNative();

  @override
  Future<void> acquire() async {
    if (_users == 0) await startNative();
    _users++;
  }

  @override
  void release() {
    if (_users == 0) return;
    _users--;
    if (_users == 0) stopNative();
  }
}

// =============================================================================
// Windows implementation (dart:ffi)
//
// A hidden message-only window receives WM_INPUT through the app's normal
// message loop (Flutter 3.35+ runs Dart on the platform thread on Windows, so
// the Dart window procedure below is called synchronously on the right thread).
//
// Privacy: the window registers with RIDEV_INPUTSINK so it works while a
// Flutter widget has focus, but input that arrives while this app is not in the
// foreground (RIM_INPUTSINK) is discarded at once and never leaves this file.
// Listening only lasts while a keyboard/touchpad test screen is open.
// =============================================================================

const _wmInput = 0x00FF;
const _ridInput = 0x10000003;
const _ridiDeviceName = 0x20000007;
const _ridevRemove = 0x00000001;
const _ridevInputSink = 0x00000100;
const _hwndMessage = -3;

const _cmDrpCapabilities = 0x10;
const _cmDrpEnumeratorName = 0x17;
const _cmDevcapRemovable = 0x04;

typedef _WndProcNative = IntPtr Function(IntPtr hwnd, Uint32 msg, IntPtr wParam, IntPtr lParam);

final class _WndClassEx extends Struct {
  @Uint32()
  external int cbSize;
  @Uint32()
  external int style;
  external Pointer<NativeFunction<_WndProcNative>> lpfnWndProc;
  @Int32()
  external int cbClsExtra;
  @Int32()
  external int cbWndExtra;
  external Pointer<Void> hInstance;
  external Pointer<Void> hIcon;
  external Pointer<Void> hCursor;
  external Pointer<Void> hbrBackground;
  external Pointer<Utf16> lpszMenuName;
  external Pointer<Utf16> lpszClassName;
  external Pointer<Void> hIconSm;
}

final class _RawInputDevice extends Struct {
  @Uint16()
  external int usUsagePage;
  @Uint16()
  external int usUsage;
  @Uint32()
  external int dwFlags;
  external Pointer<Void> hwndTarget;
}

class _Win32 {
  _Win32._();

  static final _user32 = DynamicLibrary.open('user32.dll');
  static final _kernel32 = DynamicLibrary.open('kernel32.dll');
  static final _cfgmgr32 = DynamicLibrary.open('cfgmgr32.dll');

  static final getModuleHandle =
      _kernel32.lookupFunction<Pointer<Void> Function(Pointer<Utf16>), Pointer<Void> Function(Pointer<Utf16>)>(
          'GetModuleHandleW');

  static final registerClassEx =
      _user32.lookupFunction<Uint16 Function(Pointer<_WndClassEx>), int Function(Pointer<_WndClassEx>)>(
          'RegisterClassExW');

  static final unregisterClass = _user32.lookupFunction<Int32 Function(Pointer<Utf16>, Pointer<Void>),
      int Function(Pointer<Utf16>, Pointer<Void>)>('UnregisterClassW');

  static final createWindowEx = _user32.lookupFunction<
      Pointer<Void> Function(Uint32, Pointer<Utf16>, Pointer<Utf16>, Uint32, Int32, Int32, Int32, Int32,
          Pointer<Void>, Pointer<Void>, Pointer<Void>, Pointer<Void>),
      Pointer<Void> Function(int, Pointer<Utf16>, Pointer<Utf16>, int, int, int, int, int, Pointer<Void>,
          Pointer<Void>, Pointer<Void>, Pointer<Void>)>('CreateWindowExW');

  static final destroyWindow =
      _user32.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>('DestroyWindow');

  static final defWindowProc = _user32.lookupFunction<IntPtr Function(IntPtr, Uint32, IntPtr, IntPtr),
      int Function(int, int, int, int)>('DefWindowProcW');

  static final registerRawInputDevices = _user32.lookupFunction<
      Int32 Function(Pointer<_RawInputDevice>, Uint32, Uint32),
      int Function(Pointer<_RawInputDevice>, int, int)>('RegisterRawInputDevices');

  static final getRawInputData = _user32.lookupFunction<
      Uint32 Function(IntPtr, Uint32, Pointer<Void>, Pointer<Uint32>, Uint32),
      int Function(int, int, Pointer<Void>, Pointer<Uint32>, int)>('GetRawInputData');

  static final getRawInputDeviceInfo = _user32.lookupFunction<
      Uint32 Function(Pointer<Void>, Uint32, Pointer<Void>, Pointer<Uint32>),
      int Function(Pointer<Void>, int, Pointer<Void>, Pointer<Uint32>)>('GetRawInputDeviceInfoW');

  static final cmLocateDevNode = _cfgmgr32.lookupFunction<
      Uint32 Function(Pointer<Uint32>, Pointer<Utf16>, Uint32),
      int Function(Pointer<Uint32>, Pointer<Utf16>, int)>('CM_Locate_DevNodeW');

  static final cmGetParent = _cfgmgr32.lookupFunction<Uint32 Function(Pointer<Uint32>, Uint32, Uint32),
      int Function(Pointer<Uint32>, int, int)>('CM_Get_Parent');

  static final cmGetRegistryProperty = _cfgmgr32.lookupFunction<
      Uint32 Function(Uint32, Uint32, Pointer<Uint32>, Pointer<Void>, Pointer<Uint32>, Uint32),
      int Function(int, int, Pointer<Uint32>, Pointer<Void>, Pointer<Uint32>, int)>(
      'CM_Get_DevNode_Registry_PropertyW');
}

class WindowsRawInputService extends RawInputServiceBase {
  static const _className = 'SolLapCheckerRawInput';

  NativeCallable<_WndProcNative>? _callback;
  Pointer<Void> _hwnd = nullptr;
  Pointer<Void> _hInstance = nullptr;
  Pointer<Utf16>? _classNamePtr;

  final _devices = <int, InputDevice>{};
  late final int _headerSize = sizeOf<IntPtr>() == 8 ? 24 : 16;

  @override
  Future<void> startNative() async {
    if (!Platform.isWindows) throw UnsupportedError('Raw Input requires Windows.');

    _callback = NativeCallable<_WndProcNative>.isolateLocal(_onMessage, exceptionalReturn: 0);
    _classNamePtr = _className.toNativeUtf16();
    _hInstance = _Win32.getModuleHandle(nullptr);

    final wc = calloc<_WndClassEx>();
    try {
      wc.ref
        ..cbSize = sizeOf<_WndClassEx>()
        ..lpfnWndProc = _callback!.nativeFunction
        ..hInstance = _hInstance
        ..lpszClassName = _classNamePtr!;
      // A stale registration from a previous run is harmless; ignore the atom.
      _Win32.registerClassEx(wc);
    } finally {
      calloc.free(wc);
    }

    final title = 'SolLapChecker raw input'.toNativeUtf16();
    try {
      _hwnd = _Win32.createWindowEx(0, _classNamePtr!, title, 0, 0, 0, 0, 0,
          Pointer<Void>.fromAddress(_hwndMessage), nullptr, _hInstance, nullptr);
    } finally {
      calloc.free(title);
    }
    if (_hwnd == nullptr) {
      _teardown();
      throw StateError('Could not create the raw input window.');
    }

    if (!_register(_ridevInputSink, _hwnd)) {
      _teardown();
      throw StateError('RegisterRawInputDevices failed.');
    }
  }

  @override
  void stopNative() => _teardown();

  /// Registers (or with RIDEV_REMOVE, unregisters) keyboards (1,6) and mice (1,2).
  bool _register(int flags, Pointer<Void> target) {
    final devs = calloc<_RawInputDevice>(2);
    try {
      devs[0]
        ..usUsagePage = 0x01
        ..usUsage = 0x06
        ..dwFlags = flags
        ..hwndTarget = target;
      devs[1]
        ..usUsagePage = 0x01
        ..usUsage = 0x02
        ..dwFlags = flags
        ..hwndTarget = target;
      return _Win32.registerRawInputDevices(devs, 2, sizeOf<_RawInputDevice>()) != 0;
    } finally {
      calloc.free(devs);
    }
  }

  void _teardown() {
    if (_hwnd != nullptr) {
      _register(_ridevRemove, nullptr);
      _Win32.destroyWindow(_hwnd);
      _hwnd = nullptr;
    }
    if (_classNamePtr != null) {
      _Win32.unregisterClass(_classNamePtr!, _hInstance);
      calloc.free(_classNamePtr!);
      _classNamePtr = null;
    }
    _callback?.close();
    _callback = null;
    _devices.clear();
  }

  /// The window procedure. Always defers to DefWindowProc (required for WM_INPUT).
  int _onMessage(int hwnd, int msg, int wParam, int lParam) {
    if (msg == _wmInput) {
      try {
        _handleInput(wParam, lParam);
      } catch (_) {
        // Never let an exception unwind into native code.
      }
    }
    return _Win32.defWindowProc(hwnd, msg, wParam, lParam);
  }

  void _handleInput(int wParam, int lParam) {
    // RIM_INPUT (0) = app in foreground; RIM_INPUTSINK (1) = in background.
    final foreground = (wParam & 0xFF) == 0;
    if (!foreground) return;

    final sizePtr = calloc<Uint32>();
    Pointer<Uint8>? buf;
    try {
      if (_Win32.getRawInputData(lParam, _ridInput, nullptr, sizePtr, _headerSize) != 0) return;
      final size = sizePtr.value;
      if (size == 0) return;

      buf = calloc<Uint8>(size);
      final got = _Win32.getRawInputData(lParam, _ridInput, buf.cast(), sizePtr, _headerSize);
      if (got != size) return;

      final bytes = Uint8List.fromList(buf.asTypedList(size));
      final packet = parseRawInput(bytes, inForeground: true, headerSize: _headerSize);
      if (packet == null) return;

      final kind = packet is RawKeyPacket ? InputDeviceKind.keyboard : InputDeviceKind.mouse;
      emit(InputEvent(_deviceFor(packet.deviceHandle, kind), packet));
    } finally {
      calloc.free(sizePtr);
      if (buf != null) calloc.free(buf);
    }
  }

  InputDevice _deviceFor(int handle, InputDeviceKind kind) {
    if (handle == 0) {
      return InputDevice(handle: 0, kind: kind, path: '', bus: DeviceBus.virtual);
    }
    return _devices.putIfAbsent(handle, () {
      final path = _devicePath(handle);
      return InputDevice(
        handle: handle,
        kind: kind,
        path: path,
        bus: classifyDevicePath(path, native: _nativeBusInfo(path)),
      );
    });
  }

  String _devicePath(int handle) {
    final h = Pointer<Void>.fromAddress(handle);
    final sizePtr = calloc<Uint32>();
    try {
      _Win32.getRawInputDeviceInfo(h, _ridiDeviceName, nullptr, sizePtr);
      final chars = sizePtr.value;
      if (chars == 0) return '';
      final buf = calloc<Uint16>(chars);
      try {
        final n = _Win32.getRawInputDeviceInfo(h, _ridiDeviceName, buf.cast(), sizePtr);
        if (n == 0xFFFFFFFF || n == 0) return '';
        return buf.cast<Utf16>().toDartString();
      } finally {
        calloc.free(buf);
      }
    } finally {
      calloc.free(sizePtr);
    }
  }

  /// Walks the device's parents in the device tree to learn whether it hangs
  /// off Bluetooth or a removable USB port. Returns null if the tree cannot be read.
  NativeBusInfo? _nativeBusInfo(String path) {
    final id = deviceInstanceIdFromPath(path);
    if (id == null) return null;

    final idPtr = id.toNativeUtf16();
    final node = calloc<Uint32>();
    try {
      if (_Win32.cmLocateDevNode(node, idPtr, 0) != 0) return null;

      final names = <String>[];
      var removable = false;
      var current = node.value;
      for (var depth = 0; depth < 12; depth++) {
        final name = _enumeratorName(current);
        if (name != null) names.add(name);
        if (name?.toUpperCase() == 'USB' && (_capabilities(current) & _cmDevcapRemovable) != 0) {
          removable = true;
        }
        final parent = calloc<Uint32>();
        try {
          if (_Win32.cmGetParent(parent, current, 0) != 0) break;
          current = parent.value;
        } finally {
          calloc.free(parent);
        }
      }
      return NativeBusInfo(enumerators: names, removable: removable);
    } catch (_) {
      return null;
    } finally {
      calloc.free(idPtr);
      calloc.free(node);
    }
  }

  String? _enumeratorName(int devInst) {
    final buf = calloc<Uint16>(256);
    final len = calloc<Uint32>()..value = 512;
    try {
      final r = _Win32.cmGetRegistryProperty(devInst, _cmDrpEnumeratorName, nullptr, buf.cast(), len, 0);
      return r == 0 ? buf.cast<Utf16>().toDartString() : null;
    } finally {
      calloc.free(buf);
      calloc.free(len);
    }
  }

  int _capabilities(int devInst) {
    final value = calloc<Uint32>();
    final len = calloc<Uint32>()..value = 4;
    try {
      final r = _Win32.cmGetRegistryProperty(devInst, _cmDrpCapabilities, nullptr, value.cast(), len, 0);
      return r == 0 ? value.value : 0;
    } finally {
      calloc.free(value);
      calloc.free(len);
    }
  }
}
