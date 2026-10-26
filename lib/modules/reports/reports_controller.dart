import 'dart:typed_data';

import 'package:get/get.dart';

import '../../controllers/app_controller.dart';
import '../../core/report/file_opener.dart';
import '../../core/report/report_builder.dart';
import '../../core/report/report_models.dart';
import '../../core/report/report_pdf.dart';
import '../../core/report/report_repository.dart';
import '../battery/battery_controller.dart';
import '../cpu/cpu_controller.dart';
import '../dashboard/dashboard_controller.dart';
import '../display/display_controller.dart';
import '../gpu/gpu_controller.dart';
import '../keyboard/keyboard_controller.dart';
import '../microphone/microphone_controller.dart';
import '../speaker/speaker_controller.dart';
import '../storage/storage_controller.dart';
import '../touchpad/touchpad_controller.dart';
import '../webcam/webcam_controller.dart';

/// Creates reports from the finished tests and manages the saved history.
class ReportsController extends GetxController {
  ReportsController(
    this._repo, {
    FileOpener? opener,
    DateTime Function()? clock,
    Future<ReportPdfAssets> Function()? loadAssets,
    this.appVersion = '1.0.0',
  })  : _opener = opener ?? WindowsFileOpener(),
        _clock = clock ?? DateTime.now,
        _loadAssets = loadAssets ?? ReportPdfAssets.load;

  final ReportRepository _repo;
  final FileOpener _opener;
  final DateTime Function() _clock;
  final Future<ReportPdfAssets> Function() _loadAssets;
  final String appVersion;

  // form
  final technician = ''.obs;
  final customer = ''.obs;

  // state
  final history = <ReportSummary>[].obs;
  final query = ''.obs;
  final isGenerating = false.obs;
  final error = RxnString();

  /// The report just created, for the "saved" banner.
  final lastSaved = Rxn<ReportSummary>();

  ReportPdfAssets? _assets;

  AppController get _app => Get.find<AppController>();

  String get folderPath => _repo.root.path;

  /// Loads the remembered technician name and the saved reports.
  Future<void> init() async {
    if (technician.value.isEmpty) technician.value = await _repo.lastTechnician();
    await refreshHistory();
  }

  int _refreshSeq = 0;

  /// Re-reads the reports folder. Refreshes can overlap (opening the screen and
  /// saving a report both trigger one), so only the most recently started one
  /// is allowed to update the list; an older, slower read must not overwrite it.
  Future<void> refreshHistory() async {
    final mine = ++_refreshSeq;
    try {
      final list = await _repo.list();
      if (mine == _refreshSeq) history.assignAll(list);
    } catch (e) {
      if (mine == _refreshSeq) error.value = 'Could not read the reports folder: $e';
    }
  }

  List<ReportSummary> get filtered => history.where((r) => r.matches(query.value)).toList();

  /// Score the report would get right now (for the live preview).
  ScoreResult get preview => computeScore(_app.statuses);

  bool get canGenerate => technician.value.trim().isNotEmpty && preview.testedCount > 0 && !isGenerating.value;

  /// Gathers every test's data from the registered controllers.
  ReportInputs collectInputs() {
    T? find<T>() => Get.isRegistered<T>() ? Get.find<T>() : null;

    final dash = find<DashboardController>();
    final battery = find<BatteryController>();
    final storage = find<StorageController>();
    final cpu = find<CpuController>();
    final gpu = find<GpuController>();
    final kb = find<KeyboardController>();
    final pad = find<TouchpadController>();
    final cam = find<WebcamController>();
    final spk = find<SpeakerController>();
    final mic = find<MicrophoneController>();
    final disp = find<DisplayController>();

    final system = {...?dash?.info.value?.toJson()};
    if (system.isNotEmpty && system['display'] == null) system['display'] = dash?.fallbackResolution;

    final gpuResults = [
      if (gpu != null) for (final e in (gpu.results.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))) e.value,
    ];

    return ReportInputs(
      system: system,
      statuses: Map.of(_app.statuses),
      battery: battery?.info.value,
      drives: storage?.drives.toList() ?? const [],
      cpu: cpu?.runner.summary.value,
      gpus: gpuResults,
      keyboard: kb?.toJson(),
      touchpad: pad?.toJson(),
      webcam: cam?.toJson(),
      speaker: spk?.toJson(),
      microphone: mic?.toJson(),
      display: disp?.toJson(),
    );
  }

  /// Builds, saves (PDF + JSON) and announces a new report. Returns it, or null on failure.
  Future<ReportSummary?> generate() async {
    error.value = null;
    if (technician.value.trim().isEmpty) {
      error.value = 'Enter the technician name.';
      return null;
    }
    if (preview.testedCount == 0) {
      error.value = 'Run at least one test before creating a report.';
      return null;
    }

    isGenerating.value = true;
    try {
      final now = _clock();
      final id = await _repo.nextId(now);
      final data = ReportBuilder.build(
        collectInputs(),
        id: id,
        createdAt: now,
        technician: technician.value,
        customer: customer.value,
        appVersion: appVersion,
      );
      final pdf = await _pdfFor(data);
      await _repo.save(data, pdf);
      await _repo.saveTechnician(data.technician);

      final summary = ReportSummary.fromData(data, hasPdf: true);
      lastSaved.value = summary;
      await refreshHistory();
      return summary;
    } catch (e) {
      error.value = 'The report could not be saved: $e';
      return null;
    } finally {
      isGenerating.value = false;
    }
  }

  Future<Uint8List> _pdfFor(ReportData data) async {
    _assets ??= await _loadAssets();
    return buildReportPdf(data, _assets!);
  }

  /// Opens a saved report's PDF; rebuilds it from the JSON copy if the PDF is gone.
  Future<void> openPdf(ReportSummary r) async {
    error.value = null;
    try {
      if (!await _repo.hasPdf(r.id)) {
        final data = await _repo.load(r.id);
        if (data == null) {
          error.value = 'The report data for ${r.id} could not be read.';
          return;
        }
        await _repo.savePdf(r.id, await _pdfFor(data));
        await refreshHistory();
      }
      await _opener.open(_repo.pdfPath(r.id));
    } catch (e) {
      error.value = 'Could not open the report: $e';
    }
  }

  Future<void> reveal(ReportSummary r) async {
    error.value = null;
    try {
      final path = await _repo.hasPdf(r.id) ? _repo.pdfPath(r.id) : _repo.jsonPath(r.id);
      await _opener.reveal(path);
    } catch (e) {
      error.value = 'Could not open the folder: $e';
    }
  }

  Future<void> openFolder() async {
    try {
      await _opener.open(_repo.root.path);
    } catch (e) {
      error.value = 'Could not open the folder: $e';
    }
  }

  Future<ReportData?> details(String id) => _repo.load(id);

  Future<void> delete(ReportSummary r) async {
    await _repo.delete(r.id);
    if (lastSaved.value?.id == r.id) lastSaved.value = null;
    await refreshHistory();
  }
}
