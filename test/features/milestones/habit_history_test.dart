// The yearly strip's data rules and geometry.
//
// dayIsDone is the single spelling of "this habit was done that day" —
// the live mirror writers, the one-time backfill, and the guest reader all
// depend on it agreeing with itself, so its truth table is pinned first.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/milestones/notifiers/habit_history_notifier.dart';
import 'package:grow_daily_v2/features/milestones/screens/year_record_screen.dart';

void main() {
  group('dayIsDone', () {
    test('a positive completion count is done', () {
      expect(dayIsDone({'completions': {'h1': 1}}, 'h1'), isTrue);
      expect(dayIsDone({'completions': {'h1': 3}}, 'h1'), isTrue);
    });

    test('zero or absent count alone is not done', () {
      expect(dayIsDone({'completions': {'h1': 0}}, 'h1'), isFalse);
      expect(dayIsDone(const {}, 'h1'), isFalse);
      expect(dayIsDone({'completions': {'h2': 5}}, 'h1'), isFalse);
    });

    test('a done-state grid square is done, partial is not', () {
      // complete and bonus are the Grid's two "actually did it" states;
      // partial/failed/skipped are records of other outcomes, not credit.
      expect(dayIsDone({'squareStates': {'h1': 'complete'}}, 'h1'), isTrue);
      expect(dayIsDone({'squareStates': {'h1': 'bonus'}}, 'h1'), isTrue);
      expect(dayIsDone({'squareStates': {'h1': 'partial'}}, 'h1'), isFalse);
      expect(dayIsDone({'squareStates': {'h1': 'failed'}}, 'h1'), isFalse);
      expect(dayIsDone({'squareStates': {'h1': 'skipped'}}, 'h1'), isFalse);
    });

    test('either source suffices — the union rule', () {
      // A past-day green set in the Grid writes squareStates only; a
      // today completion writes completions only. Both are the same fact.
      expect(
        dayIsDone(
          {'completions': {'h1': 0}, 'squareStates': {'h1': 'complete'}},
          'h1',
        ),
        isTrue,
      );
      expect(
        dayIsDone(
          {'completions': {'h1': 2}, 'squareStates': {'h1': 'none'}},
          'h1',
        ),
        isTrue,
      );
    });

    test('garbage square values read as not done, never throw', () {
      expect(dayIsDone({'squareStates': {'h1': 'wat'}}, 'h1'), isFalse);
      expect(dayIsDone({'squareStates': {'h1': null}}, 'h1'), isFalse);
    });
  });

  group('aggregateHabitHistory', () {
    test('folds days per habit across both sources', () {
      final out = aggregateHabitHistory({
        '2026-06-13': {
          'completions': {'a': 1},
          'squareStates': {'b': 'complete'},
        },
        '2026-06-14': {
          'completions': {'a': 2, 'b': 0},
        },
        '2026-06-15': {
          'squareStates': {'a': 'partial'},
        },
      });
      expect(out['a'], {'2026-06-13', '2026-06-14'});
      expect(out['b'], {'2026-06-13'});
    });

    test('empty input aggregates to empty, not to entries of empty sets',
        () {
      expect(aggregateHabitHistory(const {}), isEmpty);
      final out = aggregateHabitHistory({
        '2026-06-13': {
          'completions': {'a': 0},
        },
      });
      expect(out.containsKey('a'), isFalse);
    });
  });

  group('year strip geometry', () {
    test('column 0 row of Jan 1 matches its offset from the Saturday origin',
        () {
      // 2026-01-01 is a Thursday; the Saturday-anchored week containing it
      // starts Sat 2025-12-27, so Jan 1 sits in column 0, row 5.
      final cell = yearStripCell(DateTime(2026, 1, 1));
      expect(cell.column, 0);
      expect(cell.row, 5);
      expect(yearStripOrigin(2026), DateTime(2025, 12, 27));
    });

    test('every day of the year fits inside the column count', () {
      for (final year in [2024, 2025, 2026, 2027]) {
        final columns = yearStripColumnCount(year);
        expect(columns, inInclusiveRange(53, 54), reason: '$year');
        final lastCell = yearStripCell(DateTime(year, 12, 31));
        expect(lastCell.column, columns - 1, reason: '$year');
      }
    });

    test('consecutive days walk rows then columns', () {
      final a = yearStripCell(DateTime(2026, 8, 14)); // Friday, week end
      final b = yearStripCell(DateTime(2026, 8, 15)); // Saturday, next week
      expect(a.row, 6);
      expect(b.row, 0);
      expect(b.column, a.column + 1);
    });

    test('tap resolution honors reading direction', () {
      final year = 2026;
      final columns = yearStripColumnCount(year);
      // A tap at the very START of the strip lands in the oldest week —
      // which is the RIGHT edge in Arabic and the LEFT edge in English.
      final ltrFirst = yearStripDayAt(
          year: year, dxFraction: 0.001, row: 0, isRtl: false);
      final rtlFirst = yearStripDayAt(
          year: year, dxFraction: 0.999, row: 0, isRtl: true);
      expect(ltrFirst, yearStripOrigin(year));
      expect(rtlFirst, yearStripOrigin(year));
      // And the newest week is the opposite edge in each direction.
      final ltrLast = yearStripDayAt(
          year: year, dxFraction: 0.999, row: 0, isRtl: false);
      expect(yearStripCell(ltrLast).column, columns - 1);
    });
  });
}
