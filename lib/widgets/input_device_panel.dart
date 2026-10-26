import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../core/input/input_device.dart';
import 'glass_card.dart';

/// One keyboard/mouse row in the device list.
class DeviceRow {
  const DeviceRow({required this.device, required this.counted, required this.events});

  final InputDevice device;
  final bool counted;
  final int events;
}

/// Shows every device Raw Input has reported, whether its input is counted,
/// and lets the user override that (e.g. an internal keyboard misclassified as USB).
class InputDevicePanel extends StatelessWidget {
  const InputDevicePanel({
    super.key,
    required this.title,
    required this.rows,
    required this.onToggle,
    required this.ignored,
    required this.ignoredLabel,
    required this.emptyHint,
  });

  final String title;
  final List<DeviceRow> rows;
  final void Function(int handle, bool counted) onToggle;
  final int ignored;

  /// e.g. "Ignored key presses from external keyboards"; the count follows a colon.
  final String ignoredLabel;
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.usb_rounded, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const Spacer(),
              if (ignored > 0)
                Text(
                  '$ignoredLabel: $ignored',
                  style: const TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.w600),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            Text(emptyHint, style: const TextStyle(color: AppColors.muted, fontSize: 12.5))
          else
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    _BusChip(device: r.device),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        r.device.description,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text('${r.events}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    const SizedBox(width: 10),
                    Tooltip(
                      message: r.counted
                          ? 'Counted in the test. Turn off to ignore this device.'
                          : 'Ignored. Turn on if this is the laptop\'s own device.',
                      child: Switch(value: r.counted, onChanged: (v) => onToggle(r.device.handle, v)),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _BusChip extends StatelessWidget {
  const _BusChip({required this.device});

  final InputDevice device;

  @override
  Widget build(BuildContext context) {
    final color = device.isInternal ? AppColors.pass : (device.bus == DeviceBus.unknown ? AppColors.muted : AppColors.accent);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(device.bus.label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}
