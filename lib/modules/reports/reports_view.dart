import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/app_modules.dart';
import '../../app/theme.dart';
import '../../controllers/app_controller.dart';
import '../../core/models/test_status.dart';
import '../../core/report/report_models.dart';
import '../../core/report/report_pdf.dart' show formatReportDate;
import '../../widgets/glass_card.dart';
import '../../widgets/module_scaffold.dart';
import '../../widgets/progress_ring.dart';
import 'reports_controller.dart';

Color gradeColor(ReportGrade g) => switch (g) {
      ReportGrade.a => AppColors.pass,
      ReportGrade.b => AppColors.primary,
      ReportGrade.c => AppColors.accent,
      ReportGrade.d => AppColors.fail,
    };

class ReportsView extends StatefulWidget {
  const ReportsView({super.key});

  @override
  State<ReportsView> createState() => _ReportsViewState();
}

class _ReportsViewState extends State<ReportsView> {
  final c = Get.find<ReportsController>();
  final _tech = TextEditingController();
  final _customer = TextEditingController();
  Worker? _techWorker;

  @override
  void initState() {
    super.initState();
    _tech.text = c.technician.value;
    _customer.text = c.customer.value;
    // The remembered name arrives asynchronously from the settings file.
    _techWorker = ever<String>(c.technician, (v) {
      if (_tech.text != v) _tech.text = v;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => c.init());
  }

  @override
  void dispose() {
    _techWorker?.dispose();
    _tech.dispose();
    _customer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final module = moduleById(ModuleId.reports);
    return Obx(() => ModuleScaffold(
          title: module.title,
          subtitle: module.subtitle,
          icon: module.icon,
          status: TestStatus.notTested,
          statusChip: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (c.error.value != null) ...[
                NoticeCard(
                  icon: Icons.error_outline_rounded,
                  color: AppColors.fail,
                  title: 'Something went wrong',
                  message: c.error.value!,
                ),
                const SizedBox(height: 16),
              ],
              LayoutBuilder(builder: (context, box) {
                final form = _FormCard(c: c, tech: _tech, customer: _customer);
                final preview = _PreviewCard(c: c);
                if (box.maxWidth < 900) return Column(children: [form, const SizedBox(height: 16), preview]);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Expanded(flex: 5, child: form), const SizedBox(width: 18), Expanded(flex: 4, child: preview)],
                );
              }),
              if (c.lastSaved.value != null) ...[
                const SizedBox(height: 16),
                _SavedBanner(c: c, r: c.lastSaved.value!),
              ],
              const SizedBox(height: 26),
              _History(c: c),
            ],
          ),
        ));
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({required this.c, required this.tech, required this.customer});

  final ReportsController c;
  final TextEditingController tech;
  final TextEditingController customer;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('New report', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text(
            'A PDF and a JSON copy are saved to Documents\\SolLapChecker\\Reports.',
            style: TextStyle(color: AppColors.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: tech,
            onChanged: (v) => c.technician.value = v,
            decoration: const InputDecoration(
              labelText: 'Technician name *',
              prefixIcon: Icon(Icons.badge_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: customer,
            onChanged: (v) => c.customer.value = v,
            decoration: const InputDecoration(
              labelText: 'Customer name (optional)',
              prefixIcon: Icon(Icons.person_outline_rounded),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 18),
          Obx(() => FilledButton.icon(
                onPressed: c.canGenerate ? c.generate : null,
                icon: c.isGenerating.value
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                    : const Icon(Icons.picture_as_pdf_rounded, size: 20),
                label: Text(c.isGenerating.value ? 'Creating…' : 'Generate report (PDF)'),
              )),
          Obx(() {
            final reason = c.technician.value.trim().isEmpty
                ? 'Enter the technician name to continue.'
                : (c.preview.testedCount == 0 ? 'Run at least one test first.' : null);
            if (reason == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(reason, style: const TextStyle(color: AppColors.accent, fontSize: 12.5)),
            );
          }),
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.c});

  final ReportsController c;

  @override
  Widget build(BuildContext context) {
    final app = Get.find<AppController>();
    return Obx(() {
      // Reading the statuses subscribes this card to changes.
      final statuses = Map.of(app.statuses);
      final r = c.preview;
      final color = gradeColor(r.grade);
      final untested = [for (final m in testModules) if (!(statuses[m.id]?.isFinished ?? false)) m.title];

      return GlassCard(
        glow: r.testedCount == 0 ? null : color,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Result so far', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            Row(
              children: [
                ProgressRing(
                  value: r.score / 100,
                  size: 96,
                  strokeWidth: 9,
                  color: color,
                  endColor: color,
                  child: Text('${r.score}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Grade ${r.grade.letter}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color)),
                      Text(r.grade.verdict, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                      const SizedBox(height: 6),
                      Text('${r.testedCount} of ${r.totalCount} tests completed', style: const TextStyle(fontSize: 12.5)),
                    ],
                  ),
                ),
              ],
            ),
            if (untested.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Not tested: ${untested.join(', ')}. Grade A needs every test completed.',
                style: const TextStyle(color: AppColors.accent, fontSize: 12.5, height: 1.4),
              ),
            ],
          ],
        ),
      );
    });
  }
}

class _SavedBanner extends StatelessWidget {
  const _SavedBanner({required this.c, required this.r});

  final ReportsController c;
  final ReportSummary r;

  @override
  Widget build(BuildContext context) {
    return NoticeCard(
      icon: Icons.check_circle_rounded,
      color: AppColors.pass,
      title: 'Report ${r.id} saved',
      message: 'Grade ${r.grade.letter} · score ${r.score}. ${c.folderPath}',
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            onPressed: () => c.openPdf(r),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Open PDF'),
          ),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: () => c.reveal(r), child: const Text('Show in folder')),
        ],
      ),
    );
  }
}

class _History extends StatelessWidget {
  const _History({required this.c});

  final ReportsController c;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('History', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(width: 12),
            Obx(() => Text('${c.history.length} report${c.history.length == 1 ? '' : 's'}',
                style: const TextStyle(color: AppColors.muted, fontSize: 13))),
            const Spacer(),
            SizedBox(
              width: 260,
              child: TextField(
                onChanged: (v) => c.query.value = v,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Search reports',
                  prefixIcon: Icon(Icons.search_rounded, size: 20),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(tooltip: 'Open reports folder', onPressed: c.openFolder, icon: const Icon(Icons.folder_open_rounded)),
            IconButton(tooltip: 'Refresh', onPressed: c.refreshHistory, icon: const Icon(Icons.refresh_rounded)),
          ],
        ),
        const SizedBox(height: 12),
        Obx(() {
          final rows = c.filtered;
          if (c.history.isEmpty) {
            return const NoticeCard(
              icon: Icons.history_rounded,
              color: AppColors.primary,
              title: 'No reports yet',
              message: 'Run the tests, then create your first report above. Saved reports show up here.',
            );
          }
          if (rows.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('No report matches your search.', style: TextStyle(color: AppColors.muted)),
            );
          }
          return Column(
            children: [for (final r in rows) Padding(padding: const EdgeInsets.only(bottom: 10), child: _HistoryRow(c: c, r: r))],
          );
        }),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.c, required this.r});

  final ReportsController c;
  final ReportSummary r;

  @override
  Widget build(BuildContext context) {
    final color = gradeColor(r.grade);
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.16),
              border: Border.all(color: color, width: 1.6),
            ),
            child: Text(r.grade.letter, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.laptop, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                const SizedBox(height: 2),
                Text(
                  [r.id, if (r.serial.isNotEmpty) 'S/N ${r.serial}'].join('  ·  '),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(formatReportDate(r.createdAt), style: const TextStyle(fontSize: 12.5)),
                Text(
                  [if (r.customer != null) r.customer!, if (r.technician.isNotEmpty) 'by ${r.technician}'].join(' · '),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 92,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${r.score}/100', style: TextStyle(fontWeight: FontWeight.w800, color: color)),
                if (r.partial) const Text('partial', style: TextStyle(color: AppColors.accent, fontSize: 11.5)),
                if (!r.hasPdf) const Text('PDF missing', style: TextStyle(color: AppColors.fail, fontSize: 11.5)),
              ],
            ),
          ),
          Tooltip(
            message: r.hasPdf ? 'Open PDF' : 'Rebuild and open the PDF',
            child: FilledButton.tonalIcon(
              onPressed: () => c.openPdf(r),
              icon: Icon(r.hasPdf ? Icons.picture_as_pdf_rounded : Icons.build_rounded, size: 18),
              label: Text(r.hasPdf ? 'Open' : 'Rebuild'),
            ),
          ),
          IconButton(tooltip: 'Show in folder', onPressed: () => c.reveal(r), icon: const Icon(Icons.folder_open_rounded, size: 20)),
          IconButton(tooltip: 'View results', onPressed: () => showReportDetails(context, c, r), icon: const Icon(Icons.visibility_outlined, size: 20)),
          IconButton(
            tooltip: 'Delete',
            onPressed: () => _confirmDelete(context),
            icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.fail),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.navySoft,
        title: const Text('Delete this report?'),
        content: Text('${r.id} (${r.laptop}) and its PDF will be removed from this computer. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.fail),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await c.delete(r);
  }
}

/// In-app view of a saved report's results (from its JSON copy).
Future<void> showReportDetails(BuildContext context, ReportsController c, ReportSummary r) async {
  final data = await c.details(r.id);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: AppColors.navySoft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 680),
        child: data == null
            ? const Padding(padding: EdgeInsets.all(28), child: Text('The saved data for this report could not be read.'))
            : _DetailsBody(data: data),
      ),
    ),
  );
}

class _DetailsBody extends StatelessWidget {
  const _DetailsBody({required this.data});

  final ReportData data;

  @override
  Widget build(BuildContext context) {
    final color = gradeColor(data.grade);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data.laptopName, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                    Text('${data.id} · ${formatReportDate(data.createdAt)} · ${data.technician}',
                        style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                  ],
                ),
              ),
              Text('Grade ${data.grade.letter}  ${data.score}/100',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color)),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: ListView(
            padding: const EdgeInsets.all(20),
            shrinkWrap: true,
            children: [
              for (final t in data.tests)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          StatusChip(status: t.status),
                          const SizedBox(width: 10),
                          Text(t.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(width: 10),
                          Expanded(child: Text(t.headline, style: const TextStyle(color: AppColors.muted, fontSize: 12.5))),
                        ],
                      ),
                      for (final d in t.details)
                        Padding(
                          padding: const EdgeInsets.only(left: 6, top: 3),
                          child: Text('${d.label}: ${d.value}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
