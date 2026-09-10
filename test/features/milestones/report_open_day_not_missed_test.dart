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
// isOpenDay is exactly that window (today, plus yesterday until the cutoff),
// so the report and the board now agree about which days are still anybody's
// to finish.
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/milestones/reports/report_period.dart';
import 'package:grow_daily_v2/features/milestones/reports/report_sections.dart';

void main() {
  final today = DateTime.now().effectiveDay;

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

  MatrixCellState cellFor(IslamicHabitTemplate h, DateTime day) => cellStateFor(
        stat: HabitPeriodStat(
          habit: h,
          marks: const {},
          expected: 1,
        ),
        day: day,
        today: today,
      );

  test('a blank today is not a miss, on a daily habit', () {
    expect(cellFor(habit(), today), isNot(MatrixCellState.missed),
        reason: 'the day is still being lived');
  });

  test('a blank today is not a miss, on a specific-days habit', () {
    final h = habit(
      type: HabitFrequencyType.weekly,
      weekdays: [today.weekday],
    );
    expect(cellFor(h, today), isNot(MatrixCellState.missed));
  });

  test('a day that is genuinely over and blank is still a miss', () {
    // The rule narrows the window; it does not abolish the verdict. Two days
    // back is closed under every hour of the clock, cutoff included.
    final closed = today.subtract(const Duration(days: 2));
    expect(closed.isOpenDay, isFalse, reason: 'sanity: the day is shut');
    expect(cellFor(habit(), closed), MatrixCellState.missed);
  });

  test('yesterday follows the same cutoff the board uses', () {
    // Whichever side of 10:00 the suite runs on, the report agrees with
    // isOpenDay rather than with the calendar.
    final yesterday = today.subtract(const Duration(days: 1));
    final cell = cellFor(habit(), yesterday);
    expect(
      cell == MatrixCellState.missed,
      !yesterday.isOpenDay,
      reason: 'missed exactly when the day has closed, never before',
    );
  });

  test('a marked day is unaffected by any of this', () {
    final stat = HabitPeriodStat(
      habit: habit(),
      marks: {today.toDateKey(): SquareState.complete},
      expected: 1,
    );
    expect(
      cellStateFor(stat: stat, day: today, today: today),
      MatrixCellState.done,
    );
  });
}
