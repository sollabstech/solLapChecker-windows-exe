import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../app/theme.dart';

/// Custom window title bar: draggable area, logo, and caption buttons.
class AppTitleBar extends StatefulWidget {
  const AppTitleBar({super.key});

  static const height = 40.0;

  @override
  State<AppTitleBar> createState() => _AppTitleBarState();
}

class _AppTitleBarState extends State<AppTitleBar> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _maximized = v);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppTitleBar.height,
      color: AppColors.navyDeep,
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: _toggleMaximize,
                child: Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Row(
                    children: [
                      ClipOval(child: Image.asset('assets/logo.png', width: 22, height: 22)),
                      const SizedBox(width: 10),
                      const Text(
                        'SolLapChecker',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'by Sollabs Tech',
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _CaptionButton(
            icon: Icons.remove_rounded,
            tooltip: 'Minimize',
            onTap: windowManager.minimize,
          ),
          _CaptionButton(
            icon: _maximized ? Icons.filter_none_rounded : Icons.crop_square_rounded,
            iconSize: _maximized ? 14 : 18,
            tooltip: _maximized ? 'Restore' : 'Maximize',
            onTap: _toggleMaximize,
          ),
          _CaptionButton(
            icon: Icons.close_rounded,
            tooltip: 'Close',
            hoverColor: AppColors.fail,
            onTap: windowManager.close,
          ),
        ],
      ),
    );
  }

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.iconSize = 18,
    this.hoverColor,
  });

  final IconData icon;
  final double iconSize;
  final String tooltip;
  final VoidCallback onTap;
  final Color? hoverColor;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 46,
            height: AppTitleBar.height,
            color: _hover
                ? (widget.hoverColor ?? Colors.white.withValues(alpha: 0.1))
                : Colors.transparent,
            child: Icon(widget.icon, size: widget.iconSize, color: AppColors.text),
          ),
        ),
      ),
    );
  }
}
