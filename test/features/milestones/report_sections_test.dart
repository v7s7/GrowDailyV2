// Pure-logic tests for the reports hub's grid geometry
// (lib/features/milestones/reports/report_sections.dart).
//
// Two functions, both of which fail silently and invisibly when wrong: a
// month grid whose leading offset is off by one shifts every day under the
// wrong weekday and still looks like a calendar, and a matrix cell that
// resolves "not due" as "missed" accuses someone of misses they never made.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart'
    show startOfGridWeek;
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/milestones/reports/report_period.dart';
import 'package:grow_daily_v2/features/milestones/reports/report_sections.dart';

void main() {
  IslamicHabitTemplate habit({
    List<int> scheduledWeekdays = const [],
    DateTime? createdAt,
  }) =>
      IslamicHabitTemplate(
        id: 'h1',
        name: 'h1',
        description: '',
        category: HabitCategory.faith,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
        scheduledWeekdays: scheduledWeekdays,
        hasTimer: false,
        xpReward: 10,
        goldReward: 1,
        createdAt: createdAt,
      );

  group('monthGridCells', () {
    test('pads to whole weeks', () {
      final cells = monthGridCells(DateTime(2026, 8));
      expect(cells.length % 7, 0);
    });

    test('the 1st lands in the column its weekday deserves', () {
      // 2026-08-01 is a Saturday, which is column 0 in this app's
      // Saturday-anchored week, so there is no leading pad at all.
      final cells = monthGridCells(DateTime(2026, 8));
      expect(cells.first, DateTime(2026, 8, 1));
    });

    test('a month starting mid-week gets the right leading pad', () {
      // 2026-09-01 is a Tuesday. Saturday, Sunday, Monday come first.
      final cells = monthGridCells(DateTime(2026, 9));
      expect(cells.take(3).every((c) => c == null), isTrue);
      expect(cells[3], DateTime(2026, 9, 1));
    });

    test('holds every day of the month exactly once', () {
      final cells = monthGridCells(DateTime(2026, 2));
      final real = cells.whereType<DateTime>().toList();
      expect(real.length, 28);
      expect(real.first, DateTime(2026, 2, 1));
      expect(real.last, DateTime(2026, 2, 28));
    });

    test('leap February keeps its 29th', () {
      final real =
          monthGridCells(DateTime(2028, 2)).whereType<DateTime>().toList();
      expect(real.length, 29);
    });

    test('every real day sits under the column its weekday earns', () {
      // The off-by-one this exists to catch: a day's column index must
      // equal its offset from the week anchor, for every day of the month.
      // Checked across four months with four different starting weekdays.
      for (final month in [
        DateTime(2026, 2),
        DateTime(2026, 9),
        DateTime(2026, 11),
        DateTime(2027, 5),
      ]) {
        final cells = monthGridCells(month);
        for (var i = 0; i < cells.length; i++) {
          final day = cells[i];
          if (day == null) continue;
          expect(
            i % 7,
            day.difference(startOfGridWeek(day)).inDays,
            reason: 'the ${day.toDateKey()} cell is in the wrong column',
          );
        }
      }
    });
  });

  group('weekCellStates', () {
    final weekDays = [
      for (var i = 0; i < 7; i++) DateTime(2026, 8, 15 + i),
    ];

    test('days after today are future, never missed', () {
      // The trap: a week in progress must not report its remaining days as
      // failures the moment it is opened.
      final stat = HabitPeriodStat(
        habit: habit(),
        marks: const {},
        expected: 5,
      );
      final states = weekCellStates(
        stat: stat,
        weekDays: weekDays,
        today: DateTime(2026, 8, 19),
      );
      expect(states.sublist(5), everyElement(MatrixCellState.future));
      expect(states.sublist(0, 5), everyElement(MatrixCellState.missed));
    });

    test('a day the habit was not scheduled for is notDue, not missed', () {
      // A Monday-only habit has six blank cells a week that are not
      // failures. Drawing them as misses is the accusation this exists to
      // prevent.
      final stat = HabitPeriodStat(
        habit: habit(scheduledWeekdays: const [DateTime.monday]),
        marks: const {},
        expected: 1,
      );
      final states = weekCellStates(
        stat: stat,
        weekDays: weekDays,
        today: DateTime(2026, 8, 21),
      );
      expect(states.where((s) => s == MatrixCellState.missed).length, 1);
      expect(states.where((s) => s == MatrixCellState.notDue).length, 6);
    });

    test('days before the habit existed are notDue', () {
      final stat = HabitPeriodStat(
        habit: habit(createdAt: DateTime(2026, 8, 18)),
        marks: const {},
        expected: 2,
      );
      final states = weekCellStates(
        stat: stat,
        weekDays: weekDays,
        today: DateTime(2026, 8, 19),
      );
      expect(states.take(3), everyElement(MatrixCellState.notDue));
    });

    test('a quota habit has no missed days, only done and not due', () {
      // The contradiction this pins: a "three times a week, any three"
      // habit hit three times used to render three filled cells beside four
      // "missed" outlines AND a PERFECT badge on the same row.
      final quota = IslamicHabitTemplate(
        id: 'h1',
        name: 'h1',
        description: '',
        category: HabitCategory.faith,
        frequencyType: HabitFrequencyType.weekly,
        frequencyTarget: 3,
        hasTimer: false,
        xpReward: 10,
        goldReward: 1,
      );
      final stat = HabitPeriodStat(
        habit: quota,
        marks: {DateTime(2026, 8, 15).toDateKey(): SquareState.complete, DateTime(2026, 8, 17).toDateKey(): SquareState.complete, DateTime(2026, 8, 19).toDateKey(): SquareState.complete},
        expected: 3,
      );
      final states = weekCellStates(
        stat: stat,
        weekDays: weekDays,
        today: DateTime(2026, 8, 21),
      );
      expect(states.where((s) => s == MatrixCellState.missed), isEmpty);
      expect(states.where((s) => s == MatrixCellState.done).length, 3);
      expect(states.where((s) => s == MatrixCellState.notDue).length, 4);
      // And the row still earns its mark, without contradicting the cells.
      expect(stat.isPerfect, isTrue);
    });

    test('a daily habit still shows real misses', () {
      // The other half of the rule: where a specific day WAS owed, a blank
      // is a miss and must keep saying so.
      final stat = HabitPeriodStat(
        habit: habit(),
        marks: {DateTime(2026, 8, 15).toDateKey(): SquareState.complete},
        expected: 7,
      );
      final states = weekCellStates(
        stat: stat,
        weekDays: weekDays,
        today: DateTime(2026, 8, 21),
      );
      expect(states.where((s) => s == MatrixCellState.missed).length, 6);
    });

    test('a done day wins over every other reading', () {
      // Including a day the habit was not scheduled for: a completion that
      // actually happened is never redrawn as "not due".
      final stat = HabitPeriodStat(
        habit: habit(scheduledWeekdays: const [DateTime.monday]),
        marks: {DateTime(2026, 8, 15).toDateKey(): SquareState.complete},
        expected: 1,
      );
      final states = weekCellStates(
        stat: stat,
        weekDays: weekDays,
        today: DateTime(2026, 8, 21),
      );
      expect(states.first, MatrixCellState.done);
    });

    test('returns exactly one state per day handed in', () {
      final stat = HabitPeriodStat(
        habit: habit(),
        marks: const {},
        expected: 7,
      );
      expect(
        weekCellStates(
          stat: stat,
          weekDays: weekDays,
          today: DateTime(2026, 8, 21),
        ).length,
        7,
      );
    });
  });
}
