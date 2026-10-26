import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/app_modules.dart';
import '../../app/theme.dart';
import '../../controllers/app_controller.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/input_device_panel.dart';
import '../../widgets/module_scaffold.dart';
import '../../widgets/progress_ring.dart';
import 'keyboard_controller.dart';
import 'keyboard_layout.dart';

class KeyboardView extends StatefulWidget {
  const KeyboardView({super.key});

  @override
  State<KeyboardView> createState() => _KeyboardViewState();
}

class _KeyboardViewState extends State<KeyboardView> {
  final c = Get.find<KeyboardController>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => c.start());
  }

  @override
  void dispose() {
    // Deferred: stopping updates observable state, which must not happen mid-teardown.
    scheduleMicrotask(c.stop);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = Get.find<AppController>();
    final module = moduleById(ModuleId.keyboard);

    // The test presses every key, including Tab/Enter/arrows: swallow them so
    // they do not move focus or trigger buttons while this screen is open.
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) => KeyEventResult.handled,
      child: Obx(() => ModuleScaffold(
            title: module.title,
            subtitle: module.subtitle,
            icon: module.icon,
            status: app.statusOf(ModuleId.keyboard),
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
          )),
    );
  }

  Widget _body() {
    final err = c.error.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (err != null) ...[
          NoticeCard(
            icon: Icons.keyboard_alt_outlined,
            color: AppColors.fail,
            title: 'Keyboard detection is unavailable',
            message: 'Windows Raw Input could not be started, so key presses cannot be attributed to a device. '
                'You can still confirm keys by hand.\n$err',
          ),
          const SizedBox(height: 16),
        ],
        _Summary(c: c),
        const SizedBox(height: 18),
        _KeyboardDrawing(c: c),
        const SizedBox(height: 10),
        const Text(
          'Press every key on the laptop\'s own keyboard. Keys from an external keyboard are ignored. '
          'Fn and other keys that send no signal to Windows: click the key to confirm it by hand. '
          'Click any key to mark it as working or not working.',
          style: TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.4),
        ),
        Obx(() {
          if (c.otherKeys.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Other keys detected (not on this layout): ${c.otherKeys.join(', ')}',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          );
        }),
        const SizedBox(height: 18),
        Obx(() => InputDevicePanel(
              title: 'Keyboards detected',
              ignored: c.ignoredPresses.value,
              ignoredLabel: 'Ignored key presses from external keyboards',
              emptyHint: 'Press a key to detect your keyboards.',
              rows: [
                for (final k in c.keyboards.values)
                  DeviceRow(device: k.device, counted: k.counted, events: k.events),
              ],
              onToggle: c.setCounted,
            )),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.c});

  final KeyboardController c;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final tested = c.testedCount;
      final failed = c.failedCount;
      final untested = c.untestedCount;
      final color = failed > 0 ? AppColors.fail : (untested == 0 ? AppColors.pass : AppColors.primary);

      return GlassCard(
        child: Row(
          children: [
            ProgressRing(
              value: tested / c.total,
              size: 92,
              strokeWidth: 9,
              color: color,
              endColor: color,
              child: Text('${(tested / c.total * 100).round()}%', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 22),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$tested / ${c.total} keys tested',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (failed > 0) '$failed not working',
                      '$untested not tested yet',
                    ].join('  ·  '),
                    style: TextStyle(color: failed > 0 ? AppColors.fail : AppColors.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            if (c.listening.value)
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fiber_manual_record, size: 11, color: AppColors.pass),
                  SizedBox(width: 6),
                  Text('Listening', style: TextStyle(color: AppColors.pass, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ],
              ),
          ],
        ),
      );
    });
  }
}

/// Total key units per row; rows are scaled/padded to this so they line up.
const _rowUnits = 15.0;

class _KeyboardDrawing extends StatelessWidget {
  const _KeyboardDrawing({required this.c});

  final KeyboardController c;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          for (final row in KeyboardLayout.rows) ...[
            _KeyRow(row: row, c: c),
            const SizedBox(height: 5),
          ],
        ],
      ),
    );
  }
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.row, required this.c});

  final List<KeyDef> row;
  final KeyboardController c;

  @override
  Widget build(BuildContext context) {
    final sum = row.fold<double>(0, (s, k) => s + k.width);
    final scale = sum > _rowUnits ? _rowUnits / sum : 1.0;
    final pad = _rowUnits - sum * scale;

    return Row(
      children: [
        for (final k in row)
          Expanded(
            flex: (k.width * scale * 100).round(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _KeyCap(def: k, c: c),
            ),
          ),
        if (pad > 0.01) Spacer(flex: (pad * 100).round()),
      ],
    );
  }
}

enum _KeyAction { working, notWorking, clear }

class _KeyCap extends StatelessWidget {
  const _KeyCap({required this.def, required this.c});

  final KeyDef def;
  final KeyboardController c;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final state = c.keys[def.id] ?? KeyState.untested;
      final isLast = c.lastKeyId.value == def.id;
      final (fill, border, text) = switch (state) {
        KeyState.untested => (Colors.white.withValues(alpha: 0.06), Colors.white.withValues(alpha: 0.12), AppColors.text.withValues(alpha: 0.7)),
        KeyState.pressed => (AppColors.pass.withValues(alpha: 0.9), const Color(0xFF86EFAC), const Color(0xFF04220F)),
        KeyState.manualPass => (AppColors.pass.withValues(alpha: 0.35), AppColors.pass, AppColors.text),
        KeyState.failed => (AppColors.fail.withValues(alpha: 0.85), const Color(0xFFFCA5A5), Colors.white),
      };

      return PopupMenuButton<_KeyAction>(
        tooltip: def.manualOnly ? '${def.label}: sends no signal to Windows, click to confirm by hand' : 'Mark ${def.label} manually',
        padding: EdgeInsets.zero,
        position: PopupMenuPosition.under,
        color: AppColors.navySoft,
        onSelected: (a) => switch (a) {
          _KeyAction.working => c.markWorking(def.id),
          _KeyAction.notWorking => c.markNotWorking(def.id),
          _KeyAction.clear => c.clearKey(def.id),
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: _KeyAction.working, child: Text('Mark as working')),
          PopupMenuItem(value: _KeyAction.notWorking, child: Text('Mark as NOT working')),
          PopupMenuItem(value: _KeyAction.clear, child: Text('Reset this key')),
        ],
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border, width: def.manualOnly && state == KeyState.untested ? 1.4 : 1),
            boxShadow: isLast && state == KeyState.pressed
                ? [BoxShadow(color: AppColors.pass.withValues(alpha: 0.7), blurRadius: 14)]
                : null,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Text(def.label, style: TextStyle(color: text, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      );
    });
  }
}
