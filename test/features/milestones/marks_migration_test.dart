// The one-time marks migration, exercised against production-SHAPED data.
//
// This migration runs once per existing account on the first open after the
// update, against documents written by several features across several app
// versions. It cannot be rehearsed on other people's accounts, so what it
// gets instead is the nastiest input this file can invent: legacy values,
// every state, malformed documents, unknown strings, and two years of volume.
//
// The property that matters most is the ROUND TRIP. Aggregating daily docs,
// storing them the way the mirror stores them, and reading them back must
// return exactly what was aggregated. That composition IS the migration.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/milestones/notifiers/habit_history_notifier.dart';
import 'package:grow_daily_v2/features/milestones/reports/habit_day_marks.dart';

void main() {
  /// Aggregate, store, read back. Exactly what the migration does to an
  /// account, minus Firestore.
  Map<String, Map<String, SquareState>> roundTrip(
    Map<String, Map<String, dynamic>> dailyDocs,
  ) {
    final aggregated = aggregateHabitHistory(dailyDocs);
    final stored = {
      for (final habit in aggregated.entries)
        habit.key: {
          for (final day in habit.value.entries)
            day.key: markToStored(day.value),
        },
    };
    return {
      for (final habit in stored.entries)
        habit.key: {
          for (final day in habit.value.entries)
            day.key: markFromStored(day.value),
        },
    };
  }

  group('round trip through the mirror format', () {
    test('every state survives being written and read back', () {
      final docs = <String, Map<String, dynamic>>{
        '2026-08-01': {
          'squareStates': {'a': 'complete'},
        },
        '2026-08-02': {
          'squareStates': {'a': 'bonus'},
        },
        '2026-08-03': {
          'squareStates': {'a': 'partial'},
        },
        '2026-08-04': {
          'squareStates': {'a': 'failed'},
        },
        '2026-08-05': {
          'squareStates': {'a': 'skipped'},
        },
      };
      expect(roundTrip(docs)['a'], {
        '2026-08-01': SquareState.complete,
        '2026-08-02': SquareState.bonus,
        '2026-08-03': SquareState.partial,
        '2026-08-04': SquareState.failed,
        '2026-08-05': SquareState.skipped,
      });
    });

    test('a completion-only day round-trips as complete', () {
      // The shape every pre-Grid habit has: finished from Today, no square.
      final docs = {
        '2026-08-01': {
          'habitCompletions': {'a': 3},
        },
      };
      expect(roundTrip(docs)['a'], {'2026-08-01': SquareState.complete});
    });

    test('two years of mixed history survives intact', () {
      // Volume, and the fact that nothing is lost across it. 730 days, six
      // habits, cycling through every state.
      final states = SquareState.values;
      final docs = <String, Map<String, dynamic>>{};
      var expectedMarks = 0;
      for (var i = 0; i < 730; i++) {
        final day = DateTime(2025, 1, 1 + i);
        final key = '${day.year.toString().padLeft(4, '0')}-'
            '${day.month.toString().padLeft(2, '0')}-'
            '${day.day.toString().padLeft(2, '0')}';
        final squares = <String, dynamic>{};
        for (var h = 0; h < 6; h++) {
          final state = states[(i + h) % states.length];
          squares['h$h'] = state.toJson();
          if (state != SquareState.none) expectedMarks++;
        }
        docs[key] = {'squareStates': squares};
      }
      final out = roundTrip(docs);
      final total = out.values.fold<int>(0, (n, m) => n + m.length);
      expect(total, expectedMarks);
      // And none of it degraded into a state nobody recorded.
      expect(
        out.values.expand((m) => m.values).every((s) => s != SquareState.none),
        isTrue,
      );
    });
  });

  group('survives documents it did not expect', () {
    test('a malformed day costs that day, not the account', () {
      // The migration reads documents written across several app versions.
      // One bad shape must not abort the other nine hundred.
      final docs = <String, Map<String, dynamic>>{
        '2026-08-01': {
          'squareStates': {'a': 'complete'},
        },
        // Wrong types entirely.
        '2026-08-02': {'squareStates': 'not a map', 'habitCompletions': 42},
        '2026-08-03': {
          'squareStates': ['a', 'b'],
        },
        '2026-08-04': {
          'squareStates': {'a': 'skipped'},
        },
      };
      final out = aggregateHabitHistory(docs);
      expect(out['a'], {
        '2026-08-01': SquareState.complete,
        '2026-08-04': SquareState.skipped,
      });
    });

    test('an unknown state string degrades to nothing recorded', () {
      // A value written by a future version, or a hand edit. It must not
      // throw and must not invent a state.
      final out = aggregateHabitHistory({
        '2026-08-01': {
          'squareStates': {'a': 'teleported'},
        },
      });
      expect(out.containsKey('a'), isFalse);
    });

    test('missing and empty fields are simply nothing', () {
      expect(aggregateHabitHistory({'2026-08-01': <String, dynamic>{}}), isEmpty);
      expect(
        aggregateHabitHistory({
          '2026-08-01': {'squareStates': <String, dynamic>{}},
        }),
        isEmpty,
      );
      expect(
        aggregateHabitHistory({
          '2026-08-01': {'habitCompletions': <String, dynamic>{}},
        }),
        isEmpty,
      );
    });

    test('a null value inside squareStates is not a crash', () {
      final out = aggregateHabitHistory({
        '2026-08-01': {
          'squareStates': {'a': null, 'b': 'complete'},
        },
      });
      expect(out.containsKey('a'), isFalse);
      expect(out['b'], {'2026-08-01': SquareState.complete});
    });
  });

  group('the legacy account', () {
    test('a mirror holding only 1s still reads as a full green history', () {
      // Every account backfilled before marks existed looks exactly like
      // this. If these come back as none, that account opens the reports and
      // sees its entire life erased, which is the single worst outcome of
      // this change.
      final legacy = {
        '2026-08-01': 1,
        '2026-08-02': 1,
        '2026-08-03': 1,
      };
      final read = {
        for (final entry in legacy.entries)
          entry.key: markFromStored(entry.value),
      };
      expect(read.values.every((m) => m == SquareState.complete), isTrue);
    });

    test('legacy and new values coexist in one habit document', () {
      // What a migrated account actually holds: old days written as 1 by the
      // previous backfill, new days written as state names. A merge write
      // never removes the old keys, so both shapes live side by side forever.
      final mixed = <String, Object>{
        '2026-07-01': 1,
        '2026-08-01': 'skipped',
        '2026-08-02': 'complete',
      };
      final read = {
        for (final entry in mixed.entries)
          entry.key: markFromStored(entry.value),
      };
      expect(read, {
        '2026-07-01': SquareState.complete,
        '2026-08-01': SquareState.skipped,
        '2026-08-02': SquareState.complete,
      });
    });
  });
}
