// Pure-logic tests for the Premium Habit Insights aggregation — see
// computeInsights (insight_engine.dart) for the rules under test: greens
// and habitCompletions both count as done, skips are excluded entirely,
// weekday patterns need enough samples before they're called patterns.
import 'package:flutter_test/flutter_test.dart';
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
      );
      // steady: 14/14. slipping: 14 scheduled, 0 done. Both clear the
      // >=7-sample bar, so the titles split cleanly between them.
      expect(result.mostConsistentHabitId, 'steady');
      expect(result.needsPushHabitId, 'slipping');
    });

    test('empty window produces zero samples and no titles', () {
      final result = computeInsights(habits: [habit('a')], days: const []);
      expect(result.totalSamples, 0);
      expect(result.strongestWeekday, isNull);
      expect(result.mostConsistentHabitId, isNull);
    });
  });
}
