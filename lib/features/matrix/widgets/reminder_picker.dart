import 'dart:async';

import 'package:flutter/cupertino.dart'
    show
        CupertinoDatePicker,
        CupertinoDatePickerMode,
        CupertinoTextThemeData,
        CupertinoTheme,
        CupertinoThemeData;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/reminder_copy.dart';
import '../../../core/providers/alarm_choice_provider.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/western_digits.dart';
import '../../../shared/widgets/choice_chip_grid.dart';
import '../task_day.dart' show remindersFor;
import '../../../shared/widgets/overlay_notice.dart';
import '../../../shared/widgets/reminder_style_choice.dart';
import 'custom_offset_sheet.dart';

// arabicDigits, kReminderOffsetPresets and reminderOffsetLabel live in
// core/l10n/reminder_copy.dart, so notification copy can reach them without
// importing a widget file. Re-exported for the tests that import them from
// here (test/features/matrix/matrix_reminder_test.dart).
export '../../../core/l10n/reminder_copy.dart'
    show arabicDigits, kReminderOffsetPresets, reminderOffsetLabel;

// remindersFor and offsetsFrom live in task_day.dart, so MatrixNotifier can
// rebuild a moved task's stack without importing a widget file. Re-exported
// so the sheets and tests that import them from here keep working.
export '../task_day.dart' show remindersFor, offsetsFrom;

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
/// Genuinely public now, not just test-visible: [ReminderRow], the preview
/// line, and the custom-offset sheet's added-reminder chips all need the
/// same "which day, what time" phrasing, and a day-scale offset makes the
/// day half load-bearing — two reminders 48 hours apart otherwise render as
/// the identical clock time.
///
/// Through westernDate, like every date and time in this file: in the app
/// the raw patterns drew «سبتمبر ١٨ · ٩:٠٥ م», month first and in
/// Arabic-Indic digits. Arabic puts the day before the month.
///
/// The day half is [formatReminderDay]'s: «اليوم» on today, and the weekday
/// with the date on any other day, so «غدًا · 9:00 ص» is now «الأربعاء، 30
/// سبتمبر · 9:00 ص». Aziz, 2026-09-29: one set of day words everywhere,
/// the same the Tasks header and the Add sheet's day row use, and no word
/// for tomorrow (the row right above it names the day by its date).
String formatReminderMoment(DateTime dt, bool isAr, {DateTime? now}) {
  final locale = isAr ? 'ar' : 'en';
  final time = westernDate(dt, 'h:mm a', locale);
  return '${formatReminderDay(dt, isAr, now: now)} · $time';
}


/// Arabic-Indic digits (٠-٩) mapped to plain ASCII, so [int.tryParse] can
/// read a number typed on an Arabic keypad. Mirrors room_model.dart's
/// `_normalizeDigits` and HabitCue's equivalent — a user who types ٤٥ into
/// the minutes field must get 45, not a silent no-op.
String normalizeArabicDigits(String input) => toWesternDigits(input);


/// Two pickers back to back (the Material calendar, then a time wheel), not
/// one bespoke combined widget. The calendar is the same one Settings'
/// quiet-hours pickers and Add Habit's time step already use, and it
/// refuses past days on its own (`firstDate`).
///
/// The time used to be the Material dial too, and that is what changed: the
/// dial has no way to refuse a time, so at 4:00 PM it happily let somebody
/// choose 3:00 PM, closed, and only THEN the guard at the bottom said the
/// moment had passed, leaving them to start the whole thing over. The wheel
/// in [showReminderTimeSheet] carries a floor instead ([reminderWheelFloor]),
/// so on today's date the hours that have gone are greyed out and a spin
/// that lands on one rolls back to the earliest time still to come. Habit
/// reminders keep the dial: theirs is a recurring wall-clock time where
/// "3:00 PM" is never wrong, only late.
///
/// A task reminder is an absolute, one-off moment (see MatrixTask.
/// reminderAt's doc comment) rather than a recurring wall-clock time, which
/// is exactly why this asks for a full date *and* time instead of just a
/// TimeOfDay the way habit reminders do: in TaskDetailSheet, changing the
/// date here is how a task moves to another day (MatrixNotifier.
/// setReminders stores the new anchor's day). The Add sheet no longer comes
/// through here: its day row has already chosen the day, so its reminder
/// row opens the wheel alone ([pickReminderTimeOnDay]).
///
/// Returns null if the user backs out of either picker, or if the combined
/// result isn't actually in the future. With the floor that can only
/// happen when the clock crosses the picked minute while the wheel is still
/// open, and an overlay notice explains it rather than silently discarding
/// the pick. Either way the caller can treat null as "nothing changed,"
/// same as a cancelled showTimePicker anywhere else in this app.
Future<DateTime?> pickReminderMoment(
  BuildContext context, {
  DateTime? initial,
}) async {
  final now = DateTime.now();
  // ONE moment drives both pickers, so the date and the time can never
  // disagree. They used to be derived separately: the date defaulted to
  // today while the time defaulted to now + 1 hour, so any task added
  // after 23:00 offered today at 00:30 — a moment already in the past,
  // which the guard below then rejected. The user was left to work out on
  // their own that they had to advance the date by a day.
  final suggested = initial != null && initial.isAfter(now)
      ? initial
      : now.add(const Duration(hours: 1));
  // A year ahead, and never short of the day the calendar opens on. The
  // Tasks month sheet plans to the last day of the month a year ahead,
  // which can be a few days past now + 365, and showDatePicker asserts
  // on an initialDate after lastDate: a task planned for that day could
  // not have been given a time.
  final yearAhead = now.add(const Duration(days: 365));
  final date = await showDatePicker(
    context: context,
    initialDate: suggested,
    firstDate: now,
    lastDate: suggested.isAfter(yearAhead) ? suggested : yearAhead,
  );
  if (date == null || !context.mounted) return null;

  // Read the clock again: the calendar can stay open for a while, and the
  // floor has to be measured from the moment the wheel appears.
  final floor = reminderWheelFloor(day: date, now: DateTime.now());
  final time = await showReminderTimeSheet(
    context,
    day: date,
    initial: reminderWheelInitial(
      day: date,
      suggested: suggested,
      floor: floor,
    ),
    floor: floor,
  );
  if (time == null || !context.mounted) return null;

  final picked =
      DateTime(date.year, date.month, date.day, time.hour, time.minute);
  if (!picked.isAfter(DateTime.now())) {
    // Overlay, not SnackBar: both host sheets are modals, so the SnackBar
    // version of this message drew behind them — the user picked a past
    // time, both dialogs closed, and the row still said "set a reminder"
    // with no visible explanation of why.
    showOverlayNotice(
      context,
      S.of(context).matrixReminderPast,
      icon: Icons.history_toggle_off_rounded,
    );
    return null;
  }
  return picked;
}

/// The time half of [pickReminderMoment] alone, on a [day] the caller has
/// already settled: the Add sheet's reminder row (its day row above chose
/// the day, so a calendar step would ask the same question twice and could
/// answer it differently) and the move sheet, when a task's own time has
/// already gone on the day it is moving to.
///
/// The same floor and the same past-moment guard as [pickReminderMoment],
/// so a time that has passed can be neither landed on nor returned; the
/// guard's overlay notice explains a null when the clock crosses the picked
/// minute while the wheel is open. [initial] is the time already set, whose
/// clock time the wheel starts on (see [reminderSuggestedTime]).
Future<DateTime?> pickReminderTimeOnDay(
  BuildContext context, {
  required DateTime day,
  DateTime? initial,
}) async {
  final now = DateTime.now();
  final floor = reminderWheelFloor(day: day, now: now);
  final time = await showReminderTimeSheet(
    context,
    day: day,
    initial: reminderWheelInitial(
      day: day,
      suggested: reminderSuggestedTime(day: day, initial: initial, now: now),
      floor: floor,
    ),
    floor: floor,
  );
  if (time == null || !context.mounted) return null;

  final picked =
      DateTime(day.year, day.month, day.day, time.hour, time.minute);
  if (!picked.isAfter(DateTime.now())) {
    // Overlay, not SnackBar: the hosts are modal sheets (see
    // pickReminderMoment).
    showOverlayNotice(
      context,
      S.of(context).matrixReminderPast,
      icon: Icons.history_toggle_off_rounded,
    );
    return null;
  }
  return picked;
}

/// The time the wheel should start on for [day], before the floor lifts it
/// ([reminderWheelInitial] does that and places it on [day]).
///
///  * A time already set ([initial]) keeps its clock time, when that time
///    is still ahead on [day]: reopening a set reminder starts where it is.
///  * Otherwise, on today, an hour from now: the same default
///    [pickReminderMoment] has always used.
///  * Otherwise, on a later day, 9:00 AM. "An hour from now" means nothing
///    for next Tuesday, and 9 in the morning is where a day's plan starts.
DateTime reminderSuggestedTime({
  required DateTime day,
  DateTime? initial,
  required DateTime now,
}) {
  if (initial != null) {
    final onDay =
        DateTime(day.year, day.month, day.day, initial.hour, initial.minute);
    if (onDay.isAfter(now)) return onDay;
  }
  if (day.isSameDayAs(now)) return now.add(const Duration(hours: 1));
  return DateTime(day.year, day.month, day.day, 9);
}

/// The first whole minute after [now]: 3:04:30 PM becomes 3:05:00 PM, and
/// so does 3:04:00 PM exactly. A reminder is scheduled to the minute, so
/// "the earliest time still to come" is the next minute boundary, never
/// the one the clock is already inside.
DateTime reminderTimeFloor(DateTime now) =>
    DateTime(now.year, now.month, now.day, now.hour, now.minute + 1);

/// The earliest time the wheel may land on when the reminder is for [day],
/// or null when every time on that day is fair game.
///
/// Only today has a floor. A later day has no past hours, and an earlier
/// day cannot be picked at all (the calendar's `firstDate`). The one gap is
/// the last minute of the day: at 11:59 PM the floor rolls into tomorrow,
/// no time left today is valid, and rather than pin the wheel to a floor
/// on the wrong day this returns null and lets [pickReminderMoment]'s guard
/// say so.
DateTime? reminderWheelFloor({required DateTime day, required DateTime now}) {
  if (!day.isSameDayAs(now)) return null;
  final floor = reminderTimeFloor(now);
  return floor.isSameDayAs(day) ? floor : null;
}

/// Where the wheel starts: [suggested]'s clock time placed on [day], lifted
/// to [floor] when it would otherwise start on a time that has passed. The
/// wheel would roll a too-early start up to the floor by itself, but only
/// after animating there in front of the person; starting where it will end
/// reads as intended rather than corrected.
DateTime reminderWheelInitial({
  required DateTime day,
  required DateTime suggested,
  required DateTime? floor,
}) {
  final onDay =
      DateTime(day.year, day.month, day.day, suggested.hour, suggested.minute);
  if (floor != null && onDay.isBefore(floor)) return floor;
  return onDay;
}

/// The day the wheel is choosing a time for: «اليوم» / "Today" on today,
/// otherwise the weekday and date the Tasks header uses («الأربعاء، 30
/// سبتمبر» / "Wednesday, Sep 30"), with the year only when it is not
/// [now]'s. No «غدًا»: Aziz asked for the same day words everywhere
/// (2026-09-29). [formatReminderMoment] is this plus the time.
///
/// Through weekdayDateLabel, which puts the Arabic comma in Arabic and a
/// plain one in English; the raw 'EEEE، d MMMM' this used before printed
/// "Wednesday، 30 September" in English.
String formatReminderDay(DateTime day, bool isAr, {DateTime? now}) {
  final today = now ?? DateTime.now();
  if (day.isSameDayAs(today)) return isAr ? 'اليوم' : 'Today';
  final locale = isAr ? 'ar' : 'en';
  final label = weekdayDateLabel(day, isAr: isAr, locale: locale);
  if (day.year == today.year) return label;
  final year = toWesternDigits(day.year.toString());
  return isAr ? '$label $year' : '$label, $year';
}

/// The time half of [pickReminderMoment]: an hour / minute / AM-PM wheel in
/// one of this app's own sheets, with an optional [floor] below which the
/// wheel will not settle.
///
/// A wheel rather than the Material dial because the dial cannot carry a
/// floor at all (see [pickReminderMoment] for the mistake that let
/// through). CupertinoDatePicker greys out every hour, minute and meridiem
/// that would land before `minimumDate` and scrolls itself back to the
/// nearest valid time when a spin stops on one, which is exactly the
/// "locked" behaviour wanted, and it renders the same on Android.
/// [initial] must already be on [day] and at or after [floor]
/// ([reminderWheelInitial] guarantees both).
///
/// Returns the time behind Done, or null on a swipe-down / tap outside.
Future<TimeOfDay?> showReminderTimeSheet(
  BuildContext context, {
  required DateTime day,
  required DateTime initial,
  required DateTime? floor,
}) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ReminderTimeSheet(
      day: day,
      initial: initial,
      floor: floor,
    ),
  );
}

class _ReminderTimeSheet extends StatefulWidget {
  final DateTime day;
  final DateTime initial;
  final DateTime? floor;

  const _ReminderTimeSheet({
    required this.day,
    required this.initial,
    required this.floor,
  });

  @override
  State<_ReminderTimeSheet> createState() => _ReminderTimeSheetState();
}

class _ReminderTimeSheetState extends State<_ReminderTimeSheet> {
  late DateTime _selected = widget.initial;

  /// What Done hands back. The wheel reports every position it passes
  /// through, including a too-early one it is about to roll back from, so
  /// a Done tapped mid-roll is clamped to the floor rather than trusted.
  TimeOfDay get _result {
    final floor = widget.floor;
    final at = floor != null && _selected.isBefore(floor) ? floor : _selected;
    return TimeOfDay.fromDateTime(at);
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final floor = widget.floor;
    final locale = s.isAr ? 'ar' : 'en';
    final wheelStyle = TextStyle(
      fontSize: 21,
      fontWeight: FontWeight.w600,
      color: gp.textPrimary,
      fontFamily: GameTextStyles.fontFamily,
      fontFamilyFallback: GameTextStyles.fontFallback,
    );
    final sheet = Container(
      padding: EdgeInsets.fromLTRB(
        20,
        10,
        20,
        20 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: gp.surfaceHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: gp.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            s.matrixReminderTimeTitle,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: gp.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            formatReminderDay(widget.day, s.isAr),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: gp.textSec,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 200,
            // The wheel reads its type from CupertinoTheme, which inside a
            // MaterialApp is the platform default, not this app's font or
            // ink. Only the picker text style is overridden; the greyed-out
            // (invalid) entries keep Cupertino's own inactive grey, which
            // is the cue that makes the floor visible.
            child: CupertinoTheme(
              data: CupertinoThemeData(
                brightness: Theme.of(context).brightness,
                textTheme: CupertinoTextThemeData(
                  dateTimePickerTextStyle: wheelStyle,
                ),
              ),
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.time,
                initialDateTime: widget.initial,
                minimumDate: floor,
                // 12-hour (the default), as every other time in this app
                // is shown (formatReminderMoment's 'h:mm a').
                backgroundColor: Colors.transparent,
                onDateTimeChanged: (at) => setState(() => _selected = at),
              ),
            ),
          ),
          if (floor != null) ...[
            const SizedBox(height: 4),
            Text(
              s.matrixReminderEarliest(westernDate(floor, 'h:mm a', locale)),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: gp.textTert,
              ),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () {
              HapticFeedback.selectionClick();
              Navigator.pop(context, _result);
            },
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(s.matrixDone),
          ),
        ],
      ),
    );
    // Lifts the sheet clear of the keyboard when one is still up (the
    // task's title field usually holds it), same as every other sheet
    // here: a modal sheet is not moved by the keyboard on its own, and
    // Done would otherwise sit behind it.
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: sheet,
    );
  }
}

/// Display + tap target for a task's reminder — "Set a reminder" when
/// unset, or the formatted moment plus a clear (×) button once one's
/// picked. Purely a dumb display widget driven by callbacks, same shape as
/// VoiceNoteRecordRow/VoiceNoteRow (voice_note_player.dart): it never
/// calls [pickReminderMoment] or NotificationService
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
                set
                    ? formatReminderMoment(value!, isAr)
                    : s.matrixReminderLabel,
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

/// A task's whole reminder set: one anchor time, plus any number of
/// offsets before or after it.
///
/// Modelled deliberately on Add Habit's "Remind me" section — the same
/// [ChoiceChipGrid], the same before/after toggle, the same custom-minutes
/// escape hatch — because both screens ask the identical question and a
/// user who has learned one shouldn't have to learn the other. The
/// difference is that offsets here are *multi*-select: a task can nudge at
/// 4:00, 4:30 and 5:00, where a habit fires once.
///
/// Flow is anchor-first by design. Tapping an unset reminder goes straight
/// to the host's picker (TaskDetailSheet's date and time, the Add sheet's
/// time wheel on the day its day row holds), because when the thing
/// happens is the one piece
/// of information only the user has; everything after that is arithmetic
/// the app can do for them. Until an anchor exists there is nothing for
/// "before" or "after" to mean, so the offsets don't appear at all.
///
/// Same dumb-display contract as [ReminderRow]: it never calls
/// [pickReminderMoment], NotificationService, or the premium providers
/// itself. The sheets own all of that.
class ReminderPicker extends StatefulWidget {
  /// The moment everything else is relative to — usually the thing being
  /// remembered (the 5pm meeting), not a warning about it. Null means no
  /// reminders at all, which is most tasks.
  final DateTime? anchorAt;

  /// Signed minutes: negative before the anchor, positive after. The same
  /// convention Add Habit's `reminderOffsetMinutes` uses, so the two
  /// features can't disagree about what a negative number means.
  final Set<int> offsets;

  final Color color;
  final bool isAr;

  /// False on the free tier once an anchor exists. Matches Todoist and
  /// TickTick, which both give one reminder per task away and charge for
  /// the stack. The chips stay visible and tappable either way — tapping
  /// one just opens the upsell instead of selecting it, so the feature is
  /// discoverable rather than invisible.
  final bool canStack;

  final VoidCallback onPickAnchor;
  final VoidCallback onClear;
  final void Function(int signedMinutes) onToggleOffset;
  final VoidCallback onLocked;

  /// Whether this task's reminders ring as an alarm (MatrixTask.alarm), and
  /// what the device can offer (alarmChoiceProvider, read by the sheet). On
  /// an iPhone older than iOS 26 the choice is drawn, with the alarm cell
  /// grey and saying what it needs; where there is nothing to offer or say,
  /// it is not drawn, and the picker looks exactly as it did before alarms
  /// existed.
  final bool alarm;
  final AlarmChoice alarmChoice;

  /// The person picked the other style. The sheet owns the permission ask
  /// that "alarm" needs, so this only reports the wish.
  final void Function(bool alarm) onAlarmChanged;

  const ReminderPicker({
    super.key,
    required this.anchorAt,
    required this.offsets,
    required this.color,
    required this.isAr,
    required this.canStack,
    required this.onPickAnchor,
    required this.onClear,
    required this.onToggleOffset,
    required this.onLocked,
    this.alarm = false,
    this.alarmChoice = AlarmChoice.hidden,
    this.onAlarmChanged = _ignoreAlarmChange,
  });

  static void _ignoreAlarmChange(bool _) {}

  @override
  State<ReminderPicker> createState() => _ReminderPickerState();
}

class _ReminderPickerState extends State<ReminderPicker> {
  /// Offsets the task carries that no preset chip stands for — a hand-typed
  /// 45, or a day-scale one.
  ///
  /// No direction filter, unlike the version that had a قبل/بعد toggle: with
  /// signed presets there is no "current tab" for an offset to fall outside
  /// of, so every reminder the task holds has a chip, always. That filter was
  /// the reason a stored offset could vanish from the grid entirely while
  /// still being scheduled.
  ///
  /// Which direction the offset chips currently mean.
  ///
  /// Seeded from the task's own offsets rather than hardcoded to "before",
  /// and that is half the bug this screen had. The old initialiser was a
  /// plain `= false`, so a task built entirely out of "after" offsets
  /// reopened on the قبل tab with an empty-looking grid — every chip it
  /// actually had was in the other tab.
  ///
  /// It went unnoticed because the *other* half of the bug hid it: the
  /// anchor used to be re-guessed as the last reminder on reopen, which
  /// forced every reconstructed offset negative, so everything really was
  /// "before" and the wrong default happened to look right. Now that the
  /// anchor is stored and an after-ladder comes back as an after-ladder
  /// (see offsetsFrom), this has to read the data or it lands on the wrong
  /// tab. The two fixes only work together.
  ///
  /// Ties and empties go to "before": a reminder about a thing almost
  /// always wants to arrive ahead of it.
  late bool _isAfter = _initialIsAfter();

  bool _initialIsAfter() {
    final offsets = widget.offsets;
    if (offsets.isEmpty) return false;
    return offsets.every((o) => !o.isNegative);
  }

  int _signed(int minutes) => _isAfter ? minutes : -minutes;

  /// Offsets belonging to the *current* tab that no preset chip stands for
  /// — a hand-typed value like 45, or a day-scale one.
  ///
  /// Scoped to the direction on purpose: قبل and بعد read as two tabs, so a
  /// "2 days after" chip sitting under a selected قبل would contradict the
  /// tab it's in. Anything in the other direction is still scheduled and
  /// still listed in the preview line below; switching tabs brings it back
  /// into view, and the custom sheet lists every direction at once.
  List<int> get _unlistedOffsets {
    final out = widget.offsets
        .where((o) => o.isNegative != _isAfter)
        .where((o) => !kReminderOffsetPresets.contains(o.abs()))
        .toList()
      ..sort();
    return out;
  }

  /// The counted, unit-aware form — "يومين", not "٢٨٨٠".
  ///
  /// No direction word: [_unlistedOffsets] only ever yields offsets matching
  /// the selected tab, so every chip on screen already shares the قبل/بعد
  /// above them — printing it on each one would just repeat the tab.
  ///
  /// Latin digits on screen; the shared phrase keeps Arabic-Indic ones for
  /// the notification copy.
  ///
  /// Hours with counted minutes are too long for a chip in full: «12 ساعة
  /// و45 دقيقة» was cut to «12 ساعة و45…» on the phone. Those take the
  /// chip form, «12 س و45 د», as does every hours-and-minutes value in
  /// English ("4h 30m"). Arabic half and quarter hours are short enough to
  /// say in full, «4 ساعات ونص». The chip's screen-reader label is always
  /// the full phrase.
  String _unlistedLabel(S s, int offset) {
    final magnitude = offset.abs();
    final rest = magnitude % 60;
    final chipForm = magnitude > 60 &&
        rest != 0 &&
        (!widget.isAr || (rest != 30 && rest != 15));
    return toWesternDigits(
      chipForm
          ? formatOffsetMagnitude(offset, widget.isAr, s)
          : formatOffsetVerbose(offset, widget.isAr, s, withDirection: false),
    );
  }

  /// Whether an offset would still land in the future. An offset that has
  /// already elapsed can be previewed and stored but will never be
  /// scheduled (see MatrixNotifier.futureTaskReminders), so offering it
  /// would promise a nudge that silently never arrives.
  bool _isReachable(int signedMinutes) {
    final at = widget.anchorAt?.add(Duration(minutes: signedMinutes));
    return at != null && at.isAfter(DateTime.now());
  }

  /// Why the last tap didn't do anything, shown inline under the grid.
  ///
  /// Inline rather than a SnackBar, because this widget lives inside a
  /// showModalBottomSheet and the ScaffoldMessenger is *behind* that sheet —
  /// a SnackBar posted from here is drawn under the sheet and never seen.
  /// The custom-offset sheet already learned this the hard way and states it
  /// in its own source; the two rejections reachable from this grid (the
  /// slot ceiling, an offset that has already elapsed) were still answering
  /// with nothing at all.
  String? _notice;
  Timer? _noticeTimer;

  void _showNotice(String message) {
    setState(() => _notice = message);
    _noticeTimer?.cancel();
    // Roughly a SnackBar's dwell. Cleared rather than left in place so the
    // section doesn't accumulate a permanent scolding line.
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    super.dispose();
  }

  void _toggle(int minutes) {
    final s = S.of(context);
    final signed = _signed(minutes);
    // Deselecting is always allowed, whatever the entitlement says. The
    // premium gate is on *adding* — see kFreeTaskReminders' doc comment,
    // which promises a task keeps the reminders it already has if a
    // subscription lapses. Gating removal too would strand someone with an
    // inherited stack they can only clear wholesale, never trim.
    if (widget.offsets.contains(signed)) {
      HapticFeedback.selectionClick();
      widget.onToggleOffset(signed);
      return;
    }
    if (!widget.canStack) {
      widget.onLocked();
      return;
    }
    // The anchor occupies a slot too, so this is the same arithmetic the
    // host sheets do before they persist. Checked here as well because here
    // is where the tap happens and so here is where it can be explained.
    if (widget.offsets.length + 1 >=
        NotificationService.kMaxTaskReminderSlots) {
      HapticFeedback.lightImpact();
      _showNotice(s.matrixReminderMaxReached);
      return;
    }
    if (!_isReachable(signed)) {
      HapticFeedback.lightImpact();
      _showNotice(s.matrixReminderOffsetPast);
      return;
    }
    HapticFeedback.selectionClick();
    widget.onToggleOffset(signed);
  }

  /// Opens the custom-offset sheet — a number, its unit, and the list of
  /// what's already set, none of which fits beside the grid on a phone.
  ///
  /// Everything the sheet changes is applied through
  /// [ReminderPicker.onToggleOffset] as it happens rather than handed back
  /// on close, so dismissing it can never lose an entry.
  void _openCustomSheet() {
    final anchor = widget.anchorAt;
    if (anchor == null) return;
    showCustomOffsetSheet(
      context,
      anchor: anchor,
      offsets: widget.offsets,
      // Seeds the sheet with whatever direction the grid is showing, so
      // opening it doesn't silently flip what a typed "45" would mean.
      isAfter: _isAfter,
      color: widget.color,
      isAr: widget.isAr,
      // A closure over `widget`, not the bool: the sheet outlives this
      // build, and `widget` is always the current one, so the answer stays
      // live for as long as the sheet is open. Our own parents already
      // re-supply canStack via ref.watch, so this is the only frozen link.
      canStack: () => widget.canStack,
      onToggle: widget.onToggleOffset,
      // The sheet owns the direction while it's open, and the grid adopts
      // whatever it ends on, so the offsets you just created are the ones in
      // view when you come back.
      onDirectionChanged: (after) => setState(() => _isAfter = after),
      onLocked: widget.onLocked,
      maxOffsets: NotificationService.kMaxTaskReminderSlots,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final gp = context.gp;
    final anchor = widget.anchorAt;
    if (anchor == null) {
      return ReminderRow(
        value: null,
        color: widget.color,
        isAr: widget.isAr,
        onTap: widget.onPickAnchor,
        onClear: () {},
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ReminderRow(
          value: anchor,
          color: widget.color,
          isAr: widget.isAr,
          onTap: widget.onPickAnchor,
          onClear: widget.onClear,
        ),
        const SizedBox(height: 14),
        // Named "extra reminders", not just "remind me": the row above is
        // already a reminder, and without saying so these chips read as if
        // they replace it rather than add to it. The hint spells out that
        // more than one can be picked — a multi-select grid is otherwise
        // indistinguishable from the single-choice ones used everywhere
        // else in this app.
        Text(
          s.matrixExtraRemindersSection,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: context.gp.textTert,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          s.matrixExtraRemindersHint,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: context.gp.textTert.withOpacity(0.75),
          ),
        ),
        const SizedBox(height: 8),
        ChoiceChipGrid(
          columns: 2,
          items: [
            PlainChoiceChip(
              selected: !_isAfter,
              label: s.offsetBeforeLabel,
              selectedColor: widget.color,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _isAfter = false);
              },
            ),
            PlainChoiceChip(
              selected: _isAfter,
              label: s.offsetAfterLabel,
              selectedColor: widget.color,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _isAfter = true);
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Multi-select, unlike every other ChoiceChipGrid in the app: each
        // chip is an independent on/off, because the whole point is picking
        // several at once. Selection is read back off `offsets` rather than
        // held locally, so the chips can't drift out of step with the
        // reminders actually stored on the task.
        //
        // Five presets plus the custom field: six cells on three columns,
        // two complete rows in the default state. Any offset the presets
        // don't cover is appended as its own chip.
        //
        // Unreachable offsets (an hour's lead on something 20 minutes away)
        // are dimmed rather than hidden, so the grid keeps its shape
        // instead of reflowing under the user's finger as time passes.
        ChoiceChipGrid(
          columns: 3,
          items: [
            for (final m in kReminderOffsetPresets)
              _OffsetChip(
                selected: widget.offsets.contains(_signed(m)),
                reachable: _isReachable(_signed(m)),
                // Latin, like the preview line under the grid; the shared
                // label keeps Arabic-Indic digits for notifications.
                label: toWesternDigits(reminderOffsetLabel(m, widget.isAr)),
                semanticsLabel: formatOffsetVerbose(_signed(m), widget.isAr, s),
                color: widget.color,
                onTap: () => _toggle(m),
              ),
            for (final o in _unlistedOffsets)
              _OffsetChip(
                selected: true,
                reachable: true,
                label: _unlistedLabel(s, o),
                semanticsLabel: formatOffsetVerbose(o, widget.isAr, s),
                color: widget.color,
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onToggleOffset(o);
                },
              ),
            // The custom cell opens a sheet rather than being an inline
            // field: entering a value needs a direction *and* a number
            // *and* a unit, three controls more than this row can hold on
            // a phone. It adds one reminder and closes; what it added
            // shows up here as its own chip.
            PlainChoiceChip(
              selected: false,
              label: s.leadCustomOption,
              selectedColor: widget.color,
              onTap: _openCustomSheet,
            ),
          ],
        ),
        if (widget.alarmChoice != AlarmChoice.hidden)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            // Notification or alarm, the same switch the habit sheet shows
            // under its reminder time (see _AddHabitSheetState
            // ._reminderStyleRow), so the two features read as one.
            child: ReminderStyleChoice(
              alarm: widget.alarm,
              accent: widget.color,
              onChanged: widget.onAlarmChanged,
              alarmChoice: widget.alarmChoice,
            ),
          ),
        if (_notice != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 13, color: gp.textTert),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _notice!,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: gp.textTert,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        _ReminderPreview(
          anchor: anchor,
          offsets: widget.offsets,
          color: widget.color,
          isAr: widget.isAr,
          // Opens the same sheet the "مخصص" cell does. Once a task carries
          // four or five reminders this line wraps into a dense run of
          // times, and it's precisely then that someone wants to look at
          // what they've set and drop one — the sheet lists them as
          // labelled rows with remove buttons.
          onTap: _openCustomSheet,
        ),
      ],
    );
  }
}

/// A preset offset. Wraps [PlainChoiceChip] purely to add the dimmed state
/// for an offset whose moment has already passed — selection styling,
/// geometry and motion all still come from the shared chip, so this can't
/// drift from Add Habit's.
///
/// Dimmed but still tappable, deliberately. It used to be wrapped in an
/// IgnorePointer, so a user setting a reminder ten minutes out saw the
/// longer leads greyed and could not find out why — the tap simply did
/// nothing. Letting it through means [_ReminderPickerState._toggle] gets to
/// say "that time has already passed" instead of the chip silently
/// swallowing the press. Marked disabled for assistive tech either way,
/// since 0.35 opacity conveys nothing to a screen reader.
///
/// An already-selected chip never dims: it represents a reminder the task
/// genuinely has, and greying it out would imply it isn't real while also
/// making it look unremovable.
class _OffsetChip extends StatelessWidget {
  final bool selected;
  final bool reachable;
  final String label;
  final String semanticsLabel;
  final Color color;
  final VoidCallback onTap;

  const _OffsetChip({
    required this.selected,
    required this.reachable,
    required this.label,
    required this.semanticsLabel,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final chip = PlainChoiceChip(
      selected: selected,
      label: label,
      semanticsLabel: semanticsLabel,
      selectedColor: color,
      onTap: onTap,
    );
    if (selected || reachable) return chip;
    return Semantics(
      enabled: false,
      child: Opacity(opacity: 0.35, child: chip),
    );
  }
}

/// The arithmetic, done. Lists every moment the task will actually fire at,
/// in order, so the user never has to work out what "30 before" lands on —
/// which is the whole reason the offsets are worth offering.
///
/// Hidden when there's only the anchor: the row directly above already
/// shows that time, and repeating it would read as a second reminder.
class _ReminderPreview extends StatelessWidget {
  final DateTime anchor;
  final Set<int> offsets;
  final Color color;
  final bool isAr;
  final VoidCallback onTap;

  const _ReminderPreview({
    required this.anchor,
    required this.offsets,
    required this.color,
    required this.isAr,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final all = remindersFor(anchor: anchor, offsets: offsets);
    if (all.length <= 1) return const SizedBox.shrink();
    // formatReminderMoment, not a bare time: once day-scale offsets exist a
    // stack can span dates, and "10:31 AM · 10:31 AM" for two reminders two
    // days apart is worse than no preview at all. But the day only where it
    // changes: since the day half names the weekday too (2026-09-29), three
    // reminders on one day read «الجمعة، 2 أكتوبر · 4:15 م   ·   4:45 م   ·
    // 5:00 م» instead of repeating the whole date three times. The list is
    // sorted (remindersFor), so "where it changes" is simply "differs from
    // the one before".
    final locale = isAr ? 'ar' : 'en';
    final labels = <String>[
      for (var i = 0; i < all.length; i++)
        i > 0 && all[i].isSameDayAs(all[i - 1])
            ? westernDate(all[i], 'h:mm a', locale)
            : formatReminderMoment(all[i], isAr),
    ];
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.notifications_active_rounded, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  labels.join('   ·   '),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: context.gp.textSec,
                    height: 1.35,
                  ),
                ),
              ),
              // A quiet affordance — without it the summary looks like a
              // caption, and nobody discovers that it opens anything.
              Padding(
                padding: const EdgeInsets.only(top: 1),
                // chevron_right, same as ReminderRow's — Flutter mirrors it
                // under RTL, so hardcoding "left" here would point the wrong
                // way in the language this screen is mostly used in.
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: context.gp.textTert,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
