// Pure-logic tests for the Friday weekly recap computation and the
// full-row celebration trigger — see computeWeeklyRecap (weekly_recap_card.
// dart) and isHabitRowComplete (weekly_grid_notifier.dart).
import 'dart:math';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/grid/models/covered_day.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';
import 'package:grow_daily_v2/features/grid/widgets/weekly_recap_card.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
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
          dailyGreenCounts: counts, weekStart: weekStart, now: null);
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
          dailyGreenCounts: counts, weekStart: weekStart, now: null);
      expect(r.bestDay, weekStart.add(const Duration(days: 1)));
    });

    test('empty week: zero totals and no best day', () {
      final r = computeWeeklyRecap(
          dailyGreenCounts: const {}, weekStart: weekStart, now: null);
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

  group('the recap on a Friday morning', () {
    // Aziz, 2026-09-11: a day still open is not a day missed. The recap shows
    // on Friday, and on Friday morning Thursday is still open until
    // kDayCutoffHour, and Friday itself until the morning after.
    final week = [for (var i = 0; i < 7; i++) DateTime(2026, 9, 5 + i)];
    final beforeCutoff = DateTime(2026, 9, 11, kDayCutoffHour - 1, 59);
    final atCutoff = DateTime(2026, 9, 11, kDayCutoffHour);
    final gym = IslamicHabitTemplate(
      id: 'gym',
      name: 'gym',
      description: '',
      category: HabitCategory.fitness,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 10,
      goldReward: 5,
    );

    /// [marks] by day of September 2026.
    SquareState Function(String, DateTime) squares(
      Map<int, SquareState> marks,
    ) =>
        (id, day) => marks[day.day] ?? SquareState.none;

    ({int done, int scheduled, List<RecapDot> dots}) rowAt(
      Map<int, SquareState> marks,
      DateTime now,
    ) =>
        habitWeekRow(
          habit: gym,
          days: week,
          squareOn: (day) => marks[day.day] ?? SquareState.none,
          now: now,
        );

    test('the calendar these tests rest on', () {
      expect(week.first.weekday, DateTime.saturday);
      expect(week.last.weekday, DateTime.friday);
    });

    test('a blank Thursday and Friday are not misses before the cutoff', () {
      // Done Saturday to Tuesday; Wednesday, Thursday and Friday blank.
      final marks = {for (var d = 5; d <= 8; d++) d: SquareState.complete};
      expect(
        mostMissedHabitThisWeek(
          habits: [gym],
          days: week,
          squareFor: squares(marks),
          now: beforeCutoff,
        ),
        isNull,
        reason: 'only Wednesday has closed, and one miss is life',
      );
      expect(
        mostMissedHabitThisWeek(
          habits: [gym],
          days: week,
          squareFor: squares(marks),
          now: atCutoff,
        )?.id,
        'gym',
        reason: 'Thursday has closed blank as well: two misses',
      );
    });

    test('an explicit فشل counts at once', () {
      final marks = {
        for (var d = 5; d <= 9; d++) d: SquareState.complete,
        10: SquareState.failed,
        11: SquareState.failed,
      };
      expect(
        mostMissedHabitThisWeek(
          habits: [gym],
          days: week,
          squareFor: squares(marks),
          now: beforeCutoff,
        )?.id,
        'gym',
      );
    });

    test('the row leaves open blank days out of its count, and paints them quiet',
        () {
      final marks = {for (var d = 5; d <= 9; d++) d: SquareState.complete};
      final before = rowAt(marks, beforeCutoff);
      expect((before.done, before.scheduled), (5, 5));
      expect(before.dots.sublist(5), [RecapDot.quiet, RecapDot.quiet]);
      final after = rowAt(marks, atCutoff);
      expect((after.done, after.scheduled), (5, 6));
      expect(after.dots.sublist(5), [RecapDot.missed, RecapDot.quiet]);
    });

    test('an open جزئي keeps its colour but waits to be counted', () {
      final marks = {
        for (var d = 5; d <= 9; d++) d: SquareState.complete,
        10: SquareState.partial,
      };
      final before = rowAt(marks, beforeCutoff);
      expect((before.scheduled, before.dots[5]), (5, RecapDot.partial));
      final after = rowAt(marks, atCutoff);
      expect((after.scheduled, after.dots[5]), (6, RecapDot.partial));
    });

    test('a skipped day stays in the count once it closes, as it always did',
        () {
      // Done Saturday to Wednesday, تخطّي on Thursday.
      final marks = {
        for (var d = 5; d <= 9; d++) d: SquareState.complete,
        10: SquareState.skipped,
      };
      final before = rowAt(marks, beforeCutoff);
      expect(
        (before.done, before.scheduled, before.dots[5]),
        (5, 5, RecapDot.skipped),
        reason: 'Thursday is still open, so it waits',
      );
      final after = rowAt(marks, atCutoff);
      expect(
        (after.done, after.scheduled, after.dots[5]),
        (5, 6, RecapDot.skipped),
        reason: 'closed, it counts the way the recap always counted a skip',
      );
    });

    test('a week that has closed reads as it always did', () {
      final marks = {for (var d = 5; d <= 9; d++) d: SquareState.complete};
      final row = rowAt(marks, DateTime(2026, 9, 12, kDayCutoffHour));
      expect((row.done, row.scheduled), (5, 7));
      expect(row.dots.sublist(5), [RecapDot.missed, RecapDot.missed]);
    });

    test('the change against last week holds back the days still open', () {
      // Last week, Sat 29 Aug to Fri 4 Sep: two greens a day, 14. This week:
      // two a day Saturday to Wednesday, one on Thursday, none yet on Friday,
      // 11. Compared in full that is 3 down on Friday morning, and the card
      // said «أسبوع أهدى» before Thursday, let alone Friday, had closed.
      final counts = <String, int>{
        for (var i = 0; i < 7; i++) DateTime(2026, 8, 29 + i).toDateKey(): 2,
        for (var d = 5; d <= 9; d++) DateTime(2026, 9, d).toDateKey(): 2,
        DateTime(2026, 9, 10).toDateKey(): 1,
      };
      WeeklyRecapData at(DateTime? now) => computeWeeklyRecap(
            dailyGreenCounts: counts,
            weekStart: week.first,
            now: now,
          );
      expect(at(null).delta, -3, reason: 'no clock: every day in full');
      expect(at(beforeCutoff).delta, 0,
          reason: 'Thursday and Friday are both still open');
      expect(at(atCutoff).delta, -1,
          reason: 'Thursday has closed on 1 against 2; Friday is still open');
      for (final now in [null, beforeCutoff, atCutoff]) {
        final r = at(now);
        expect((r.thisWeekTotal, r.lastWeekTotal), (11, 14),
            reason: 'each total is a fact about its own week: $now');
      }
    });

    test('an open day can still raise the change', () {
      final counts = <String, int>{
        DateTime(2026, 9, 4).toDateKey(): 2, // last Friday
        DateTime(2026, 9, 11).toDateKey(): 3, // this Friday, still open
      };
      expect(
        computeWeeklyRecap(
          dailyGreenCounts: counts,
          weekStart: week.first,
          now: atCutoff,
        ).delta,
        1,
      );
    });

    // Three times a week, any three. The recap has always counted such a
    // habit day by day, like any other, and still does: only the days still
    // open are held back.
    final gym3 = IslamicHabitTemplate(
      id: 'gym3',
      name: 'gym3',
      description: '',
      category: HabitCategory.fitness,
      frequencyType: HabitFrequencyType.weekly,
      frequencyTarget: 3,
      hasTimer: false,
      xpReward: 10,
      goldReward: 5,
    );

    test('a quota habit is missed day by day, once each day has closed', () {
      // Saturday to Tuesday done; Wednesday, Thursday and Friday blank.
      final marks = {for (var d = 5; d <= 8; d++) d: SquareState.complete};
      IslamicHabitTemplate? most(DateTime now) => mostMissedHabitThisWeek(
            habits: [gym3],
            days: week,
            squareFor: squares(marks),
            now: now,
          );
      expect(
        most(beforeCutoff),
        isNull,
        reason: 'only Wednesday has closed, and one miss is life',
      );
      expect(
        most(atCutoff)?.id,
        'gym3',
        reason: 'Thursday has closed blank as well',
      );
    });

    test('a quota row counts every settled day it was alive, and rings its '
        'closed blanks', () {
      ({int done, int scheduled, List<RecapDot> dots}) row(
        Map<int, SquareState> marks,
      ) =>
          habitWeekRow(
            habit: gym3,
            days: week,
            squareOn: (day) => marks[day.day] ?? SquareState.none,
            now: atCutoff,
          );
      final twoDone = row({5: SquareState.complete, 6: SquareState.complete});
      expect((twoDone.done, twoDone.scheduled), (2, 6));
      expect(twoDone.dots, [
        RecapDot.done,
        RecapDot.done,
        RecapDot.missed,
        RecapDot.missed,
        RecapDot.missed,
        RecapDot.missed,
        // Friday is still open.
        RecapDot.quiet,
      ]);
      final blank = row(const {});
      expect((blank.done, blank.scheduled), (0, 6));
      expect(blank.dots, [
        for (var i = 0; i < 6; i++) RecapDot.missed,
        RecapDot.quiet,
      ]);
    });
  });

  group('the count at the end of a recap row', () {
    final week = [for (var i = 0; i < 7; i++) DateTime(2026, 9, 5 + i)];
    final fri0500 = DateTime(2026, 9, 11, 5);
    IslamicHabitTemplate template(
      String id, {
      HabitFrequencyType type = HabitFrequencyType.daily,
      int target = 1,
      DateTime? createdAt,
    }) =>
        IslamicHabitTemplate(
          id: id,
          name: id,
          description: '',
          category: HabitCategory.fitness,
          frequencyType: type,
          frequencyTarget: target,
          hasTimer: false,
          xpReward: 10,
          goldReward: 5,
          createdAt: createdAt,
        );

    String countOf(
      IslamicHabitTemplate habit,
      Map<int, SquareState> marks,
      DateTime now,
    ) {
      final row = habitWeekRow(
        habit: habit,
        days: week,
        squareOn: (day) => marks[day.day] ?? SquareState.none,
        now: now,
      );
      return recapRowCount(done: row.done, scheduled: row.scheduled);
    }

    test('done over the days counted', () {
      expect(recapRowCount(done: 2, scheduled: 5), '2/5');
      expect(recapRowCount(done: 0, scheduled: 1), '0/1');
    });

    test('a week that owes nothing yet prints a placeholder, never 0/0', () {
      expect(recapRowCount(done: 0, scheduled: 0), '–');
      // Friday 05:00. A 3x habit created on Thursday: both its days are still
      // open. A daily habit created on Friday: its only day is still open.
      expect(
        countOf(
          template(
            'new3',
            type: HabitFrequencyType.weekly,
            target: 3,
            createdAt: DateTime(2026, 9, 10),
          ),
          const {},
          fri0500,
        ),
        '–',
      );
      expect(
        countOf(
          template('newDaily', createdAt: DateTime(2026, 9, 11)),
          const {},
          fri0500,
        ),
        '–',
      );
    });

    test('a quota row past its target still counts its settled days', () {
      // Friday 05:00: four sessions Saturday to Tuesday, Wednesday closed
      // blank, Thursday and Friday still open.
      final marks = {for (var d = 5; d <= 8; d++) d: SquareState.complete};
      expect(
        countOf(
          template('gym3', type: HabitFrequencyType.weekly, target: 3),
          marks,
          fri0500,
        ),
        '4/5',
      );
    });
  });

  group('a day that has closed reads as it did before the open-day rule', () {
    // The recap's arithmetic before 2026-09-11, kept here as the oracle.
    // Every scheduled day up to today counted, a تخطّي included; a green one
    // was done; a flexible quota habit counted every day it was alive, like
    // any other; and a scheduled day neither green nor skipped was a miss.
    // The open-day rule may only hold back the days not yet settled: a
    // scheduled one leaves the count, and a blank one draws quiet instead of
    // the hollow ring. Nothing about a day that has closed may move.
    final week = [for (var i = 0; i < 7; i++) DateTime(2026, 9, 5 + i)];
    IslamicHabitTemplate template(
      String id, {
      HabitFrequencyType type = HabitFrequencyType.daily,
      int target = 1,
      List<int> weekdays = const [],
    }) =>
        IslamicHabitTemplate(
          id: id,
          name: id,
          description: '',
          category: HabitCategory.fitness,
          frequencyType: type,
          frequencyTarget: target,
          scheduledWeekdays: weekdays,
          hasTimer: false,
          xpReward: 10,
          goldReward: 5,
          createdAt: DateTime(2026, 8),
        );
    final habits = [
      template('daily'),
      template(
        'monThu',
        type: HabitFrequencyType.weekly,
        target: 2,
        weekdays: const [DateTime.monday, DateTime.thursday],
      ),
      template('three', type: HabitFrequencyType.weekly, target: 3),
    ];
    const alphabet = [
      SquareState.none,
      SquareState.complete,
      SquareState.partial,
      SquareState.failed,
      SquareState.skipped,
    ];

    /// The row as the card drew it on a Friday before the rule.
    ({int done, int scheduled, List<RecapDot> dots}) oldRow(
      IslamicHabitTemplate habit,
      List<SquareState> marks,
    ) {
      var done = 0;
      var scheduled = 0;
      final dots = <RecapDot>[];
      for (var i = 0; i < week.length; i++) {
        final sq = marks[i];
        final isScheduled = habit.isScheduledFor(week[i]);
        if (isScheduled) {
          scheduled++;
          if (sq.isGreen) done++;
        }
        final covered = isCoveredDay(
          habit: habit,
          day: week[i],
          today: week.last,
          square: sq,
        );
        dots.add(
          covered
              ? RecapDot.covered
              : !isScheduled
                  ? RecapDot.quiet
                  : sq.isGreen
                      ? RecapDot.done
                      : sq == SquareState.failed
                          ? RecapDot.failed
                          : sq == SquareState.skipped
                              ? RecapDot.skipped
                              : sq == SquareState.partial
                                  ? RecapDot.partial
                                  : RecapDot.missed,
        );
      }
      return (done: done, scheduled: scheduled, dots: dots);
    }

    test('a fixed sample of mark patterns, on Friday morning, at the cutoff '
        'and after', () {
      final clocks = [
        DateTime(2026, 9, 11, 5, 19),
        DateTime(2026, 9, 11, kDayCutoffHour),
        DateTime(2026, 9, 12, kDayCutoffHour),
      ];
      final failures = <String>[];
      final total = pow(alphabet.length, week.length).toInt();
      // 4000 of the 78125 patterns, seeded so every run reads the same ones,
      // plus the all-blank and the all-skipped week. The whole set took
      // minutes on a busy machine for no extra reach: each day's dot and
      // count stand alone, and only the miss threshold couples them.
      final random = Random(20260911);
      final codes = {
        0,
        total - 1,
        for (var i = 0; i < 4000; i++) random.nextInt(total),
      };
      for (final habit in habits) {
        for (final code in codes) {
          final marks = <SquareState>[];
          var x = code;
          for (var i = 0; i < week.length; i++) {
            marks.add(alphabet[x % alphabet.length]);
            x ~/= alphabet.length;
          }
          SquareState on(DateTime day) => marks[day.day - 5];
          final old = oldRow(habit, marks);
          for (final now in clocks) {
            var heldBack = 0;
            var misses = 0;
            final dots = <RecapDot>[];
            for (var i = 0; i < week.length; i++) {
              final settled =
                  week[i].isSettledAt(now, answered: marks[i].answersDay);
              final scheduled = habit.isScheduledFor(week[i]);
              if (scheduled && !settled) heldBack++;
              if (scheduled &&
                  settled &&
                  !marks[i].isGreen &&
                  marks[i] != SquareState.skipped) {
                misses++;
              }
              dots.add(
                !settled && old.dots[i] == RecapDot.missed
                    ? RecapDot.quiet
                    : old.dots[i],
              );
            }
            final row = habitWeekRow(
              habit: habit,
              days: week,
              squareOn: on,
              now: now,
            );
            String label() => '${habit.id} $marks at $now';
            if (row.done != old.done ||
                row.scheduled != old.scheduled - heldBack ||
                !listEquals(row.dots, dots)) {
              failures.add('row ${label()}: ${row.done}/${row.scheduled} '
                  '${row.dots}, expected ${old.done}/'
                  '${old.scheduled - heldBack} $dots');
            }
            final named = mostMissedHabitThisWeek(
              habits: [habit],
              days: week,
              squareFor: (_, day) => on(day),
              now: now,
            );
            if ((named != null) != (misses >= 2)) {
              failures.add('most missed ${label()}: $named at $misses misses');
            }
          }
        }
      }
      expect(
        failures.take(10).toList(),
        isEmpty,
        reason: '${failures.length} failures',
      );
    });
  });
}
