import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

import 'app/theme.dart';
import 'controllers/app_controller.dart';
import 'modules/battery/battery_controller.dart';
import 'modules/cpu/cpu_controller.dart';
import 'modules/dashboard/dashboard_controller.dart';
import 'modules/display/display_controller.dart';
import 'core/input/raw_input_service.dart';
import 'core/media/audio_output.dart';
import 'core/media/camera_service.dart';
import 'core/media/mic_recorder.dart';
import 'core/media/window_control.dart';
import 'core/report/report_repository.dart';
import 'modules/gpu/gpu_controller.dart';
import 'modules/keyboard/keyboard_controller.dart';
import 'modules/microphone/microphone_controller.dart';
import 'modules/reports/reports_controller.dart';
import 'modules/speaker/speaker_controller.dart';
import 'modules/storage/storage_controller.dart';
import 'modules/touchpad/touchpad_controller.dart';
import 'modules/webcam/webcam_controller.dart';
import 'widgets/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Custom title bar and the minimum window size from the spec.
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(1280, 800),
    minimumSize: Size(1100, 700),
    center: true,
    title: 'SolLapChecker',
    titleBarStyle: TitleBarStyle.hidden,
    backgroundColor: AppColors.navy,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // Reports live in Documents\SolLapChecker\Reports.
  final reports = await ReportRepository.inDocuments();

  runApp(SolLapCheckerApp(reports: reports));
}

class SolLapCheckerApp extends StatelessWidget {
  const SolLapCheckerApp({super.key, required this.reports});

  final ReportRepository reports;

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'SolLapChecker',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      initialBinding: BindingsBuilder(() {
        Get.put(AppController(), permanent: true);
        Get.put(DashboardController(), permanent: true);
        Get.put(BatteryController(), permanent: true);
        Get.put(StorageController(), permanent: true);
        Get.put(CpuController(), permanent: true);
        Get.put(GpuController(), permanent: true);
        // One Raw Input listener shared by the keyboard and touchpad tests.
        final input = WindowsRawInputService();
        Get.put(KeyboardController(input), permanent: true);
        Get.put(TouchpadController(input), permanent: true);
        Get.put(WebcamController(CameraPackageService()), permanent: true);
        Get.put(SpeakerController(AudioPlayersOutput()), permanent: true);
        Get.put(MicrophoneController(RecordPackageMic(), AudioPlayersOutput()), permanent: true);
        Get.put(DisplayController(WindowManagerControl()), permanent: true);
        Get.put(ReportsController(reports), permanent: true);
      }),
      home: const AppShell(),
    );
  }
}
