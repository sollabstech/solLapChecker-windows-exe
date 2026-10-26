import 'package:flutter/material.dart';

/// Every screen reachable from the sidebar.
enum ModuleId {
  dashboard,
  battery,
  storage,
  cpu,
  gpu,
  keyboard,
  touchpad,
  webcam,
  speaker,
  microphone,
  display,
  reports,
}

/// Static description of a sidebar entry.
class ModuleDef {
  const ModuleDef({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.phase,
    this.isTest = true,
  });

  final ModuleId id;
  final String title;
  final String subtitle;
  final IconData icon;

  /// Build phase in which the module's real screen is delivered.
  final int phase;

  /// Tests carry a status and take part in the guided "Run Full Test" wizard.
  final bool isTest;
}

const dashboardModule = ModuleDef(
  id: ModuleId.dashboard,
  title: 'Dashboard',
  subtitle: 'System information and overall progress',
  icon: Icons.space_dashboard_rounded,
  phase: 1,
  isTest: false,
);

const reportsModule = ModuleDef(
  id: ModuleId.reports,
  title: 'Reports',
  subtitle: 'Create a certified report and reopen saved ones',
  icon: Icons.history_rounded,
  phase: 6,
  isTest: false,
);

/// The tests, in the order the guided wizard runs them.
const testModules = <ModuleDef>[
  ModuleDef(
    id: ModuleId.battery,
    title: 'Battery Health',
    subtitle: 'Design vs. current capacity and cycle count',
    icon: Icons.battery_charging_full_rounded,
    phase: 2,
  ),
  ModuleDef(
    id: ModuleId.storage,
    title: 'SSD / Storage',
    subtitle: 'SMART health, wear and power-on hours',
    icon: Icons.storage_rounded,
    phase: 2,
  ),
  ModuleDef(
    id: ModuleId.cpu,
    title: 'CPU Stress Test',
    subtitle: 'Full load, max temperature and throttling',
    icon: Icons.memory_rounded,
    phase: 3,
  ),
  ModuleDef(
    id: ModuleId.gpu,
    title: 'GPU Stress Test',
    subtitle: 'Compute load and max temperature',
    icon: Icons.developer_board_rounded,
    phase: 3,
  ),
  ModuleDef(
    id: ModuleId.keyboard,
    title: 'Keyboard Test',
    subtitle: 'Built-in keyboard only',
    icon: Icons.keyboard_rounded,
    phase: 4,
  ),
  ModuleDef(
    id: ModuleId.touchpad,
    title: 'Touchpad Test',
    subtitle: 'Clicks, taps and two-finger scroll',
    icon: Icons.touch_app_rounded,
    phase: 4,
  ),
  ModuleDef(
    id: ModuleId.webcam,
    title: 'Webcam Test',
    subtitle: 'Live preview',
    icon: Icons.videocam_rounded,
    phase: 5,
  ),
  ModuleDef(
    id: ModuleId.speaker,
    title: 'Speaker Test',
    subtitle: 'Left, right and both channels',
    icon: Icons.volume_up_rounded,
    phase: 5,
  ),
  ModuleDef(
    id: ModuleId.microphone,
    title: 'Microphone Test',
    subtitle: 'Level meter, record and playback',
    icon: Icons.mic_rounded,
    phase: 5,
  ),
  ModuleDef(
    id: ModuleId.display,
    title: 'Display Test',
    subtitle: 'Solid colours to find dead pixels',
    icon: Icons.monitor_rounded,
    phase: 5,
  ),
];

final allModules = <ModuleDef>[dashboardModule, ...testModules, reportsModule];

ModuleDef moduleById(ModuleId id) =>
    allModules.firstWhere((m) => m.id == id);
