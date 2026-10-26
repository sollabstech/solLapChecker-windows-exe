import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../app/app_modules.dart';
import '../app/theme.dart';
import '../controllers/app_controller.dart';
import '../modules/battery/battery_view.dart';
import '../modules/cpu/cpu_view.dart';
import '../modules/dashboard/dashboard_view.dart';
import '../modules/display/display_view.dart';
import '../modules/gpu/gpu_view.dart';
import '../modules/keyboard/keyboard_view.dart';
import '../modules/microphone/microphone_view.dart';
import '../modules/placeholder/module_placeholder_view.dart';
import '../modules/reports/reports_view.dart';
import '../modules/speaker/speaker_view.dart';
import '../modules/storage/storage_view.dart';
import '../modules/touchpad/touchpad_view.dart';
import '../modules/webcam/webcam_view.dart';
import 'sidebar.dart';
import 'active_test_bar.dart';
import 'title_bar.dart';
import 'wizard_banner.dart';

/// Window chrome: title bar, sidebar and the active module's screen.
class AppShell extends GetView<AppController> {
  const AppShell({super.key});

  /// Real screens, registered as each build phase lands. Anything missing
  /// falls back to a "coming in Phase N" placeholder.
  static final Map<ModuleId, Widget Function()> _screens = {
    ModuleId.dashboard: () => const DashboardView(),
    ModuleId.battery: () => const BatteryView(),
    ModuleId.storage: () => const StorageView(),
    ModuleId.cpu: () => const CpuView(),
    ModuleId.gpu: () => const GpuView(),
    ModuleId.keyboard: () => const KeyboardView(),
    ModuleId.touchpad: () => const TouchpadView(),
    ModuleId.webcam: () => const WebcamView(),
    ModuleId.speaker: () => const SpeakerView(),
    ModuleId.microphone: () => const MicrophoneView(),
    ModuleId.display: () => const DisplayView(),
    ModuleId.reports: () => const ReportsView(),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const AppTitleBar(),
          Expanded(
            child: Row(
              children: [
                const AppSidebar(),
                Expanded(
                  child: Stack(
                    children: [
                      const Positioned.fill(child: _Backdrop()),
                      Column(
                        children: [
                          const WizardBanner(),
                          const ActiveTestBar(),
                          Expanded(
                            child: Obx(() {
                              final id = controller.selected.value;
                              return AnimatedSwitcher(
                                duration: const Duration(milliseconds: 250),
                                transitionBuilder: (child, anim) => FadeTransition(
                                  opacity: anim,
                                  child: SlideTransition(
                                    position: Tween(begin: const Offset(0, 0.015), end: Offset.zero)
                                        .animate(anim),
                                    child: child,
                                  ),
                                ),
                                child: KeyedSubtree(
                                  key: ValueKey(id),
                                  child: _screens[id]?.call() ??
                                      ModulePlaceholderView(module: moduleById(id)),
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
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

/// Soft radial glows behind the content for depth.
class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0.8, -1.0),
            radius: 1.1,
            colors: [AppColors.primary.withValues(alpha: 0.16), Colors.transparent],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-1.0, 1.1),
              radius: 0.9,
              colors: [AppColors.pass.withValues(alpha: 0.08), Colors.transparent],
            ),
          ),
        ),
      ),
    );
  }
}
