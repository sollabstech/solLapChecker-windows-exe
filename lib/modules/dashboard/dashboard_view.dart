import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/theme.dart';
import '../../controllers/app_controller.dart';
import '../../core/models/system_info.dart';
import '../../core/models/test_status.dart';
import '../../core/utils/format.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/progress_ring.dart';
import 'dashboard_controller.dart';

/// Landing screen: system information, overall progress and "Run Full Test".
class DashboardView extends GetView<DashboardController> {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    final app = Get.find<AppController>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(onRun: app.startFullTest, onRefresh: controller.load),
          const SizedBox(height: 24),
          Obx(() {
            if (controller.isLoading.value && controller.info.value == null) {
              return const _Loading();
            }
            final err = controller.error.value;
            if (err != null && controller.info.value == null) {
              return _ErrorCard(message: err, onRetry: controller.load);
            }
            final info = controller.info.value;
            if (info == null) return const SizedBox.shrink();
            return _Content(info: info, fallbackResolution: controller.fallbackResolution);
          }),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onRun, required this.onRefresh});

  final VoidCallback onRun;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Dashboard', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
              SizedBox(height: 4),
              Text(
                'Check a laptop before you buy or sell it.',
                style: TextStyle(color: AppColors.muted, fontSize: 14),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Refresh system info',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded, color: AppColors.muted),
        ),
        const SizedBox(width: 8),
        _RunButton(onTap: onRun),
      ],
    );
  }
}

/// The big call-to-action; the glow pulses gently to draw the eye.
class _RunButton extends StatefulWidget {
  const _RunButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_RunButton> createState() => _RunButtonState();
}

class _RunButtonState extends State<_RunButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  bool _hover = false;

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) => AnimatedScale(
            scale: _hover ? 1.04 : 1,
            duration: const Duration(milliseconds: 150),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                gradient: const LinearGradient(colors: [AppColors.primary, Color(0xFF3AA6FF)]),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35 + 0.3 * _pulse.value),
                    blurRadius: 22 + 18 * _pulse.value,
                    spreadRadius: -2,
                  ),
                ],
              ),
              child: child,
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_arrow_rounded, size: 26, color: Colors.white),
              SizedBox(width: 8),
              Text(
                'Run Full Test',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.info, required this.fallbackResolution});

  final SystemInfo info;
  final String? fallbackResolution;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _InfoCard(
        icon: Icons.memory_rounded,
        title: 'Processor',
        rows: [
          _Row('Model', info.cpu.name),
          _Row('Cores', info.cpu.summary),
        ],
      ),
      _InfoCard(
        icon: Icons.developer_board_rounded,
        title: info.gpus.length > 1 ? 'Graphics (${info.gpus.length})' : 'Graphics',
        rows: info.gpus.isEmpty
            ? [const _Row('GPU', 'Not detected')]
            : [for (final g in info.gpus) _Row('GPU', g.name, sub: 'Driver ${g.driver}')],
      ),
      _InfoCard(
        icon: Icons.sd_card_rounded,
        title: 'Memory',
        rows: [
          _Row('Installed', info.ramSummary),
          _Row('Modules', info.ramModules.isEmpty ? 'Unknown' : '${info.ramModules.length}'),
        ],
      ),
      _InfoCard(
        icon: Icons.storage_rounded,
        title: 'Storage',
        rows: [
          _Row('Total', info.storageSummary),
          for (final d in info.drives) _Row('Drive', d.model, sub: formatCapacity(d.sizeBytes)),
        ],
      ),
      _InfoCard(
        icon: Icons.monitor_rounded,
        title: 'Display & System',
        rows: [
          _Row('Resolution', info.displayResolution ?? fallbackResolution ?? 'Unknown'),
          _Row('Windows', info.windows),
        ],
      ),
      _InfoCard(
        icon: Icons.memory_outlined,
        title: 'BIOS',
        rows: [
          _Row('Version', info.biosVersion),
          _Row('Date', info.biosDate.isEmpty ? 'Unknown' : info.biosDate),
        ],
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Hero(info: info),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, c) {
            final columns = c.maxWidth >= 900 ? 2 : 1;
            const gap = 20.0;
            final w = (c.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [for (final card in cards) SizedBox(width: w, child: card)],
            );
          },
        ),
      ],
    );
  }
}

/// Device identity plus overall test progress.
class _Hero extends StatelessWidget {
  const _Hero({required this.info});
  final SystemInfo info;

  @override
  Widget build(BuildContext context) {
    final app = Get.find<AppController>();

    return GlassCard(
      glow: AppColors.primary,
      padding: const EdgeInsets.all(28),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.brand.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  info.model,
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.15),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(Icons.tag_rounded, size: 16, color: AppColors.muted),
                    const SizedBox(width: 6),
                    const Text('Serial', style: TextStyle(color: AppColors.muted)),
                    const SizedBox(width: 8),
                    SelectableText(
                      info.serialNumber,
                      style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Obx(() {
            final done = app.finishedCount;
            return Row(
              children: [
                ProgressRing(
                  value: app.progress,
                  size: 120,
                  strokeWidth: 11,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$done/${app.totalTests}',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                      ),
                      const Text('tests', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                    ],
                  ),
                ),
                const SizedBox(width: 22),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final s in [TestStatus.pass, TestStatus.warning, TestStatus.fail])
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${app.countOf(s)} ${s.label.toLowerCase()}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _Row {
  const _Row(this.label, this.value, {this.sub});
  final String label;
  final String value;
  final String? sub;
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.title, required this.rows});

  final IconData icon;
  final String title;
  final List<_Row> rows;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 14),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(r.label, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.value, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                        if (r.sub != null)
                          Text(r.sub!, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppColors.primary),
              SizedBox(height: 16),
              Text('Reading system information…', style: TextStyle(color: AppColors.muted)),
            ],
          ),
        ),
      );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => GlassCard(
        glow: AppColors.fail,
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.fail, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Could not read system information',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(message, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                ],
              ),
            ),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
}
