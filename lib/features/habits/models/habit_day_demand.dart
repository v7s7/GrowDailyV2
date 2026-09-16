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
///  - specific-days habit → the weekday is one of its days;
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
import 'weekly_quota_plan.dart';

export 'weekly_quota_plan.dart' show DayDemand;

/// Whether [habit] is a flexible weekly quota: "N times a week, any days".
///
/// Deliberately NOT `frequencyType == weekly` alone — "Specific Days" is
/// stored as weekly too, and is told apart only by [scheduledWeekdays] being
/// set. A target below 1 is not a quota either: it can never be reached, so
/// [weeklyQuotaDemand]'s clamp would invent an obligation nobody set.
bool isFlexibleQuota(IslamicHabitTemplate habit) =>
    habit.frequencyType == HabitFrequencyType.weekly &&
    habit.scheduledWeekdays.isEmpty &&
    habit.frequencyTarget > 0;

/// Reads whether one habit's square on one day counts as a completed session.
///
/// A function rather than a map because the callers hold the truth in
/// different shapes: the Grid holds a live week, the heatmap holds the
/// `habit_history` mirror, the reports hold a HabitPeriodStat. Each passes
/// its own reader and they all get the same arithmetic.
typedef GreenOnDay = bool Function(String habitId, DateTime day);

/// What the Saturday week containing [day] asked of [habit], day by day,
/// index 0 being that Saturday. Null for anything that is not a flexible
/// quota — those cadences are answered by the weekday list alone.
///
/// Always a full seven days: a quota is a promise about a week, and clamping
/// the window (to a month's edge, say) would quietly lower the target and
/// call owed days spare.
List<DayDemand>? quotaDemandForWeekOf({
  required IslamicHabitTemplate habit,
  required DateTime day,
  required GreenOnDay isGreen,
}) {
  if (!isFlexibleQuota(habit)) return null;
  final start = day.startOfDisplayWeek;
  return weeklyQuotaDemand(
    dayCount: 7,
    doneDays: {
      for (var i = 0; i < 7; i++)
        if (isGreen(habit.id, DateTime(start.year, start.month, start.day + i)))
          i,
    },
    target: habit.frequencyTarget,
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
}) {
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
}) =>
    {
      for (final habit in habits)
        if (habitOwesDay(habit: habit, day: day, isGreen: isGreen)) habit.id,
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
}) =>
    [
      for (final habit in habits)
        if (habit.isScheduledFor(day) &&
            (isGreen == null ||
                alsoOwing.contains(habit.id) ||
                habitOwesDay(habit: habit, day: day, isGreen: isGreen)))
          habit,
    ];
