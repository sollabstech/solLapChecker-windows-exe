import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../app/app_modules.dart';
import '../../app/theme.dart';
import '../../controllers/app_controller.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/module_scaffold.dart';
import 'display_controller.dart';

class DisplayView extends StatelessWidget {
  const DisplayView({super.key});

  Future<void> _start(BuildContext context, DisplayController c) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    await c.begin();
    // The colour page covers the whole window, title bar included.
    await navigator.push(PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => DisplayColorPage(c: c),
    ));
    if (c.sequenceCompleted.value && c.answer.value == null && context.mounted) {
      await _askVerdict(context, c);
    }
  }

  Future<void> _askVerdict(BuildContext context, DisplayController c) async {
    final fine = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.navySoft,
        title: const Text('Did you see any problems?'),
        content: const Text(
          'Dead pixels (black dots on colours), stuck pixels (bright dots on black), '
          'stains, flicker, uneven brightness or discoloured areas.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.fail, side: const BorderSide(color: AppColors.fail)),
            child: const Text('Yes, I saw problems'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.pass, foregroundColor: const Color(0xFF07152A)),
            child: const Text('No, display looks perfect'),
          ),
        ],
      ),
    );
    if (fine != null) c.setAnswer(fine);
  }

  @override
  Widget build(BuildContext context) {
    final c = Get.find<DisplayController>();
    final app = Get.find<AppController>();
    final module = moduleById(ModuleId.display);

    return Obx(() => ModuleScaffold(
          title: module.title,
          subtitle: module.subtitle,
          icon: module.icon,
          status: app.statusOf(ModuleId.display),
          actions: [
            FilledButton.icon(
              onPressed: () => _start(context, c),
              icon: const Icon(Icons.fullscreen_rounded, size: 20),
              label: Text(c.answer.value == null && !c.sequenceCompleted.value ? 'Start display test' : 'Run again'),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The screen fills with five solid colours. Look closely at each one for dots that stay black or '
                'bright, stains, or uneven areas. Clean the screen first so dust is not mistaken for a pixel.',
                style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.45),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [for (final col in DisplayController.colors) _Swatch(col: col)],
              ),
              const SizedBox(height: 18),
              const GlassCard(
                child: Row(
                  children: [
                    Icon(Icons.keyboard_alt_outlined, color: AppColors.primary),
                    SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Controls in the test: click or press Space / → for the next colour, ← for the previous one, '
                        'Esc to quit early.',
                        style: TextStyle(fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              if (c.answer.value != null) ...[
                const SizedBox(height: 18),
                NoticeCard(
                  icon: c.answer.value! ? Icons.check_circle_rounded : Icons.report_problem_rounded,
                  color: c.answer.value! ? AppColors.pass : AppColors.fail,
                  title: c.answer.value! ? 'No display problems reported' : 'Display problems reported',
                  message: c.answer.value!
                      ? 'You checked all five colours and saw nothing wrong.'
                      : 'You noted dead or stuck pixels, stains or other display faults.',
                ),
              ] else if (!c.sequenceCompleted.value && c.index.value > 0 && !c.active.value)
                const Padding(
                  padding: EdgeInsets.only(top: 14),
                  child: Text(
                    'The test was left before the last colour, so there is no result yet.',
                    style: TextStyle(color: AppColors.accent, fontSize: 12.5),
                  ),
                ),
            ],
          ),
        ));
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.col});

  final DisplayColor col;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 74,
            decoration: BoxDecoration(
              color: col.color,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
            ),
          ),
          const SizedBox(height: 8),
          Text(col.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(col.hint, style: const TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.3)),
        ],
      ),
    );
  }
}

/// The fullscreen colour page. A small hint shows briefly for each colour
/// and then disappears so it never covers a dead pixel.
class DisplayColorPage extends StatefulWidget {
  const DisplayColorPage({super.key, required this.c});

  final DisplayController c;

  @override
  State<DisplayColorPage> createState() => _DisplayColorPageState();
}

class _DisplayColorPageState extends State<DisplayColorPage> {
  bool _showHint = true;
  int _hintFor = 0;
  Worker? _closeWorker;

  DisplayController get c => widget.c;

  @override
  void initState() {
    super.initState();
    _scheduleHintHide();
    // When the controller leaves fullscreen (last colour or Esc) close this page.
    _closeWorker = ever<bool>(c.active, (active) {
      if (!active && mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _closeWorker?.dispose();
    super.dispose();
  }

  void _scheduleHintHide() {
    final token = ++_hintFor;
    Future<void>.delayed(const Duration(milliseconds: 1800), () {
      if (mounted && token == _hintFor) setState(() => _showHint = false);
    });
  }

  void _go(Future<void> Function() action) {
    setState(() => _showHint = true);
    action();
    _scheduleHintHide();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.handled;
        final k = event.logicalKey;
        if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.enter) {
          _go(c.next);
        } else if (k == LogicalKeyboardKey.arrowLeft) {
          setState(() => _showHint = true);
          c.previous();
          _scheduleHintHide();
        } else if (k == LogicalKeyboardKey.escape) {
          c.exit();
        }
        return KeyEventResult.handled;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _go(c.next),
        onSecondaryTap: c.previous,
        child: Obx(() {
          final col = c.current;
          final dark = col.color.computeLuminance() < 0.4;
          return ColoredBox(
            color: col.color,
            child: Stack(
              children: [
                Positioned(
                  left: 20,
                  bottom: 16,
                  child: AnimatedOpacity(
                    opacity: _showHint ? 1 : 0,
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      '${col.name}  ${c.index.value + 1}/${DisplayController.colors.length}   ·   click / Space: next   ← back   Esc: quit',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: dark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
