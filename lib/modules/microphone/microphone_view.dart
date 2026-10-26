import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/app_modules.dart';
import '../../app/theme.dart';
import '../../controllers/app_controller.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/module_scaffold.dart';
import '../../widgets/verdict_buttons.dart';
import 'microphone_controller.dart';

class MicrophoneView extends StatefulWidget {
  const MicrophoneView({super.key});

  @override
  State<MicrophoneView> createState() => _MicrophoneViewState();
}

class _MicrophoneViewState extends State<MicrophoneView> {
  final c = Get.find<MicrophoneController>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => c.init());
  }

  @override
  void dispose() {
    scheduleMicrotask(c.stop);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = Get.find<AppController>();
    final module = moduleById(ModuleId.microphone);

    return Obx(() => ModuleScaffold(
          title: module.title,
          subtitle: module.subtitle,
          icon: module.icon,
          status: app.statusOf(ModuleId.microphone),
          actions: [
            OutlinedButton.icon(
              onPressed: c.reset,
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('Reset'),
            ),
          ],
          child: _body(),
        ));
  }

  Widget _body() {
    final phase = c.phase.value;
    final recording = phase == MicPhase.recording;
    final monitoring = phase == MicPhase.monitoring;
    final recorded = phase == MicPhase.recorded || phase == MicPhase.playing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (c.permissionDenied.value) ...[
          const NoticeCard(
            icon: Icons.mic_off_rounded,
            color: AppColors.fail,
            title: 'Microphone access is blocked',
            message: 'Allow desktop apps to use the microphone in Windows Settings > Privacy & security > Microphone, '
                'or check that a microphone is connected and enabled, then try again.',
          ),
          const SizedBox(height: 16),
        ],
        if (c.error.value != null) ...[
          NoticeCard(
            icon: Icons.error_outline_rounded,
            color: AppColors.fail,
            title: 'Microphone problem',
            message: c.error.value!,
          ),
          const SizedBox(height: 16),
        ],
        GlassCard(
          glow: recording ? AppColors.fail : (monitoring ? AppColors.primary : null),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.mic_rounded, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      c.devices.isEmpty ? 'Default microphone' : c.devices.join('  ·  '),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                    ),
                  ),
                  if (recording)
                    Text('Recording… ${c.secondsLeft.value}s',
                        style: const TextStyle(color: AppColors.fail, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 18),
              _LevelMeter(level: c.level.value, active: recording || monitoring),
              const SizedBox(height: 6),
              Text(
                recording || monitoring
                    ? 'Speak or tap near the microphone: the bar should jump.'
                    : 'Press "Check level" for a live meter, or "Record 5 seconds".',
                style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (monitoring)
                    OutlinedButton.icon(
                      onPressed: c.stopMonitor,
                      icon: const Icon(Icons.stop_rounded, size: 18),
                      label: const Text('Stop checking'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: recording ? null : c.startMonitor,
                      icon: const Icon(Icons.graphic_eq_rounded, size: 18),
                      label: const Text('Check level'),
                    ),
                  FilledButton.icon(
                    onPressed: recording ? null : c.record,
                    style: FilledButton.styleFrom(backgroundColor: AppColors.fail),
                    icon: const Icon(Icons.fiber_manual_record_rounded, size: 16),
                    label: Text(recorded ? 'Record again' : 'Record 5 seconds'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (recorded) ...[
          const SizedBox(height: 18),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: phase == MicPhase.playing ? c.stopPlayback : c.play,
                      icon: Icon(phase == MicPhase.playing ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 20),
                      label: Text(phase == MicPhase.playing ? 'Stop' : 'Play back recording'),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        c.signalDetected
                            ? 'Sound was picked up (peak ${c.peakDb.value!.toStringAsFixed(0)} dB).'
                            : 'Almost no sound was picked up. The microphone may be muted, blocked or broken.',
                        style: TextStyle(
                          color: c.signalDetected ? AppColors.muted : AppColors.accent,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text('Could you hear your own voice clearly in the playback?',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                VerdictButtons(
                  passLabel: 'Yes, it works',
                  failLabel: 'No / distorted',
                  answer: c.answer.value,
                  onPass: () => c.setAnswer(true),
                  onFail: () => c.setAnswer(false),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// 24-segment LED style meter: green, then gold, then red near full scale.
class _LevelMeter extends StatelessWidget {
  const _LevelMeter({required this.level, required this.active});

  final double level;
  final bool active;

  static const _segments = 24;

  @override
  Widget build(BuildContext context) {
    final lit = active ? (level * _segments).round() : 0;
    return Row(
      children: [
        for (var i = 0; i < _segments; i++)
          Expanded(
            child: Container(
              height: 26,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: i < lit ? _color(i) : Colors.white.withValues(alpha: 0.07),
                boxShadow: i < lit ? [BoxShadow(color: _color(i).withValues(alpha: 0.5), blurRadius: 6)] : null,
              ),
            ),
          ),
      ],
    );
  }

  Color _color(int i) {
    final f = i / _segments;
    if (f > 0.85) return AppColors.fail;
    if (f > 0.65) return AppColors.accent;
    return AppColors.pass;
  }
}
