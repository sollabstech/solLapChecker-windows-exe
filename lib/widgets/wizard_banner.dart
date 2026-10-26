import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../app/theme.dart';
import '../controllers/app_controller.dart';

/// Strip shown above the content while the guided "Run Full Test" wizard runs.
class WizardBanner extends GetView<AppController> {
  const WizardBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (!controller.wizardActive.value) return const SizedBox.shrink();

      final step = controller.currentWizardStep;
      final index = controller.wizardIndex.value;
      final total = controller.wizardSteps.length;

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.14),
          border: Border(bottom: BorderSide(color: AppColors.primary.withValues(alpha: 0.35))),
        ),
        child: Row(
          children: [
            const Icon(Icons.route_rounded, size: 20, color: AppColors.primary),
            const SizedBox(width: 12),
            Text(
              'Guided test · Step ${index + 1} of $total',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(width: 10),
            Text(step.title, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            const Spacer(),
            TextButton(onPressed: controller.nextStep, child: const Text('Skip')),
            const SizedBox(width: 6),
            OutlinedButton(
              onPressed: controller.stopWizard,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.fail,
                side: const BorderSide(color: AppColors.fail),
              ),
              child: const Text('Stop'),
            ),
          ],
        ),
      );
    });
  }
}
