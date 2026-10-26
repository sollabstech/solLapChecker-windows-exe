import 'dart:convert';
import 'dart:io';

import '../models/drive_health.dart';

/// smartctl.exe could not be found next to the app.
class SmartctlMissingException implements Exception {
  SmartctlMissingException(this.searched);
  final List<String> searched;

  @override
  String toString() => 'smartctl.exe was not found. Looked in: ${searched.join(', ')}';
}

/// Reads SMART data for every internal drive via the bundled smartctl.exe.
class SmartctlService {
  SmartctlService({String? smartctlPath}) : _explicitPath = smartctlPath;

  final String? _explicitPath;

  /// Places smartctl.exe may live: the installed layout first
  /// (`<app>\tools\smartctl.exe`), then development fallbacks.
  static List<String> candidatePaths() {
    final sep = Platform.pathSeparator;
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final cwd = Directory.current.path;
    return [
      '$exeDir${sep}tools${sep}smartctl.exe',
      '$exeDir${sep}smartctl.exe',
      '$cwd${sep}tools${sep}smartctl.exe',
    ];
  }

  String _resolve() {
    if (_explicitPath != null) return _explicitPath;
    final tried = candidatePaths();
    for (final p in tried) {
      if (File(p).existsSync()) return p;
    }
    throw SmartctlMissingException(tried);
  }

  Future<List<DriveHealth>> readAll() async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Drive health requires Windows.');
    }
    final exe = _resolve();

    final scan = await _runJson(exe, ['--scan', '-j']);
    final devices = (scan['devices'] as List?)?.whereType<Map>() ?? const <Map>[];

    final drives = <DriveHealth>[];
    for (final d in devices) {
      final name = d['name']?.toString();
      if (name == null) continue;
      final type = d['type']?.toString();
      try {
        // smartctl exits non-zero for many SMART warnings while still
        // printing valid JSON, so the exit code is deliberately ignored.
        final doc = await _runJson(exe, ['-a', '-j', if (type != null) ...['-d', type], name]);
        final drive = DriveHealth.fromSmartctlJson(doc);
        if (drive != null) drives.add(drive);
      } catch (_) {
        // A device that cannot be read (card reader, USB stick) is skipped.
      }
    }
    return drives;
  }

  Future<Map<String, dynamic>> _runJson(String exe, List<String> args) async {
    final result = await Process.run(exe, args, stdoutEncoding: utf8, stderrEncoding: utf8)
        .timeout(const Duration(seconds: 40));
    final out = '${result.stdout}'.trim();
    final decoded = out.isEmpty ? null : jsonDecode(out);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('smartctl returned no JSON (exit ${result.exitCode})');
    }
    return decoded;
  }
}
