// A habit's CURRENT streak has to read the same on every screen.
//
// habitStreakCounts is the raw persisted counter and it only ever moves when
// the habit is completed, so a habit abandoned three weeks ago goes on
// reporting the streak it died on. DashboardState.habitStreak applies the
// staleness rule instead: once a day the habit runs on has ended without it,
// the current streak is zero. Given a clock it waits for that day to CLOSE
// (kDayCutoffHour the morning after); no screen passes one yet, and the last
// test of the cutoff group says why.
//
// HabitCard (main.dart) always read the corrected one and the habit detail
// sheet read the raw one, so the same habit in the same session showed 0 on
// the home screen and 12 in its own report, with nothing to tell a person
// which number the app believed.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/habits/models/habit_schedule.dart';

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

  group('yesterday is only a miss once it has closed', () {
    // Pinned clocks on today's date. This used to be one test, "two days is
    // already stale", reading the real clock: the rule Aziz reported against
    // on 2026-09-11. At 05:00 yesterday can still be marked, and marking it
    // continues the streak.
    DateTime at(int h, [int m = 0]) =>
        DateTime(today.year, today.month, today.day, h, m);
    final twoDaysAgo = today.subtract(const Duration(days: 2));

    test('done two days ago keeps its streak while yesterday is open', () {
      final state = withLastCompleted(twoDaysAgo, 12);
      expect(state.habitStreak('h1', now: at(5)), 12);
      expect(state.habitStreak('h1', now: at(kDayCutoffHour - 1, 59)), 12);
    });

    test('and is stale from the cutoff on, with yesterday still blank', () {
      final state = withLastCompleted(twoDaysAgo, 12);
      expect(state.habitStreak('h1', now: at(kDayCutoffHour)), 0);
      expect(state.habitStreak('h1', now: at(11)), 0);
    });

    test('the day before yesterday has closed at every hour', () {
      final threeDaysAgo = today.subtract(const Duration(days: 3));
      expect(
        withLastCompleted(threeDaysAgo, 12).habitStreak('h1', now: at(5)),
        0,
      );
    });

    test('without a clock, the older reading stands', () {
      expect(withLastCompleted(twoDaysAgo, 12).habitStreak('h1'), 0);
    });

    test('the screens keep the older reading until ticking today first keeps it',
        () {
      // Last done two days ago on a 12-day streak, read at 05:00 with
      // yesterday still blank and open. Ticking TODAY first is the natural
      // tap, and completeHabit measures it as a scheduledGap of 2, which
      // nextHabitStreak restarts at 1; ticking yesterday afterwards cannot
      // bring the 12 back. So the habit detail sheet and the reminder builder
      // call habitStreak without a clock: 0 before the tap and 1 after it,
      // never a 12 that the tap takes away. The open-day reading would show
      // that 12, which is why it waits for a writer that keeps the streak.
      final state = withLastCompleted(twoDaysAgo, 12);
      final afterTickingToday = nextHabitStreak(
        gapDays: scheduledGap(
          last: twoDaysAgo,
          day: today,
          weekdays: const {},
        ),
        previousStreak: 12,
      );
      expect(afterTickingToday, 1);
      expect(state.habitStreak('h1'), lessThanOrEqualTo(afterTickingToday),
          reason: 'what the screens show can only rise on that tap');
      expect(
        state.habitStreak('h1', now: at(5)),
        greaterThan(afterTickingToday),
        reason: 'the open-day reading would promise a streak the tap breaks',
      );
    });
  });

  group('a habit pinned to weekdays is judged on its own days', () {
    // Relative to today so the suite passes on any day of the week: the
    // habit runs today and three days ago, and on nothing in between.
    final threeDaysAgo = today.subtract(const Duration(days: 3));
    final twoDaysAgo = today.subtract(const Duration(days: 2));

    test('reported bug: done on its last day, still alive on its next', () {
      // Measured on the calendar this was "two days stale". Not one of the
      // habit's days had ended without it.
      expect(
        withLastCompleted(threeDaysAgo, 12).habitStreak(
          'h1',
          scheduledWeekdays: {today.weekday, threeDaysAgo.weekday},
        ),
        12,
      );
    });

    test('a skipped scheduled day in between is still a miss', () {
      expect(
        withLastCompleted(threeDaysAgo, 12).habitStreak(
          'h1',
          scheduledWeekdays: {today.weekday, twoDaysAgo.weekday},
        ),
        0,
      );
    });

    test('an empty schedule is the every-day rule, unchanged', () {
      expect(
        withLastCompleted(twoDaysAgo, 12)
            .habitStreak('h1', scheduledWeekdays: const {}),
        0,
      );
    });
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
