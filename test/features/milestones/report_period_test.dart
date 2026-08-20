// Pure-logic tests for the reports hub's shared period math
// (lib/features/milestones/reports/report_period.dart) — the layer the
// أسبوعي / شهري / سنوي tabs all compute their numbers through.
//
// The denominator is what most of this file is about. A single "days in the
// period" denominator misreports two of the three habit shapes this app
// supports (fixed-weekday habits and weekly-quota habits), so
// expectedCompletions gets its own group per shape.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/milestones/reports/report_period.dart';

void main() {
  IslamicHabitTemplate habit({
    String id = 'h1',
    HabitFrequencyType frequencyType = HabitFrequencyType.daily,
    int frequencyTarget = 1,
    List<int> scheduledWeekdays = const [],
    DateTime? createdAt,
    DateTime? archivedAt,
  }) =>
      IslamicHabitTemplate(
        id: id,
        name: id,
        description: '',
        category: HabitCategory.faith,
        frequencyType: frequencyType,
        frequencyTarget: frequencyTarget,
        scheduledWeekdays: scheduledWeekdays,
        hasTimer: false,
        xpReward: 10,
        goldReward: 1,
        createdAt: createdAt,
        archivedAt: archivedAt,
      );

  List<DateTime> daysOf(DateTime start, int n) =>
      [for (var i = 0; i < n; i++) DateTime(start.year, start.month, start.day + i)];

  group('reportWindow', () {
    test('week is Saturday-anchored, seven days inclusive', () {
      // 2026-08-19 is a Wednesday; its display week starts Saturday the 15th.
      final w = reportWindow(ReportScope.week, DateTime(2026, 8, 19));
      expect(w.start.weekday, DateTime.saturday);
      expect(w.end.difference(w.start).inDays, 6);
    });

    test('month covers the first through the real last day', () {
      final w = reportWindow(ReportScope.month, DateTime(2026, 2, 14));
      expect(w.start, DateTime(2026, 2, 1));
      expect(w.end, DateTime(2026, 2, 28));
    });

    test('leap February ends on the 29th', () {
      final w = reportWindow(ReportScope.month, DateTime(2028, 2, 14));
      expect(w.end, DateTime(2028, 2, 29));
    });

    test('year spans Jan 1 through Dec 31', () {
      final w = reportWindow(ReportScope.year, DateTime(2026, 6, 6));
      expect(w.start, DateTime(2026, 1, 1));
      expect(w.end, DateTime(2026, 12, 31));
    });
  });

  group('reportPeriodUnlocked', () {
    final now = DateTime(2026, 8, 20);

    test('premium opens every grain at any depth', () {
      for (final scope in ReportScope.values) {
        expect(
          reportPeriodUnlocked(
            scope: scope,
            anchor: DateTime(2019, 3, 4),
            now: now,
            isPremium: true,
          ),
          isTrue,
        );
      }
    });

    test('a free account may open any past week', () {
      // The Grid has never gated past weeks and shows the same completions
      // for free, so a wall here would guard nothing and only read as
      // arbitrary.
      expect(
        reportPeriodUnlocked(
          scope: ReportScope.week,
          anchor: DateTime(2024, 1, 8),
          now: now,
          isPremium: false,
        ),
        isTrue,
      );
    });

    test('a free account keeps the recent months and loses the old ones', () {
      expect(
        reportPeriodUnlocked(
          scope: ReportScope.month,
          anchor: DateTime(2026, 8, 3),
          now: now,
          isPremium: false,
        ),
        isTrue,
      );
      expect(
        reportPeriodUnlocked(
          scope: ReportScope.month,
          anchor: DateTime(2026, 6, 3),
          now: now,
          isPremium: false,
        ),
        isTrue,
      );
      expect(
        reportPeriodUnlocked(
          scope: ReportScope.month,
          anchor: DateTime(2026, 5, 3),
          now: now,
          isPremium: false,
        ),
        isFalse,
      );
    });

    test('the year is never blocked at the step, it mutes instead', () {
      // Blocking would hide years the strip can partly show; the muted
      // cells are the gate, and tapping them raises the demo sheet.
      expect(
        reportPeriodUnlocked(
          scope: ReportScope.year,
          anchor: DateTime(2019, 6, 1),
          now: now,
          isPremium: false,
        ),
        isTrue,
      );
    });
  });

  group('elapsedDaysIn', () {
    test('never runs past today', () {
      final days = elapsedDaysIn(
        start: DateTime(2026, 8, 1),
        end: DateTime(2026, 8, 31),
        today: DateTime(2026, 8, 10),
      );
      expect(days.length, 10);
      expect(days.last, DateTime(2026, 8, 10));
    });

    test('a fully past window is returned whole', () {
      final days = elapsedDaysIn(
        start: DateTime(2026, 7, 1),
        end: DateTime(2026, 7, 31),
        today: DateTime(2026, 8, 10),
      );
      expect(days.length, 31);
    });

    test('a window starting after today is empty', () {
      final days = elapsedDaysIn(
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 30),
        today: DateTime(2026, 8, 10),
      );
      expect(days, isEmpty);
    });
  });

  group('expectedCompletions — daily habits', () {
    test('owes one per elapsed day', () {
      expect(
        expectedCompletions(
            habit: habit(), days: daysOf(DateTime(2026, 8, 1), 10)),
        10,
      );
    });

    test('owes nothing for days before it was created', () {
      final h = habit(createdAt: DateTime(2026, 8, 6));
      expect(
        expectedCompletions(habit: h, days: daysOf(DateTime(2026, 8, 1), 10)),
        5,
      );
    });

    test('owes nothing after it was archived', () {
      final h = habit(archivedAt: DateTime(2026, 8, 4));
      expect(
        expectedCompletions(habit: h, days: daysOf(DateTime(2026, 8, 1), 10)),
        4,
      );
    });
  });

  group('expectedCompletions — fixed weekday habits', () {
    test('a Monday/Thursday habit owes only Mondays and Thursdays', () {
      // A full 28-day stretch holds exactly four of each.
      final h = habit(
        frequencyType: HabitFrequencyType.weekly,
        frequencyTarget: 2,
        scheduledWeekdays: const [DateTime.monday, DateTime.thursday],
      );
      expect(
        expectedCompletions(habit: h, days: daysOf(DateTime(2026, 8, 1), 28)),
        8,
      );
    });

    test('counting all seven weekdays instead would understate the rate', () {
      // The regression this arm exists to prevent: 8 of 8 must read 100%,
      // not 8 of 28.
      final h = habit(
        frequencyType: HabitFrequencyType.weekly,
        frequencyTarget: 2,
        scheduledWeekdays: const [DateTime.monday, DateTime.thursday],
      );
      final days = daysOf(DateTime(2026, 8, 1), 28);
      final stat = HabitPeriodStat(
        habit: h,
        marks: {for (final d in days)
            if (h.isScheduledFor(d)) d.toDateKey(): SquareState.complete},
        expected: expectedCompletions(habit: h, days: days),
      );
      expect(stat.rate, 1.0);
      expect(stat.isPerfect, isTrue);
    });
  });

  group('expectedCompletions — weekly quota habits', () {
    test('owes the target per week, not one per day', () {
      // Four whole Saturday-anchored weeks at three a week.
      final h = habit(
        frequencyType: HabitFrequencyType.weekly,
        frequencyTarget: 3,
      );
      final start = DateTime(2026, 8, 15); // a Saturday
      expect(expectedCompletions(habit: h, days: daysOf(start, 28)), 12);
    });

    test('a partial week owes only the days it actually had', () {
      // Two days of a week can never owe three completions.
      final h = habit(
        frequencyType: HabitFrequencyType.weekly,
        frequencyTarget: 3,
      );
      final start = DateTime(2026, 8, 15); // Saturday
      expect(expectedCompletions(habit: h, days: daysOf(start, 2)), 2);
    });

    test('three of three in a week is perfect, not 43%', () {
      final h = habit(
        frequencyType: HabitFrequencyType.weekly,
        frequencyTarget: 3,
      );
      final start = DateTime(2026, 8, 15);
      final stat = HabitPeriodStat(
        habit: h,
        marks: {DateTime(2026, 8, 15).toDateKey(): SquareState.complete, DateTime(2026, 8, 17).toDateKey(): SquareState.complete, DateTime(2026, 8, 19).toDateKey(): SquareState.complete},
        expected: expectedCompletions(habit: h, days: daysOf(start, 7)),
      );
      expect(stat.expected, 3);
      expect(stat.rate, 1.0);
    });

    test('rate never exceeds 1 when someone beats their quota', () {
      final h = habit(
        frequencyType: HabitFrequencyType.weekly,
        frequencyTarget: 2,
      );
      final start = DateTime(2026, 8, 15);
      final stat = HabitPeriodStat(
        habit: h,
        marks: {for (var i = 0; i < 5; i++)
            DateTime(2026, 8, 15 + i).toDateKey(): SquareState.complete},
        expected: expectedCompletions(habit: h, days: daysOf(start, 7)),
      );
      expect(stat.rate, 1.0);
      expect(stat.isPerfect, isTrue);
    });
  });

  group('rest days leave the denominator', () {
    test('a skipped day is not counted against the habit', () {
      // The arithmetic finally agreeing with the app's own position that a
      // rest day is not a missed day. Seven days, two rested, five done:
      // that is a perfect week, not 5/7.
      final stats = computeHabitPeriodStats(
        habits: [habit()],
        history: {
          'h1': {
            DateTime(2026, 8, 15).toDateKey(): SquareState.complete,
            DateTime(2026, 8, 16).toDateKey(): SquareState.complete,
            DateTime(2026, 8, 17).toDateKey(): SquareState.skipped,
            DateTime(2026, 8, 18).toDateKey(): SquareState.skipped,
            DateTime(2026, 8, 19).toDateKey(): SquareState.complete,
            DateTime(2026, 8, 20).toDateKey(): SquareState.complete,
            DateTime(2026, 8, 21).toDateKey(): SquareState.complete,
          },
        },
        days: daysOf(DateTime(2026, 8, 15), 7),
      );
      final stat = stats.single;
      expect(stat.restCount, 2);
      expect(stat.expected, 5);
      expect(stat.doneCount, 5);
      expect(stat.rate, 1.0);
      expect(stat.isPerfect, isTrue);
    });

    test('an explicit failure still counts against the habit', () {
      // فشل is an admission someone typed. It is not a rest and must not
      // get a rest's exemption.
      final stats = computeHabitPeriodStats(
        habits: [habit()],
        history: {
          'h1': {
            DateTime(2026, 8, 15).toDateKey(): SquareState.complete,
            DateTime(2026, 8, 16).toDateKey(): SquareState.failed,
          },
        },
        days: daysOf(DateTime(2026, 8, 15), 2),
      );
      final stat = stats.single;
      expect(stat.failedCount, 1);
      expect(stat.expected, 2);
      expect(stat.rate, 0.5);
      expect(stat.isPerfect, isFalse);
    });

    test('a partial day earns half, matching the Grid', () {
      // The 0.5 is not invented here: the Grid's own daily ratio has scored
      // partial at 0.5 since before these reports existed.
      final stats = computeHabitPeriodStats(
        habits: [habit()],
        history: {
          'h1': {
            DateTime(2026, 8, 15).toDateKey(): SquareState.complete,
            DateTime(2026, 8, 16).toDateKey(): SquareState.partial,
          },
        },
        days: daysOf(DateTime(2026, 8, 15), 2),
      );
      final stat = stats.single;
      expect(stat.creditedUnits, 1.5);
      expect(stat.rate, 0.75);
      // The day COUNT stays honest: one full day was done, not one and a half.
      expect(stat.doneCount, 1);
    });

    test('bonus counts as done and keeps its own mark', () {
      final stats = computeHabitPeriodStats(
        habits: [habit()],
        history: {
          'h1': {DateTime(2026, 8, 15).toDateKey(): SquareState.bonus},
        },
        days: daysOf(DateTime(2026, 8, 15), 1),
      );
      final stat = stats.single;
      expect(stat.doneCount, 1);
      expect(stat.markOn(DateTime(2026, 8, 15)), SquareState.bonus);
    });

    test('a fully rested window owes nothing and claims nothing', () {
      final stats = computeHabitPeriodStats(
        habits: [habit()],
        history: {
          'h1': {
            for (var i = 0; i < 3; i++)
              DateTime(2026, 8, 15 + i).toDateKey(): SquareState.skipped,
          },
        },
        days: daysOf(DateTime(2026, 8, 15), 3),
      );
      final stat = stats.single;
      expect(stat.expected, 0);
      expect(stat.rate, 0);
      // Not perfect: owing nothing is not the same as achieving everything.
      expect(stat.isPerfect, isFalse);
    });
  });

  group('HabitPeriodStat.isPerfect', () {
    test('a habit that owed nothing has not earned a perfect mark', () {
      // The PERFECT ribbon must not appear over a habit that simply was
      // not due in this period, which is every archived habit and every
      // fixed-weekday habit in a window holding none of its weekdays.
      final stat = HabitPeriodStat(
        habit: habit(),
        marks: const {},
        expected: 0,
      );
      expect(stat.isPerfect, isFalse);
      expect(stat.rate, 0);
    });

    test('done short of what was owed is not perfect', () {
      final stat = HabitPeriodStat(
        habit: habit(),
        marks: {DateTime(2026, 8, 1).toDateKey(): SquareState.complete},
        expected: 2,
      );
      expect(stat.isPerfect, isFalse);
      expect(stat.rate, 0.5);
    });
  });

  group('computeHabitPeriodStats', () {
    test('keeps only the done days that fall inside the window', () {
      final h = habit();
      final stats = computeHabitPeriodStats(
        habits: [h],
        history: {
          'h1': {
            DateTime(2026, 8, 2).toDateKey(): SquareState.complete,
            DateTime(2026, 8, 3).toDateKey(): SquareState.complete,
            // just before the window
            DateTime(2026, 7, 31).toDateKey(): SquareState.complete,
            // just after it
            DateTime(2026, 8, 20).toDateKey(): SquareState.complete,
          },
        },
        days: daysOf(DateTime(2026, 8, 1), 10),
      );
      expect(stats.single.doneCount, 2);
    });

    test('drops a habit that owed nothing and recorded nothing', () {
      final dead = habit(id: 'gone', archivedAt: DateTime(2026, 1, 1));
      final stats = computeHabitPeriodStats(
        habits: [dead],
        history: const {},
        days: daysOf(DateTime(2026, 8, 1), 10),
      );
      expect(stats, isEmpty);
    });

    test('keeps a live habit with an empty row', () {
      final stats = computeHabitPeriodStats(
        habits: [habit()],
        history: const {},
        days: daysOf(DateTime(2026, 8, 1), 10),
      );
      expect(stats.single.doneCount, 0);
      expect(stats.single.expected, 10);
    });
  });

  group('dayCountsFrom', () {
    test('counts how many habits were done on each day', () {
      final counts = dayCountsFrom([
        HabitPeriodStat(
          habit: habit(id: 'a'),
          marks: {DateTime(2026, 8, 1).toDateKey(): SquareState.complete, DateTime(2026, 8, 2).toDateKey(): SquareState.complete},
          expected: 2,
        ),
        HabitPeriodStat(
          habit: habit(id: 'b'),
          marks: {DateTime(2026, 8, 2).toDateKey(): SquareState.complete},
          expected: 2,
        ),
      ]);
      expect(counts[DateTime(2026, 8, 1).toDateKey()], 1);
      expect(counts[DateTime(2026, 8, 2).toDateKey()], 2);
      expect(counts[DateTime(2026, 8, 3).toDateKey()], isNull);
    });

    test('the total matches the filled cells, which is the point', () {
      // The regression: totals used to come from dailyGreenCounts while the
      // grids came from the per-habit mirror, so a day sheet could be
      // headed "4" above six ticked rows. Counting the cells is now the
      // definition, so the two cannot drift.
      final stats = [
        HabitPeriodStat(
          habit: habit(id: 'a'),
          marks: {DateTime(2026, 8, 1).toDateKey(): SquareState.complete},
          expected: 1,
        ),
        HabitPeriodStat(
          habit: habit(id: 'b'),
          marks: {DateTime(2026, 8, 1).toDateKey(): SquareState.complete},
          expected: 1,
        ),
      ];
      final summary = computePeriodSummary(
        dayCounts: dayCountsFrom(stats),
        days: daysOf(DateTime(2026, 8, 1), 7),
        habitStats: stats,
      );
      expect(summary.totalDone, 2);
      expect(
        summary.totalDone,
        stats.fold<int>(0, (n, s) => n + s.doneCount),
      );
    });
  });

  group('splitArchived', () {
    HabitPeriodStat stat(String id, {DateTime? archivedAt, int done = 0}) =>
        HabitPeriodStat(
          habit: habit(id: id, archivedAt: archivedAt),
          marks: {for (var i = 0; i < done; i++) DateTime(2026, 8, 1 + i).toDateKey(): SquareState.complete},
          expected: 10,
        );

    test('live habits stay in the main list', () {
      final split = splitArchived([stat('a'), stat('b', done: 3)]);
      expect(split.active.length, 2);
      expect(split.archived, isEmpty);
    });

    test('an archived habit with history moves to the fold', () {
      // The complaint this fixes: on the monthly tab an archived habit's
      // card rendered identically to a live one, so a habit deliberately
      // put away read as a current commitment.
      final split = splitArchived([
        stat('live'),
        stat('gone', archivedAt: DateTime(2026, 8, 20), done: 4),
      ]);
      expect(split.active.single.habit.id, 'live');
      expect(split.archived.single.habit.id, 'gone');
    });

    test('an archived habit with nothing in the window is dropped', () {
      // Not folded, dropped: an empty archived row is pure noise, which is
      // the "or they should not appear" half of the rule.
      final split = splitArchived([
        stat('gone', archivedAt: DateTime(2026, 8, 20)),
      ]);
      expect(split.active, isEmpty);
      expect(split.archived, isEmpty);
    });

    test('a live habit with an empty row is still kept', () {
      // The asymmetry is deliberate: an empty live row is a commitment
      // waiting to be started, an empty archived row is history that ended.
      final split = splitArchived([stat('live')]);
      expect(split.active.single.doneCount, 0);
    });
  });

  group('computePeriodSummary', () {
    test('longestRun counts consecutive active days inside the window only', () {
      final counts = {
        DateTime(2026, 8, 1).toDateKey(): 2,
        DateTime(2026, 8, 2).toDateKey(): 1,
        DateTime(2026, 8, 3).toDateKey(): 3,
        // 4th is a gap
        DateTime(2026, 8, 5).toDateKey(): 1,
      };
      final summary = computePeriodSummary(
        dayCounts: counts,
        days: daysOf(DateTime(2026, 8, 1), 7),
        habitStats: const [],
      );
      expect(summary.longestRun, 3);
      expect(summary.activeDays, 4);
      expect(summary.totalDone, 7);
      expect(summary.bestDay, DateTime(2026, 8, 3));
      expect(summary.bestDayCount, 3);
    });

    test('a run already going before the window does not carry in', () {
      final counts = {
        DateTime(2026, 7, 28).toDateKey(): 5,
        DateTime(2026, 7, 29).toDateKey(): 5,
        DateTime(2026, 7, 30).toDateKey(): 5,
        DateTime(2026, 7, 31).toDateKey(): 5,
        DateTime(2026, 8, 1).toDateKey(): 1,
      };
      final summary = computePeriodSummary(
        dayCounts: counts,
        days: daysOf(DateTime(2026, 8, 1), 7),
        habitStats: const [],
      );
      expect(summary.longestRun, 1);
    });

    test('rate is measured against what the habits owed', () {
      final h = habit();
      final days = daysOf(DateTime(2026, 8, 1), 10);
      final stats = computeHabitPeriodStats(
        habits: [h],
        history: {
          'h1': {for (var i = 0; i < 5; i++) DateTime(2026, 8, 1 + i).toDateKey(): SquareState.complete},
        },
        days: days,
      );
      final summary = computePeriodSummary(
        dayCounts: {
          for (var i = 0; i < 5; i++) DateTime(2026, 8, 1 + i).toDateKey(): 1,
        },
        days: days,
        habitStats: stats,
      );
      expect(summary.expectedTotal, 10);
      expect(summary.rate, 0.5);
    });

    test('an empty window reports nothing rather than dividing by zero', () {
      final summary = computePeriodSummary(
        dayCounts: const {},
        days: const [],
        habitStats: const [],
      );
      expect(summary.rate, 0);
      expect(summary.hasAnything, isFalse);
      expect(summary.bestDay, isNull);
    });
  });

  group('periodDelta', () {
    Map<String, Map<String, SquareState>> historyOf(List<DateTime> days) => {
          'h1': {for (final d in days) d.toDateKey(): SquareState.complete},
        };

    test('compares only the same stretch of the previous month', () {
      // Through the 10th of August against the FIRST TEN DAYS of July, not
      // all 31. The bug this pins: an identical month showed a large
      // deficit every month until roughly its last day.
      final history = historyOf([
        for (var i = 0; i < 10; i++) DateTime(2026, 8, 1 + i),
        for (var i = 0; i < 10; i++) DateTime(2026, 7, 1 + i),
        // Late July, outside the compared stretch, must not count.
        for (var i = 0; i < 15; i++) DateTime(2026, 7, 15 + i),
      ]);
      final delta = periodDelta(
        scope: ReportScope.month,
        anchor: DateTime(2026, 8, 10),
        history: history,
        habits: [habit()],
        today: DateTime(2026, 8, 10),
        earliestData: DateTime(2026, 1, 1),
      );
      expect(delta, 0);
    });

    test('a real improvement reads positive', () {
      final history = historyOf([
        for (var i = 0; i < 10; i++) DateTime(2026, 8, 1 + i),
        for (var i = 0; i < 4; i++) DateTime(2026, 7, 1 + i),
      ]);
      final delta = periodDelta(
        scope: ReportScope.month,
        anchor: DateTime(2026, 8, 10),
        history: history,
        habits: [habit()],
        today: DateTime(2026, 8, 10),
        earliestData: DateTime(2026, 1, 1),
      );
      expect(delta, 6);
    });

    test('no baseline when the previous period predates the account', () {
      // Otherwise a brand new account gets a delta identical to its own
      // total, which looks like growth and is the same figure twice.
      final history = historyOf([
        for (var i = 0; i < 5; i++) DateTime(2026, 8, 1 + i),
      ]);
      final delta = periodDelta(
        scope: ReportScope.month,
        anchor: DateTime(2026, 8, 10),
        history: history,
        habits: [habit()],
        today: DateTime(2026, 8, 10),
        earliestData: DateTime(2026, 8, 1),
      );
      expect(delta, isNull);
    });

    test('weeks compare against the previous week', () {
      final history = historyOf([
        DateTime(2026, 8, 15),
        DateTime(2026, 8, 16),
        DateTime(2026, 8, 8),
      ]);
      final delta = periodDelta(
        scope: ReportScope.week,
        anchor: DateTime(2026, 8, 16),
        history: history,
        habits: [habit()],
        today: DateTime(2026, 8, 21),
        earliestData: DateTime(2026, 1, 1),
      );
      expect(delta, 1);
    });

    test('counts from the same source as the headline total', () {
      // The July card read "40 مربعًا أخضر" beside "+80" because the total
      // came from the per-habit mirror and the delta from a different
      // tally. Both numbers here must come from `history`.
      final history = historyOf([
        for (var i = 0; i < 6; i++) DateTime(2026, 8, 1 + i),
      ]);
      final days = daysOf(DateTime(2026, 8, 1), 6);
      final total =
          totalDoneIn(history: history, habits: [habit()], days: days);
      final delta = periodDelta(
        scope: ReportScope.month,
        anchor: DateTime(2026, 8, 6),
        history: history,
        habits: [habit()],
        today: DateTime(2026, 8, 6),
        earliestData: DateTime(2026, 1, 1),
      );
      // Nothing in July, so the delta is exactly the total. Never more.
      expect(total, 6);
      expect(delta, 6);
    });
  });

  group('computeWeekdayInsight', () {
    test('finds the strongest and weakest weekday across a month', () {
      // Every Tuesday loaded, every Thursday empty, everything else even.
      final counts = <String, int>{};
      for (var i = 0; i < 28; i++) {
        final day = DateTime(2026, 8, 1 + i);
        counts[day.toDateKey()] = switch (day.weekday) {
          DateTime.tuesday => 8,
          DateTime.thursday => 0,
          _ => 3,
        };
      }
      final insight = computeWeekdayInsight(
        dayCounts: counts,
        days: daysOf(DateTime(2026, 8, 1), 28),
      );
      expect(insight, isNotNull);
      expect(insight!.bestWeekday, DateTime.tuesday);
      expect(insight.worstWeekday, DateTime.thursday);
      expect(insight.isMeaningful, isTrue);
      expect(insight.occurrences, greaterThanOrEqualTo(2));
    });

    test('a single week is one sample per weekday, not a pattern', () {
      final counts = {
        for (var i = 0; i < 7; i++) DateTime(2026, 8, 15 + i).toDateKey(): i,
      };
      final insight = computeWeekdayInsight(
        dayCounts: counts,
        days: daysOf(DateTime(2026, 8, 15), 7),
      );
      expect(insight, isNotNull);
      expect(insight!.occurrences, 1);
      expect(insight.isMeaningful, isFalse);
    });

    test('an empty window yields no insight at all', () {
      final insight = computeWeekdayInsight(
        dayCounts: const {},
        days: daysOf(DateTime(2026, 8, 1), 28),
      );
      expect(insight, isNull);
    });

    test('a flat year is even, not short of history', () {
      // The two failure modes must be distinguishable: this window has
      // plenty of samples and simply no winner, which is a different
      // sentence from "not enough history yet".
      final counts = {
        for (var i = 0; i < 364; i++) DateTime(2026, 1, 1 + i).toDateKey(): 4,
      };
      final insight = computeWeekdayInsight(
        dayCounts: counts,
        days: [for (var i = 0; i < 364; i++) DateTime(2026, 1, 1 + i)],
      );
      expect(insight!.hasEnoughSamples, isTrue);
      expect(insight.isMeaningful, isFalse);
    });

    test('a single week has neither enough samples nor a claim', () {
      final counts = {
        for (var i = 0; i < 7; i++) DateTime(2026, 8, 15 + i).toDateKey(): i,
      };
      final insight = computeWeekdayInsight(
        dayCounts: counts,
        days: [for (var i = 0; i < 7; i++) DateTime(2026, 8, 15 + i)],
      );
      expect(insight!.hasEnoughSamples, isFalse);
      expect(insight.isMeaningful, isFalse);
    });

    test('a flat month has no meaningful best or worst', () {
      final counts = {
        for (var i = 0; i < 28; i++) DateTime(2026, 8, 1 + i).toDateKey(): 4,
      };
      final insight = computeWeekdayInsight(
        dayCounts: counts,
        days: daysOf(DateTime(2026, 8, 1), 28),
      );
      expect(insight!.isMeaningful, isFalse);
    });

    test('a window shorter than a full week yields nothing', () {
      final counts = {
        for (var i = 0; i < 3; i++) DateTime(2026, 8, 1 + i).toDateKey(): 4,
      };
      final insight = computeWeekdayInsight(
        dayCounts: counts,
        days: daysOf(DateTime(2026, 8, 1), 3),
      );
      expect(insight, isNull);
    });
  });
}
