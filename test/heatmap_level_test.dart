import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/screens/monthly_heatmap_screen.dart';

/// The heatmap colors a day by what fraction of the user's habit list it
/// completed, not by a raw count — otherwise someone tracking 2 habits
/// could never reach full green, while someone tracking 10 could look
/// "more done" on a half-finished day than a 2-habit user having a perfect
/// one.
void main() {
  _archivedCounting();

  test('a perfect day is always the deepest green, at any habit count', () {
    expect(heatLevel(2, 2), 4);
    expect(heatLevel(10, 10), 4);
  });

  test('80%+ but not perfect is one shade lighter', () {
    expect(heatLevel(4, 5), 3); // 80%
    expect(heatLevel(8, 10), 3); // 80%
  });

  test('50-79% is lighter still', () {
    expect(heatLevel(1, 2), 2); // 50%
    expect(heatLevel(3, 5), 2); // 60%
  });

  test('anything below half but above zero is the lightest green', () {
    expect(heatLevel(1, 5), 1); // 20%
  });

  test('no green squares that day is unpainted regardless of habit count', () {
    expect(heatLevel(0, 5), 0);
    expect(heatLevel(0, 0), 0);
  });

  test('a count that exceeds the current habit list still caps at full green', () {
    // e.g. a habit was archived after being completed on a past day.
    expect(heatLevel(6, 3), 4);
  });

  test('falls back to an absolute scale when there are no habits at all', () {
    expect(heatLevel(1, 0), 1);
    expect(heatLevel(3, 0), 2);
    expect(heatLevel(5, 0), 3);
    expect(heatLevel(8, 0), 4);
  });
}

/// derivedDayCounts decides WHICH habits still mark your past.
///
/// Two different acts get confused here, and the difference is the whole
/// test. DELETING a habit throws it away, and its orphaned ids used to paint
/// glowing perfect days on months that were really a habit list being
/// rebuilt. ARCHIVING one puts it aside while deliberately keeping its
/// history: the reports hub folds archived habits under المؤرشفة rather than
/// dropping them, and the Year Record does the same.
///
/// The heatmap used to filter both out, which made it the only screen that
/// forgot archived days: 82 squares here against 83 in the yearly report for
/// the same window, one archived habit apart.
void _archivedCounting() {
  group('derivedDayCounts', () {
    final mirror = {
      'live': {
        '2026-06-01': SquareState.complete,
        '2026-06-02': SquareState.complete,
      },
      'archived': {'2026-06-01': SquareState.complete},
      'deleted': {'2026-06-01': SquareState.complete},
    };

    test('counts archived habits, because archiving is not deleting', () {
      // The caller passes every habit that STILL EXISTS, archived included.
      final counts = derivedDayCounts(mirror, {'live', 'archived'});
      expect(counts['2026-06-01'], 2,
          reason: 'the archived habit still marks the day it was done');
      expect(counts['2026-06-02'], 1);
    });

    test('still ignores habits that no longer exist', () {
      // 'deleted' is absent from the id set because it is gone from the
      // habit list, which is exactly how deletion stays excluded.
      final counts = derivedDayCounts(mirror, {'live', 'archived'});
      expect(counts['2026-06-01'], isNot(3),
          reason: 'a thrown-away habit must not keep grading the past');
    });

    test('the old live-only filter is what made the two screens disagree', () {
      final liveOnly = derivedDayCounts(mirror, {'live'});
      final withArchived = derivedDayCounts(mirror, {'live', 'archived'});
      expect(liveOnly['2026-06-01'], 1);
      expect(withArchived['2026-06-01'], 2);
    });

    test('a partial or failed mark is not a done day', () {
      final counts = derivedDayCounts({
        'live': {
          '2026-06-01': SquareState.partial,
          '2026-06-02': SquareState.failed,
          '2026-06-03': SquareState.bonus,
        },
      }, {'live'});
      expect(counts['2026-06-01'], isNull);
      expect(counts['2026-06-02'], isNull);
      expect(counts['2026-06-03'], 1, reason: 'bonus is a green day');
    });
  });
}
