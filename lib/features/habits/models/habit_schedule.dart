/// Counting a habit's schedule between two days.
///
/// ── Why this exists ────────────────────────────────────────────────────────
///
/// Every "how long since" question about ONE habit used to be answered on the
/// calendar: `today.difference(lastDone).inDays`. That is the right answer
/// for a daily habit and the wrong one for every other cadence. A habit set
/// to Wednesday and Saturday, done on Wednesday, was three calendar days
/// "late" by Saturday morning, and the person who was exactly on schedule got
/// a reminder saying «صار لها ٣ أيام، وما ضاع شي» about a habit that had lost
/// nothing because it had owed nothing. The same arithmetic, in
/// completeHabit, reset that habit's own streak to 1 on every completion, so
/// its milestone bonuses could never fire and its detail sheet never rose
/// above 1.
///
/// The app-wide day streak already counts only the days that OWED something
/// (see DashboardNotifier.resolveStreakGap). This file gives the per-habit
/// questions the same rule: a gap is measured in the habit's own scheduled
/// days, and a day the habit does not run on cannot widen it.
///
/// Ints and dates only, no habit and no clock, so the dashboard's streak rule
/// and the notification scheduler's wording can both call it and cannot drift
/// apart. `weekdays` is DateTime.weekday values (1 = Monday … 7 = Sunday),
/// empty meaning every day, exactly as IslamicHabitTemplate.scheduledWeekdays
/// stores it.
library;

import 'weekly_quota_plan.dart';

/// Whether a habit with [weekdays] runs on [day]. Empty means every day.
bool runsOnWeekday(DateTime day, Set<int> weekdays) =>
    weekdays.isEmpty || weekdays.contains(day.weekday);

/// Whole calendar days from [from] to [to], via UTC so a DST hour can never
/// move a date. Same rule as dashboard_notifier's daysBetweenDates, repeated
/// here rather than imported so this file stays free of the notifier.
int calendarDaysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;

/// [day] plus [days] calendar days, built through the constructor rather
/// than `add(Duration)` so it stays at local midnight across a DST change.
DateTime dayPlus(DateTime day, int days) =>
    DateTime(day.year, day.month, day.day + days);

/// How many days STRICTLY between [from] and [to] a habit with [weekdays]
/// runs on. Zero when [to] is not after [from].
///
/// Strictly between is the shape every caller needs: the last completed day
/// is settled, and the day being asked about (today, or the day a reminder
/// will land on) is still open and must never be counted as missed.
int scheduledDaysStrictlyBetween(
  DateTime from,
  DateTime to,
  Set<int> weekdays,
) {
  final span = calendarDaysBetween(from, to);
  if (span <= 1) return 0;
  if (weekdays.isEmpty) return span - 1;
  var count = 0;
  for (var i = 1; i < span; i++) {
    if (weekdays.contains(dayPlus(from, i).weekday)) count++;
  }
  return count;
}

/// The gap completeHabit feeds nextHabitStreak, measured on the habit's own
/// schedule.
///
/// For a habit that runs every day this is exactly the calendar difference
/// it always was, including the zero (re-ticking a day already recorded) and
/// the negative (marking yesterday inside its grace tail after today) that
/// nextHabitStreak and the grace path already handle. For a habit pinned to
/// weekdays it is the number of scheduled days from [last] to [day],
/// counting [day] itself: a Wed/Sat habit done Wednesday and again Saturday
/// measures 1, and continues its streak, where the calendar said 3 and
/// restarted it.
///
/// [day] itself counts even when it is not one of the habit's days. A
/// completion never breaks a streak; someone doing a Wed/Sat habit on a
/// Monday as well has done more than they promised, not less.
int scheduledGap({
  required DateTime last,
  required DateTime day,
  required Set<int> weekdays,
}) {
  final calendar = calendarDaysBetween(last, day);
  if (weekdays.isEmpty || calendar <= 0) return calendar;
  return scheduledDaysStrictlyBetween(last, day, weekdays) + 1;
}

/// What a flexible weekly quota ("N times a week, any days") can honestly
/// say about itself on [fireDay], the day a reminder will land on.
///
/// A quota habit has no scheduled weekdays to count, so the questions above
/// do not apply to it; what it has instead is the week. [weekStart] is the
/// Saturday that starts the CURRENT display week, [doneDays] the indices
/// (0 = that Saturday) already logged in it, or null while the week's
/// squares have not loaded, and [lastDone] the habit's last completed day on
/// any week, or null if it never has been.
///
///  - [done]: how many of the week [fireDay] falls in are already logged.
///    Known for the current week; zero for a later one, since nothing in it
///    can have been logged yet; null when the current week is unknown.
///  - [owed]: whether [fireDay] is load-bearing per [weeklyQuotaDemand]:
///    skipping it puts the week's target out of reach.
///  - [missedSinceLastDone]: owed days PROVABLY left empty between
///    [lastDone] and [fireDay]. Two things prove one: a whole display week
///    with no completion at all (every one of its owed days was missed,
///    whatever they were), and an owed day of the current week, after
///    [lastDone], whose square is empty. The week [lastDone] itself fell in,
///    when it is an earlier week, is NOT judged: this function has no record
///    of how that week went, and a lapse it cannot see is not one it may
///    claim.
///
/// Days of the current week after [fireDay] are never counted, and days
/// before it are read as they stand now: the text is baked when the reminder
/// is armed, and any completion between now and then re-arms it.
({int? done, bool owed, int missedSinceLastDone}) quotaFactsOn({
  required DateTime fireDay,
  required DateTime weekStart,
  required Set<int>? doneDays,
  required int target,
  required DateTime? lastDone,
}) {
  const week = 7;
  final daysIn = calendarDaysBetween(weekStart, fireDay);
  // A fire day before the week it is measured against cannot happen (the
  // scheduler only ever arms the future), but a negative index must not be
  // able to reach into a list.
  final weeksAhead = daysIn < 0 ? 0 : daysIn ~/ week;
  final fireIndex = daysIn < 0 ? 0 : daysIn % week;
  final effectiveTarget = target.clamp(1, week);

  // ── Whole weeks with nothing in them ──────────────────────────────────
  //
  // Three stretches can hold one, and none of them overlap: the weeks
  // strictly between lastDone's week and the current week, the current week
  // itself (judged square by square below), and the weeks strictly between
  // the current week and the fire week. Nothing after lastDone has been
  // logged, or it would be lastDone, so a whole week without it is a whole
  // week with nothing in it, and every day it owed was missed.
  var missed = 0;
  // lastDone's position in the current week: 0..6 when it is in it, negative
  // when it is earlier, and -1 when there is no lastDone at all. Only the
  // "strictly after" loops below read it, so the last two cases are the
  // same to them: every day of the week is after it.
  var lastDoneIndex = -1;
  if (lastDone != null) {
    lastDoneIndex = calendarDaysBetween(weekStart, lastDone);
    // The Saturday of the week lastDone fell in, found the same way
    // DateTimeGameExt.startOfDisplayWeek finds it.
    final fromSaturday = (lastDone.weekday - DateTime.saturday + week) % week;
    final lastDoneWeekStart = dayPlus(lastDone, -fromSaturday);
    final weeksBefore =
        calendarDaysBetween(lastDoneWeekStart, weekStart) ~/ week;
    if (weeksBefore > 1) missed += (weeksBefore - 1) * effectiveTarget;
  }
  if (weeksAhead > 1) missed += (weeksAhead - 1) * effectiveTarget;

  // ── The current week, square by square ────────────────────────────────
  if (doneDays == null) {
    return (done: null, owed: false, missedSinceLastDone: missed);
  }
  final demand = weeklyQuotaDemand(
    dayCount: week,
    doneDays: doneDays,
    target: effectiveTarget,
  );
  // Owed and empty, strictly after lastDone and strictly before the fire
  // day: up to the fire day when it is in this week, and the whole week
  // when the fire day is in a later one.
  final judgedUpTo = weeksAhead == 0 ? fireIndex : week;
  for (var i = lastDoneIndex + 1; i < judgedUpTo; i++) {
    if (i >= 0 && demand[i] == DayDemand.owed) missed++;
  }
  if (weeksAhead == 0) {
    return (
      done: doneDays.length,
      owed: demand[fireIndex] == DayDemand.owed,
      missedSinceLastDone: missed,
    );
  }
  // A later week starts from nothing, so whether its fire day is owed
  // depends only on the target and how many days are left in it.
  final laterDemand = weeklyQuotaDemand(
    dayCount: week,
    doneDays: const {},
    target: effectiveTarget,
  );
  return (
    done: 0,
    owed: laterDemand[fireIndex] == DayDemand.owed,
    missedSinceLastDone: missed,
  );
}
