// A day that asked for nothing must not break a streak.
//
// The bug: willCompleteAllHabitsToday refuses to earn a streak point on a
// day with no scheduled habits, deliberately — "a day with nothing
// scheduled isn't a completed day, it's a day off". lastActiveDate is only
// advanced on a day that earned the point, so it does not move across rest
// days. The loader then counted RAW CALENDAR days since lastActiveDate,
// which read every rest day as a miss: someone training Sat/Mon/Wed burned
// a streak freeze on their first Sunday and lost the streak on the next
// one, and a 3x-a-week habit could never hold a streak at all.
//
// These tests pin the counting rule the fix turns on: only days that
// actually OWED something count toward a gap.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';

/// A habit scheduled only on the given weekdays, alive for all of history.
IslamicHabitTemplate _habit(List<int> weekdays) => IslamicHabitTemplate(
      id: 'gym',
      name: 'تمرين',
      description: '',
      category: HabitCategory.fitness,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 10,
      goldReward: 5,
      scheduledWeekdays: weekdays,
    );

/// The rule under test, in the same shape resolveStreakGap applies it:
/// days STRICTLY between the last earning day and today that asked for
/// something.
int owedDaysBetween(
  DateTime from,
  DateTime today,
  Iterable<IslamicHabitTemplate> habits,
) {
  var owed = 0;
  for (var d = from.add(const Duration(days: 1));
      d.isBefore(today);
      d = d.add(const Duration(days: 1))) {
    if (habits.any((h) => h.isScheduledFor(d))) owed++;
  }
  return owed;
}

void main() {
  // August 2026: the 15th is a Saturday, so 16 Sun, 17 Mon, 18 Tue, 19 Wed.
  final sat = DateTime(2026, 8, 15);
  final sun = DateTime(2026, 8, 16);
  final mon = DateTime(2026, 8, 17);
  final wed = DateTime(2026, 8, 19);

  test('the calendar assumption these tests rest on', () {
    expect(sat.weekday, DateTime.saturday);
    expect(mon.weekday, DateTime.monday);
    expect(wed.weekday, DateTime.wednesday);
  });

  test('a Sat/Mon/Wed schedule owes nothing for the Sunday in between', () {
    // Earned Saturday, opened the app Monday. One calendar day sat in
    // between and it asked for nothing, so there is no gap to punish.
    final habits = [_habit(const [DateTime.saturday, DateTime.monday, DateTime.wednesday])];
    expect(owedDaysBetween(sat, mon, habits), 0,
        reason: 'Sunday was a rest day, not a miss');
  });

  test('the same schedule DOES owe the Monday when it was skipped', () {
    // Earned Saturday, opened the app Wednesday. Sunday asked nothing,
    // Monday and Tuesday: Monday asked, so exactly one day was missed.
    final habits = [_habit(const [DateTime.saturday, DateTime.monday, DateTime.wednesday])];
    expect(owedDaysBetween(sat, wed, habits), 1,
        reason: 'Monday was scheduled and went unearned');
  });

  test('a daily habit owes every day in the gap, as it always did', () {
    // The behaviour that must NOT change: an everyday habit still breaks.
    final habits = [_habit(const [])]; // empty == every day
    expect(owedDaysBetween(sat, wed, habits), 3,
        reason: 'Sun, Mon and Tue all asked and none were earned');
  });

  test('today is never counted, because today is still in progress', () {
    final habits = [_habit(const [])];
    // Earned yesterday, opened today: nothing strictly between them.
    expect(owedDaysBetween(sat, sun, habits), 0);
  });

  test('a habit archived before the gap does not owe those days', () {
    // allHabitsEverProvider hands back habits that have since been paused,
    // bounded by their real dates — a habit that was already gone cannot
    // have demanded the days it was away for.
    final ended = _habit(const []).withDates(
      createdAt: DateTime(2026, 8, 1),
      archivedAt: sat,
    );
    expect(owedDaysBetween(sat, wed, [ended]), 0,
        reason: 'archived on the Saturday, so it asked for nothing after');
  });

  test('the pending gap starts null and survives a copyWith', () {
    final initial = DashboardState.initial();
    expect(initial.pendingStreakGapFrom, isNull);
    final pending = initial.copyWith(pendingStreakGapFrom: sat);
    expect(pending.pendingStreakGapFrom, sat);
    // An unrelated copyWith must not silently drop it, or the gap would be
    // forgotten before anything could judge it.
    expect(pending.copyWith(gold: 5).pendingStreakGapFrom, sat);
    // And clearing is explicit.
    expect(pending.copyWith(clearPendingStreakGap: true).pendingStreakGapFrom,
        isNull);
  });
}
