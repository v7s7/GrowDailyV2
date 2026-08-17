import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/features/insights/insight_engine.dart';

HabitPattern pattern(String id, {required int scheduled, required int done}) =>
    HabitPattern(id)
      ..scheduled = scheduled
      ..completed = done;

/// The per-habit list on InsightsScreen is the app's only "which of your
/// habits is working" ranking, so what sits at the top of it is a claim.
void main() {
  group('rankHabitPatterns', () {
    test('a 1-of-1 habit does not outrank a real 18-of-28', () {
      // The bug: sorting on rate alone put "قراءة القرآن 1/1" (100%) above
      // "صلاة الوتر 18/28" (64%) — one opportunity crowning the list.
      final ranked = rankHabitPatterns([
        pattern('once', scheduled: 1, done: 1),
        pattern('real', scheduled: 28, done: 18),
      ]);
      expect(ranked.first.habitId, 'real');
      expect(ranked.last.habitId, 'once');
    });

    test('thin habits keep their row, they just sort last', () {
      final ranked = rankHabitPatterns([
        pattern('thin_perfect', scheduled: 2, done: 2),
        pattern('thin_poor', scheduled: 3, done: 0),
        pattern('solid', scheduled: 20, done: 5),
      ]);
      expect(ranked.map((p) => p.habitId), ['solid', 'thin_perfect', 'thin_poor'],
          reason: 'nothing is dropped; the floor only reorders');
      expect(ranked.length, 3);
    });

    test('above the floor, higher rate wins', () {
      final ranked = rankHabitPatterns([
        pattern('mid', scheduled: 10, done: 5),
        pattern('high', scheduled: 10, done: 9),
        pattern('low', scheduled: 10, done: 1),
      ]);
      expect(ranked.map((p) => p.habitId), ['high', 'mid', 'low']);
    });

    test('equal rates break on volume, not insertion order', () {
      final ranked = rankHabitPatterns([
        pattern('small', scheduled: 6, done: 3),
        pattern('big', scheduled: 40, done: 20),
      ]);
      expect(ranked.first.habitId, 'big',
          reason: '50% off 40 days is a stronger claim than 50% off 6');
    });

    test('thin habits are ranked among themselves by rate', () {
      final ranked = rankHabitPatterns([
        pattern('thin_low', scheduled: 2, done: 0),
        pattern('thin_high', scheduled: 2, done: 2),
      ]);
      expect(ranked.map((p) => p.habitId), ['thin_high', 'thin_low']);
    });

    test('exactly at the floor counts as a real sample', () {
      final ranked = rankHabitPatterns(
        [
          pattern('at_floor', scheduled: 5, done: 5),
          pattern('below_floor', scheduled: 4, done: 4),
        ],
        minSamples: 5,
      );
      expect(ranked.first.habitId, 'at_floor');
    });

    test('an empty input is not an error', () {
      expect(rankHabitPatterns(const []), isEmpty);
    });

    test('a zero-scheduled habit reports rate 0 rather than dividing by 0', () {
      final p = pattern('never', scheduled: 0, done: 0);
      expect(p.rate, 0);
      expect(rankHabitPatterns([p]).single.habitId, 'never');
    });
  });
}
