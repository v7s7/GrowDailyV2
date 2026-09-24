// A Grid mark judges today's streak point against the day's own BOARD, the
// list the summary card counts «من N عادات اليوم» from.
//
// It used every habit allowed on that weekday (isScheduledFor), so a weekly
// quota's rest day sat in the Grid's denominator while the card, Today's Mark
// Done, Tasbih, steps and every grace-day mark left it out. Aziz's board on
// 2026-09-21: 11 habits, the card said 9 for the day (تمرين resting, تنعيم
// اللحية off that weekday), the Grid's own check counted 10. A day of 7 of 8
// on the card (88%) was 7 of 9 (78%) there and earned no point.
//
// Two halves, for the reason half_square_counts_everywhere_test.dart gives:
// the arithmetic in one place, and a sweep over the call sites, because a
// unit test of the function passes however many callers bypass it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';

IslamicHabitTemplate _habit(
  String id, {
  HabitFrequencyType type = HabitFrequencyType.daily,
  int target = 1,
}) =>
    IslamicHabitTemplate(
      id: id,
      name: id,
      description: '',
      category: HabitCategory.custom,
      frequencyType: type,
      frequencyTarget: target,
      hasTimer: false,
      xpReward: 10,
      goldReward: 5,
    );

void main() {
  // Saturday 19 to Friday 25 September 2026, marked on the Wednesday.
  final saturday = DateTime(2026, 9, 19);
  final wednesday = DateTime(2026, 9, 23);
  final dailies = [for (var i = 1; i <= 5; i++) _habit('d$i')];
  // Twice a week, any days, and already done twice (Saturday and Sunday):
  // every other day of the week is an earned rest day.
  final quota = _habit('gym', type: HabitFrequencyType.weekly, target: 2);
  final habits = [...dailies, quota];
  final week = WeeklyGridState(
    weekStart: saturday,
    states: {
      '2026-09-19': {'gym': SquareState.complete},
      '2026-09-20': {'gym': SquareState.complete},
    },
    notes: const {},
  );
  final threeDone = DashboardState(
    level: 1,
    currentLevelXp: 0,
    cumulativeXp: 0,
    gold: 0,
    streak: 3,
    completions: const {'d1': 1, 'd2': 1, 'd3': 1},
  );

  group('gridStreakRoster', () {
    test("a quota's rest day is not on the roster", () {
      final roster = gridStreakRoster(
        habits: habits,
        grid: week,
        markingId: 'd4',
        day: wednesday,
      );
      expect(roster.map((h) => h.id), ['d1', 'd2', 'd3', 'd4', 'd5']);
    });

    test('4 of 5 owed habits crosses 80%, as the card shows it', () {
      final roster = gridStreakRoster(
        habits: habits,
        grid: week,
        markingId: 'd4',
        day: wednesday,
      );
      expect(
        willCompleteAllHabitsToday(
          state: threeDone,
          todayHabits: roster,
          habitId: 'd4',
          frequencyTarget: 1,
        ),
        isTrue,
      );
      // The roster the Grid used to build: the resting quota inside it made
      // the same day 4 of 6.
      final old = habits
          .where((h) => h.isScheduledFor(wednesday))
          .map((h) => (id: h.id, frequencyTarget: h.effectiveDailyTarget));
      expect(
        willCompleteAllHabitsToday(
          state: threeDone,
          todayHabits: old,
          habitId: 'd4',
          frequencyTarget: 1,
        ),
        isFalse,
      );
    });

    test('the habit being marked stays on it, even on its own rest day', () {
      final roster = gridStreakRoster(
        habits: habits,
        grid: week,
        markingId: 'gym',
        day: wednesday,
      );
      expect(roster.map((h) => h.id), contains('gym'));
    });

    test('a week it cannot read keeps the quota owed', () {
      // Still loading, or scrolled to another week: an unreadable week is
      // not evidence of a rest day (see boardHabitsOn).
      final loading = WeeklyGridState(
        weekStart: saturday,
        states: week.states,
        notes: const {},
        isLoading: true,
      );
      final roster = gridStreakRoster(
        habits: habits,
        grid: loading,
        markingId: 'd4',
        day: wednesday,
      );
      expect(roster.map((h) => h.id), contains('gym'));
    });
  });

  test('every streak roster in lib is a day board, never isScheduledFor', () {
    // Each `todayHabits = ...` assignment in a file that decides a day's
    // streak point, up to its semicolon.
    final bad = <String>[];
    var seen = 0;
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final src = entity.readAsStringSync();
      if (!src.contains('willCompleteAllHabitsToday(')) continue;
      var i = src.indexOf('final todayHabits =');
      while (i != -1) {
        final end = src.indexOf(';', i);
        final expr = src.substring(i, end);
        seen++;
        final isBoard = expr.contains('boardHabitsOn(') ||
            expr.contains('gridStreakRoster(') ||
            expr.contains('_streakRosterFor(');
        if (!isBoard || expr.contains('isScheduledFor(')) {
          bad.add('${entity.path}: ${expr.split('\n').first}');
        }
        i = src.indexOf('final todayHabits =', end);
      }
    }
    // Grid table (three), cell editor, main.dart (two), Tasbih, steps.
    expect(seen, greaterThanOrEqualTo(7),
        reason: 'rosters disappeared, so this sweep guards nothing');
    expect(bad, isEmpty,
        reason: "these judge the day's streak on a different list from the "
            'one the Grid card shows');
  });
}
