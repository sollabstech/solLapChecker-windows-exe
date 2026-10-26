import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/app_modules.dart';
import '../../app/theme.dart';
import '../../controllers/app_controller.dart';
import '../../core/models/stress.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/module_scaffold.dart';
import '../../widgets/stress_panel.dart';
import '../stress/stress_notices.dart';
import 'gpu_controller.dart';

class GpuView extends StatefulWidget {
  const GpuView({super.key});

  @override
  State<GpuView> createState() => _GpuViewState();
}

class _GpuViewState extends State<GpuView> {
  final c = Get.find<GpuController>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => c.loadInfo());
  }

  @override
  Widget build(BuildContext context) {
    final app = Get.find<AppController>();
    final module = moduleById(ModuleId.gpu);

    return Obx(() {
      final running = c.runner.isRunning.value;
      return ModuleScaffold(
        title: module.title,
        subtitle: module.subtitle,
        icon: module.icon,
        status: app.statusOf(ModuleId.gpu),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _body(running),
            if (c.runner.error.value != null) ...[
              const SizedBox(height: 16),
              StressErrorNotice(
                code: c.runner.errorCode.value,
                message: c.runner.error.value!,
                pawnIo: c.info.value?.pawnIo,
              ),
            ],
            const SizedBox(height: 20),
            StressPanel(runner: c.runner, part: 'graphics card'),
          ],
        ),
      );
    });
  }

  Widget _body(bool running) {
    if (c.isLoadingInfo.value && c.info.value == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    final err = c.infoError.value;
    if (err != null) {
      return StressErrorNotice(
        code: err.contains('SolHelper.exe was not found') ? 'helper-missing' : null,
        message: err,
      );
    }
    final gpus = c.gpus;
    if (gpus.isEmpty) {
      return const NoticeCard(
        icon: Icons.developer_board_off_rounded,
        title: 'No GPU found',
        message: 'Windows did not report a graphics adapter that can run the compute test.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassCard(
          child: Row(
            children: [
              const Text('Duration', style: TextStyle(color: AppColors.muted, fontSize: 13)),
              const SizedBox(width: 14),
              for (final m in GpuController.durationOptions) ...[
                ChoiceChip(
                  label: Text('$m min'),
                  selected: c.durationMin.value == m,
                  onSelected: running ? null : (_) => c.setDuration(m),
                ),
                const SizedBox(width: 8),
              ],
              const Spacer(),
              Text(
                'Stops by itself at ${GpuController.safetyLimitC} °C',
                style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
              ),
              if (gpus.length > 1) ...[
                const SizedBox(width: 16),
                FilledButton.icon(
                  onPressed: running ? null : c.startAll,
                  icon: const Icon(Icons.playlist_play_rounded, size: 20),
                  label: const Text('Test all GPUs'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        for (final g in gpus) ...[
          _GpuCard(gpu: g, c: c, running: running),
          const SizedBox(height: 12),
        ],
        if (c.info.value?.pawnIo == false && gpus.any((g) => !g.hasTempSensor))
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Some GPUs have no readable temperature. Installing the PawnIO sensor driver usually fixes this.',
              style: TextStyle(color: AppColors.accent, fontSize: 12.5),
            ),
          ),
      ],
    );
  }
}

class _GpuCard extends StatelessWidget {
  const _GpuCard({required this.gpu, required this.c, required this.running});

  final GpuDevice gpu;
  final GpuController c;
  final bool running;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final result = c.results[gpu.index];
      final active = running && c.activeIndex.value == gpu.index;
      final color = result?.status.color ?? AppColors.primary;

      return GlassCard(
        glow: active ? AppColors.primary : null,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                gpu.integrated ? Icons.memory_rounded : Icons.videogame_asset_rounded,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(gpu.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 3),
                  Text(
                    [
                      gpu.kind,
                      if (!gpu.integrated && gpu.dedicatedMb > 0) '${(gpu.dedicatedMb / 1024).toStringAsFixed(0)} GB VRAM',
                      if (!gpu.hasTempSensor) 'no temperature sensor'
                      else if (!gpu.hasOwnTempSensor) 'temperature from CPU package',
                    ].join('  ·  '),
                    style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                  ),
                  if (result != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${result.status.label}'
                      '${result.maxTempC == null ? '' : ' · max ${result.maxTempC!.toStringAsFixed(0)} °C'}'
                      '${result.reason == StressEndReason.safety ? ' · stopped for safety' : ''}',
                      style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5),
                    ),
                  ],
                ],
              ),
            ),
            if (active)
              OutlinedButton.icon(
                onPressed: c.stop,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.fail,
                  side: const BorderSide(color: AppColors.fail),
                ),
                icon: const Icon(Icons.stop_rounded, size: 18),
                label: const Text('Stop'),
              )
            else
              FilledButton.tonalIcon(
                onPressed: running ? null : () => c.start(gpu),
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: Text(result == null ? 'Test' : 'Run again'),
              ),
          ],
        ),
      );
    });
  }
}
