import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/bluetooth_notifier.dart';

/// Accessible battery indicator backed by the BLE Battery Service.
///
/// Accessibility (WCAG 1.4.1 — don't rely on colour alone):
/// - The percentage is always shown as text, not just encoded in colour.
/// - The icon *shape* changes at a low charge (a distinct alert glyph), so the
///   "low battery" state is conveyed without depending on the red tint.
/// - Charging is shown with a dedicated charging glyph, not colour.
/// - A [Semantics] label spells the state out for screen readers.
///
/// Colour is used only as a secondary reinforcement of the level.
class BatteryIndicator extends ConsumerWidget {
  const BatteryIndicator({
    Key? key,
    this.foregroundColor = Colors.white,
    this.iconSize = 24,
    this.fontSize = 14,
  }) : super(key: key);

  /// Colour for the percentage text (defaults to white for the app bar). The
  /// battery icon itself is tinted by the charge level as a secondary cue.
  final Color foregroundColor;
  final double iconSize;
  final double fontSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(bluetoothNotifierProvider);
    if (!device.isConnected) return const SizedBox.shrink();

    final int? level = device.batteryLevel;
    final bool charging = device.isCharging;

    final Color statusColor = _statusColor(level);
    final String percentText = level == null ? '—' : '$level%';
    final String semanticsLabel = level == null
        ? 'Battery level unknown'
        : 'Battery $level percent${charging ? ', charging' : ''}';

    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: Tooltip(
        message: semanticsLabel,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_iconForLevel(level, charging),
                  color: statusColor, size: iconSize),
              const SizedBox(width: 4),
              Text(
                percentText,
                style: TextStyle(
                  color: foregroundColor,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForLevel(int? level, bool charging) {
    if (charging) return Icons.battery_charging_full;
    if (level == null) return Icons.battery_unknown;
    // A distinct glyph for low charge conveys the state without relying on the
    // red tint alone.
    if (level <= 15) return Icons.battery_alert;
    if (level >= 95) return Icons.battery_full;
    if (level >= 80) return Icons.battery_6_bar;
    if (level >= 65) return Icons.battery_5_bar;
    if (level >= 50) return Icons.battery_4_bar;
    if (level >= 35) return Icons.battery_3_bar;
    if (level >= 25) return Icons.battery_2_bar;
    return Icons.battery_1_bar;
  }

  Color _statusColor(int? level) {
    if (level == null) return Colors.grey.shade400;
    if (level <= 15) return const Color(0xFFE53935); // red
    if (level <= 30) return const Color(0xFFFFB300); // amber
    return const Color(0xFF43A047); // green
  }
}
