import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../app/theme.dart';
import '../core/models/stress.dart';
import '../core/models/test_status.dart';
import '../modules/stress/stress_runner.dart';
import 'glass_card.dart';
import 'live_chart.dart';
import 'module_scaffold.dart';

/// Live view of a running (or finished) stress test: progress, key figures,
/// three charts and the verdict. Used by both the CPU and GPU screens.
class StressPanel extends StatelessWidget {
  const StressPanel({super.key, required this.runner, required this.part, this.showClockPower = true});

  final StressRunner runner;

  /// "processor" / "graphics card": used in result wording.
  final String part;
  final bool showClockPower;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final samples = runner.samples.toList();
      final summary = runner.summary.value;
      final planned = runner.plannedSec.value;
      final running = runner.isRunning.value;

      if (samples.isEmpty && summary == null && !running) return const SizedBox.shrink();

      final temps = samples.map((s) => s.tempC).toList();
      final lastTemp = temps.isEmpty ? null : temps.last;
      final nonNull = temps.whereType<double>().toList();
      final maxTemp = nonNull.isEmpty ? null : nonNull.reduce((a, b) => a > b ? a : b);
      final avgTemp = nonNull.isEmpty ? null : nonNull.reduce((a, b) => a + b) / nonNull.length;
      final last = samples.isEmpty ? null : samples.last;
      final limit = runner.limitC.value;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (running || summary == null) _Progress(elapsed: samples.length, planned: planned),
          const SizedBox(height: 16),
          TileGrid(minTileWidth: 150, children: [
            StatTile(
              label: 'Temperature',
              value: lastTemp == null ? '—' : lastTemp.toStringAsFixed(0),
              unit: '°C',
              color: _tempColor(lastTemp, limit),
            ),
            StatTile(label: 'Max', value: maxTemp == null ? '—' : maxTemp.toStringAsFixed(0), unit: '°C', color: _tempColor(maxTemp, limit)),
            StatTile(label: 'Average', value: avgTemp == null ? '—' : avgTemp.toStringAsFixed(0), unit: '°C'),
            if (showClockPower)
              StatTile(label: 'Clock', value: last?.clockMhz == null ? '—' : last!.clockMhz!.toStringAsFixed(0), unit: 'MHz'),
            StatTile(label: 'Load', value: last?.loadPct == null ? '—' : last!.loadPct!.toStringAsFixed(0), unit: '%'),
            _ThrottleTile(summary: summary, running: running),
          ]),
          const SizedBox(height: 16),
          LiveChart(
            title: 'Temperature',
            values: temps,
            totalSeconds: planned,
            minY: 20,
            maxY: 100,
            color: AppColors.accent,
            current: lastTemp == null ? null : '${lastTemp.toStringAsFixed(0)} °C',
            threshold: limit,
            thresholdLabel: 'Safety limit ${limit.toStringAsFixed(0)} °C',
            height: 210,
          ),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, c) {
            final clock = _clockChart(samples, planned);
            final load = LiveChart(
              title: 'Load',
              values: samples.map((s) => s.loadPct).toList(),
              totalSeconds: planned,
              minY: 0,
              maxY: 100,
              color: AppColors.pass,
              current: last?.loadPct == null ? null : '${last!.loadPct!.toStringAsFixed(0)} %',
              height: 130,
            );
            if (c.maxWidth < 760) return Column(children: [clock, const SizedBox(height: 14), load]);
            return Row(children: [Expanded(child: clock), const SizedBox(width: 14), Expanded(child: load)]);
          }),
          if (runner.warnings.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final w in runner.warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('⚠ $w', style: const TextStyle(color: AppColors.accent, fontSize: 12.5)),
              ),
          ],
          if (summary != null) ...[
            const SizedBox(height: 16),
            _SummaryCard(summary: summary, part: part),
          ],
        ],
      );
    });
  }

  Widget _clockChart(List<StressSample> samples, int planned) {
    final clocks = samples.map((s) => s.clockMhz).toList();
    final vals = clocks.whereType<double>().toList();
    var lo = vals.isEmpty ? 0.0 : vals.reduce((a, b) => a < b ? a : b);
    var hi = vals.isEmpty ? 1000.0 : vals.reduce((a, b) => a > b ? a : b);
    if (hi - lo < 200) {
      lo = (lo - 100).clamp(0, double.infinity);
      hi = hi + 100;
    }
    lo = (lo * 0.9).floorToDouble();
    hi = (hi * 1.05).ceilToDouble();
    final last = clocks.isEmpty ? null : clocks.last;
    return LiveChart(
      title: 'Clock speed',
      values: clocks,
      totalSeconds: planned,
      minY: lo,
      maxY: hi,
      color: AppColors.primary,
      current: last == null ? null : '${last.toStringAsFixed(0)} MHz',
      height: 130,
    );
  }

  Color? _tempColor(double? t, double limit) {
    if (t == null) return null;
    if (t >= limit - 5) return AppColors.fail;
    if (t >= StressSummary.hotWarningC - 5) return AppColors.accent;
    return null;
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.elapsed, required this.planned});

  final int elapsed;
  final int planned;

  @override
  Widget build(BuildContext context) {
    final p = planned <= 0 ? 0.0 : (elapsed / planned).clamp(0.0, 1.0);
    final remaining = (planned - elapsed).clamp(0, planned);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Elapsed ${formatMmSs(elapsed)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const Spacer(),
            Text('${formatMmSs(remaining)} remaining', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: p,
            minHeight: 8,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }
}

class _ThrottleTile extends StatelessWidget {
  const _ThrottleTile({required this.summary, required this.running});

  final StressSummary? summary;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    if (s == null) {
      return StatTile(label: 'Throttling', value: running ? 'Checking…' : '—');
    }
    if (s.throttled) {
      return StatTile(label: 'Throttling', value: 'Thermal', color: AppColors.fail, hint: s.throttleNote);
    }
    if (s.powerLimited) {
      return StatTile(label: 'Throttling', value: 'Power limit', color: AppColors.accent, hint: s.throttleNote);
    }
    return const StatTile(label: 'Throttling', value: 'None', color: AppColors.pass);
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary, required this.part});

  final StressSummary summary;
  final String part;

  @override
  Widget build(BuildContext context) {
    final status = summary.status;
    final safety = summary.reason == StressEndReason.safety;
    final color = safety ? AppColors.fail : status.color;
    final title = switch (summary.reason) {
      StressEndReason.safety => 'Stopped for safety',
      StressEndReason.stopped => 'Stopped early',
      StressEndReason.error => 'Test failed',
      StressEndReason.completed => switch (status) {
          TestStatus.pass => 'Passed',
          TestStatus.warning => 'Completed with a warning',
          _ => 'Completed',
        },
    };

    return GlassCard(
      glow: color,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            safety ? Icons.local_fire_department_rounded : Icons.fact_check_rounded,
            color: color,
            size: 30,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
                const SizedBox(height: 4),
                Text(describeStressSummary(summary, part: part), style: const TextStyle(height: 1.4, fontSize: 13.5)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 22,
                  runSpacing: 4,
                  children: [
                    if (summary.maxTempC != null) _Fact('Max', '${summary.maxTempC!.toStringAsFixed(0)} °C'),
                    if (summary.avgTempC != null) _Fact('Average', '${summary.avgTempC!.toStringAsFixed(0)} °C'),
                    if (summary.maxClockMhz != null) _Fact('Peak clock', '${summary.maxClockMhz!.toStringAsFixed(0)} MHz'),
                    if (summary.minClockMhz != null) _Fact('Lowest clock', '${summary.minClockMhz!.toStringAsFixed(0)} MHz'),
                    _Fact('Duration', formatMmSs(summary.elapsedSec)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Text.rich(
        TextSpan(children: [
          TextSpan(text: '$label  ', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
          TextSpan(text: value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
        ]),
      );
}
