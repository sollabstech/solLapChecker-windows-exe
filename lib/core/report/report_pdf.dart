import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/test_status.dart';
import 'report_models.dart';

/// Brand colours for print.
class _C {
  static const navy = PdfColor.fromInt(0xFF0B1F3A);
  static const blue = PdfColor.fromInt(0xFF1E90FF);
  static const green = PdfColor.fromInt(0xFF16A34A); // slightly deeper than the UI green, for white paper
  static const red = PdfColor.fromInt(0xFFDC2626);
  static const gold = PdfColor.fromInt(0xFFD97706);
  static const text = PdfColor.fromInt(0xFF1F2937);
  static const muted = PdfColor.fromInt(0xFF6B7280);
  static const line = PdfColor.fromInt(0xFFE2E8F0);
  static const panel = PdfColor.fromInt(0xFFF3F6FB);
  static const track = PdfColor.fromInt(0xFFE5E9F0);
}

PdfColor _statusColor(TestStatus s) => switch (s) {
      TestStatus.pass => _C.green,
      TestStatus.warning => _C.gold,
      TestStatus.fail => _C.red,
      _ => _C.muted,
    };

String _statusWord(TestStatus s) => switch (s) {
      TestStatus.pass => 'PASS',
      TestStatus.warning => 'WARNING',
      TestStatus.fail => 'FAIL',
      _ => 'NOT TESTED',
    };

PdfColor _gradeColor(ReportGrade g) => switch (g) {
      ReportGrade.a => _C.green,
      ReportGrade.b => _C.blue,
      ReportGrade.c => _C.gold,
      ReportGrade.d => _C.red,
    };

/// Fonts and logo the PDF embeds.
class ReportPdfAssets {
  const ReportPdfAssets({required this.logo, required this.regular, required this.bold});

  final Uint8List logo;
  final ByteData regular;
  final ByteData bold;

  /// Loads the bundled logo and Roboto (Latin text with °, ×, · and dashes).
  static Future<ReportPdfAssets> load() async {
    final logo = await rootBundle.load('assets/logo.png');
    return ReportPdfAssets(
      logo: logo.buffer.asUint8List(),
      regular: await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
      bold: await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
    );
  }
}

String _two(int v) => v.toString().padLeft(2, '0');

String formatReportDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}  ${_two(d.hour)}:${_two(d.minute)}';

/// Builds the "SolLapChecker Report – Certified by Sollabs Tech" PDF.
Future<Uint8List> buildReportPdf(ReportData r, ReportPdfAssets assets) async {
  final doc = pw.Document(
    title: 'SolLapChecker Report - ${r.id}',
    author: 'Sollabs Tech',
    creator: 'SolLapChecker ${r.appVersion}',
    subject: 'Laptop health report for ${r.laptopName}',
    keywords: 'laptop, health check, ${r.id}',
  );

  final theme = pw.ThemeData.withFont(base: pw.Font.ttf(assets.regular), bold: pw.Font.ttf(assets.bold))
      .copyWith(defaultTextStyle: const pw.TextStyle(fontSize: 9.5, color: _C.text));
  final logo = pw.MemoryImage(assets.logo);

  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(34, 30, 34, 40),
        theme: theme,
      ),
      header: (ctx) => ctx.pageNumber == 1 ? _banner(r, logo) : _compactHeader(r),
      footer: (ctx) => _footer(r, ctx),
      build: (ctx) => [
        pw.SizedBox(height: 14),
        _summary(r),
        pw.SizedBox(height: 14),
        _laptopAndPeople(r),
        pw.SizedBox(height: 16),
        _sectionTitle('Test results'),
        pw.SizedBox(height: 6),
        for (final t in r.tests) _testBlock(t),
        pw.SizedBox(height: 14),
        _howToRead(r),
      ],
    ),
  );

  return doc.save();
}

// --- header / footer ---------------------------------------------------------------

pw.Widget _banner(ReportData r, pw.ImageProvider logo) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    decoration: const pw.BoxDecoration(color: _C.navy, borderRadius: pw.BorderRadius.all(pw.Radius.circular(10))),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Image(logo, width: 50, height: 50),
        pw.SizedBox(width: 14),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('SolLapChecker Report',
                  style: pw.TextStyle(color: PdfColors.white, fontSize: 21, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 3),
              pw.Text('Certified by Sollabs Tech',
                  style: pw.TextStyle(color: const PdfColor.fromInt(0xFFF59E0B), fontSize: 11.5, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('REPORT ID', style: const pw.TextStyle(color: PdfColor.fromInt(0xFF8EA3C0), fontSize: 7.5)),
            pw.Text(r.id, style: pw.TextStyle(color: PdfColors.white, fontSize: 12.5, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 5),
            pw.Text(formatReportDate(r.createdAt), style: const pw.TextStyle(color: PdfColors.white, fontSize: 9.5)),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _compactHeader(ReportData r) => pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 6),
      margin: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _C.line))),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('SolLapChecker Report', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _C.navy)),
          pw.Text('${r.laptopName}  ·  ${r.id}', style: const pw.TextStyle(color: _C.muted)),
        ],
      ),
    );

pw.Widget _footer(ReportData r, pw.Context ctx) => pw.Container(
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _C.line))),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('SolLapChecker by Sollabs Tech  ·  lapchecker.sollabstech.com', style: const pw.TextStyle(fontSize: 8, color: _C.muted)),
          pw.Text('${r.id}  ·  Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: _C.muted)),
        ],
      ),
    );

// --- summary: score ring, grade, QR ---------------------------------------------------

pw.Widget _summary(ReportData r) {
  final color = _gradeColor(r.grade);

  return pw.Container(
    padding: const pw.EdgeInsets.all(14),
    decoration: pw.BoxDecoration(
      color: _C.panel,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
      border: pw.Border.all(color: _C.line),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        _scoreRing(r.score, color),
        pw.SizedBox(width: 18),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: pw.BoxDecoration(color: color, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8))),
                    child: pw.Text('GRADE ${r.grade.letter}',
                        style: pw.TextStyle(color: PdfColors.white, fontSize: 17, fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.SizedBox(width: 10),
                  pw.Expanded(
                    child: pw.Text(r.grade.verdict,
                        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _C.navy)),
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Row(children: [
                _count('${r.count(TestStatus.pass)}', 'passed', _C.green),
                _count('${r.count(TestStatus.warning)}', 'warnings', _C.gold),
                _count('${r.count(TestStatus.fail)}', 'failed', _C.red),
                _count('${r.totalCount - r.testedCount}', 'not tested', _C.muted),
              ]),
              pw.SizedBox(height: 8),
              pw.Text(
                'Health score ${r.score} / 100'
                '${r.partial ? '  ·  partial report: ${r.testedCount} of ${r.totalCount} tests completed' : ''}',
                style: const pw.TextStyle(color: _C.muted, fontSize: 9),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 14),
        pw.Column(
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.all(5),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: _C.line),
              ),
              child: pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(errorCorrectLevel: pw.BarcodeQRCorrectionLevel.medium),
                data: r.verifyUrl,
                width: 82,
                height: 82,
                drawText: false,
                color: _C.navy,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text('Scan to verify', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _C.navy)),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _count(String n, String label, PdfColor color) => pw.Padding(
      padding: const pw.EdgeInsets.only(right: 16),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(n, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: color)),
          pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: _C.muted)),
        ],
      ),
    );

/// A ring that fills clockwise from 12 o'clock in proportion to [score], with the number in the middle.
pw.Widget _scoreRing(int score, PdfColor color) {
  const size = 104.0;
  return pw.SizedBox(
    width: size,
    height: size,
    child: pw.Stack(
      alignment: pw.Alignment.center,
      children: [
        pw.CustomPaint(
          size: const PdfPoint(size, size),
          painter: (canvas, box) {
            const stroke = 10.0;
            final cx = box.x / 2;
            final cy = box.y / 2;
            final r = box.x / 2 - stroke / 2 - 1;

            canvas
              ..setStrokeColor(_C.track)
              ..setLineWidth(stroke)
              ..drawEllipse(cx, cy, r, r)
              ..strokePath();

            final sweep = 2 * math.pi * (score.clamp(0, 100) / 100);
            if (sweep <= 0) return;
            canvas
              ..setStrokeColor(color)
              ..setLineWidth(stroke)
              ..setLineCap(PdfLineCap.round);
            // Polyline along the arc, starting at the top and going clockwise.
            final steps = math.max(2, (sweep / (2 * math.pi) * 120).ceil());
            for (var i = 0; i <= steps; i++) {
              final a = math.pi / 2 - sweep * i / steps;
              final x = cx + r * math.cos(a);
              final y = cy + r * math.sin(a);
              i == 0 ? canvas.moveTo(x, y) : canvas.lineTo(x, y);
            }
            canvas.strokePath();
          },
        ),
        pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Text('$score', style: pw.TextStyle(fontSize: 30, fontWeight: pw.FontWeight.bold, color: _C.navy)),
            pw.Text('HEALTH SCORE', style: const pw.TextStyle(fontSize: 6.5, color: _C.muted)),
          ],
        ),
      ],
    ),
  );
}

// --- laptop details --------------------------------------------------------------------

pw.Widget _laptopAndPeople(ReportData r) {
  final s = r.system;
  String v(String key) {
    final x = s[key];
    if (x == null) return 'N/A';
    if (x is List) return x.isEmpty ? 'N/A' : x.join('; ');
    final t = '$x'.trim();
    return t.isEmpty ? 'N/A' : t;
  }

  final rows = <(String, String)>[
    ('Brand', v('brand')),
    ('Model', v('model')),
    ('Serial number', v('serialNumber')),
    ('BIOS', v('bios')),
    ('Processor', '${v('cpu')}${s['cpuCores'] != null ? '  (${s['cpuCores']} cores / ${s['cpuThreads']} threads)' : ''}'),
    ('Graphics', v('gpus')),
    ('Memory', v('ram')),
    ('Storage', v('storage')),
    ('Windows', v('windows')),
    ('Display', v('display')),
  ];

  final people = <(String, String)>[
    ('Technician', r.technician.isEmpty ? 'N/A' : r.technician),
    if (r.customer != null) ('Customer', r.customer!),
    ('Date', formatReportDate(r.createdAt)),
    ('Max CPU temperature', r.maxCpuTempC == null ? 'Not measured' : '${r.maxCpuTempC!.round()} °C'),
    ('Max GPU temperature', r.maxGpuTempC == null ? 'Not measured' : '${r.maxGpuTempC!.round()} °C'),
  ];

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        flex: 6,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _sectionTitle('Laptop'),
            pw.SizedBox(height: 4),
            _kv(rows, labelWidth: 70),
          ],
        ),
      ),
      pw.SizedBox(width: 18),
      pw.Expanded(
        flex: 4,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _sectionTitle('Inspection'),
            pw.SizedBox(height: 4),
            _kv(people, labelWidth: 96),
          ],
        ),
      ),
    ],
  );
}

pw.Widget _kv(List<(String, String)> rows, {required double labelWidth}) => pw.Column(
      children: [
        for (final (k, val) in rows)
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 3.2),
            decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _C.line, width: 0.5))),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(width: labelWidth, child: pw.Text(k, style: const pw.TextStyle(color: _C.muted, fontSize: 8.5))),
                pw.Expanded(child: pw.Text(val, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
              ],
            ),
          ),
      ],
    );

pw.Widget _sectionTitle(String t) => pw.Text(
      t.toUpperCase(),
      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _C.blue, letterSpacing: 1.2),
    );

// --- test results ---------------------------------------------------------------------------

pw.Widget _testBlock(ReportTest t) {
  final color = _statusColor(t.status);
  // No bordered box: a decorated box that straddles a page break leaves a stray
  // sliver of its border on the previous page. A colour bar plus a divider line
  // reads the same and breaks cleanly.
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 7),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Container(width: 4, height: 15, color: color),
            pw.SizedBox(width: 8),
            pw.SizedBox(width: 118, child: pw.Text(t.title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.5, color: _C.navy))),
            pw.Container(
              width: 66,
              padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
              alignment: pw.Alignment.center,
              decoration: pw.BoxDecoration(color: color, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(9))),
              child: pw.Text(_statusWord(t.status),
                  style: pw.TextStyle(color: PdfColors.white, fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(child: pw.Text(t.headline, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5))),
          ],
        ),
        if (t.details.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          for (final d in t.details)
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 12, top: 1.4),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: 112,
                    child: pw.Text(d.label, style: const pw.TextStyle(color: _C.muted, fontSize: 8.5)),
                  ),
                  pw.Expanded(child: pw.Text(d.value, style: const pw.TextStyle(fontSize: 8.5))),
                ],
              ),
            ),
        ],
        pw.SizedBox(height: 7),
        pw.Container(height: 0.6, color: _C.line),
      ],
    ),
  );
}

pw.Widget _howToRead(ReportData r) => pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: const pw.BoxDecoration(color: _C.panel, borderRadius: pw.BorderRadius.all(pw.Radius.circular(8))),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('About this report', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _C.navy, fontSize: 9.5)),
          pw.SizedBox(height: 4),
          pw.Text(
            'Health score: weighted result of the completed tests (battery 15, storage 20, processor 15, graphics 10, '
            'keyboard, touchpad, camera and display 10 each). Grade A is 90 and above, B 75, C 60, '
            'D below. A failed test limits the grade to C, and Grade A needs every test completed.',
            style: const pw.TextStyle(fontSize: 8, color: _C.muted, lineSpacing: 2),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Results describe the laptop at the time of testing. Verify this report online: ${r.verifyUrl}',
            style: const pw.TextStyle(fontSize: 8, color: _C.muted, lineSpacing: 2),
          ),
        ],
      ),
    );
