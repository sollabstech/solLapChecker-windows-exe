import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/app_modules.dart';
import '../../app/theme.dart';
import '../../controllers/app_controller.dart';
import '../../core/media/camera_service.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/module_scaffold.dart';
import '../../widgets/verdict_buttons.dart';
import 'webcam_controller.dart';

class WebcamView extends StatefulWidget {
  const WebcamView({super.key});

  @override
  State<WebcamView> createState() => _WebcamViewState();
}

class _WebcamViewState extends State<WebcamView> {
  final c = Get.find<WebcamController>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => c.start());
  }

  @override
  void dispose() {
    // Releases the camera (its light goes off); deferred so state is not touched mid-teardown.
    scheduleMicrotask(c.stop);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = Get.find<AppController>();
    final module = moduleById(ModuleId.webcam);

    return Obx(() => ModuleScaffold(
          title: module.title,
          subtitle: module.subtitle,
          icon: module.icon,
          status: app.statusOf(ModuleId.webcam),
          child: _body(),
        ));
  }

  Widget _body() {
    if (c.noCamera.value) {
      return NoticeCard(
        icon: Icons.videocam_off_rounded,
        title: 'No camera detected',
        message: 'Windows reports no camera. It may be disabled in the BIOS or Device Manager, covered by a '
            'privacy shutter, or missing. Ask the seller about it.',
        action: OutlinedButton(onPressed: c.start, child: const Text('Check again')),
      );
    }
    final err = c.error.value;
    if (err != null) {
      return NoticeCard(
        icon: Icons.error_outline_rounded,
        color: AppColors.fail,
        title: 'The camera could not be opened',
        message: 'Another app may be using it, or camera access is blocked in Windows privacy settings.\n$err',
        action: FilledButton(onPressed: c.start, child: const Text('Try again')),
      );
    }

    final session = c.session.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _InfoChip(icon: Icons.videocam_rounded, label: 'Camera', value: c.current?.name ?? '—'),
            _InfoChip(icon: Icons.aspect_ratio_rounded, label: 'Resolution', value: formatResolution(session?.resolution)),
            if (c.cameras.length > 1)
              DropdownButton<int>(
                value: c.selected.value.clamp(0, c.cameras.length - 1),
                dropdownColor: AppColors.navySoft,
                underline: const SizedBox.shrink(),
                items: [
                  for (var i = 0; i < c.cameras.length; i++)
                    DropdownMenuItem(value: i, child: Text(c.cameras[i].name)),
                ],
                onChanged: (i) => i == null ? null : c.select(i),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: GlassCard(
              glow: AppColors.primary,
              padding: const EdgeInsets.all(10),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ColoredBox(
                    color: Colors.black,
                    child: session == null
                        ? Center(
                            child: c.isStarting.value
                                ? const CircularProgressIndicator(color: AppColors.primary)
                                : const Text('Camera is off', style: TextStyle(color: AppColors.muted)),
                          )
                        : Stack(
                            fit: StackFit.expand,
                            children: [
                              session.buildPreview(),
                              _FaceOverlay(state: c.face.value),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: Column(
            children: [
              Text(
                switch (c.face.value) {
                  FaceState.detected => 'Face detected: the camera works.',
                  FaceState.unavailable => 'Do you see a clear, live picture of yourself?',
                  _ => 'Look at the camera. The test passes as soon as your face is detected.',
                },
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              if (c.face.value == FaceState.unavailable) ...[
                const SizedBox(height: 6),
                Text(
                  'Automatic face check is not available here (${c.faceError.value ?? 'unknown reason'}). '
                  'Judge the picture yourself.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                ),
              ],
              if (c.face.value == FaceState.looking) ...[
                const SizedBox(height: 6),
                const Text(
                  'No face available? Judge the picture yourself:',
                  style: TextStyle(color: AppColors.muted, fontSize: 12.5),
                ),
              ],
              const SizedBox(height: 12),
              VerdictButtons(
                passLabel: 'Camera works',
                failLabel: 'Camera not working',
                answer: c.answer.value,
                onPass: session == null ? null : () => c.setAnswer(true),
                onFail: () => c.setAnswer(false),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Show your face" prompt while looking, a big tick once a face is seen.
class _FaceOverlay extends StatelessWidget {
  const _FaceOverlay({required this.state});

  final FaceState state;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case FaceState.looking:
        return Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.7)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.face_retouching_natural_rounded, color: AppColors.accent, size: 20),
                SizedBox(width: 8),
                Text('Show your face to the camera', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ],
            ),
          ),
        );
      case FaceState.detected:
        return ColoredBox(
          color: Colors.black.withValues(alpha: 0.35),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_rounded, color: AppColors.pass, size: 96),
                SizedBox(height: 8),
                Text('Face detected', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        );
      case FaceState.idle:
      case FaceState.unavailable:
        return const SizedBox.shrink();
    }
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Text('$label  ', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
  }
}
