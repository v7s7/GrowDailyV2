// A day that is still open is not a day missed.
//
// Aziz, 2026-09-09: «It auto mark as fail if user didnt do it ... this should
// be marked after the flex hours. Maybe he will train before he sleep for the
// past day.»
//
// The report grid asked only whether a day was in the future. Today is not,
// so a blank TODAY was drawn as a miss from the moment the day began, and
// yesterday from midnight, while the board itself goes on accepting a mark
// for yesterday until kDayCutoffHour (10:00). The report was calling a day
// lost hours before the app stopped letting somebody win it.
//
// The cell now asks DateTimeGameExt.isSettledAt, the same test every report
// percentage asks, so the grey cells and the number beside them count the
// same days. Every clock here is pinned (2026-09-11): this file used to read
// the real clock, so its yesterday case passed on either side of 10:00
// without ever saying which side it had run on.
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/milestones/reports/report_period.dart';
import 'package:grow_daily_v2/features/milestones/reports/report_sections.dart';

void main() {
  // Wednesday 9 to Friday 11 September 2026.
  final wed9 = DateTime(2026, 9, 9);
  final thu10 = DateTime(2026, 9, 10);
  final fri11 = DateTime(2026, 9, 11);
  DateTime friAt(int h, [int m = 0]) => DateTime(2026, 9, 11, h, m);

  IslamicHabitTemplate habit({
    HabitFrequencyType type = HabitFrequencyType.daily,
    int target = 1,
    List<int> weekdays = const [],
  }) =>
      IslamicHabitTemplate(
        id: 'train',
        name: 'Train',
        description: '',
        category: HabitCategory.health,
        frequencyType: type,
        frequencyTarget: target,
        hasTimer: false,
        xpReward: 20,
        goldReward: 8,
        scheduledWeekdays: weekdays,
      );

  MatrixCellState cellFor(
    IslamicHabitTemplate h,
    DateTime day,
    DateTime? now, {
    DateTime? today,
  }) =>
      cellStateFor(
        stat: HabitPeriodStat(habit: h, marks: const {}, expected: 1),
        day: day,
        today: today ?? fri11,
        now: now,
      );

  test('the calendar these tests rest on', () {
    expect(fri11.weekday, DateTime.friday);
  });

  test('a blank today is not a miss on a daily habit, at any hour of it', () {
    for (final h in [0, 5, kDayCutoffHour, 23]) {
      expect(cellFor(habit(), fri11, friAt(h)), isNot(MatrixCellState.missed),
          reason: 'the day is still being lived at $h:00');
    }
  });

  test('a blank today is not a miss on a specific-days habit', () {
    final h = habit(
      type: HabitFrequencyType.weekly,
      weekdays: const [DateTime.friday],
    );
    expect(cellFor(h, fri11, friAt(5, 19)), isNot(MatrixCellState.missed));
  });

  test('a day that is genuinely over and blank is still a miss, at every hour',
      () {
    // The rule narrows the window; it does not abolish the verdict.
    for (var h = 0; h < 24; h++) {
      expect(cellFor(habit(), wed9, friAt(h)), MatrixCellState.missed,
          reason: '$h:00');
    }
  });

  test('yesterday is not a miss one minute before the cutoff', () {
    expect(
      cellFor(habit(), thu10, friAt(kDayCutoffHour - 1, 59)),
      isNot(MatrixCellState.missed),
    );
  });

  test('yesterday is a miss from the cutoff on', () {
    expect(cellFor(habit(), thu10, friAt(kDayCutoffHour)),
        MatrixCellState.missed);
  });

  test('the grey cells and the percentage beside them count the same days',
      () {
    final h = habit();
    final days = [for (var d = 1; d <= 11; d++) DateTime(2026, 9, d)];
    for (final now in [friAt(5, 19), friAt(kDayCutoffHour)]) {
      final stat = computeHabitPeriodStats(
        habits: [h],
        history: const {},
        days: days,
        now: now,
        windowEnd: DateTime(2026, 9, 30),
      ).single;
      final missed = [
        for (final d in days)
          if (cellStateFor(stat: stat, day: d, today: fri11, now: now) ==
              MatrixCellState.missed)
            d,
      ];
      expect(missed.length, stat.expected, reason: 'at $now');
    }
  });

  test('a marked day is unaffected by any of this', () {
    final stat = HabitPeriodStat(
      habit: habit(),
      marks: {fri11.toDateKey(): SquareState.complete},
      expected: 1,
    );
    expect(
      cellStateFor(stat: stat, day: fri11, today: fri11, now: friAt(5, 19)),
      MatrixCellState.done,
    );
  });

  test('without a clock the cell reads the real one, as every caller once did',
      () {
    final realToday = DateTime.now().effectiveDay;
    final twoDaysBack = realToday.subtract(const Duration(days: 2));
    expect(cellFor(habit(), twoDaysBack, null, today: realToday),
        MatrixCellState.missed);
    expect(cellFor(habit(), realToday, null, today: realToday),
        isNot(MatrixCellState.missed));
  });
}
