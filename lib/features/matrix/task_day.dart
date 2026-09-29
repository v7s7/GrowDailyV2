// THE DAY RULE for the Tasks page: which day a task belongs to, and which
// day boards it shows on. Pure functions over MatrixTask, no Flutter, no
// clock of their own (every "today" is passed in), so the board, the
// expanded quadrant, the «مُرحّلة» and «قادمة» chips, the month sheet's
// dots, the bottom bar's badge and main.dart's evening count can all read
// the same answer and never disagree. Nothing outside this file should
// work out a task's day on its own.
//
// ── WHY A TASK HAS A DAY AT ALL ───────────────────────────────────────────
//
// The board once filed a task by its reminder day, on the reasoning that a
// task set two days out is a deliberate "not now". It lost people their
// tasks: they added a task, set a reminder for tomorrow morning, and could
// not find it again. It had moved to a day nobody was looking at, and
// nothing on the screen said where it went. The fix back then was to file
// every task on the day it was CREATED, which never loses a task but is
// wrong in two other ways people hit:
//
//  * A task created on Sunday for Tuesday 17:00 was, on Tuesday, a task
//    "from before today": it sat under «مُرحّلة», missing from Today and
//    from the badge, on the very day it was for.
//  * «قادمة» read the task's FIRST reminder, so a task with a "2 days
//    before" warning left «قادمة» two days early and landed in Today while
//    its real day was still ahead.
//
// So the task's day is now the day it is FOR, and the lesson from the lost
// tasks is kept a different way: the day is always visible. The header's
// date, the month sheet's dots, the «قادمة» count, the row's time line and
// the «عرض» snackbar after an add all show where a task went. Filing is
// safe when nothing is ever filed out of sight.
//
// ── MIDNIGHT, NOT 10:00 ───────────────────────────────────────────────────
//
// Every day here is startOfDay, never effectiveDay or the habits' 10:00
// grace. That window exists for HABITS (a late sleeper's 1 AM workout still
// counting for the day they have not slept on). A todo board is a different
// thing: at 12 AM the phone says a new day and the board agrees. Days are
// stepped with DateTime(y, m, d + n), never .add(Duration(days: n)), which
// lands an hour off across a DST change on phones that have one.

import '../../core/extensions/datetime_ext.dart';
import 'models/matrix_task.dart';

/// The day [t] belongs to, as a local midnight.
///
/// In order:
///  1. It has reminders: the day of the moment the person picked
///     ([MatrixTask.reminderAnchorAt]), never of an early warning or a
///     follow-up. A 17:00 task with a "2 days before" warning is Tuesday's
///     task, not Sunday's. A task saved before the anchor was stored falls
///     back to its last reminder, the same guess [MatrixTask.resolveAnchor]
///     makes everywhere else.
///  2. It has a [MatrixTask.plannedDay]: that day (a task added for another
///     day without a time, or one whose time was cleared, see
///     [plannedDayOnWrite]).
///  3. Otherwise the day it was created, which is what every task written
///     before plannedDay existed keeps, so an old board opens unchanged.
///
/// Done or open makes no difference here; a done task's completion day is a
/// second day it shows on, see [showsOnDay].
DateTime taskDay(MatrixTask t) {
  final anchor = MatrixTask.resolveAnchor(t.reminderAnchorAt, t.reminderAts);
  if (anchor != null) return anchor.toLocal().startOfDay;
  final planned = parseDayKey(t.plannedDay);
  if (planned != null) return planned;
  return t.createdAt.toLocal().startOfDay;
}

/// [d]'s calendar day as 'yyyy-MM-dd', the form [MatrixTask.plannedDay] is
/// stored in and [dayMarks] is keyed by. The time of day is ignored.
String dayKey(DateTime d) => d.toDateKey();

/// The local midnight a 'yyyy-MM-dd' key names, or null for null or for
/// anything that is not exactly that shape and a real date. Strict on
/// purpose: a stored plannedDay that does not parse must fall through to the
/// next rule in [taskDay], not become some neighbouring day (Dart's
/// DateTime(2026, 2, 30) silently means March 2).
DateTime? parseDayKey(String? k) {
  if (k == null) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(k);
  if (m == null) return null;
  final y = int.parse(m[1]!);
  final mo = int.parse(m[2]!);
  final d = int.parse(m[3]!);
  final day = DateTime(y, mo, d);
  if (day.year != y || day.month != mo || day.day != d) return null;
  return day;
}

/// Whether [t] belongs on [day]'s board: planned for it, or done on it.
///
/// Every task shows on its own day, open or done. A done task ALSO shows on
/// the day it was finished, so a task planned for Thursday and done early on
/// Tuesday sits on both boards: Tuesday's, because that is what you got done
/// that day, and Thursday's, so the day you planned it for does not look
/// like the task vanished. A done task with no completedAt (written before
/// that stamp existed) shows on its own day only.
bool showsOnDay(MatrixTask t, DateTime day) {
  if (taskDay(t).isSameDayAs(day)) return true;
  final done = t.completedAt;
  return t.isDone && done != null && done.toLocal().isSameDayAs(day);
}

/// Open, and its day is before [today]: the «مُرحّلة» chip.
///
/// With [isOpenOnDay] for today and [isUpcoming], this splits every open
/// task into exactly one of three places, so no open task can be on none of
/// them (lost) or on two (counted twice).
bool isCarriedOver(MatrixTask t, DateTime today) =>
    !t.isDone && taskDay(t).isBefore(today.startOfDay);

/// Open, and its day is after [today]: the «قادمة» chip. Keyed off the
/// task's own day, not its first reminder, so an early warning does not pull
/// a task out of «قادمة» before its day (see the file header).
bool isUpcoming(MatrixTask t, DateTime today) =>
    !t.isDone && taskDay(t).isAfter(today.startOfDay);

/// Open, and its day is [day]. For today this is the open half of the Today
/// board and exactly what the bottom bar's Tasks badge counts.
bool isOpenOnDay(MatrixTask t, DateTime day) =>
    !t.isDone && taskDay(t).isSameDayAs(day);

/// How many open tasks belong to [day]. The badge's number when [day] is
/// today (see matrixOpenTodayCount), so the badge and the board a tap on it
/// lands on read the same rule.
int openOnDayCount(Iterable<MatrixTask> tasks, DateTime day) =>
    tasks.where((t) => isOpenOnDay(t, day)).length;

/// What the month sheet draws under a day number.
enum DayMark {
  /// Nothing on that day's board.
  none,

  /// At least one open task belongs to that day.
  open,

  /// The day's board has tasks and every one of them is done.
  allDone,
}

/// Every day that has something on its board, keyed by [dayKey], by the
/// same rule as [showsOnDay]: an open task marks its own day; a done task
/// marks its own day and the day it was finished. One open task makes the
/// day [DayMark.open] whatever else is on it. A day missing from the map is
/// [DayMark.none].
///
/// One pass over the tasks rather than a [showsOnDay] call per grid cell,
/// so a month of 42 cells over a long task list stays cheap.
Map<String, DayMark> dayMarks(Iterable<MatrixTask> tasks) {
  final marks = <String, DayMark>{};
  void mark(DateTime day, DayMark m) {
    final key = dayKey(day);
    if (marks[key] == DayMark.open) return;
    marks[key] = m;
  }

  for (final t in tasks) {
    if (!t.isDone) {
      mark(taskDay(t), DayMark.open);
      continue;
    }
    mark(taskDay(t), DayMark.allDone);
    final done = t.completedAt;
    if (done != null) mark(done.toLocal(), DayMark.allDone);
  }
  return marks;
}

/// The plannedDay a write should store when it replaces [before]'s
/// reminders with [newReminders] (anchored at [newAnchor]).
///
/// The rule exists so that no edit moves a task by accident:
///  * Setting reminders stores the new anchor's day. The reminders already
///    decide the day while they exist ([taskDay] reads them first); storing
///    it too is what keeps the task on that day if the time is removed
///    later, instead of it falling back to the day it was created.
///  * Clearing the reminders stores the day the task shows on right now
///    ([taskDay] of [before]). For a task this build has written, that is
///    the plannedDay it already carries. For a timed task saved before
///    plannedDay existed, it freezes the old anchor's day, so taking the
///    time off a Tuesday 17:00 task leaves it on Tuesday rather than
///    sending it back to the Sunday it was typed on. And if an older build
///    changed the reminders without knowing about plannedDay, the day on
///    screen wins over the stale key.
///
/// [newAnchor] is re-checked the way the model checks it
/// ([MatrixTask.resolveAnchor]), so an anchor that is not one of
/// [newReminders] cannot pick the day.
String plannedDayOnWrite({
  required MatrixTask before,
  required List<DateTime> newReminders,
  DateTime? newAnchor,
}) {
  final anchor = MatrixTask.resolveAnchor(
    newAnchor,
    MatrixTask.normalizeReminders(newReminders),
  );
  if (anchor != null) return dayKey(anchor.toLocal());
  return dayKey(taskDay(before));
}

/// Every moment a task will nudge at: the anchor itself, plus one reminder
/// per selected offset.
///
/// The anchor is always included: it's the time the user actually picked,
/// and both TickTick and Todoist treat "at the time" as a reminder in its
/// own right rather than something you have to ask for separately. Offsets
/// are signed: negative is before, positive is after.
///
/// Lives here rather than in reminder_picker.dart (which re-exports it, so
/// the sheets and tests that import it from there are unchanged) because
/// MatrixNotifier.moveToDay rebuilds a moved task's stack with it, and a
/// notifier importing a widget file would drag the widget layer into it.
List<DateTime> remindersFor({
  required DateTime? anchor,
  required Set<int> offsets,
}) {
  if (anchor == null) return const [];
  return MatrixTask.normalizeReminders([
    anchor,
    for (final o in offsets) anchor.add(Duration(minutes: o)),
  ]);
}

/// Inverse of [remindersFor], for reopening a task whose reminders were
/// saved on a previous visit.
///
/// Takes the anchor as an input rather than guessing it, which is the whole
/// fix: the arithmetic genuinely cannot be inverted, so an earlier version
/// that assumed `reminders.last` was the anchor reframed every "after" stack
/// on reopen. A 12:00 anchor with a +15 offset came back claiming 12:15 was
/// the moment you'd picked and 12:00 was a warning about it, the same
/// alarms telling a story the user never wrote. Which entry was really
/// chosen now lives on the task (MatrixTask.reminderAnchorAt), and
/// MatrixTask.resolveAnchor supplies the old `reminders.last` guess only for
/// tasks saved before that field existed.
///
/// The anchor's own entry contributes no offset (it would be zero), so a
/// task with a single reminder comes back with an empty set.
Set<int> offsetsFrom({
  required DateTime? anchor,
  required List<DateTime> reminders,
}) {
  if (anchor == null) return <int>{};
  return {
    for (final r in reminders)
      if (r.difference(anchor).inMinutes != 0) r.difference(anchor).inMinutes,
  };
}
