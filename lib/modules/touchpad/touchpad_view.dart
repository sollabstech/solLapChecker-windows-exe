import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/app_modules.dart';
import '../../app/theme.dart';
import '../../controllers/app_controller.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/input_device_panel.dart';
import '../../widgets/module_scaffold.dart';
import 'touchpad_controller.dart';

class TouchpadView extends StatefulWidget {
  const TouchpadView({super.key});

  @override
  State<TouchpadView> createState() => _TouchpadViewState();
}

class _TouchpadViewState extends State<TouchpadView> {
  final c = Get.find<TouchpadController>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => c.start());
  }

  @override
  void dispose() {
    scheduleMicrotask(c.stop);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = Get.find<AppController>();
    final module = moduleById(ModuleId.touchpad);

    return Obx(() => ModuleScaffold(
          title: module.title,
          subtitle: module.subtitle,
          icon: module.icon,
          status: app.statusOf(ModuleId.touchpad),
          actions: [
            OutlinedButton.icon(
              onPressed: c.reset,
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('Reset'),
            ),
            FilledButton.icon(
              onPressed: c.finish,
              icon: const Icon(Icons.flag_rounded, size: 18),
              label: const Text('Finish test'),
            ),
          ],
          child: _body(),
        ));
  }

  Widget _body() {
    final err = c.error.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (err != null) ...[
          NoticeCard(
            icon: Icons.mouse_outlined,
            color: AppColors.fail,
            title: 'Touchpad detection is unavailable',
            message: 'Windows Raw Input could not be started, so touchpad actions cannot be told apart from an '
                'external mouse. You can still confirm each action by hand.\n$err',
          ),
          const SizedBox(height: 16),
        ],
        LayoutBuilder(builder: (context, box) {
          final surface = _PadSurface(c: c);
          final list = _Checklist(c: c);
          if (box.maxWidth < 900) {
            return Column(children: [surface, const SizedBox(height: 16), list]);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Expanded(flex: 5, child: surface), const SizedBox(width: 18), Expanded(flex: 4, child: list)],
          );
        }),
        const SizedBox(height: 18),
        Obx(() => InputDevicePanel(
              title: 'Pointing devices detected',
              ignored: c.ignoredEvents.value,
              ignoredLabel: 'Ignored events from external mice',
              emptyHint: 'Move the touchpad to detect it.',
              rows: [
                for (final m in c.mice.values) DeviceRow(device: m.device, counted: m.counted, events: m.events),
              ],
              onToggle: c.setCounted,
            )),
        const SizedBox(height: 10),
        const Text(
          'Use the laptop\'s own touchpad. An external mouse is ignored. If an action cannot be detected '
          '(for example a gesture Windows handles itself), confirm it by hand with the buttons on the right.',
          style: TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.4),
        ),
      ],
    );
  }
}

/// The area to touch: shows a fading trail of the pointer for feedback.
/// Detection does not depend on it: that comes from Raw Input.
class _PadSurface extends StatefulWidget {
  const _PadSurface({required this.c});

  final TouchpadController c;

  @override
  State<_PadSurface> createState() => _PadSurfaceState();
}

class _PadSurfaceState extends State<_PadSurface> {
  final _trail = ValueNotifier<List<Offset>>(const []);

  void _add(Offset p) {
    final next = [..._trail.value, p];
    _trail.value = next.length > 70 ? next.sublist(next.length - 70) : next;
  }

  @override
  void dispose() {
    _trail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      glow: AppColors.primary,
      padding: const EdgeInsets.all(14),
      child: Listener(
        onPointerHover: (e) => _add(e.localPosition),
        onPointerMove: (e) => _add(e.localPosition),
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) widget.c.onFlutterScroll();
        },
        onPointerPanZoomUpdate: (_) => widget.c.onFlutterScroll(),
        child: MouseRegion(
          cursor: SystemMouseCursors.precise,
          child: SizedBox(
            height: 330,
            width: double.infinity,
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: Colors.black.withValues(alpha: 0.18),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: ValueListenableBuilder<List<Offset>>(
                    valueListenable: _trail,
                    builder: (_, pts, _) => CustomPaint(painter: _TrailPainter(pts)),
                  ),
                ),
                const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.touch_app_rounded, size: 40, color: AppColors.muted),
                      SizedBox(height: 8),
                      Text('Test area', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
                      SizedBox(height: 2),
                      Text(
                        'Move, click, tap and scroll with the touchpad',
                        style: TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrailPainter extends CustomPainter {
  _TrailPainter(this.points);

  final List<Offset> points;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    for (var i = 1; i < points.length; i++) {
      final t = i / points.length;
      canvas.drawLine(
        points[i - 1],
        points[i],
        Paint()
          ..color = AppColors.primary.withValues(alpha: 0.15 + 0.7 * t)
          ..strokeWidth = 1.5 + 3 * t
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.drawCircle(points.last, 7, Paint()..color = AppColors.primary);
  }

  @override
  bool shouldRepaint(_TrailPainter old) => old.points != points;
}

class _Checklist extends StatelessWidget {
  const _Checklist({required this.c});

  final TouchpadController c;

  @override
  Widget build(BuildContext context) {
    return Obx(() => GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Column(
            children: [
              for (final a in PadAction.values) _ActionRow(action: a, state: c.actions[a]!, c: c),
            ],
          ),
        ));
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.action, required this.state, required this.c});

  final PadAction action;
  final ActionState state;
  final TouchpadController c;

  @override
  Widget build(BuildContext context) {
    final done = state == ActionState.detected || state == ActionState.manualPass;
    final failed = state == ActionState.failed;
    final color = failed ? AppColors.fail : (done ? AppColors.pass : AppColors.muted);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done || failed ? color : Colors.transparent,
              border: Border.all(color: color.withValues(alpha: 0.7), width: 1.6),
              boxShadow: done || failed ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 10)] : null,
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Icon(
                failed ? Icons.close_rounded : Icons.check_rounded,
                key: ValueKey(state),
                size: 18,
                color: done || failed ? const Color(0xFF07152A) : Colors.transparent,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(action.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                Text(
                  state == ActionState.manualPass ? 'Confirmed by hand' : action.hint,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Works (confirm by hand)',
            visualDensity: VisualDensity.compact,
            onPressed: () => c.markWorking(action),
            icon: const Icon(Icons.thumb_up_alt_outlined, size: 18, color: AppColors.pass),
          ),
          IconButton(
            tooltip: 'Not working',
            visualDensity: VisualDensity.compact,
            onPressed: () => c.markNotWorking(action),
            icon: const Icon(Icons.thumb_down_alt_outlined, size: 18, color: AppColors.fail),
          ),
        ],
      ),
    );
  }
}
