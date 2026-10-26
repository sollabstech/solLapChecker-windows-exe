import 'package:flutter/material.dart';

import '../../app/app_modules.dart';
import '../../app/theme.dart';
import '../../widgets/glass_card.dart';

/// Stand-in screen for modules that are delivered in a later build phase.
class ModulePlaceholderView extends StatelessWidget {
  const ModulePlaceholderView({super.key, required this.module});

  final ModuleDef module;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(module.icon, size: 56, color: AppColors.primary),
            const SizedBox(height: 18),
            Text(module.title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(module.subtitle, style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
              ),
              child: Text(
                'Coming in Phase ${module.phase}',
                style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
