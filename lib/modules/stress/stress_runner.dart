import 'dart:async';

import 'package:get/get.dart';

import '../../core/models/stress.dart';
import '../../core/services/helper_service.dart';

/// Drives one SolHelper stress process and exposes its live state to the UI.
/// Shared by the CPU and GPU tests; each controller owns one runner.
class StressRunner {
  StressRunner(this._service);

  final SolHelperService _service;

  /// Seconds of data per run; the chart's x-axis spans [plannedSec].
  final samples = <StressSample>[].obs;
  final isRunning = false.obs;
  final plannedSec = 0.obs;
  final device = RxnString();
  final tempSource = RxnString();
  final limitC = 95.0.obs;
  final summary = Rxn<StressSummary>();

  /// Set when the helper could not start or died; [errorCode] is machine-readable.
  final error = RxnString();
  final errorCode = RxnString();
  final warnings = <String>[].obs;

  StressSession? _session;

  /// Runs `SolHelper <args>` for [durationSec] and returns the final summary,
  /// or null if the run failed before producing one (see [error]).
  Future<StressSummary?> run(List<String> args, {required int durationSec, String? deviceName}) async {
    if (isRunning.value) return null;
    _reset(durationSec, deviceName);
    isRunning.value = true;

    StressSummary? result;
    try {
      final session = await _service.start(args);
      _session = session;

      await for (final e in session.events) {
        switch (e) {
          case StressStarted():
            device.value = e.device;
            tempSource.value = e.tempSource;
            limitC.value = e.limitC;
            plannedSec.value = e.durationSec;
          case StressSampled():
            samples.add(e.sample);
          case StressWarning():
            warnings.add(e.message);
          case StressFailed():
            errorCode.value = e.code;
            error.value = e.message;
          case StressEnded():
            result = e.summary.withContext(device: device.value ?? deviceName, plannedSec: plannedSec.value);
            summary.value = result;
          case HelperInfoEvent():
            break;
        }
      }

      if (result == null && error.value == null) {
        final code = await session.exitCode;
        final tail = session.stderrTail;
        error.value = 'SolHelper exited unexpectedly (code $code).${tail.isEmpty ? '' : ' $tail'}';
        errorCode.value = 'helper-crashed';
      }
    } on HelperMissingException catch (e) {
      errorCode.value = 'helper-missing';
      error.value = '$e';
    } catch (e) {
      errorCode.value = 'start-failed';
      error.value = '$e';
    } finally {
      _session = null;
      isRunning.value = false;
    }
    return result;
  }

  /// Stops the running test (no-op if idle).
  Future<void> stop() async => _session?.stop();

  void _reset(int durationSec, String? deviceName) {
    samples.clear();
    warnings.clear();
    summary.value = null;
    error.value = null;
    errorCode.value = null;
    plannedSec.value = durationSec;
    device.value = deviceName;
    tempSource.value = null;
  }
}
