import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'report_models.dart';

/// Reads and writes saved reports: `<id>.pdf` and `<id>.json` side by side in
/// `Documents\SolLapChecker\Reports`.
class ReportRepository {
  ReportRepository(this.root);

  final Directory root;

  static final _sep = Platform.pathSeparator;
  static final _idPattern = RegExp(r'^SLC-(\d{8})-(\d{4})$');

  /// The default location: `<Documents>\SolLapChecker\Reports`.
  static Future<ReportRepository> inDocuments() async {
    final docs = await getApplicationDocumentsDirectory();
    return ReportRepository(Directory('${docs.path}${_sep}SolLapChecker${_sep}Reports'));
  }

  String pdfPath(String id) => '${root.path}$_sep$id.pdf';

  String jsonPath(String id) => '${root.path}$_sep$id.json';

  Future<void> _ensure() => root.create(recursive: true);

  /// Next free report ID for [now]'s date: `SLC-20261025-0001`, `-0002`, ...
  /// The sequence continues from the highest number already on disk for that day.
  Future<String> nextId(DateTime now) async {
    final day = '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    var highest = 0;
    if (await root.exists()) {
      await for (final e in root.list()) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.last;
        final dot = name.lastIndexOf('.');
        final m = _idPattern.firstMatch(dot > 0 ? name.substring(0, dot) : name);
        if (m != null && m.group(1) == day) {
          final n = int.parse(m.group(2)!);
          if (n > highest) highest = n;
        }
      }
    }
    return 'SLC-$day-${(highest + 1).toString().padLeft(4, '0')}';
  }

  /// Writes the PDF and the JSON copy. Each file is written to a temporary
  /// name first and renamed, so a crash never leaves a half-written report.
  Future<void> save(ReportData data, Uint8List pdf) async {
    await _ensure();
    await _writeAtomic(pdfPath(data.id), pdf);
    await _writeAtomic(jsonPath(data.id), utf8.encode(const JsonEncoder.withIndent('  ').convert(data.toJson())));
  }

  /// Replaces only the PDF (used to regenerate a missing or damaged one).
  Future<void> savePdf(String id, Uint8List pdf) async {
    await _ensure();
    await _writeAtomic(pdfPath(id), pdf);
  }

  Future<void> _writeAtomic(String path, List<int> bytes) async {
    final tmp = File('$path.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(path);
  }

  Future<ReportData?> load(String id) async {
    final f = File(jsonPath(id));
    if (!await f.exists()) return null;
    try {
      final j = jsonDecode(await f.readAsString());
      return j is Map<String, dynamic> ? ReportData.fromJson(j) : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasPdf(String id) => File(pdfPath(id)).exists();

  /// All readable reports, newest first. Unreadable JSON files are skipped.
  Future<List<ReportSummary>> list() async {
    if (!await root.exists()) return const [];
    final out = <ReportSummary>[];
    await for (final e in root.list()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      final name = e.uri.pathSegments.last;
      final id = name.substring(0, name.length - 5);
      if (!_idPattern.hasMatch(id)) continue;
      final data = await load(id);
      if (data != null) out.add(ReportSummary.fromData(data, hasPdf: await hasPdf(id)));
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  Future<void> delete(String id) async {
    for (final path in [pdfPath(id), jsonPath(id)]) {
      final f = File(path);
      if (await f.exists()) await f.delete();
    }
  }

  // --- remembered settings (technician name) --------------------------------

  File get _settingsFile => File('${root.path}${_sep}settings.json');

  Future<String> lastTechnician() async {
    try {
      final j = jsonDecode(await _settingsFile.readAsString());
      return j is Map ? '${j['technician'] ?? ''}' : '';
    } catch (_) {
      return '';
    }
  }

  Future<void> saveTechnician(String name) async {
    await _ensure();
    await _settingsFile.writeAsString(jsonEncode({'technician': name}), flush: true);
  }
}
