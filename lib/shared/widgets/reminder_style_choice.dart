import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/alarm_choice_provider.dart' show AlarmChoice;
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
///
/// Where no alarm can ring ([alarmChoice]: an iPhone older than iOS 26, or
/// one whose alarm permission was refused) the alarm cell is grey and
/// cannot be chosen (Aziz, 2026-09-18), dimmed the way a reminder chip that
/// can no longer be picked is (ReminderPicker's _OffsetChip). Still
/// tappable on purpose, like that chip: the tap never switches, the cell
/// shakes once and the line under the switch says why and what fixes it,
/// so the grey is never a dead end.
class ReminderStyleChoice extends StatefulWidget {
  /// True when the reminder rings as an alarm.
  final bool alarm;

  /// The sheet's accent: gold in the habit sheet, the quadrant colour in a
  /// task sheet.
  final Color accent;

  final ValueChanged<bool> onChanged;

  /// What this phone can do with an alarm (alarmChoiceProvider). Anything
  /// that cannot ring one greys the alarm cell, and [onChanged] is then
  /// never called with true. A reminder already set to alarm, on another
  /// iPhone or before the permission went, still shows as one, with the
  /// note in place of the hint: on this phone it arrives as a notification.
  final AlarmChoice alarmChoice;

  const ReminderStyleChoice({
    super.key,
    required this.alarm,
    required this.accent,
    required this.onChanged,
    this.alarmChoice = AlarmChoice.available,
  });

  @override
  State<ReminderStyleChoice> createState() => _ReminderStyleChoiceState();
}

class _ReminderStyleChoiceState extends State<ReminderStyleChoice>
    with SingleTickerProviderStateMixin {
  static const double _height = 46;
  static const double _inset = 4;

  /// The alarm cell was tapped on a phone that cannot ring one. The note
  /// then stays for as long as the switch is on screen.
  bool _explained = false;

  /// One damped side-to-side shake of the alarm cell's content: the "no"
  /// every iPhone already gives for a wrong passcode. Made in initState,
  /// not lazily: a switch that never shook would otherwise first create it
  /// in dispose, where a ticker can no longer look up its TickerMode.
  late final AnimationController _shake;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  void _explainAlarm() {
    HapticFeedback.lightImpact();
    _shake.forward(from: 0);
    if (!_explained) setState(() => _explained = true);
  }

  /// Why no alarm can ring on this phone, and the icon the note wears, or
  /// null when one can.
  ({String text, IconData icon})? _blockedNote(S s) =>
      switch (widget.alarmChoice) {
        AlarmChoice.needsNewerIos => (
            text: s.alarmNeedsNewerIos,
            icon: Icons.system_update_rounded,
          ),
        AlarmChoice.permissionDenied => (
            text: s.alarmPermissionDenied,
            icon: Icons.alarm_off_rounded,
          ),
        AlarmChoice.available || AlarmChoice.hidden => null,
      };

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final gp = context.gp;
    final alarm = widget.alarm;
    final accent = widget.accent;
    final blockedNote = _blockedNote(s);
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
                        onTap: () => widget.onChanged(false),
                      ),
                      _cell(
                        context,
                        selected: alarm,
                        icon: Icons.alarm_rounded,
                        label: s.reminderStyleAlarm,
                        blockedHint: blockedNote?.text,
                        onTap: blockedNote != null
                            ? _explainAlarm
                            : () => widget.onChanged(true),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
        // The hint grows in under the switch instead of appearing at once,
        // and only for the cell that needs explaining. On a phone that
        // cannot ring an alarm, the note that says why takes its place.
        AnimatedSize(
          duration: GameMotion.standard,
          curve: Curves.easeOutCubic,
          alignment: AlignmentDirectional.topStart,
          child: blockedNote != null && (alarm || _explained)
              ? Semantics(
                  liveRegion: true,
                  child: _line(
                    context,
                    icon: blockedNote.icon,
                    iconColor: gp.textTert,
                    text: blockedNote.text,
                  ),
                )
              : alarm
                  ? _line(
                      context,
                      icon: Icons.alarm_on_rounded,
                      iconColor: accent,
                      text: s.reminderStyleAlarmHint,
                    )
                  : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _line(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String text,
  }) {
    final gp = context.gp;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: iconColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
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
    );
  }

  /// [blockedHint] marks the alarm cell on a phone that cannot ring one:
  /// it is dimmed and marked disabled, its tap explains instead of
  /// selecting (so no selection click), and a screen reader hears the
  /// reason before tapping at all. A selected cell never dims, as an offset
  /// chip never does: an alarm set on another iPhone is real there.
  Widget _cell(
    BuildContext context, {
    required bool selected,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    String? blockedHint,
  }) {
    final gp = context.gp;
    final color = selected ? widget.accent : gp.textSec;
    final blocked = blockedHint != null;
    final dimmed = blocked && !selected;
    Widget content = Row(
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
    );
    if (blocked) {
      content = AnimatedBuilder(
        animation: _shake,
        builder: (context, child) {
          final t = _shake.value;
          final dx = math.sin(t * math.pi * 6) * 5 * (1 - t);
          return Transform.translate(offset: Offset(dx, 0), child: child);
        },
        child: content,
      );
    }
    if (dimmed) content = Opacity(opacity: 0.35, child: content);
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        enabled: dimmed ? false : null,
        label: label,
        hint: blockedHint,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (selected) return;
            if (!blocked) HapticFeedback.selectionClick();
            onTap();
          },
          child: Center(child: content),
        ),
      ),
    );
  }
}
