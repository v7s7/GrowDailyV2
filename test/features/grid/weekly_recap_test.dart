// Pure-logic tests for the Friday weekly recap computation and the
// full-row celebration trigger — see computeWeeklyRecap (weekly_recap_card.
// dart) and isHabitRowComplete (weekly_grid_notifier.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';
import 'package:grow_daily_v2/features/grid/widgets/weekly_recap_card.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';

void main() {
  // 2026-07-11 is a Saturday — a valid grid week start.
  final weekStart = DateTime(2026, 7, 11);
  final prevStart = weekStart.subtract(const Duration(days: 7));

  group('computeWeeklyRecap', () {
    test('sums exactly the 7 days of each week, nothing outside', () {
      final counts = {
        // This week: 2 + 3 = 5.
        weekStart.toDateKey(): 2,
        weekStart.add(const Duration(days: 6)).toDateKey(): 3,
        // Last week: 4.
        prevStart.add(const Duration(days: 2)).toDateKey(): 4,
        // Two weeks ago — must not leak into either total.
        prevStart.subtract(const Duration(days: 1)).toDateKey(): 99,
        // Next week — must not leak either.
        weekStart.add(const Duration(days: 7)).toDateKey(): 99,
      };
      final r = computeWeeklyRecap(
          dailyGreenCounts: counts, weekStart: weekStart);
      expect(r.thisWeekTotal, 5);
      expect(r.lastWeekTotal, 4);
      expect(r.delta, 1);
    });

    test('bestDay is the strongest day, ties resolve to the earliest', () {
      final counts = {
        weekStart.add(const Duration(days: 1)).toDateKey(): 3,
        weekStart.add(const Duration(days: 4)).toDateKey(): 3,
        weekStart.add(const Duration(days: 2)).toDateKey(): 1,
      };
      final r = computeWeeklyRecap(
          dailyGreenCounts: counts, weekStart: weekStart);
      expect(r.bestDay, weekStart.add(const Duration(days: 1)));
    });

    test('empty week: zero totals and no best day', () {
      final r = computeWeeklyRecap(
          dailyGreenCounts: const {}, weekStart: weekStart);
      expect(r.thisWeekTotal, 0);
      expect(r.lastWeekTotal, 0);
      expect(r.bestDay, isNull);
    });
  });

  group('weeklyTotals', () {
    test('returns oldest-first, ending with the current week', () {
      final counts = {
        weekStart.add(const Duration(days: 2)).toDateKey(): 5, // current
        prevStart.toDateKey(): 3, // 1 back
        weekStart.subtract(const Duration(days: 21)).toDateKey(): 7, // 3 back
      };
      expect(
        weeklyTotals(
            dailyGreenCounts: counts, currentWeekStart: weekStart),
        [7, 0, 3, 5],
      );
    });

    test('all-empty history is four zeros', () {
      expect(
        weeklyTotals(
            dailyGreenCounts: const {}, currentWeekStart: weekStart),
        [0, 0, 0, 0],
      );
    });
  });

  group('isHabitRowComplete', () {
    final days =
        List.generate(7, (i) => weekStart.add(Duration(days: i)));

    test('true when every scheduled day is green', () {
      expect(
        isHabitRowComplete(
          days: days,
          isScheduled: (_) => true,
          squareFor: (_) => SquareState.complete,
        ),
        isTrue,
      );
    });

    test('bonus counts as green too', () {
      expect(
        isHabitRowComplete(
          days: days,
          isScheduled: (_) => true,
          squareFor: (d) =>
              d.weekday.isEven ? SquareState.bonus : SquareState.complete,
        ),
        isTrue,
      );
    });

    test('one non-green scheduled day breaks the row', () {
      expect(
        isHabitRowComplete(
          days: days,
          isScheduled: (_) => true,
          squareFor: (d) =>
              d == days.last ? SquareState.partial : SquareState.complete,
        ),
        isFalse,
      );
    });

    test('unscheduled days are ignored entirely', () {
      // Scheduled Mon+Thu only; both green, every other day empty.
      expect(
        isHabitRowComplete(
          days: days,
          isScheduled: (d) =>
              d.weekday == DateTime.monday || d.weekday == DateTime.thursday,
          squareFor: (d) => (d.weekday == DateTime.monday ||
                  d.weekday == DateTime.thursday)
              ? SquareState.complete
              : SquareState.none,
        ),
        isTrue,
      );
    });

    test('a single-scheduled-day week never celebrates as a "row"', () {
      expect(
        isHabitRowComplete(
          days: days,
          isScheduled: (d) => d.weekday == DateTime.friday,
          squareFor: (_) => SquareState.complete,
        ),
        isFalse,
      );
    });
  });

  group('canBrowseHistoryMonth', () {
    final now = DateTime(2026, 7, 17);

    test('free: current month and 2 back are open, the 3rd back is not', () {
      expect(
        canBrowseHistoryMonth(
            monthStart: DateTime(2026, 7, 1), now: now, isPremium: false),
        isTrue,
      );
      expect(
        canBrowseHistoryMonth(
            monthStart: DateTime(2026, 5, 1), now: now, isPremium: false),
        isTrue,
      );
      expect(
        canBrowseHistoryMonth(
            monthStart: DateTime(2026, 4, 1), now: now, isPremium: false),
        isFalse,
      );
    });

    test('free: year boundaries count months correctly', () {
      expect(
        canBrowseHistoryMonth(
            monthStart: DateTime(2025, 12, 1),
            now: DateTime(2026, 1, 10),
            isPremium: false),
        isTrue, // 1 month back
      );
      expect(
        canBrowseHistoryMonth(
            monthStart: DateTime(2025, 10, 1),
            now: DateTime(2026, 1, 10),
            isPremium: false),
        isFalse, // 3 months back
      );
    });

    test('premium: everything is open', () {
      expect(
        canBrowseHistoryMonth(
            monthStart: DateTime(2020, 1, 1), now: now, isPremium: true),
        isTrue,
      );
    });
  });
}
