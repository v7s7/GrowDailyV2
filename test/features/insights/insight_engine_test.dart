// Pure-logic tests for the Premium Habit Insights aggregation — see
// computeInsights (insight_engine.dart) for the rules under test: greens
// and habitCompletions both count as done, skips are excluded entirely,
// weekday patterns need enough samples before they're called patterns.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/insights/insight_engine.dart';

IslamicHabitTemplate habit(String id, {List<int> weekdays = const []}) =>
    IslamicHabitTemplate(
      id: id,
      name: id,
      description: '',
      category: HabitCategory.faith,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      scheduledWeekdays: weekdays,
      hasTimer: false,
      xpReward: 10,
      goldReward: 5,
    );

void main() {
  // 2026-06-01 is a Monday — 4 clean weeks of deterministic weekdays.
  final start = DateTime(2026, 6, 1);
  List<DateTime> days(int count) =>
      List.generate(count, (i) => start.add(Duration(days: i)));

  group('computeInsights', () {
    test('greens and habitCompletions both count as done', () {
      final h = habit('a');
      final result = computeInsights(
        habits: [h],
        days: [
          (days(2)[0], {'squareStates': {'a': 'complete'}}),
          (days(2)[1], {'habitCompletions': {'a': 2}}),
        ],
        now: null,
      );
      expect(result.patterns['a']!.scheduled, 2);
      expect(result.patterns['a']!.completed, 2);
    });

    test('skipped days are excluded from the scheduled total entirely', () {
      final h = habit('a');
      final result = computeInsights(
        habits: [h],
        days: [
          (days(2)[0], {'squareStates': {'a': 'skipped'}}),
          (days(2)[1], const <String, dynamic>{}),
        ],
        now: null,
      );
      expect(result.patterns['a']!.scheduled, 1); // only the real miss
      expect(result.patterns['a']!.completed, 0);
    });

    test('worstWeekday needs enough samples and a real miss rate', () {
      final h = habit('a');
      // 4 Mondays all missed, 4 Tuesdays all done — everything else
      // absent (habit scheduled Mon+Tue only).
      final scheduled = habit('a', weekdays: const [1, 2]);
      final windowDays = days(28);
      final result = computeInsights(
        habits: [scheduled],
        days: [
          for (final d in windowDays)
            (
              d,
              d.weekday == DateTime.tuesday
                  ? {'squareStates': {'a': 'complete'}}
                  : const <String, dynamic>{},
            ),
        ],
        now: null,
      );
      expect(result.patterns[h.id]!.worstWeekday(), DateTime.monday);
    });

    test('best and worst titles go to the right, distinct habits', () {
      final steady = habit('steady');
      final slipping = habit('slipping');
      final windowDays = days(14);
      final result = computeInsights(
        habits: [steady, slipping],
        days: [
          for (final d in windowDays)
            (
              d,
              {
                'squareStates': {'steady': 'complete'},
              },
            ),
        ],
        now: null,
      );
      // steady: 14/14. slipping: 14 scheduled, 0 done. Both clear the
      // >=7-sample bar, so the titles split cleanly between them.
      expect(result.mostConsistentHabitId, 'steady');
      expect(result.needsPushHabitId, 'slipping');
    });

    test('empty window produces zero samples and no titles', () {
      final result = computeInsights(habits: [habit('a')], days: const [], now: null);
      expect(result.totalSamples, 0);
      expect(result.strongestWeekday, isNull);
      expect(result.mostConsistentHabitId, isNull);
    });

    // These four guard the exact thing the Habit Insights detail sheet's
    // day-by-day wave chart depends on: that scheduledByWeekday /
    // completedByWeekday are keyed by real DateTime.monday..sunday values
    // matching the actual calendar day, for both a single habit's pattern
    // and the account-wide totals. The chart widget itself (which also had
    // to get RTL mirroring right so Arabic labels land over the correct
    // point) isn't reachable from here — it's a private class in a Flutter
    // widget file, out of reach for a plain logic test — but if this data
    // is wrong, no amount of correct widget code fixes what gets drawn.
    test('scheduledByWeekday/completedByWeekday key by the real calendar weekday', () {
      final h = habit('a');
      final result = computeInsights(
        habits: [h],
        days: [
          (DateTime(2026, 6, 1), {'squareStates': {'a': 'complete'}}), // Monday, done
          (DateTime(2026, 6, 2), const <String, dynamic>{}), // Tuesday, missed
        ],
        now: null,
      );
      final p = result.patterns['a']!;
      expect(p.scheduledByWeekday[DateTime.monday], 1);
      expect(p.completedByWeekday[DateTime.monday], 1);
      expect(p.scheduledByWeekday[DateTime.tuesday], 1);
      // Tuesday was scheduled but never completed - completedByWeekday only
      // ever gets a key written on a real completion (see computeInsights'
      // `if (done)` block), so a missed day leaves the key entirely absent
      // rather than present-and-zero. Every real caller already reads this
      // map through `?? 0` (see _WeekdayWaveChart), so this is the actual
      // contract they depend on, not just an implementation detail.
      expect(p.completedByWeekday.containsKey(DateTime.tuesday), isFalse);
      // No Wednesday in the window at all - same absent-key contract.
      expect(p.scheduledByWeekday.containsKey(DateTime.wednesday), isFalse);
    });

    test('overallScheduledByWeekday/overallCompletedByWeekday sum every habit, same weekday keys', () {
      final a = habit('a');
      final b = habit('b');
      final result = computeInsights(
        habits: [a, b],
        days: [
          (
            DateTime(2026, 6, 1), // Monday
            {
              'squareStates': {'a': 'complete'},
              'habitCompletions': {'b': 1},
            },
          ),
        ],
        now: null,
      );
      expect(result.overallScheduledByWeekday[DateTime.monday], 2);
      expect(result.overallCompletedByWeekday[DateTime.monday], 2);
      expect(result.overallScheduledByWeekday.containsKey(DateTime.tuesday), isFalse);
    });

    test('strongestWeekday names the weekday that actually has the highest rate', () {
      final h = habit('a');
      // 4 full weeks from a Monday: every weekday gets exactly 4 samples,
      // clearing the >=4 floor strongestWeekday requires. Only Mondays are
      // marked done, so Monday should win outright, not by coincidence of
      // list order.
      final windowDays =
          List.generate(28, (i) => DateTime(2026, 6, 1).add(Duration(days: i)));
      final result = computeInsights(
        habits: [h],
        days: [
          for (final d in windowDays)
            (
              d,
              d.weekday == DateTime.monday
                  ? {'squareStates': {'a': 'complete'}}
                  : const <String, dynamic>{},
            ),
        ],
        now: null,
      );
      expect(result.strongestWeekday, DateTime.monday);
    });
  });

  group('computeInsights with a clock', () {
    // Friday 11 September 2026 at 05:19: Thursday is still open until
    // kDayCutoffHour, and Friday has only just begun. A blank day still open
    // is not a miss yet (Aziz, 2026-09-11).
    final wed9 = DateTime(2026, 9, 9);
    final thu10 = DateTime(2026, 9, 10);
    final fri11 = DateTime(2026, 9, 11);
    final at0519 = DateTime(2026, 9, 11, 5, 19);
    final atCutoff = DateTime(2026, 9, 11, kDayCutoffHour);

    List<(DateTime, Map<String, dynamic>)> blanks() => [
          (wed9, const <String, dynamic>{}),
          (thu10, const <String, dynamic>{}),
          (fri11, const <String, dynamic>{}),
        ];

    test('a blank day still open is not a sample yet', () {
      final result =
          computeInsights(habits: [habit('a')], days: blanks(), now: at0519);
      expect(result.patterns['a']!.scheduled, 1,
          reason: 'only Wednesday has closed');
      expect(result.patterns['a']!.completed, 0);
    });

    test('an answered open day counts at once, done or فشل', () {
      final result = computeInsights(
        habits: [habit('a')],
        days: [
          (wed9, const <String, dynamic>{}),
          (thu10, {'habitCompletions': {'a': 1}}),
          (fri11, {'squareStates': {'a': 'failed'}}),
        ],
        now: at0519,
      );
      expect(result.patterns['a']!.scheduled, 3);
      expect(result.patterns['a']!.completed, 1);
    });

    test('an open جزئي waits like a blank day', () {
      final result = computeInsights(
        habits: [habit('a')],
        days: [
          (wed9, const <String, dynamic>{}),
          (thu10, {'squareStates': {'a': 'partial'}}),
        ],
        now: at0519,
      );
      expect(result.patterns['a']!.scheduled, 1);
    });

    test('a counted habit part way there counts the way this engine always did',
        () {
      // 1 of 4 on a Thursday still open at 05:19. This engine has always
      // called any recorded count completed, so the day is answered by its
      // own reading and counts at once, as it did before the clock existed,
      // rather than waiting for 10:00 and then jumping in whole. The reports
      // credit the same day as a جزئي; that difference predates this rule.
      List<(DateTime, Map<String, dynamic>)> withThursday(int count) => [
            (wed9, const <String, dynamic>{}),
            (
              thu10,
              {
                'habitCompletions': {'a': count},
                'habitTargets': {'a': 4},
              }
            ),
          ];
      for (final now in [at0519, atCutoff]) {
        for (final count in [1, 4]) {
          final p = computeInsights(
            habits: [habit('a')],
            days: withThursday(count),
            now: now,
          ).patterns['a']!;
          expect((p.scheduled, p.completed), (2, 1),
              reason: '$count of 4, read at $now');
        }
      }
    });

    test('a blank day enters when it closes', () {
      final result =
          computeInsights(habits: [habit('a')], days: blanks(), now: atCutoff);
      expect(result.patterns['a']!.scheduled, 2);
    });

    test('without a clock every day counts, as before', () {
      final result = computeInsights(habits: [habit('a')], days: blanks(), now: null);
      expect(result.patterns['a']!.scheduled, 3);
    });

    test('a habit whose only days are still open has no pattern yet', () {
      final result = computeInsights(
        habits: [habit('a')],
        days: [(fri11, const <String, dynamic>{})],
        now: at0519,
      );
      expect(result.patterns, isEmpty);
      expect(result.totalSamples, 0);
    });
  });
}
