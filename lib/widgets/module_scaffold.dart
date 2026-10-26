import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../app/theme.dart';
import '../controllers/app_controller.dart';
import '../core/models/test_status.dart';
import 'glass_card.dart';

/// Common frame for every test screen: title, status chip, action buttons,
/// the screen body, and the wizard's "Continue" footer.
class ModuleScaffold extends StatelessWidget {
  const ModuleScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.status,
    required this.child,
    this.actions = const [],
    this.statusChip = true,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final TestStatus status;
  final Widget child;
  final List<Widget> actions;

  /// Hide the status pill for screens that are not tests (e.g. Reports).
  final bool statusChip;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(icon, size: 28, color: AppColors.primary),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                          Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                        ],
                      ),
                    ),
                    if (statusChip) StatusChip(status: status),
                    for (final a in actions) ...[const SizedBox(width: 10), a],
                  ],
                ),
                const SizedBox(height: 24),
                child,
              ],
            ),
          ),
        ),
        const _WizardFooter(),
      ],
    );
  }
}

/// Rounded pill showing a [TestStatus] in its colour.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status, this.label});

  final TestStatus status;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: status.color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label ?? status.label,
        style: TextStyle(color: status.color, fontWeight: FontWeight.w700, fontSize: 12.5),
      ),
    );
  }
}

/// Appears while the guided wizard is active and the current test has a result.
class _WizardFooter extends GetView<AppController> {
  const _WizardFooter();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final show = controller.wizardActive.value &&
          controller.statusOf(controller.currentWizardStep.id).isFinished &&
          controller.selected.value == controller.currentWizardStep.id;
      if (!show) return const SizedBox.shrink();

      final last = controller.wizardIndex.value >= controller.wizardSteps.length - 1;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.navyDeep,
          border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FilledButton.icon(
              onPressed: controller.nextStep,
              icon: Icon(last ? Icons.flag_rounded : Icons.arrow_forward_rounded),
              label: Text(last ? 'Finish' : 'Continue to next test'),
            ),
          ],
        ),
      );
    });
  }
}

/// Small "label / big value" tile used in metric grids.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.color,
    this.hint,
  });

  final String label;
  final String value;
  final String? unit;
  final Color? color;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final tile = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color ?? AppColors.text),
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(unit!, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ],
          ),
        ],
      ),
    );
    return hint == null ? tile : Tooltip(message: hint!, child: tile);
  }
}

/// Lays [children] out in a responsive grid of equal-width cells.
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.children, this.minTileWidth = 190});

  final List<Widget> children;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      const gap = 12.0;
      final cols = (c.maxWidth / (minTileWidth + gap)).floor().clamp(1, 6);
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final ch in children) SizedBox(width: w, child: ch)],
      );
    });
  }
}

/// Centered message card for "no battery", "tool missing" and similar states.
class NoticeCard extends StatelessWidget {
  const NoticeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.color = AppColors.accent,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      glow: color,
      child: Row(
        children: [
          Icon(icon, size: 36, color: color),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(message, style: const TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4)),
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: 16), action!],
        ],
      ),
    );
  }
}
