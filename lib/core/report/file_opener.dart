import 'dart:io';

/// Opens files in their default app and reveals them in the file manager.
abstract class FileOpener {
  Future<void> open(String path);

  Future<void> reveal(String path);
}

class WindowsFileOpener implements FileOpener {
  @override
  Future<void> open(String path) async {
    if (!Platform.isWindows) throw UnsupportedError('Opening files requires Windows.');
    // explorer.exe opens the file with its default application (the PDF viewer).
    await Process.start('explorer.exe', [path], mode: ProcessStartMode.detached);
  }

  @override
  Future<void> reveal(String path) async {
    if (!Platform.isWindows) throw UnsupportedError('Opening files requires Windows.');
    await Process.start('explorer.exe', ['/select,$path'], mode: ProcessStartMode.detached);
  }
}
