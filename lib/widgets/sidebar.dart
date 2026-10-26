import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../app/app_modules.dart';
import '../app/theme.dart';
import '../controllers/app_controller.dart';
import 'status_icon.dart';

/// Left navigation: dashboard, every test with its live status, and history.
class AppSidebar extends GetView<AppController> {
  const AppSidebar({super.key});

  static const width = 272.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: AppColors.navyDeep,
        border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 14),
          _NavItem(module: dashboardModule),
          const _SectionLabel('TESTS'),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [for (final m in testModules) _NavItem(module: m)],
            ),
          ),
          const _SectionLabel('REPORTS'),
          _NavItem(module: reportsModule),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            letterSpacing: 1.6,
            fontWeight: FontWeight.w700,
            color: AppColors.muted,
          ),
        ),
      );
}

class _NavItem extends GetView<AppController> {
  const _NavItem({required this.module});

  final ModuleDef module;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final selected = controller.selected.value == module.id;
      final status = module.isTest ? controller.statusOf(module.id) : null;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            hoverColor: Colors.white.withValues(alpha: 0.05),
            onTap: () => controller.select(module.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: selected ? AppColors.primary.withValues(alpha: 0.16) : Colors.transparent,
                border: Border.all(
                  color: selected ? AppColors.primary.withValues(alpha: 0.5) : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    module.icon,
                    size: 20,
                    color: selected ? AppColors.primary : AppColors.muted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          module.title,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected ? Colors.white : AppColors.text,
                          ),
                        ),
                        if (status != null)
                          Text(
                            status.label,
                            style: TextStyle(fontSize: 11, color: status.color),
                          ),
                      ],
                    ),
                  ),
                  if (status != null) StatusIcon(status: status),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

