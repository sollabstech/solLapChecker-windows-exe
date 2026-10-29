import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/stress.dart';

/// SolHelper.exe could not be found next to the app.
class HelperMissingException implements Exception {
  HelperMissingException(this.searched);
  final List<String> searched;

  @override
  String toString() => 'SolHelper.exe was not found. Looked in: ${searched.join(', ')}';
}

/// SolHelper could not look for faces (Windows face detection unavailable, unreadable image...).
class FaceDetectionException implements Exception {
  FaceDetectionException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A running SolHelper stress process. [events] ends when the process exits.
abstract class StressSession {
  Stream<StressEvent> get events;

  /// Completes with the process exit code.
  Future<int> get exitCode;

  /// Last text the helper wrote to stderr (diagnostics for failures).
  String get stderrTail;

  /// Asks the helper to stop gracefully; force-kills it if it does not exit.
  Future<void> stop();
}

/// Starts SolHelper.exe and decodes its JSON-lines output.
class SolHelperService {
  SolHelperService({String? helperPath}) : _explicitPath = helperPath;

  final String? _explicitPath;

  /// `<app>\tools\SolHelper.exe` when installed, plus development fallbacks
  /// (the SOLHELPER_PATH override and the helper's publish folder).
  static List<String> candidatePaths() {
    final sep = Platform.pathSeparator;
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final cwd = Directory.current.path;
    final env = Platform.environment['SOLHELPER_PATH'];
    return [
      if (env != null && env.isNotEmpty) env,
      '$exeDir${sep}tools${sep}SolHelper.exe',
      '$exeDir${sep}SolHelper.exe',
      '$cwd${sep}tools${sep}SolHelper.exe',
    ];
  }

  String _resolve() {
    if (_explicitPath != null) return _explicitPath;
    final tried = candidatePaths();
    for (final p in tried) {
      if (File(p).existsSync()) return p;
    }
    throw HelperMissingException(tried);
  }

  /// Queries sensors and GPUs (`SolHelper info`).
  Future<HelperInfo> info() async {
    if (!Platform.isWindows) throw UnsupportedError('SolHelper requires Windows.');
    final exe = _resolve();
    final result = await Process.run(exe, ['info'], stdoutEncoding: utf8, stderrEncoding: utf8)
        .timeout(const Duration(seconds: 60));
    for (final line in const LineSplitter().convert('${result.stdout}')) {
      final e = parseHelperLine(line);
      if (e is HelperInfoEvent) return e.info;
    }
    throw StateError('SolHelper returned no information (exit ${result.exitCode}). ${result.stderr}'.trim());
  }

  /// Number of faces in the image at [imagePath] (`SolHelper face-detect`).
  Future<int> detectFaces(String imagePath) async {
    if (!Platform.isWindows) throw UnsupportedError('Face detection requires Windows.');
    final exe = _resolve();
    final result = await Process.run(exe, ['face-detect', '--image', imagePath], stdoutEncoding: utf8, stderrEncoding: utf8)
        .timeout(const Duration(seconds: 20));
    for (final line in const LineSplitter().convert('${result.stdout}')) {
      final Object? j;
      try {
        j = jsonDecode(line.trim());
      } on FormatException {
        continue;
      }
      if (j is! Map) continue;
      if (j['type'] == 'face') return (j['faces'] as num?)?.toInt() ?? 0;
      if (j['type'] == 'error') throw FaceDetectionException('${j['message'] ?? 'Face detection failed.'}');
    }
    throw FaceDetectionException('SolHelper returned no face result (exit ${result.exitCode}). ${result.stderr}'.trim());
  }

  /// Starts `SolHelper <args>`; the returned session streams its events.
  Future<StressSession> start(List<String> args) async {
    if (!Platform.isWindows) throw UnsupportedError('SolHelper requires Windows.');
    final exe = _resolve();
    final process = await Process.start(exe, args);
    return _ProcessSession(process);
  }
}

class _ProcessSession implements StressSession {
  _ProcessSession(this._process) {
    final lines = _process.stdout.transform(utf8.decoder).transform(const LineSplitter());
    _sub = lines.listen(
      (line) {
        final e = parseHelperLine(line);
        if (e != null) _controller.add(e);
      },
      onDone: _controller.close,
      onError: _controller.addError,
    );
    _process.stderr.transform(utf8.decoder).listen((s) {
      _stderr = (_stderr + s);
      if (_stderr.length > 2000) _stderr = _stderr.substring(_stderr.length - 2000);
    });
    exitCode = _process.exitCode;
  }

  final Process _process;
  final _controller = StreamController<StressEvent>();
  late final StreamSubscription<String> _sub;
  String _stderr = '';
  bool _stopping = false;

  @override
  Stream<StressEvent> get events => _controller.stream;

  @override
  late final Future<int> exitCode;

  @override
  String get stderrTail => _stderr.trim();

  @override
  Future<void> stop() async {
    if (_stopping) return;
    _stopping = true;
    try {
      _process.stdin.writeln('stop');
      await _process.stdin.flush();
    } catch (_) {
      // stdin already closed: the helper is exiting anyway.
    }
    // The helper removes the load and prints its summary within a moment;
    // if it is stuck, never leave a stress load running.
    unawaited(Future<void>.delayed(const Duration(seconds: 6), () {
      _process.kill();
      _sub.cancel();
    }));
  }
}
