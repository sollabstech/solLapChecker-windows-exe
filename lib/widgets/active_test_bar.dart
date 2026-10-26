import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../app/app_modules.dart';
import '../app/theme.dart';
import '../controllers/app_controller.dart';

/// Red strip shown on every screen while a stress test runs, so the
/// Stop button is always one click away.
class ActiveTestBar extends GetView<AppController> {
  const ActiveTestBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Reading statuses subscribes this widget to status changes.
      final _ = controller.statuses.length;
      final id = controller.runningStress;
      if (id == null) return const SizedBox.shrink();
      final title = moduleById(id).title;

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.fail.withValues(alpha: 0.16),
          border: Border(bottom: BorderSide(color: AppColors.fail.withValues(alpha: 0.4))),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.fail),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$title is running and will stop automatically if the laptop gets too hot.',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            FilledButton.icon(
              onPressed: controller.stopRunning,
              style: FilledButton.styleFrom(backgroundColor: AppColors.fail),
              icon: const Icon(Icons.stop_rounded, size: 18),
              label: const Text('Stop'),
            ),
          ],
        ),
      );
    });
  }
}
