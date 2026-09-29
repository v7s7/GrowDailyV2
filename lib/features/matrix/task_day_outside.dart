// THE DAY RULE outside the Tasks page: the two places main.dart reads the
// task board without drawing it, the evening note's urgent count and the
// task widgets' payload. Pure and clock-free like task_day.dart (every
// "today" is passed in), and kept out of main.dart so a test can reach them
// without building the app.
//
// Both used to read a task as "open, so it is today's work", which was true
// while every task was filed on the day it was created. Now a task can be
// planned for a later day (plannedDay, or a reminder on that day), and read
// that way the evening note counted next week's plans as urgent tonight, and
// the Lock Screen put a task planned for Thursday among today's untimed work.
// Each answer below goes through task_day.dart, so it cannot disagree with
// the board a tap on the note or the widget lands on.

import 'models/matrix_task.dart';
import 'task_day.dart';

/// How many open Do First tasks the evening note may call urgent tonight
/// («وعندك مهمتين عاجلتين»): those whose day is [today] or already behind
/// it, the Today board's open Do First tasks plus the «مُرحّلة» ones.
///
/// A task planned for a later day is left out. It is not urgent tonight,
/// and counting it told someone who had cleared today's Do First tasks that
/// two were still waiting, both of them next week's. Carried-over tasks stay
/// in: open and past their day is exactly what the sentence is for.
///
/// Written as "not «قادمة»" ([isUpcoming]) rather than as its own date test,
/// so the count is by construction the complement of the chip.
int openDoFirstDueCount(Iterable<MatrixTask> tasks, DateTime today) => tasks
    .where(
      (t) =>
          t.quadrant == MatrixQuadrant.doFirst &&
          !t.isDone &&
          !isUpcoming(t, today),
    )
    .length;

/// The moment the task widgets receive as a task's `dueAt`
/// (HomeWidgetService.updateMatrixWidgetData), which the Lock Screen sorts
/// by (ios/GrowDailyWidget/MatrixLockScreenOrder.swift): a time on the day
/// drawn, then no time, then a time on another day.
///
///  * A timed task: the moment the user picked, [MatrixTask.
///    reminderAnchorAt], exactly as before. Still null for a legacy task
///    saved before the anchor existed, as it always was on the widget.
///  * An untimed task planned for a day after [today]: the last minute of
///    that day (23:59). With no time at all it fell in the Swift side's
///    "no time" band, which is today's untimed work, so a task planned for
///    Thursday sat on Tuesday's Lock Screen above tasks that are Tuesday's.
///    A moment on its own day files it with the other days instead.
///  * Any other untimed task (today's, or carried over): null, as before.
///
/// 23:59 and not the start of the day, because the widget re-reads which day
/// a moment falls on by itself (that is why it sorts in Swift at all) and
/// the app is usually not running at midnight to rewrite the list. When the
/// planned day arrives on a stale list, a 00:00 moment reads as "a time
/// today, already passed" and jumps to the very top, above a Do First task
/// at 17:00. 23:59 lands it after today's timed tasks and just before the
/// untimed ones, next to where the app puts it on its next write (the
/// untimed band, once the task's day is today). On the days before it, it
/// sits after any timed task of its own day, the same "times first" order a
/// day board reads in. The widget never prints this moment and never reads
/// it as a reminder: isLate and hasReminder are computed from the reminders
/// themselves, which an untimed task does not have.
DateTime? widgetDueAt(MatrixTask t, DateTime today) {
  if (t.reminderAts.isNotEmpty) return t.reminderAnchorAt;
  if (!isUpcoming(t, today)) return null;
  final day = taskDay(t);
  return DateTime(day.year, day.month, day.day, 23, 59);
}
