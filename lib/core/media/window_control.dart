import 'package:window_manager/window_manager.dart';

/// Fullscreen switch for the display test.
abstract class WindowControl {
  Future<void> setFullScreen(bool value);
}

class WindowManagerControl implements WindowControl {
  @override
  Future<void> setFullScreen(bool value) => windowManager.setFullScreen(value);
}
