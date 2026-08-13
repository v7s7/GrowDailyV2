import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/game_theme.dart';

/// Small "what does this number mean" sheet, opened by tapping any of
/// ProfileScreen's five stat cells (streak/best/total/gold/XP) - see
/// _StatCell's onTap in profile_screen_hero_dashboard.dart. Same visual
/// language as every other bottom sheet in this app (drag handle,
/// gp.surfaceHigh card, rounded top corners) - just the handle, no separate
/// close button crowding it: swipe-down or tap-outside already dismisses
/// this like any other modal sheet, and there's nothing else to pick or
/// confirm here, just something to read and dismiss. Shows the actual
/// current [value] alongside the explanation so it reads as "here's what
/// your 12 means," not a generic dictionary entry.
Future<void> showStatInfoSheet(
  BuildContext context, {
  required IconData icon,
  required Color color,
  required String value,
  required String title,
  required String description,
}) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (_) => _StatInfoSheet(
      icon: icon,
      color: color,
      value: value,
      title: title,
      description: description,
    ),
  );
}

class _StatInfoSheet extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String title;
  final String description;
  const _StatInfoSheet({
    required this.icon,
    required this.color,
    required this.value,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: gp.border, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Just the drag handle - no close button crowding it (see this
            // class's own doc comment for why one isn't needed here).
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: gp.border,
                  borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: color.withOpacity(0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: color),
            ),
            const SizedBox(height: 14),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
                height: 1,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: gp.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: gp.textSec, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}
