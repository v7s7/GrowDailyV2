// Reports read a flexible quota's جزئي the way the rooms and the Grid do: a
// half session holding one of its week's places, worth half a day, and
// pushed out by whole sessions. Aziz, 2026-09-26: "0.5 is a day count,
// unless it's overwritten with a full day".
//
// His three weeks, read the Saturday morning after they closed, تمرين four
// times a week: two halves and nothing else is 1 of 4, two halves and four
// whole sessions is 4 of 4, two whole and two halves is 3 of 4. The first
// and last already read that way before this rule; the second read 5 of 4
// in the header.
//
// Since 2026-10-03 halves add up ("3 + 0.5 + 0.5 = 4"): three whole and two
// halves is a PERFECT 4 of 4 here and in the rooms alike, where for a week
// the rooms scored 3.5 and this read 3.5 with them.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/milestones/reports/report_period.dart';

void main() {
  final fourAWeek = IslamicHabitTemplate(
    id: 'gym',
    name: 'gym',
    nameAr: 'تمرين',
    description: '',
    category: HabitCategory.custom,
    frequencyType: HabitFrequencyType.weekly,
    frequencyTarget: 4,
    hasTimer: false,
    xpReward: 10,
    goldReward: 1,
    createdAt: DateTime(2026),
  );
  // Saturday 19 to Friday 25 September 2026, read at 10:00 on the 26th.
  final week = reportWindow(ReportScope.week, DateTime(2026, 9, 22));
  final closed = DateTime(2026, 9, 26, kDayCutoffHour);
  String day(int d) => DateTime(2026, 9, d).toDateKey();

  HabitPeriodStat statOf(Map<int, SquareState> marks, {DateTime? now}) =>
      computeHabitPeriodStats(
        habits: [fourAWeek],
        history: {
          'gym': {for (final e in marks.entries) day(e.key): e.value},
        },
        days: elapsedDaysIn(
          start: week.start,
          end: week.end,
          today: (now ?? closed).effectiveDay,
        ),
        now: now ?? closed,
        windowEnd: week.end,
      ).single;

  const half = SquareState.partial;
  const whole = SquareState.complete;

  (int, double, bool) read(HabitPeriodStat s) =>
      (s.expected, s.creditedUnits, s.isPerfect);

  test('the week is the Saturday week the rooms grade', () {
    expect(week.start, DateTime(2026, 9, 19));
    expect(week.end, DateTime(2026, 9, 25));
  });

  test('two halves and nothing else: 1 of 4', () {
    expect(read(statOf({19: half, 20: half})), (4, 1.0, false));
  });

  test('two halves, then four whole sessions: the whole ones count, 4 of 4',
      () {
    final s = statOf({
      19: half,
      20: half,
      21: whole,
      22: whole,
      23: whole,
      24: whole,
    });
    expect(read(s), (4, 4.0, true));
  });

  test('two whole sessions and two halves: 3 of 4', () {
    expect(
      read(statOf({19: whole, 20: whole, 21: half, 22: half})),
      (4, 3.0, false),
    );
  });

  test('three whole and two halves add up: 4 of 4, PERFECT', () {
    // Aziz, 2026-10-03: "make halves add up, 3 + 0.5 + 0.5 = 4". It read 3.5
    // and was refused the ribbon for a week that met its four.
    final s = statOf({19: half, 20: half, 21: whole, 22: whole, 23: whole});
    expect(read(s), (4, 4.0, true));
  });

  test('two whole and four halves add up: two to each place left, 4 of 4', () {
    final s = statOf({
      19: whole,
      20: whole,
      21: half,
      22: half,
      23: half,
      24: half,
    });
    expect(read(s), (4, 4.0, true));
  });

  test('whole sessions past the target count as they always did', () {
    // The per-habit cap is its own open question (see
    // report_header_half_credit_test.dart); halves do not reopen it.
    final s = statOf({
      19: whole,
      20: whole,
      21: whole,
      22: whole,
      23: whole,
    });
    expect(read(s), (4, 5.0, true));
  });

  test('while the week is open a closed half is owed, as the room reads it',
      () {
    // Monday the 21st after 10:00: Saturday's whole session and Sunday's
    // half have closed. Both are sessions the week has had, so it owes two
    // and holds one and a half: 75%, the room's own number that Monday.
    final monday = DateTime(2026, 9, 21, 11);
    final withHalf = statOf({19: whole, 20: half}, now: monday);
    expect((withHalf.expected, withHalf.creditedUnits), (2, 1.5));
    // Finishing Monday with a whole session only ever raises it.
    final finished = statOf({19: whole, 20: half, 21: whole}, now: monday);
    expect((finished.expected, finished.creditedUnits), (3, 2.5));
    expect(finished.rate, greaterThan(withHalf.rate));
  });

  test('finishing the week with a whole session never reads worse', () {
    // Two halves on a 2x week, Monday open. The halves hold both places;
    // Monday's whole session takes one, and the two halves share the other:
    // 2 of 2, halves adding up. Had the halves sat on top of what the week
    // owed, the week would have read 1.0 of 1 before Monday and less after
    // it, lower for doing more.
    final twoAWeek = IslamicHabitTemplate(
      id: 'two',
      name: 'two',
      description: '',
      category: HabitCategory.custom,
      frequencyType: HabitFrequencyType.weekly,
      frequencyTarget: 2,
      hasTimer: false,
      xpReward: 10,
      goldReward: 1,
      createdAt: DateTime(2026),
    );
    HabitPeriodStat two(Map<int, SquareState> marks) => computeHabitPeriodStats(
          habits: [twoAWeek],
          history: {
            'two': {for (final e in marks.entries) day(e.key): e.value},
          },
          days: elapsedDaysIn(
            start: week.start,
            end: week.end,
            today: DateTime(2026, 9, 21),
          ),
          now: DateTime(2026, 9, 21, 11),
          windowEnd: week.end,
        ).single;
    final before = two({19: half, 20: half});
    final after = two({19: half, 20: half, 21: whole});
    expect((before.expected, before.creditedUnits), (2, 1.0));
    expect((after.expected, after.creditedUnits), (2, 2.0));
    expect(after.rate, greaterThanOrEqualTo(before.rate));
  });
}
