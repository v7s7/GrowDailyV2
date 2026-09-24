/// The one question every "how much of this day got done" number in the app
/// asks: **did this habit OWE this day?**
///
/// ── Why this exists ────────────────────────────────────────────────────────
///
/// [IslamicHabitTemplate.isScheduledFor] answers a different, narrower
/// question — "was this habit alive on this day, and does its weekday list
/// allow it" — and for a flexible weekly quota ("4 times a week, any days")
/// it answers `true` on all seven days, because any of them will do. Used as
/// a denominator that is simply wrong: a 4x-a-week habit puts itself into
/// every day of the week and then fails three of them by construction.
///
/// Aziz, 2026-09-16, on 13 September: "تمرين is a rest day, it's 4x a week
/// and on the 13th we are in the second day of the week... even the Grid said
/// you finished the whole day without finishing تمرين." Both pictures were on
/// the same screen: the Grid row read the day as covered (it already resolves
/// the week through [weeklyQuotaDemand]) while the heatmap cell above it read
/// the day as partial, because it counted the habit through `isScheduledFor`.
/// The rule below is the Grid's, lifted out so every surface shares it and
/// the two can never disagree again.
///
/// ── The rule ───────────────────────────────────────────────────────────────
///
/// A habit owes a day when it was alive on it AND:
///
///  - daily habit → always;
///  - specific-days habit → the weekday is one of its days, UNLESS a session
///    on another day of the same week stands in for it (see
///    moved_day_plan.dart). A session on a day off the plan counts on its own
///    day, like a quota's extra session;
///  - flexible weekly quota → the day was **load-bearing**, per
///    [weeklyQuotaDemand]: either it was actually done, or skipping it put
///    the week's target out of arithmetic reach. A `spare` day (enough days
///    still remain) and an `earned` day (the target is already banked) owe
///    nothing.
///
/// Because [weeklyQuotaDemand] is day-local, a resolved day's answer never
/// flips retroactively, and the count of owed-and-empty days in a week is
/// exactly the shortfall — a 4x week with 2 sessions marks precisely 2 days
/// missed, never 5 and never 0. That guarantee is what makes this safe to use
/// as a denominator everywhere.
///
/// A day the habit did NOT owe is still perfectly tappable: doing a fifth
/// session on a 4x week is someone doing more than they promised, and it
/// enters both sides of the ratio (see [habitOwesDay]'s `done` branch), so
/// extra work can only ever pull a day up.
library;

import '../../../core/extensions/datetime_ext.dart';
import '../../grid/models/square_state.dart' show SquareState;
import '../catalog/islamic_habit_catalog.dart' show IslamicHabitTemplate;
import 'habit_model.dart' show HabitFrequencyType;
import 'habit_schedule.dart' show scheduledGapBy;
import 'moved_day_plan.dart';
import 'weekly_quota_plan.dart';

export 'weekly_quota_plan.dart' show DayDemand;

/// Whether [habit] is a flexible weekly quota: "N times a week, any days".
///
/// Deliberately NOT `frequencyType == weekly` alone — "Specific Days" is
/// stored as weekly too, and is told apart only by [scheduledWeekdays] being
/// set. A target below 1 is not a quota either: it can never be reached, so
/// [weeklyQuotaDemand]'s clamp would invent an obligation nobody set.
///
/// The habit as it stands NOW. A question about a past day asks
/// [isFlexibleQuotaOn] instead: a habit that was four times a week last month
/// and is daily today still owed last month by the week.
bool isFlexibleQuota(IslamicHabitTemplate habit) =>
    habit.frequencyType == HabitFrequencyType.weekly &&
    habit.scheduledWeekdays.isEmpty &&
    habit.frequencyTarget > 0;

/// [isFlexibleQuota] for the schedule [habit] had on [day] (see
/// IslamicHabitTemplate.cadenceOn).
bool isFlexibleQuotaOn(IslamicHabitTemplate habit, DateTime day) =>
    habit.cadenceOn(day).isFlexibleQuota;

/// Reads whether one habit's square on one day counts as a completed session.
///
/// A function rather than a map because the callers hold the truth in
/// different shapes: the Grid holds a live week, the heatmap holds the
/// `habit_history` mirror, the reports hold a HabitPeriodStat. Each passes
/// its own reader and they all get the same arithmetic.
typedef GreenOnDay = bool Function(String habitId, DateTime day);

/// Reads what, if anything, was recorded for one habit on one day. Only the
/// moved-session rule needs more than [GreenOnDay]: a session on a day off a
/// specific-days plan covers a planned day with NOTHING recorded, never one
/// the person marked فشل, تخطّي or جزئي (see moved_day_plan.dart). Every
/// function taking one treats it as optional, and without it reads a day that
/// is not green as unmarked.
typedef MarkOnDay = SquareState Function(String habitId, DateTime day);

/// What the Saturday week containing [day] asked of [habit], day by day,
/// index 0 being that Saturday. Null when [day]'s own schedule was not a
/// flexible quota — those cadences are answered by the weekday list alone.
///
/// Always a full seven days: a quota is a promise about a week, and clamping
/// the window (to a month's edge, say) would quietly lower the target and
/// call owed days spare.
///
/// Worked out with the target in force on [day]. In the week a schedule
/// changed in, the week's other days may belong to a different schedule, so
/// only [day]'s own entry is an answer, which is the only one [quotaDemandOn]
/// reads. Every session of the week still counts toward the target, the ones
/// logged under the old schedule included: "four times this week" means this
/// week. And because [weeklyQuotaDemand] is day-local, a day's verdict never
/// depends on what came after it, so the old schedule's days of a week cut
/// short by a change are judged exactly as they were before it.
List<DayDemand>? quotaDemandForWeekOf({
  required IslamicHabitTemplate habit,
  required DateTime day,
  required GreenOnDay isGreen,
}) {
  final cadence = habit.cadenceOn(day);
  if (!cadence.isFlexibleQuota) return null;
  final start = day.startOfDisplayWeek;
  return weeklyQuotaDemand(
    dayCount: 7,
    doneDays: {
      for (var i = 0; i < 7; i++)
        if (isGreen(habit.id, DateTime(start.year, start.month, start.day + i)))
          i,
    },
    target: cadence.frequencyTarget,
  );
}

/// [quotaDemandOn] for every day of one row at once, index for index with
/// [days]: the Grid's week row and the reports' week matrix, which hold the
/// row's squares already and read them through [isGreenAt].
///
/// Null as a whole when no day of the row was on a flexible quota, which is
/// every daily and specific-days habit, so they render exactly as before. A
/// day whose own schedule was not a quota gets a null entry: the row of the
/// week a habit went from four a week to daily is quota days, then daily ones.
///
/// [days] is a whole display week, Saturday first, as both callers pass it;
/// each quota day is resolved over the whole row with its own target, the
/// same day-local arithmetic [quotaDemandForWeekOf] does.
///
/// A specific-days row with a session on a day off its plan is answered by
/// [movedDayDemand] instead (see [movedDemandForRow]), so the planned day that
/// session stands in for reads as covered on the Grid and in the reports
/// alike.
List<DayDemand?>? quotaDemandForRow({
  required IslamicHabitTemplate habit,
  required List<DateTime> days,
  required bool Function(int index) isGreenAt,
  bool Function(int index)? isUnmarkedAt,
  DateTime? now,
}) {
  if (!days.any((d) => habit.cadenceOn(d).isFlexibleQuota)) {
    return movedDemandForRow(
      habit: habit,
      days: days,
      isGreenAt: isGreenAt,
      isUnmarkedAt: isUnmarkedAt,
      now: now,
    );
  }
  List<DayDemand?>? out;
  Set<int>? done;
  final byTarget = <int, List<DayDemand>>{};
  for (var i = 0; i < days.length; i++) {
    final cadence = habit.cadenceOn(days[i]);
    if (!cadence.isFlexibleQuota) continue;
    done ??= {
      for (var j = 0; j < days.length; j++)
        if (isGreenAt(j)) j,
    };
    final week = byTarget.putIfAbsent(
      cadence.frequencyTarget,
      () => weeklyQuotaDemand(
        dayCount: days.length,
        doneDays: done!,
        target: cadence.frequencyTarget,
      ),
    );
    (out ??= List<DayDemand?>.filled(days.length, null))[i] = week[i];
  }
  return out;
}

/// What one display week asked of a specific-days habit that has a session on
/// a day off its plan, index for index with [days], or null when the week has
/// nothing for [movedDayDemand] to decide: no session off the plan (every
/// planned day is owed, exactly as before), or a flexible quota anywhere in the
/// week (the quota's own arithmetic owns those weeks, see
/// [quotaDemandForRow]). A null entry is a day the habit did not exist on.
///
/// [now] decides which empty planned days are already closed, and so are made
/// up first; the real clock when null. [isUnmarkedAt] says which days have
/// nothing recorded at all (see [MarkOnDay]); null reads every day that is not
/// green as unmarked.
List<DayDemand?>? movedDemandForRow({
  required IslamicHabitTemplate habit,
  required List<DateTime> days,
  required bool Function(int index) isGreenAt,
  bool Function(int index)? isUnmarkedAt,
  DateTime? now,
}) {
  if (days.any((d) => habit.cadenceOn(d).isFlexibleQuota)) return null;
  final alive = [for (final d in days) habit.isAliveOn(d)];
  final planned = [for (final d in days) habit.isScheduledFor(d)];
  // Only a day the habit existed on and did not plan can hold a moved
  // session. A daily habit has no such day, so nearly every row stops here
  // without reading a single square: this runs for every habit on every day
  // the progress map draws.
  var offDaySession = false;
  for (var i = 0; i < days.length && !offDaySession; i++) {
    offDaySession = alive[i] && !planned[i] && isGreenAt(i);
  }
  if (!offDaySession) return null;
  final green = [
    for (var i = 0; i < days.length; i++) alive[i] && isGreenAt(i),
  ];
  final clock = now ?? DateTime.now();
  final today = DateTime(clock.year, clock.month, clock.day);
  return movedDayDemand(
    alive: alive,
    planned: planned,
    green: green,
    unmarked: isUnmarkedAt == null
        ? null
        : [for (var i = 0; i < days.length; i++) isUnmarkedAt(i)],
    closed: [
      for (final d in days) d.startOfDay.isBefore(today) && !d.isOpenDayAt(clock),
    ],
  );
}

/// [movedDemandForRow] for the display week holding [day], narrowed to [day].
/// Null when that week has no session off the plan, or [day] is outside the
/// habit's life.
DayDemand? movedDemandOn({
  required IslamicHabitTemplate habit,
  required DateTime day,
  required GreenOnDay isGreen,
  MarkOnDay? markOn,
  DateTime? now,
}) {
  final start = day.startOfDisplayWeek;
  final week = [
    for (var i = 0; i < 7; i++) DateTime(start.year, start.month, start.day + i),
  ];
  final demand = movedDemandForRow(
    habit: habit,
    days: week,
    isGreenAt: (i) => isGreen(habit.id, week[i]),
    isUnmarkedAt: markOn == null
        ? null
        : (i) => markOn(habit.id, week[i]) == SquareState.none,
    now: now,
  );
  if (demand == null) return null;
  final i = day.startOfDay.difference(start).inDays;
  return i < 0 || i > 6 ? null : demand[i];
}

/// [IslamicHabitTemplate.runsOn] minus the days a session on another day of
/// the same week stands in for, for a habit's own streak.
///
/// The per-habit streak counts the habit's run days between two sessions as
/// missed (see habit_schedule.dart's scheduledGapBy). A Monday, Thursday and
/// Saturday habit done on Wednesday instead of Thursday would otherwise read
/// Thursday as a miss the next day and restart at 1 on Saturday, for a week
/// in which every promised session happened. [isGreen] null excuses nothing.
bool Function(DateTime day) runsOnExcusing(
  IslamicHabitTemplate habit,
  GreenOnDay? isGreen, {
  MarkOnDay? markOn,
}) {
  if (isGreen == null) return habit.runsOn;
  return (day) =>
      habit.runsOn(day) &&
      movedDemandOn(habit: habit, day: day, isGreen: isGreen, markOn: markOn) !=
          DayDemand.earned;
}

/// The weekday rule [habit]'s own streak is measured on for a completion
/// landing on [day]: [runsOnExcusing] over the squares actually stored.
///
/// Plain [IslamicHabitTemplate.runsOn] unless that would restart the streak.
/// Only then are the display weeks from the last completion
/// ([lastCompletedKey], DashboardState.habitLastCompletedDate) to [day] read
/// through [squaresOn], to see whether a session on a day off the plan
/// covered the days in between: a Monday, Thursday and Saturday habit done on
/// Wednesday instead of Thursday keeps its streak on Saturday. Nearly every
/// completion reads nothing. A last completion more than three weeks back is
/// left to the plain rule: whatever covered it, that gap is real.
Future<bool Function(DateTime day)> streakRunsOn({
  required IslamicHabitTemplate habit,
  required DateTime day,
  required String? lastCompletedKey,
  required Future<Map<String, SquareState>?> Function(DateTime day) squaresOn,
}) async {
  final last = lastCompletedKey == null ? null : DateTime.tryParse(lastCompletedKey);
  if (last == null) return habit.runsOn;
  final lastDay = DateTime(last.year, last.month, last.day);
  final markDay = DateTime(day.year, day.month, day.day);
  if (scheduledGapBy(last: lastDay, day: markDay, runsOn: habit.runsOn) <= 1) {
    return habit.runsOn;
  }
  if (markDay.difference(lastDay).inDays > 21) return habit.runsOn;
  final squares = <String, Map<String, SquareState>>{};
  final toWeek = markDay.startOfDisplayWeek;
  final end = DateTime(toWeek.year, toWeek.month, toWeek.day + 6);
  for (var d = lastDay.startOfDisplayWeek;
      !d.isAfter(end);
      d = DateTime(d.year, d.month, d.day + 1)) {
    final read = await squaresOn(d);
    if (read != null) squares[d.toDateKey()] = read;
  }
  final markKey = markDay.toDateKey();
  // The session landing right now is not stored yet, and it is green.
  SquareState markOn(String id, DateTime d) {
    final key = d.toDateKey();
    if (id == habit.id && key == markKey) return SquareState.complete;
    return squares[key]?[id] ?? SquareState.none;
  }

  return runsOnExcusing(
    habit,
    (id, d) => markOn(id, d).isGreen,
    markOn: markOn,
  );
}

/// [quotaDemandForWeekOf] narrowed to [day] itself. Null for non-quota habits.
DayDemand? quotaDemandOn({
  required IslamicHabitTemplate habit,
  required DateTime day,
  required GreenOnDay isGreen,
}) {
  final week = quotaDemandForWeekOf(habit: habit, day: day, isGreen: isGreen);
  if (week == null) return null;
  final start = day.startOfDisplayWeek;
  final i = day.startOfDay.difference(start).inDays;
  return i < 0 || i > 6 ? null : week[i];
}

/// Whether [habit] owed [day] — see the library comment for the whole rule.
///
/// This is the predicate for every DENOMINATOR: how full a day is, whether a
/// blank square is a miss, whether the day streak's board still has something
/// outstanding. It is NOT the predicate for whether a habit may be shown or
/// tapped on a day: a quota habit stays available all week, owed or not, and
/// [IslamicHabitTemplate.isScheduledFor] is still the right question there.
bool habitOwesDay({
  required IslamicHabitTemplate habit,
  required DateTime day,
  required GreenOnDay isGreen,
  MarkOnDay? markOn,
}) {
  // A specific-days week holding a session off its plan: a planned day that
  // session stands in for owes nothing, and the session counts on its own
  // day, on both sides, exactly like a quota's extra session.
  final moved =
      movedDemandOn(habit: habit, day: day, isGreen: isGreen, markOn: markOn);
  if (moved != null) return !moved.isRest;
  if (!habit.isScheduledFor(day)) return false;
  final demand = quotaDemandOn(habit: habit, day: day, isGreen: isGreen);
  // Daily and specific-days habits: isScheduledFor already is the answer.
  if (demand == null) return true;
  // `done` counts, and must: a session that happened adds 1 to both sides of
  // the ratio, so extra sessions can only pull a day up, never create a
  // 3-of-2. Only a rest day (spare or earned) leaves the denominator.
  return !demand.isRest;
}

/// Every habit in [habits] that owed [day], by id.
///
/// Deduped by id, so the several synthetic stints
/// `allHabitsEverProvider` emits for one paused-and-resumed habit count once.
Set<String> owedHabitIdsOn({
  required Iterable<IslamicHabitTemplate> habits,
  required DateTime day,
  required GreenOnDay isGreen,
  MarkOnDay? markOn,
}) =>
    {
      for (final habit in habits)
        if (habitOwesDay(
          habit: habit,
          day: day,
          isGreen: isGreen,
          markOn: markOn,
        ))
          habit.id,
    };

/// A [GreenOnDay] over the `habit_history` mirror (habitId → dateKey → mark),
/// with an optional live reader layered on top.
///
/// The mirror is a cache written by three fire-and-forget writers and lags
/// the current week, which is why the reports have `withLiveToday` at all; a
/// [live] reader (the Grid's own loaded week, say) covers exactly the days it
/// can speak for and answers null elsewhere.
///
/// The two are UNIONED, not overridden: either source saying green is enough.
/// Deliberate, and in the one safe direction. Adding a completion to a quota
/// week can only move its days toward rest ([weeklyQuotaDemand]'s `need` can
/// only shrink), so a stale green at worst forgives a day; dropping a real
/// one would accuse someone of a miss they did not make. It also means a Grid
/// that has not finished loading its week cannot blank out a week the mirror
/// already knows.
GreenOnDay greenFromMirror(
  Map<String, Map<String, SquareState>> mirror, {
  SquareState? Function(String habitId, DateTime day)? live,
}) =>
    (habitId, day) {
      if (live?.call(habitId, day)?.isGreen ?? false) return true;
      return (mirror[habitId]?[day.toDateKey()] ?? SquareState.none).isGreen;
    };

/// [greenFromMirror]'s twin for the whole mark (see [MarkOnDay]), over the
/// same two sources. A mark either source holds wins over none, and a live
/// mark over the mirror's: the same safe direction, a day with anything on it
/// is never read as empty, and so never covered by a moved session.
MarkOnDay markFromMirror(
  Map<String, Map<String, SquareState>> mirror, {
  SquareState? Function(String habitId, DateTime day)? live,
}) =>
    (habitId, day) {
      final fromLive = live?.call(habitId, day);
      if (fromLive != null && fromLive != SquareState.none) return fromLive;
      return mirror[habitId]?[day.toDateKey()] ?? SquareState.none;
    };

/// The habits a LIVE board on [day] is answerable for — Today's counter, the
/// Grid summary's ring, and the roster [willCompleteAllHabitsToday] measures
/// the day streak against.
///
/// Separate from [owedHabitIdsOn] because a live board has two things a
/// history surface does not:
///
///  - [isGreen] can be NULL, meaning this week's squares are unreadable (the
///    Grid is still loading, or the person has scrolled it to another week).
///    A quota habit then stays on the board exactly as it always was: an
///    unreadable week is not evidence of a rest day, and the safe direction
///    for a live board is to keep asking.
///  - [alsoOwing] keeps a habit on the board whatever the week says. The
///    completion that is LANDING right now goes here: without it, finishing a
///    quota habit on one of its own spare days would drop it out of the very
///    board it is being counted into, and willCompleteAllHabitsToday — which
///    returns false when it cannot find the habit it was asked about — would
///    deny a day that was in fact finished.
///
/// A habit that is not on the board is never hidden from Today: it can still
/// be opened, tapped and rewarded, and doing it is worth a session. It simply
/// stops being counted as outstanding, which is the whole point.
List<IslamicHabitTemplate> boardHabitsOn({
  required Iterable<IslamicHabitTemplate> habits,
  required DateTime day,
  required GreenOnDay? isGreen,
  Set<String> alsoOwing = const {},
  MarkOnDay? markOn,
}) =>
    [
      for (final habit in habits)
        if ((habit.isScheduledFor(day) ||
                _offPlanSession(habit, day, isGreen, alsoOwing)) &&
            (isGreen == null ||
                alsoOwing.contains(habit.id) ||
                habitOwesDay(
                  habit: habit,
                  day: day,
                  isGreen: isGreen,
                  markOn: markOn,
                )))
          habit,
    ];

/// A specific-days habit done today on a day that is not one of its days, or
/// being marked on one right now ([alsoOwing]). It joins the board it is being
/// counted into, the same way a quota's extra session does: without it,
/// willCompleteAllHabitsToday, which answers false when it cannot find the
/// habit it was asked about, would refuse a day that was in fact finished.
/// A habit that did not exist on [day] never joins.
bool _offPlanSession(
  IslamicHabitTemplate habit,
  DateTime day,
  GreenOnDay? isGreen,
  Set<String> alsoOwing,
) =>
    habit.isAliveOn(day) &&
    (alsoOwing.contains(habit.id) || (isGreen?.call(habit.id, day) ?? false));
