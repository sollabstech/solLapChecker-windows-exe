import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/app_modules.dart';
import '../../app/theme.dart';
import '../../controllers/app_controller.dart';
import '../../core/media/tone_generator.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/module_scaffold.dart';
import '../../widgets/verdict_buttons.dart';
import 'speaker_controller.dart';

class SpeakerView extends StatelessWidget {
  const SpeakerView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<SpeakerController>();
    final app = Get.find<AppController>();
    final module = moduleById(ModuleId.speaker);

    return Obx(() => ModuleScaffold(
          title: module.title,
          subtitle: module.subtitle,
          icon: module.icon,
          status: app.statusOf(ModuleId.speaker),
          actions: [
            OutlinedButton.icon(
              onPressed: c.playing.value != null ? c.stopPlayback : c.playAll,
              icon: Icon(c.playing.value != null ? Icons.stop_rounded : Icons.playlist_play_rounded, size: 20),
              label: Text(c.playing.value != null ? 'Stop' : 'Play all in order'),
            ),
            OutlinedButton.icon(
              onPressed: c.reset,
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('Reset'),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Turn the volume to a comfortable level (about half) and make sure no headphones are plugged in. '
                'Play each tone and say which speaker you heard it from.',
                style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4),
              ),
              if (c.error.value != null) ...[
                const SizedBox(height: 12),
                NoticeCard(
                  icon: Icons.volume_off_rounded,
                  color: AppColors.fail,
                  title: 'Sound could not be played',
                  message: c.error.value!,
                ),
              ],
              const SizedBox(height: 18),
              LayoutBuilder(builder: (context, box) {
                final cards = [for (final ch in ToneChannel.values) _ChannelCard(channel: ch, c: c)];
                if (box.maxWidth < 760) {
                  return Column(children: [for (final w in cards) Padding(padding: const EdgeInsets.only(bottom: 14), child: w)]);
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      if (i > 0) const SizedBox(width: 14),
                      Expanded(child: cards[i]),
                    ],
                  ],
                );
              }),
            ],
          ),
        ));
  }
}

class _ChannelCard extends StatelessWidget {
  const _ChannelCard({required this.channel, required this.c});

  final ToneChannel channel;
  final SpeakerController c;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final answer = c.heard[channel];
      final playing = c.playing.value == channel;
      final busy = c.playing.value != null;
      final color = answer == null ? AppColors.primary : (answer ? AppColors.pass : AppColors.fail);

      return GlassCard(
        glow: playing ? AppColors.primary : (answer == null ? null : color),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Speaker(label: 'L', active: channel != ToneChannel.right, playing: playing),
                const SizedBox(width: 26),
                _Speaker(label: 'R', active: channel != ToneChannel.left, playing: playing),
              ],
            ),
            const SizedBox(height: 14),
            Text(channel.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: busy ? null : () => c.play(channel),
              icon: playing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                  : const Icon(Icons.play_arrow_rounded, size: 20),
              label: Text(playing ? 'Playing…' : 'Play tone'),
            ),
            const SizedBox(height: 16),
            Text(
              channel.question,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            VerdictButtons(
              passLabel: 'Yes',
              failLabel: 'No',
              answer: answer,
              onPass: () => c.answer(channel, true),
              onFail: () => c.answer(channel, false),
            ),
          ],
        ),
      );
    });
  }
}

/// A speaker glyph that lights up when it is meant to be sounding.
class _Speaker extends StatelessWidget {
  const _Speaker({required this.label, required this.active, required this.playing});

  final String label;
  final bool active;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final lit = active && playing;
    final color = active ? AppColors.primary : AppColors.muted.withValues(alpha: 0.4);
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: lit ? 0.3 : 0.12),
            border: Border.all(color: color.withValues(alpha: active ? 0.9 : 0.4), width: 1.6),
            boxShadow: lit ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.6), blurRadius: 20)] : null,
          ),
          child: Icon(active ? Icons.volume_up_rounded : Icons.volume_off_rounded, size: 30, color: color),
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
      ],
    );
  }
}
