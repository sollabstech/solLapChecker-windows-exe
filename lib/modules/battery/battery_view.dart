import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/app_modules.dart';
import '../../app/theme.dart';
import '../../controllers/app_controller.dart';
import '../../core/models/battery_info.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/module_scaffold.dart';
import '../../widgets/progress_ring.dart';
import 'battery_controller.dart';

class BatteryView extends StatefulWidget {
  const BatteryView({super.key});

  @override
  State<BatteryView> createState() => _BatteryViewState();
}

class _BatteryViewState extends State<BatteryView> {
  final c = Get.find<BatteryController>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => c.runIfNeeded());
  }

  @override
  Widget build(BuildContext context) {
    final app = Get.find<AppController>();
    final module = moduleById(ModuleId.battery);

    return Obx(() => ModuleScaffold(
          title: module.title,
          subtitle: module.subtitle,
          icon: module.icon,
          status: app.statusOf(ModuleId.battery),
          actions: [
            FilledButton.icon(
              onPressed: c.isRunning.value ? null : c.run,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(c.info.value == null ? 'Run test' : 'Run again'),
            ),
          ],
          child: _body(),
        ));
  }

  Widget _body() {
    final err = c.error.value;
    final info = c.info.value;

    if (c.isRunning.value && info == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    if (err != null) {
      return NoticeCard(
        icon: Icons.error_outline_rounded,
        color: AppColors.fail,
        title: 'Battery check failed',
        message: err,
      );
    }
    if (info == null) {
      return const NoticeCard(
        icon: Icons.battery_unknown_rounded,
        color: AppColors.primary,
        title: 'Ready to check the battery',
        message: 'Press "Run test" to read design capacity, current capacity and cycle count.',
      );
    }
    if (!info.present) {
      return const NoticeCard(
        icon: Icons.battery_alert_rounded,
        title: 'No battery detected',
        message:
            'Windows reports no battery. The battery may be removed, completely dead, or this is not a laptop. '
            'Ask the seller about it before buying.',
      );
    }
    return _Result(info: info);
  }
}

Color _gradeColor(BatteryGrade? g) => switch (g) {
      BatteryGrade.good => AppColors.pass,
      BatteryGrade.fair => AppColors.accent,
      BatteryGrade.replace => AppColors.fail,
      null => AppColors.muted,
    };

String _gradeMessage(BatteryGrade? g) => switch (g) {
      BatteryGrade.good => 'The battery holds most of its original capacity.',
      BatteryGrade.fair => 'Noticeably worn. Expect shorter runtime than a new laptop.',
      BatteryGrade.replace => 'Heavily worn. A replacement battery is recommended.',
      null => 'Windows did not report both capacity values, so health cannot be calculated.',
    };

class _Result extends StatelessWidget {
  const _Result({required this.info});

  final BatteryInfo info;

  String _mwh(int? v) => v == null ? 'N/A' : _group(v);

  /// 47,000 style thousands separator without pulling in intl.
  String _group(int v) => v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

  @override
  Widget build(BuildContext context) {
    final health = info.healthPercent;
    final grade = info.grade;
    final color = _gradeColor(grade);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassCard(
          glow: color,
          padding: const EdgeInsets.all(28),
          child: Row(
            children: [
              ProgressRing(
                value: (health ?? 0) / 100,
                size: 150,
                strokeWidth: 13,
                color: color,
                endColor: color,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      health == null ? '—' : '$health%',
                      style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
                    ),
                    const Text('health', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 32),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      grade == null ? 'Health unavailable' : grade.label,
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: color),
                    ),
                    const SizedBox(height: 6),
                    Text(_gradeMessage(grade), style: const TextStyle(color: AppColors.muted, height: 1.4)),
                    const SizedBox(height: 16),
                    const Wrap(
                      spacing: 18,
                      runSpacing: 6,
                      children: [
                        _Legend('≥ 80%  Good', AppColors.pass),
                        _Legend('60–79%  Fair', AppColors.accent),
                        _Legend('< 60%  Replace', AppColors.fail),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        TileGrid(children: [
          StatTile(label: 'Design capacity', value: _mwh(info.designMWh), unit: info.designMWh == null ? null : 'mWh'),
          StatTile(
            label: 'Full charge capacity',
            value: _mwh(info.fullChargeMWh),
            unit: info.fullChargeMWh == null ? null : 'mWh',
            color: color,
          ),
          StatTile(
            label: 'Cycle count',
            value: info.cycleCount?.toString() ?? 'N/A',
            hint: info.cycleCount == null ? 'This laptop does not report a cycle count.' : null,
          ),
          StatTile(label: 'Current charge', value: info.chargePercent == null ? 'N/A' : '${info.chargePercent}', unit: info.chargePercent == null ? null : '%'),
          StatTile(label: 'Status', value: info.chargeState.label),
          StatTile(label: 'Manufacturer', value: info.manufacturer ?? 'Unknown'),
        ]),
        if (info.source == BatterySource.powercfg)
          const Padding(
            padding: EdgeInsets.only(top: 14),
            child: Text(
              'Capacity values were read from the Windows battery report (powercfg).',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 7),
          Text(text, style: const TextStyle(fontSize: 12.5)),
        ],
      );
}
