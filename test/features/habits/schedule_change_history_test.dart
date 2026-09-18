// A schedule change reaches forward only.
//
// Aziz, 2026-09-18: "i had a habit that is spec days, and after some weeks, i
// made it daily habit, it should still for the previous days that is spec
// days, like rest rest days and the other, and the days after are daily. so
// its fair for the user."
//
// Every surface that looks back judged a habit's whole past by the schedule
// it has today, so one edit rewrote weeks: a Monday-and-Thursday habit made
// daily turned every old Tuesday into a miss. These tests walk that exact
// habit through each surface's rule, and the opposite edit, and the two
// weekly-quota edits whose week is cut in half by the change.
//
// September 2026: Saturday the 12th starts the week of the change, Monday the
// 14th, Tuesday the 15th, Wednesday the 16th (the day of the change),
// Thursday the 17th, Friday the 18th.
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/features/grid/models/covered_day.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_cadence.dart';
import 'package:grow_daily_v2/features/habits/models/habit_day_demand.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/models/habit_schedule.dart';
import 'package:grow_daily_v2/features/insights/insight_engine.dart';
import 'package:grow_daily_v2/features/milestones/reports/report_period.dart';
import 'package:grow_daily_v2/features/milestones/reports/report_sections.dart';

const monThu = HabitCadence(
  frequencyType: HabitFrequencyType.weekly,
  frequencyTarget: 2,
  scheduledWeekdays: [DateTime.monday, DateTime.thursday],
);
const daily = HabitCadence(
  frequencyType: HabitFrequencyType.daily,
  frequencyTarget: 1,
);
const fourAWeek = HabitCadence(
  frequencyType: HabitFrequencyType.weekly,
  frequencyTarget: 4,
);

DateTime sep(int day) => DateTime(2026, 9, day);

/// A habit on [now] since 1 August, on [before] until [until].
IslamicHabitTemplate changed({
  required HabitCadence before,
  required DateTime until,
  required HabitCadence now,
}) =>
    IslamicHabitTemplate(
      id: 'h',
      name: 'Sadaqah',
      description: '',
      category: HabitCategory.custom,
      frequencyType: now.frequencyType,
      frequencyTarget: now.frequencyTarget,
      scheduledWeekdays: now.scheduledWeekdays,
      hasTimer: false,
      xpReward: 10,
      goldReward: 5,
      createdAt: DateTime(2026, 8, 1),
      pastCadences: [PastCadence(until: until, cadence: before)],
    );

GreenOnDay greenOn(Set<DateTime> days) =>
    (id, day) => days.any((d) => d.isSameDayAs(day));

List<DateTime> daysFrom(DateTime start, int n) => [
      for (var i = 0; i < n; i++)
        DateTime(start.year, start.month, start.day + i),
    ];

void main() {
  // Saturday 19 September at 11:00: every day through Friday the 18th has
  // closed.
  final after = DateTime(2026, 9, 19, 11);
  final today = sep(19);

  group("Aziz's habit: Monday and Thursday, made daily on the 16th", () {
    final h = changed(before: monThu, until: sep(15), now: daily);

    test('its old off-days are still off-days', () {
      expect(h.isScheduledFor(sep(8)), isFalse, reason: 'Tuesday, before');
      expect(h.isScheduledFor(sep(15)), isFalse, reason: 'Tuesday, the eve');
      expect(h.isScheduledFor(sep(7)), isTrue, reason: 'Monday, before');
      expect(h.isScheduledFor(sep(10)), isTrue, reason: 'Thursday, before');
      expect(h.isScheduledFor(sep(16)), isTrue, reason: 'the change day');
      expect(h.isScheduledFor(sep(18)), isTrue, reason: 'Friday, after');
    });

    test('an old empty off-day paints as rest, a new empty day does not', () {
      bool covered(DateTime day) => isCoveredDay(
            habit: h,
            day: day,
            today: today,
            square: SquareState.none,
          );
      expect(covered(sep(8)), isTrue);
      expect(covered(sep(15)), isTrue);
      expect(covered(sep(10)), isFalse, reason: 'an old Thursday was owed');
      expect(covered(sep(16)), isFalse, reason: 'daily from the change day');
      expect(covered(sep(18)), isFalse);
    });

    test('only the days it owed then are owed now', () {
      final isGreen = greenOn(const {});
      expect(habitOwesDay(habit: h, day: sep(8), isGreen: isGreen), isFalse);
      expect(habitOwesDay(habit: h, day: sep(10), isGreen: isGreen), isTrue);
      expect(habitOwesDay(habit: h, day: sep(15), isGreen: isGreen), isFalse);
      expect(habitOwesDay(habit: h, day: sep(16), isGreen: isGreen), isTrue);
    });

    test('the report counts the old schedule, then the new one', () {
      // 1 to 18 September: Thursday 3, Monday 7, Thursday 10 and Monday 14
      // under the old schedule, then 16, 17 and 18 daily. Seven, not
      // eighteen: eleven old rest days were read as misses before.
      final days = daysFrom(sep(1), 18);
      expect(
        expectedCompletions(
          habit: h,
          days: days,
          now: after,
          windowEnd: DateTime(2026, 9, 30),
        ),
        7,
      );
      expect(missIsAttributableOn(h, sep(8)), isTrue,
          reason: 'still a day-level schedule, just not one that ran then');
    });

    test('the report grid draws an old Tuesday as rest, not as a miss', () {
      final stat = HabitPeriodStat(
        habit: h,
        marks: const {},
        expected: 0,
        now: after,
      );
      expect(
        cellStateFor(stat: stat, day: sep(8), today: today, now: after),
        MatrixCellState.covered,
      );
      expect(
        cellStateFor(stat: stat, day: sep(10), today: today, now: after),
        MatrixCellState.missed,
      );
      expect(
        cellStateFor(stat: stat, day: sep(17), today: today, now: after),
        MatrixCellState.missed,
      );
    });

    test('the streak carries across the change', () {
      // Done Monday the 14th, then Wednesday the 16th: Tuesday between was a
      // rest day when it happened, so this continues the streak.
      expect(
        scheduledGapBy(last: sep(14), day: sep(16), runsOn: h.runsOn),
        1,
      );
      // Measured by today's schedule it was a gap of two, and a restart.
      expect(scheduledGap(last: sep(14), day: sep(16), weekdays: const {}), 2);
      // And from the Thursday before: Friday to Sunday and Tuesday were off,
      // Monday was owed and missed, so the streak restarts (a gap of 2).
      expect(
        scheduledGapBy(last: sep(10), day: sep(16), runsOn: h.runsOn),
        2,
      );
      expect(runDaysStrictlyBetween(sep(14), sep(18), h.runsOn), 2,
          reason: 'Tuesday rested; Wednesday and Thursday are daily days');
    });

    test("the change day's reminder still carries the streak", () {
      // Done Monday the 14th with a streak of 5; the reminder fires on
      // Wednesday the 16th at 20:00, the day it became daily.
      ({int streak, int missed}) facts({bool Function(DateTime)? runsOn}) {
        final f = NotificationService.reminderFactsAtFireDay(
          today: sep(16),
          fireDay: sep(16),
          fireTime: DateTime(2026, 9, 16, 20),
          streak: 5,
          completedCount: 0,
          lastDoneDaysAgo: 2,
          scheduledWeekdays: const {},
          weekTarget: null,
          weekDoneDays: null,
          runsOn: runsOn,
        );
        return (streak: f.streak, missed: f.missedSinceLastDone);
      }

      expect(facts(runsOn: h.runsOn), (streak: 5, missed: 0),
          reason: 'Tuesday was a rest day then');
      expect(facts(), (streak: 0, missed: 1),
          reason: "by today's schedule alone Tuesday read as a lapse");
    });
  });

  group('the opposite edit: daily, moved to Monday and Thursday on the 16th',
      () {
    final h = changed(before: daily, until: sep(15), now: monThu);

    test('an old blank Tuesday is still a miss, a new one is rest', () {
      expect(h.isScheduledFor(sep(15)), isTrue);
      expect(h.isScheduledFor(sep(8)), isTrue);
      expect(h.isScheduledFor(sep(22)), isFalse);
      expect(
        isCoveredDay(
          habit: h,
          day: sep(15),
          today: today,
          square: SquareState.none,
        ),
        isFalse,
        reason: 'moving the schedule cannot excuse a day already missed',
      );
      expect(
        isCoveredDay(
          habit: h,
          day: sep(18),
          today: today,
          square: SquareState.none,
        ),
        isTrue,
      );
    });

    test('the streak sees the old daily day that was missed', () {
      // Done Monday the 14th, next on Thursday the 17th: Tuesday the 15th was
      // a daily day and nobody did it.
      expect(scheduledGapBy(last: sep(14), day: sep(17), runsOn: h.runsOn), 2);
    });
  });

  group('four a week until Monday the 14th, daily from Tuesday the 15th', () {
    final h = changed(before: fourAWeek, until: sep(14), now: daily);
    final week = daysFrom(sep(12), 7);

    test("the Grid row: quota days by the week, daily days by the day", () {
      final demand = quotaDemandForRow(
        habit: h,
        days: week,
        isGreenAt: (_) => false,
      );
      expect(demand, isNotNull);
      // Saturday to Monday: four in seven was still in reach, so each was a
      // spare day, never owed.
      expect(demand!.sublist(0, 3), everyElement(DayDemand.spare));
      expect(demand.sublist(3), everyElement(isNull));
      expect(
        isCoveredDay(
          habit: h,
          day: sep(12),
          today: today,
          square: SquareState.none,
          demand: demand[0],
        ),
        isTrue,
      );
    });

    test('the progress map and the streak roster: an old quota day was spare',
        () {
      // habitOwesDay is what the progress map, the day score and the day
      // streak all ask. Read with today's daily schedule, Saturday the 12th
      // would have been owed and blank: a miss that never happened.
      final isGreen = greenOn(const {});
      expect(habitOwesDay(habit: h, day: sep(12), isGreen: isGreen), isFalse);
      expect(habitOwesDay(habit: h, day: sep(14), isGreen: isGreen), isFalse);
      expect(habitOwesDay(habit: h, day: sep(15), isGreen: isGreen), isTrue,
          reason: 'daily from Tuesday');
      expect(
        owedHabitIdsOn(habits: [h], day: sep(13), isGreen: isGreen),
        isEmpty,
      );
    });

    test('the report owes the four daily days and none of the quota days', () {
      // Squeezing the target of four into the three quota days would have
      // made all three owed, for a week nobody had fallen behind in.
      expect(
        expectedCompletions(habit: h, days: week, now: after, windowEnd: sep(18)),
        4,
      );
    });

    test('the report grid: old quota days rest, the daily days are missed', () {
      final stat = HabitPeriodStat(
        habit: h,
        marks: const {},
        expected: 4,
        now: after,
      );
      final cells = weekCellStates(
        stat: stat,
        weekDays: week,
        today: today,
        now: after,
      );
      expect(cells.sublist(0, 3), everyElement(MatrixCellState.covered),
          reason: 'spare quota days, never a miss');
      expect(cells.sublist(3), everyElement(MatrixCellState.missed));
      // A single cell with no week in hand still never calls a quota day a
      // miss: the quota was the schedule that day, whatever it is now.
      expect(missIsAttributableOn(h, sep(12)), isFalse);
      expect(
        cellStateFor(stat: stat, day: sep(12), today: today, now: after),
        isNot(MatrixCellState.missed),
      );
    });
  });

  group('daily until Monday the 14th, four a week from Tuesday the 15th', () {
    final h = changed(before: daily, until: sep(14), now: fourAWeek);
    final week = daysFrom(sep(12), 7);
    final done = {sep(12), sep(13), sep(14)};

    test('the sessions done this week count toward the new target', () {
      final demand = quotaDemandForRow(
        habit: h,
        days: week,
        isGreenAt: (i) => done.any((d) => d.isSameDayAs(week[i])),
      );
      expect(demand!.sublist(0, 3), everyElement(isNull),
          reason: 'daily days, answered by the day');
      // Three done, one to go: Tuesday to Thursday are spare, Friday owed.
      expect(demand.sublist(3, 6), everyElement(DayDemand.spare));
      expect(demand[6], DayDemand.owed);
      expect(
        habitOwesDay(habit: h, day: sep(18), isGreen: greenOn(done)),
        isTrue,
      );
      expect(
        habitOwesDay(habit: h, day: sep(16), isGreen: greenOn(done)),
        isFalse,
      );
    });

    test('the report owes three daily days and the one session left', () {
      expect(
        expectedCompletions(
          habit: h,
          days: week,
          marks: {for (final d in done) d.toDateKey(): SquareState.complete},
          now: after,
          windowEnd: sep(18),
        ),
        4,
      );
    });
  });

  group('a quota whose target changed keeps each week at its own target', () {
    // Three a week until Friday the 11th, four a week from Saturday the 12th:
    // a change on a week boundary, so both weeks are whole weeks.
    final h = changed(
      before: const HabitCadence(
        frequencyType: HabitFrequencyType.weekly,
        frequencyTarget: 3,
      ),
      until: sep(11),
      now: fourAWeek,
    );

    test("each day's demand uses its own week's target", () {
      // Three sessions done Saturday to Monday of the old week: the target
      // of three is met, so Thursday the 10th was already earned. Judged by
      // today's target of four it would still be spare, not earned.
      final done = {sep(5), sep(6), sep(7)};
      expect(
        quotaDemandOn(habit: h, day: sep(10), isGreen: greenOn(done)),
        DayDemand.earned,
      );
      // And a blank old week owes its LAST three days, not four.
      final blank = greenOn(const {});
      expect(quotaDemandOn(habit: h, day: sep(8), isGreen: blank),
          DayDemand.spare);
      expect(quotaDemandOn(habit: h, day: sep(9), isGreen: blank),
          DayDemand.owed);
    });

    test('report: three for the old week, four for the new one', () {
      expect(
        expectedCompletions(
          habit: h,
          days: daysFrom(sep(5), 14),
          now: after,
          windowEnd: sep(18),
        ),
        7,
      );
    });
  });

  group('Insights', () {
    // A 56-day window ending Friday 18 September, newest first.
    List<(DateTime, Map<String, dynamic>)> docs(Map<DateTime, SquareState> m) =>
        [
          for (var i = 0; i < 56; i++)
            (
              DateTime(2026, 9, 18 - i),
              {
                if (m[DateTime(2026, 9, 18 - i)] != null)
                  'squareStates': {'h': m[DateTime(2026, 9, 18 - i)]!.name},
              },
            ),
        ];

    test('a habit moved to Monday and Thursday is never said to slip on its '
        'old Wednesdays', () {
      // Daily until Sunday 30 August, and every Wednesday of that stretch
      // missed. Monday and Thursday since, all done.
      final h = changed(before: daily, until: DateTime(2026, 8, 30), now: monThu);
      final marks = <DateTime, SquareState>{
        for (var d = DateTime(2026, 7, 24);
            !d.isAfter(DateTime(2026, 9, 18));
            d = DateTime(d.year, d.month, d.day + 1))
          if (d.weekday != DateTime.wednesday &&
              (d.isBefore(DateTime(2026, 8, 31)) ||
                  d.weekday == DateTime.monday ||
                  d.weekday == DateTime.thursday))
            d: SquareState.complete,
      };
      final result = computeInsights(
        habits: [h],
        days: docs(marks),
        now: after,
      );
      final p = result.patterns['h']!;
      expect(p.cadence, InsightCadence.specificDays);
      expect(p.scheduledByWeekday.keys.toSet(),
          {DateTime.monday, DateTime.thursday});
      expect(p.worstWeekday(), isNull);
      // The old Wednesdays still count in the habit's own rate: they were
      // owed then and they were missed.
      expect(p.rate, lessThan(1));
    });

    test('quota weeks: each week at its own target, the week cut by a '
        'change never scored', () {
      // Three a week until Tuesday 8 September, four a week since.
      final h = changed(
        before: const HabitCadence(
          frequencyType: HabitFrequencyType.weekly,
          frequencyTarget: 3,
        ),
        until: sep(8),
        now: fourAWeek,
      );
      final result = computeInsights(habits: [h], days: docs(const {}), now: after);
      final weeks = result.patterns['h']!.quotaWeeks;
      final byStart = {for (final w in weeks) w.start.toDateKey(): w};
      expect(byStart['2026-08-29']!.target, 3);
      expect(byStart['2026-08-29']!.whole, isTrue);
      expect(byStart['2026-09-05']!.whole, isFalse,
          reason: 'three a week until Tuesday, four after: not one quota');
      expect(byStart['2026-09-12']!.target, 4);
      expect(byStart['2026-09-12']!.whole, isTrue);
      expect(result.patterns['h']!.quotaTarget, 4);
    });
  });
}
