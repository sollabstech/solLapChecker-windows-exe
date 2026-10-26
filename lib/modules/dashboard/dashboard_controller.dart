import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/models/system_info.dart';
import '../../core/services/system_info_service.dart';

/// Loads the laptop's system information for the dashboard.
class DashboardController extends GetxController {
  DashboardController([SystemInfoService? service])
      : _service = service ?? SystemInfoService();

  final SystemInfoService _service;

  final info = Rxn<SystemInfo>();
  final isLoading = false.obs;
  final error = RxnString();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    error.value = null;
    try {
      info.value = await _service.load();
    } catch (e) {
      error.value = '$e';
    } finally {
      isLoading.value = false;
    }
  }

  /// Native display size, used when WMI does not report a resolution.
  String? get fallbackResolution {
    final displays = WidgetsBinding.instance.platformDispatcher.displays;
    if (displays.isEmpty) return null;
    final s = displays.first.size;
    return '${s.width.round()} × ${s.height.round()}';
  }
}
