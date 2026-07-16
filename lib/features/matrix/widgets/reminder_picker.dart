import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';

/// Formats [dt] for display on [ReminderRow] / anywhere else a task's
/// reminder needs a human label — "Today · 5:00 PM" / "Tomorrow · 9:00 AM"
/// / "Jul 18 · 9:00 AM". [now] defaults to the real clock but is
/// overridable so this stays a pure, deterministic function for
/// test/matrix_reminder_test.dart rather than something that has to mock
/// DateTime.now().
///
/// Deliberately keyed off the *real* calendar day (DateTimeGameExt.
/// isSameDayAs), not MatrixTask's own effectiveDay/carried-over concept —
/// a reminder fires at a real wall-clock moment, so "Today" here means
/// what the device's clock says today is, same reasoning as
/// DateTimeGameExt.isRealToday.
///
/// Public (not `_formatReminderMoment`) only so the test file — a separate
/// library — can call it directly; every other caller should go through
/// [ReminderRow] rather than calling this on its own.
@visibleForTesting
String formatReminderMoment(DateTime dt, bool isAr, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final locale = isAr ? 'ar' : 'en';
  final time = DateFormat('h:mm a', locale).format(dt);
  if (dt.isSameDayAs(today)) {
    return isAr ? 'اليوم · $time' : 'Today · $time';
  }
  if (dt.isSameDayAs(today.add(const Duration(days: 1)))) {
    return isAr ? 'غدًا · $time' : 'Tomorrow · $time';
  }
  final date = DateFormat('MMM d', locale).format(dt);
  return '$date · $time';
}

/// Two native dialogs (date, then time), not one bespoke combined widget —
/// this app has no custom date+time picker anywhere yet, and
/// showDatePicker/showTimePicker back to back is the same interaction a
/// user already knows from Settings' quiet-hours pickers
/// (notification_settings_screen.dart's _TimeRow) and Add Habit's time step
/// (add_habit_sheet.dart's _pickTime). Introducing a third, bespoke
/// combined picker just for this one row isn't worth the inconsistency.
///
/// A task reminder is an absolute, one-off moment (see MatrixTask.
/// reminderAt's doc comment) rather than a recurring wall-clock time, which
/// is exactly why this asks for a full date *and* time instead of just a
/// TimeOfDay the way habit reminders do — a Matrix task can sit carried
/// over for days (see MatrixScreen._carriedOverOnly), so "remind me" has to
/// be able to point at a day other than today or tomorrow.
///
/// Returns null if the user backs out of either dialog, or if the combined
/// result isn't actually in the future — a plain SnackBar explains the
/// second case rather than silently discarding it, but either way the
/// caller can treat null as "nothing changed," same as a cancelled
/// showTimePicker anywhere else in this app.
Future<DateTime?> pickReminderMoment(
  BuildContext context, {
  DateTime? initial,
}) async {
  final now = DateTime.now();
  final date = await showDatePicker(
    context: context,
    initialDate: initial != null && initial.isAfter(now) ? initial : now,
    firstDate: now,
    lastDate: now.add(const Duration(days: 365)),
  );
  if (date == null || !context.mounted) return null;

  final time = await showTimePicker(
    context: context,
    initialTime: initial != null
        ? TimeOfDay(hour: initial.hour, minute: initial.minute)
        : TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
  );
  if (time == null || !context.mounted) return null;

  final picked =
      DateTime(date.year, date.month, date.day, time.hour, time.minute);
  if (!picked.isAfter(DateTime.now())) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(S.of(context).matrixReminderPast)),
    );
    return null;
  }
  return picked;
}

/// Display + tap target for a task's reminder — "Set a reminder" when
/// unset, or the formatted moment plus a clear (×) button once one's
/// picked. Purely a dumb display widget driven by callbacks, same shape as
/// MicRecordButton/VoiceNoteRow (add_task_sheet.dart / voice_note_player.
/// dart): it never calls [pickReminderMoment] or NotificationService
/// itself, so AddTaskSheet (which can't persist anything yet — the task
/// doesn't exist) and TaskDetailSheet (which persists immediately, see its
/// own reminder handler) can each decide what picking or clearing actually
/// does, exactly like every other control shared between those two sheets.
class ReminderRow extends StatelessWidget {
  final DateTime? value;
  final Color color;
  final bool isAr;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const ReminderRow({
    super.key,
    required this.value,
    required this.color,
    required this.isAr,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final set = value != null;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: gp.surfaceHL,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: gp.border, width: 0.5),
        ),
        child: Row(
          children: [
            Icon(
              Icons.notifications_outlined,
              size: 18,
              color: set ? color : gp.textTert,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                set ? formatReminderMoment(value!, isAr) : s.matrixReminderLabel,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: set ? FontWeight.w700 : FontWeight.w600,
                  color: set ? gp.textPrimary : gp.textTert,
                ),
              ),
            ),
            if (set)
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  onClear();
                },
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child:
                      Icon(Icons.close_rounded, size: 16, color: gp.textTert),
                ),
              )
            else
              Icon(Icons.chevron_right_rounded, size: 18, color: gp.textTert),
          ],
        ),
      ),
    );
  }
}
