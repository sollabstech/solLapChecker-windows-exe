
import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

/// A camera the system reports.
class CameraInfo {
  const CameraInfo({required this.name, this.raw});

  /// Friendly name, e.g. "Integrated Camera".
  final String name;

  /// Platform object (a `CameraDescription` for the real service).
  final Object? raw;
}

/// An open camera: shows a live preview until disposed.
abstract class CameraSession {
  /// Preview size the camera reports, if known.
  Size? get resolution;

  Widget buildPreview();

  /// Saves one still frame as a JPEG and returns its path (the caller deletes it).
  Future<String> capture();

  Future<void> dispose();
}

abstract class CameraService {
  Future<List<CameraInfo>> list();

  Future<CameraSession> open(CameraInfo camera);
}

/// camera_windows reports names like "Integrated Camera <\\?\usb#vid_...>".
/// Only the part before the device path is meant for people.
String cleanCameraName(String raw) {
  final i = raw.indexOf(' <');
  final name = (i >= 0 ? raw.substring(0, i) : raw).trim();
  return name.isEmpty ? 'Camera' : name;
}

/// Formats a size as "1280 × 720".
String formatResolution(Size? s) => s == null ? 'Unknown' : '${s.width.round()} × ${s.height.round()}';

class CameraPackageService implements CameraService {
  @override
  Future<List<CameraInfo>> list() async {
    final cams = await availableCameras();
    return [for (final c in cams) CameraInfo(name: cleanCameraName(c.name), raw: c)];
  }

  @override
  Future<CameraSession> open(CameraInfo camera) async {
    final controller = CameraController(
      camera.raw! as CameraDescription,
      ResolutionPreset.high,
      enableAudio: false,
    );
    await controller.initialize();
    return _PackageSession(controller);
  }
}

class _PackageSession implements CameraSession {
  _PackageSession(this._controller);

  final CameraController _controller;

  @override
  Size? get resolution => _controller.value.previewSize;

  @override
  Widget buildPreview() => CameraPreview(_controller);

  @override
  Future<String> capture() async => (await _controller.takePicture()).path;

  @override
  Future<void> dispose() => _controller.dispose();
}
