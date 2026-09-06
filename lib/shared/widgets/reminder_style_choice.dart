import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/game_theme.dart';

/// Notification or alarm: the one choice about HOW a reminder arrives, drawn
/// as a two-cell switch with a sliding highlight, under the section that
/// decides WHEN. Shared by the add-habit sheet and both task sheets so the
/// two features read as one control.
///
/// Notification sits first because it is the default and the only thing the
/// app did before alarms existed. The alarm cell carries a one-line hint
/// underneath, shown only while it is selected, that says what the cell
/// buys: through Silent, through Focus. Nothing here asks for permission;
/// the sheet that owns the value does, in [onChanged].
class ReminderStyleChoice extends StatelessWidget {
  /// True when the reminder rings as an alarm.
  final bool alarm;

  /// The sheet's accent: gold in the habit sheet, the quadrant colour in a
  /// task sheet.
  final Color accent;

  final ValueChanged<bool> onChanged;

  const ReminderStyleChoice({
    super.key,
    required this.alarm,
    required this.accent,
    required this.onChanged,
  });

  static const double _height = 46;
  static const double _inset = 4;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final gp = context.gp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          s.reminderStyleSection,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: gp.textTert,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: _height,
          padding: const EdgeInsets.all(_inset),
          decoration: BoxDecoration(
            color: gp.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: gp.border.withOpacity(0.8), width: 0.8),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cellWidth = constraints.maxWidth / 2;
              return Stack(
                children: [
                  // The highlight slides between the cells rather than
                  // blinking from one to the other: the eye follows the
                  // choice it just made.
                  AnimatedAlign(
                    duration: GameMotion.standard,
                    curve: Curves.easeOutCubic,
                    alignment: alarm
                        ? AlignmentDirectional.centerEnd
                        : AlignmentDirectional.centerStart,
                    child: Container(
                      width: cellWidth,
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: accent, width: 1.1),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      _cell(
                        context,
                        selected: !alarm,
                        icon: Icons.notifications_none_rounded,
                        label: s.reminderStyleNotification,
                        onTap: () => onChanged(false),
                      ),
                      _cell(
                        context,
                        selected: alarm,
                        icon: Icons.alarm_rounded,
                        label: s.reminderStyleAlarm,
                        onTap: () => onChanged(true),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
        // The hint grows in under the switch instead of appearing at once,
        // and only for the cell that needs explaining.
        AnimatedSize(
          duration: GameMotion.standard,
          curve: Curves.easeOutCubic,
          alignment: AlignmentDirectional.topStart,
          child: alarm
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.alarm_on_rounded, size: 13, color: accent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          s.reminderStyleAlarmHint,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: gp.textSec,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _cell(
    BuildContext context, {
    required bool selected,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final gp = context.gp;
    final color = selected ? accent : gp.textSec;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (selected) return;
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  scale: selected ? 1.0 : 0.9,
                  duration: GameMotion.quick,
                  child: Icon(icon, size: 17, color: color),
                ),
                const SizedBox(width: 6),
                AnimatedDefaultTextStyle(
                  duration: GameMotion.quick,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                    color: color,
                    height: 1.1,
                  ),
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
