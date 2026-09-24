// A window's best and weakest days, judged on how FULL each day was.
//
// Aziz, 2026-09-22, replacing the month page's weekday card ("in month we
// need to choose a day of month like 23th, not a Monday"): the fullest day
// is the best; between equally full days, the one with more habits; still
// equal, every one of them shares the mark. The weakest mirrors it over the
// days that have closed.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/milestones/reports/report_period.dart';

void main() {
  DateTime sep(int d) => DateTime(2026, 9, d);

  /// Runs [dayExtremes] over September days given as day -> (done, owed),
  /// with every day up to [openFrom] (exclusive) closed.
  ({List<DateTime> best, List<DateTime> weakest}) extremesOf(
    Map<int, (int, int)> days, {
    int openFrom = 99,
  }) =>
      dayExtremes(
        days: [for (final d in days.keys) sep(d)],
        doneOn: (day) => days[day.day]!.$1,
        owedOn: (day) => days[day.day]!.$2,
        settledOn: (day) => day.day < openFrom,
      );

  group('the best day', () {
    test('the fullest day wins, and between two full days the one with more',
        () {
      // His September: the 13th was 7 of 7 and the 14th 8 of 8, both full;
      // the 20th and 21st had 8 too, but of 9.
      final e = extremesOf({
        13: (7, 7),
        14: (8, 8),
        20: (8, 9),
        21: (8, 9),
      });
      expect(e.best, [sep(14)]);
    });

    test('days still equal after that share the star', () {
      final e = extremesOf({12: (6, 8), 13: (8, 8), 14: (8, 8)});
      expect(e.best, [sep(13), sep(14)]);
    });

    test('equally full means the same fraction, however it is written', () {
      // 2 of 6 and 1 of 3: the fraction ties, the one with more done wins.
      final e = extremesOf({3: (1, 3), 4: (2, 6)});
      expect(e.best, [sep(4)]);
    });

    test('work past what was owed is clamped to full', () {
      final e = extremesOf({5: (9, 8), 6: (8, 8)});
      expect(e.best, [sep(5), sep(6)],
          reason: '9 of 8 reads as 8 of 8, so the two days are equal');
    });

    test('work done on a day that asked for nothing reads full, as its cell',
        () {
      // The calendar draws such a day full (dayFill), so the star agrees.
      final e = extremesOf({7: (1, 0), 8: (3, 6)});
      expect(e.best, [sep(7)]);
      expect(extremesOf({7: (1, 0), 8: (2, 2)}).best, [sep(8)],
          reason: 'equally full, and the 8th has more habits');
    });

    test('with nothing done there is no best day', () {
      expect(extremesOf({9: (0, 4), 10: (0, 4)}).best, isEmpty);
    });
  });

  group('the weakest day', () {
    test('the emptiest day that has closed', () {
      // His 1st (1 of 5) against his 4th (2 of 7).
      final e = extremesOf({1: (1, 5), 4: (2, 7), 14: (8, 8)});
      expect(e.weakest, [sep(1)]);
    });

    test('a day still open is never the weak one', () {
      // Today has nothing yet, and can still be finished.
      final e = extremesOf({1: (1, 5), 14: (8, 8), 22: (0, 9)}, openFrom: 21);
      expect(e.weakest, [sep(1)]);
    });

    test('between equally empty days, the one that asked for more', () {
      final e = extremesOf({2: (1, 4), 3: (2, 8), 14: (8, 8)});
      expect(e.weakest, [sep(3)]);
    });

    test('days still equal after that all carry the ring', () {
      final e = extremesOf({2: (1, 4), 3: (1, 4), 14: (8, 8)});
      expect(e.weakest, [sep(2), sep(3)]);
    });

    test('a month of equally full days names no weak day', () {
      final e = extremesOf({1: (2, 2), 2: (2, 2), 3: (2, 2)});
      expect(e.best, [sep(1), sep(2), sep(3)]);
      expect(e.weakest, isEmpty);
    });

    test('a day that asked for nothing is not a weak day', () {
      final e = extremesOf({6: (0, 0), 7: (2, 4), 14: (8, 8)});
      expect(e.weakest, [sep(7)]);
    });
  });
}
