import 'dart:async';

import 'package:get/get.dart';

import '../app/app_modules.dart';
import '../core/models/test_status.dart';

/// App-wide state: which screen is open, every test's status, and the
/// guided "Run Full Test" wizard. Test modules report into this controller
/// via [setStatus] and, when the wizard is active, advance it via [nextStep].
class AppController extends GetxController {
  AppController({this.autoAdvanceDelay = const Duration(seconds: 3)});

  final selected = ModuleId.dashboard.obs;

  /// Status per test module; the sidebar and the report both read this.
  final statuses = <ModuleId, TestStatus>{
    for (final m in testModules) m.id: TestStatus.notTested,
  }.obs;

  // --- running stress tests --------------------------------------------------

  /// Stop callbacks of long-running tests, registered by their controllers so
  /// a Stop button can be offered on every screen while one runs.
  final _stoppers = <ModuleId, Future<void> Function()>{};

  void registerStopper(ModuleId id, Future<void> Function() stop) => _stoppers[id] = stop;

  /// The stress test currently running, if any.
  ModuleId? get runningStress {
    for (final id in _stoppers.keys) {
      if (statusOf(id) == TestStatus.running) return id;
    }
    return null;
  }

  Future<void> stopRunning() async {
    final id = runningStress;
    if (id != null) await _stoppers[id]!();
  }

  // --- guided wizard -------------------------------------------------------
  final wizardActive = false.obs;
  final wizardIndex = 0.obs;

  /// How long a finished step's result stays on screen before the guided run
  /// moves on by itself.
  final Duration autoAdvanceDelay;

  /// Stress-test length during the guided run (the screens offer longer runs).
  static const guidedStressSeconds = 10;

  /// Called once the guided run has gone through every step (creates the report).
  void Function()? onFullTestComplete;

  Timer? _advanceTimer;
  ModuleId? _advanceFor;
  final _workers = <Worker>[];

  @override
  void onInit() {
    super.onInit();
    _workers
      ..add(ever(statuses, (_) => _autoAdvance()))
      ..add(ever(wizardIndex, (_) => _autoAdvance()))
      ..add(ever(wizardActive, (_) => _autoAdvance()));
  }

  @override
  void onClose() {
    for (final w in _workers) {
      w.dispose();
    }
    _cancelAdvance();
    super.onClose();
  }

  /// Moves on [autoAdvanceDelay] after the current step gets a verdict.
  void _autoAdvance() {
    if (!wizardActive.value) return _cancelAdvance();
    final id = currentWizardStep.id;
    if (statusOf(id).isFinished) {
      _scheduleAdvance(id);
    } else if (_advanceFor == id) {
      _cancelAdvance(); // e.g. "Run again" reopened it
    }
  }

  /// For a step that could not run at all (no battery, missing tool, camera
  /// error...): leave its message up briefly, then carry on with the rest.
  void skipSoon(ModuleId id) {
    if (wizardActive.value && currentWizardStep.id == id) _scheduleAdvance(id);
  }

  void _scheduleAdvance(ModuleId id) {
    if (_advanceFor == id && _advanceTimer != null) return;
    _cancelAdvance();
    _advanceFor = id;
    _advanceTimer = Timer(autoAdvanceDelay, () {
      _advanceTimer = null;
      _advanceFor = null;
      if (wizardActive.value && currentWizardStep.id == id) nextStep();
    });
  }

  void _cancelAdvance() {
    _advanceTimer?.cancel();
    _advanceTimer = null;
    _advanceFor = null;
  }

  List<ModuleDef> get wizardSteps => testModules;

  ModuleDef get currentWizardStep => wizardSteps[wizardIndex.value];

  void select(ModuleId id) => selected.value = id;

  TestStatus statusOf(ModuleId id) => statuses[id] ?? TestStatus.notTested;

  void setStatus(ModuleId id, TestStatus status) => statuses[id] = status;

  int get totalTests => testModules.length;

  int get finishedCount => statuses.values.where((s) => s.isFinished).length;

  int countOf(TestStatus s) => statuses.values.where((v) => v == s).length;

  /// Fraction of tests that have a final verdict (0..1).
  double get progress => totalTests == 0 ? 0 : finishedCount / totalTests;

  void resetAll() {
    for (final m in testModules) {
      statuses[m.id] = TestStatus.notTested;
    }
  }

  // --- wizard control ------------------------------------------------------

  /// Starts the guided run from the first test.
  void startFullTest() {
    resetAll();
    wizardActive.value = true;
    wizardIndex.value = 0;
    select(currentWizardStep.id);
  }

  /// Moves to the next test, or ends the wizard after the last one.
  void nextStep() {
    if (!wizardActive.value) return;
    _cancelAdvance();
    if (wizardIndex.value >= wizardSteps.length - 1) {
      stopWizard();
      // The guided run is over: go and create the report.
      select(ModuleId.reports);
      onFullTestComplete?.call();
      return;
    }
    wizardIndex.value++;
    select(currentWizardStep.id);
  }

  void stopWizard() {
    _cancelAdvance();
    wizardActive.value = false;
  }
}
