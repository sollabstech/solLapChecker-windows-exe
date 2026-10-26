import 'dart:async';

import 'package:sollapchecker/core/models/stress.dart';
import 'package:sollapchecker/core/services/helper_service.dart';

/// A scripted helper process: tests push events and decide when it exits.
class FakeSession implements StressSession {
  final _controller = StreamController<StressEvent>();
  final _exit = Completer<int>();
  bool stopRequested = false;

  @override
  Stream<StressEvent> get events => _controller.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  String get stderrTail => '';

  void emit(StressEvent e) => _controller.add(e);

  Future<void> finish({int code = 0}) async {
    await _controller.close();
    if (!_exit.isCompleted) _exit.complete(code);
  }

  @override
  Future<void> stop() async {
    stopRequested = true;
    // The real helper answers a stop with its summary and exits.
    emit(const StressEnded(StressSummary(test: 'cpu', reason: StressEndReason.stopped, maxTempC: 60, elapsedSec: 3)));
    await finish();
  }
}

class FakeHelper implements SolHelperService {
  FakeHelper({this.missing = false, this.gpus = const [], this.pawnIo = true});

  final bool missing;
  final bool pawnIo;
  final List<GpuDevice> gpus;
  final sessions = <FakeSession>[];
  final startedArgs = <List<String>>[];

  @override
  Future<HelperInfo> info() async {
    if (missing) throw HelperMissingException(['C:\\app\\tools\\SolHelper.exe']);
    return HelperInfo(version: '1.0.0', admin: true, pawnIo: pawnIo, cpuName: 'Intel Core i7', cpuTempAvailable: true, gpus: gpus);
  }

  @override
  Future<StressSession> start(List<String> args) async {
    if (missing) throw HelperMissingException(['C:\\app\\tools\\SolHelper.exe']);
    startedArgs.add(args);
    final s = FakeSession();
    sessions.add(s);
    return s;
  }
}
