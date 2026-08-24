// A habit's CURRENT streak has to read the same on every screen.
//
// habitStreakCounts is the raw persisted counter and it only ever moves when
// the habit is completed, so a habit abandoned three weeks ago goes on
// reporting the streak it died on. DashboardState.habitStreak applies the
// staleness rule instead: more than a day since habitLastCompletedDate and the
// current streak is zero.
//
// HabitCard (main.dart) always read the corrected one and the habit detail
// sheet read the raw one, so the same habit in the same session showed 0 on
// the home screen and 12 in its own report, with nothing to tell a person
// which number the app believed.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';

void main() {
  DashboardState withLastCompleted(DateTime day, int streak) =>
      DashboardState.initial().copyWith(
        habitStreakCounts: {'h1': streak},
        habitLongestStreaks: {'h1': 30},
        habitLastCompletedDate: {'h1': day.toDateKey()},
      );

  final today = DateTime.now().effectiveDay;

  test('a habit completed today reports its streak', () {
    expect(withLastCompleted(today, 12).habitStreak('h1'), 12);
  });

  test('a habit completed yesterday still reports it', () {
    // Today is not over. A streak is only broken by a day that ENDED without
    // the habit, which is why the tolerance is one day and not zero.
    final yesterday = today.subtract(const Duration(days: 1));
    expect(withLastCompleted(yesterday, 12).habitStreak('h1'), 12);
  });

  test('a habit missed for a day reports zero, not its old streak', () {
    // The number the detail sheet used to show: 12, three weeks after the last
    // completion.
    final stale = today.subtract(const Duration(days: 21));
    final state = withLastCompleted(stale, 12);
    expect(state.habitStreakCounts['h1'], 12,
        reason: 'the raw counter is untouched, which is the whole trap');
    expect(state.habitStreak('h1'), 0);
  });

  test('two days is already stale', () {
    final twoDaysAgo = today.subtract(const Duration(days: 2));
    expect(withLastCompleted(twoDaysAgo, 12).habitStreak('h1'), 0);
  });

  test('a habit never completed reports zero', () {
    expect(DashboardState.initial().habitStreak('h1'), 0);
  });

  test('an unparseable stored date reports zero rather than throwing', () {
    final state = DashboardState.initial().copyWith(
      habitStreakCounts: {'h1': 12},
      habitLastCompletedDate: {'h1': 'not a date'},
    );
    expect(state.habitStreak('h1'), 0);
  });

  test('the lifetime best is NOT subject to the staleness rule', () {
    // A record is not a claim about now. The detail sheet reads this one raw
    // on purpose.
    final stale = today.subtract(const Duration(days: 21));
    expect(withLastCompleted(stale, 12).habitLongestStreaks['h1'], 30);
  });
}
