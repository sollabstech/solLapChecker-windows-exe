import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/app_modules.dart';
import '../../app/theme.dart';
import '../../controllers/app_controller.dart';
import '../../core/models/drive_health.dart';
import '../../core/utils/format.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/module_scaffold.dart';
import '../../widgets/progress_ring.dart';
import 'storage_controller.dart';

class StorageView extends StatefulWidget {
  const StorageView({super.key});

  @override
  State<StorageView> createState() => _StorageViewState();
}

class _StorageViewState extends State<StorageView> {
  final c = Get.find<StorageController>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => c.runIfNeeded());
  }

  @override
  Widget build(BuildContext context) {
    final app = Get.find<AppController>();
    final module = moduleById(ModuleId.storage);

    return Obx(() => ModuleScaffold(
          title: module.title,
          subtitle: module.subtitle,
          icon: module.icon,
          status: app.statusOf(ModuleId.storage),
          actions: [
            FilledButton.icon(
              onPressed: c.isRunning.value ? null : c.run,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(c.hasRun.value ? 'Run again' : 'Run test'),
            ),
          ],
          child: _body(),
        ));
  }

  Widget _body() {
    if (c.isRunning.value && !c.hasRun.value) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppColors.primary),
              SizedBox(height: 16),
              Text('Reading SMART data…', style: TextStyle(color: AppColors.muted)),
            ],
          ),
        ),
      );
    }
    final err = c.error.value;
    if (err != null) {
      return NoticeCard(
        icon: c.toolMissing.value ? Icons.build_circle_outlined : Icons.error_outline_rounded,
        color: AppColors.fail,
        title: c.toolMissing.value ? 'smartctl.exe is missing' : 'Storage check failed',
        message: c.toolMissing.value
            ? 'The SMART reader (tools\\smartctl.exe) is not installed next to the app. '
                'Reinstall SolLapChecker, or see tools/README.md for how to add it.\n$err'
            : err,
      );
    }
    if (!c.hasRun.value) {
      return const NoticeCard(
        icon: Icons.storage_rounded,
        color: AppColors.primary,
        title: 'Ready to check your drives',
        message: 'Press "Run test" to read SMART health, wear, temperature and error counters for every drive.',
      );
    }
    if (c.drives.isEmpty) {
      return const NoticeCard(
        icon: Icons.search_off_rounded,
        title: 'No drives could be read',
        message:
            'smartctl found no drive with readable SMART data. Make sure SolLapChecker is running as '
            'Administrator, then run the test again.',
      );
    }
    return Column(
      children: [
        for (final d in c.drives) ...[
          _DriveCard(drive: d),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}

Color _verdictColor(DriveVerdict v) => v.status.color;

class _DriveCard extends StatelessWidget {
  const _DriveCard({required this.drive});

  final DriveHealth drive;

  @override
  Widget build(BuildContext context) {
    final verdict = drive.verdict;
    final color = _verdictColor(verdict);
    final health = drive.healthPercent;

    String? na(int? v, {String Function(int)? f}) => v == null ? null : (f ?? (x) => '$x')(v);

    final bad = AppColors.fail;
    final warn = AppColors.accent;

    return GlassCard(
      glow: color,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProgressRing(
                value: (health ?? 0) / 100,
                size: 96,
                strokeWidth: 9,
                color: color,
                endColor: color,
                child: Text(
                  health == null ? 'N/A' : '$health%',
                  style: TextStyle(fontSize: health == null ? 16 : 22, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 22),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(drive.model, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      [
                        drive.type.label,
                        if (drive.capacityBytes != null) formatCapacity(drive.capacityBytes!),
                        if (drive.serial != null) 'S/N ${drive.serial}',
                      ].join('  ·  '),
                      style: const TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              StatusChip(status: verdict.status, label: verdict.label),
            ],
          ),
          const SizedBox(height: 20),
          TileGrid(minTileWidth: 170, children: [
            StatTile(
              label: 'Life used',
              value: na(drive.percentUsed) ?? 'N/A',
              unit: drive.percentUsed == null ? null : '%',
              hint: drive.percentUsed == null ? 'This drive does not report wear.' : null,
            ),
            StatTile(
              label: 'Data written (TBW)',
              value: drive.bytesWritten == null ? 'N/A' : formatWritten(drive.bytesWritten!),
            ),
            StatTile(
              label: 'Power-on hours',
              value: na(drive.powerOnHours, f: groupThousands) ?? 'N/A',
              unit: drive.powerOnHours == null ? null : 'h',
              hint: drive.powerOnHours == null ? null : '≈ ${(drive.powerOnHours! / 24).round()} days of use',
            ),
            StatTile(label: 'Power cycles', value: na(drive.powerCycles, f: groupThousands) ?? 'N/A'),
            StatTile(
              label: 'Temperature',
              value: na(drive.temperatureC) ?? 'N/A',
              unit: drive.temperatureC == null ? null : '°C',
              color: (drive.temperatureC ?? 0) >= 70 ? warn : null,
            ),
            StatTile(
              label: 'Unsafe shutdowns',
              value: na(drive.unsafeShutdowns, f: groupThousands) ?? 'N/A',
            ),
            StatTile(
              label: 'Media errors',
              value: na(drive.mediaErrors) ?? 'N/A',
              color: (drive.mediaErrors ?? 0) > 0 ? bad : null,
            ),
            StatTile(
              label: 'Reallocated sectors',
              value: na(drive.reallocatedSectors) ?? 'N/A',
              color: (drive.reallocatedSectors ?? 0) > 0 ? bad : null,
              hint: drive.type == DriveType.nvme ? 'Not applicable to NVMe drives.' : null,
            ),
          ]),
          if (drive.issues.isNotEmpty) ...[
            const SizedBox(height: 18),
            for (final i in drive.issues)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      i.severity == DriveVerdict.bad ? Icons.cancel_rounded : Icons.warning_amber_rounded,
                      size: 18,
                      color: _verdictColor(i.severity),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(i.message, style: const TextStyle(fontSize: 13))),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
