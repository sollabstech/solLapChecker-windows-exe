import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/app_modules.dart';
import '../../app/theme.dart';
import '../../controllers/app_controller.dart';
import '../../core/utils/format.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/module_scaffold.dart';
import '../../widgets/stress_panel.dart';
import '../stress/stress_notices.dart';
import 'cpu_controller.dart';

class CpuView extends StatefulWidget {
  const CpuView({super.key});

  @override
  State<CpuView> createState() => _CpuViewState();
}

class _CpuViewState extends State<CpuView> {
  final c = Get.find<CpuController>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await c.loadInfo();
      await c.runIfNeeded();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = Get.find<AppController>();
    final module = moduleById(ModuleId.cpu);

    return Obx(() {
      return ModuleScaffold(
        title: module.title,
        subtitle: module.subtitle,
        icon: module.icon,
        status: app.statusOf(ModuleId.cpu),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Setup(c: c),
            if (c.runner.error.value != null) ...[
              const SizedBox(height: 16),
              StressErrorNotice(
                code: c.runner.errorCode.value,
                message: c.runner.error.value!,
                pawnIo: c.info.value?.pawnIo,
              ),
            ],
            const SizedBox(height: 20),
            StressPanel(runner: c.runner, part: 'processor', showTemperature: false),
          ],
        ),
      );
    });
  }
}

class _Setup extends StatelessWidget {
  const _Setup({required this.c});

  final CpuController c;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final running = c.runner.isRunning.value;
      final name = c.info.value?.cpuName ?? c.runner.device.value;
      return GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.memory_rounded, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name ?? 'Processor',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Puts every core under full load for the chosen time, with a countdown. '
              'The test stops by itself if the laptop gets too hot.',
              style: const TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Duration', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(width: 14),
                for (final m in CpuController.durationOptions) ...[
                  ChoiceChip(
                    label: Text(formatDurationChoice(m)),
                    selected: c.durationMin.value == m,
                    onSelected: running ? null : (_) => c.setDuration(m),
                  ),
                  const SizedBox(width: 8),
                ],
                const Spacer(),
                if (running)
                  OutlinedButton.icon(
                    onPressed: c.stop,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.fail,
                      side: const BorderSide(color: AppColors.fail),
                    ),
                    icon: const Icon(Icons.stop_rounded, size: 18),
                    label: const Text('Stop test'),
                  )
                else
                  FilledButton.icon(
                    onPressed: c.start,
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: Text(c.runner.summary.value == null ? 'Start stress test' : 'Run again'),
                  ),
              ],
            ),
          ],
        ),
      );
    });
  }
}
