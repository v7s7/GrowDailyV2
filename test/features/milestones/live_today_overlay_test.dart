// The live-today overlay, and the guard that stops it destroying data.
//
// The mirror is a cache of the daily documents, written by three writers, one
// fire-and-forget. For settled days it is authoritative; for today it can lag
// or miss a write, and the reports then contradict the Grid about a day the
// user is looking at on both screens. withLiveToday resolves today from the
// same two records the mirror is built from.
//
// THE GUARD IS THE DANGEROUS PART. WeeklyGridState.squareFor returns none for
// any day outside the week it has loaded, and paging the Grid back a week
// clears its states entirely. Without gridKnowsToday, browsing to last week
// and opening the reports would DELETE today's تخطّي, جزئي and فشل, because
// "the Grid says none" is indistinguishable from "the Grid has not loaded
// today". A habit with a completion behind it would survive, which is exactly
// why the bug would be invisible on the habits anyone tests with.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/milestones/reports/habit_day_marks.dart';

const _today = '2026-08-20';
const _yesterday = '2026-08-19';

Map<String, Map<String, SquareState>> run({
  Map<String, Map<String, SquareState>> mirrored = const {},
  Map<String, SquareState> squares = const {},
  Map<String, int> completions = const {},
  bool gridKnowsToday = true,
  List<String> habits = const ['a'],
  Map<String, int> targets = const {},
}) =>
    withLiveToday(
      mirrored: mirrored,
      habitIds: habits,
      squareToday: (id) => squares[id] ?? SquareState.none,
      completionsToday: (id) => completions[id] ?? 0,
      dailyTargetOf: (id) => targets[id] ?? 1,
      todayKey: _today,
      gridKnowsToday: gridKnowsToday,
    );

void main() {
  group('today follows live state', () {
    test('a completion the mirror never received still shows', () {
      // The observed bug: two habits completed today were absent from the
      // mirror entirely, so the report listed them as مطلوب.
      final out = run(completions: {'a': 1});
      expect(out['a']?[_today], SquareState.complete);
    });

    test('a completion the mirror still holds after an undo is cleared', () {
      // The other direction: complete then undo left a stale mirror entry,
      // so the report kept saying مكتمل after the Grid, XP and the day
      // percentage had all correctly returned.
      final out = run(
        mirrored: {
          'a': {_today: SquareState.complete},
        },
      );
      expect(out['a']?.containsKey(_today), isFalse);
    });

    test('a green square wins over a completion count', () {
      // dayMark's precedence: bonus keeps its flavour rather than being
      // flattened to complete.
      final out = run(
        squares: {'a': SquareState.bonus},
        completions: {'a': 1},
      );
      expect(out['a']?[_today], SquareState.bonus);
    });

    test('a completion outranks a non-green square', () {
      final out = run(
        squares: {'a': SquareState.skipped},
        completions: {'a': 1},
      );
      expect(out['a']?[_today], SquareState.complete);
    });

    test('a rest with nothing behind it stays a rest', () {
      final out = run(squares: {'a': SquareState.skipped});
      expect(out['a']?[_today], SquareState.skipped);
    });
  });

  group('THE GUARD: a Grid that cannot speak never deletes', () {
    test('a rest survives when the Grid is on another week', () {
      // squareFor returns none for a day outside the loaded week. Treating
      // that as a clearance would erase a real تخطّي.
      final out = run(
        mirrored: {
          'a': {_today: SquareState.skipped},
        },
        gridKnowsToday: false,
      );
      expect(out['a']?[_today], SquareState.skipped);
    });

    test('every non-green state survives an unloaded Grid', () {
      for (final state in [
        SquareState.skipped,
        SquareState.failed,
        SquareState.partial,
      ]) {
        final out = run(
          mirrored: {
            'a': {_today: state},
          },
          gridKnowsToday: false,
        );
        expect(out['a']?[_today], state, reason: '$state was erased');
      }
    });

    test('an assertion still applies while the Grid is unloaded', () {
      // Adding what we positively know is always safe; only removal needs
      // the Grid to be able to speak.
      final out = run(completions: {'a': 1}, gridKnowsToday: false);
      expect(out['a']?[_today], SquareState.complete);
    });

    test('with the Grid loaded, a genuine clear does clear', () {
      final out = run(
        mirrored: {
          'a': {_today: SquareState.skipped},
        },
      );
      expect(out['a']?.containsKey(_today), isFalse);
    });
  });

  group('it never touches a settled day', () {
    test('yesterday is left exactly as the mirror had it', () {
      final out = run(
        mirrored: {
          'a': {_yesterday: SquareState.partial, _today: SquareState.complete},
        },
        completions: {'a': 1},
      );
      expect(out['a']?[_yesterday], SquareState.partial);
    });

    test('a habit not in the list is untouched', () {
      final out = run(
        mirrored: {
          'b': {_today: SquareState.complete},
        },
        habits: ['a'],
      );
      expect(out['b']?[_today], SquareState.complete);
    });

    test('the input map is not mutated', () {
      final mirrored = {
        'a': {_today: SquareState.complete},
      };
      run(mirrored: mirrored);
      expect(mirrored['a']?[_today], SquareState.complete);
    });
  });

  group('a habit counted several times a day', () {
    // The bug: the overlay read any positive count as a finished day, so a
    // habit set to four times a day was reported DONE on tap one — while the
    // Grid, correctly, still showed a part-filled square. The reports and the
    // board contradicted each other about a day the user can see on both.
    test('one of four is part done, not done', () {
      final out = run(
        completions: {'a': 1},
        targets: {'a': 4},
      );
      expect(out['a']?[_today], SquareState.partial,
          reason: '1 of 4 must not be reported as a completed day');
    });

    test('three of four is still not done', () {
      final out = run(completions: {'a': 3}, targets: {'a': 4});
      expect(out['a']?[_today], SquareState.partial);
    });

    test('four of four is done', () {
      final out = run(completions: {'a': 4}, targets: {'a': 4});
      expect(out['a']?[_today], SquareState.complete);
    });

    test('past the target is still done, never something stranger', () {
      final out = run(completions: {'a': 9}, targets: {'a': 4});
      expect(out['a']?[_today], SquareState.complete);
    });

    test('nothing done today leaves the square to speak for itself', () {
      final out = run(
        completions: {'a': 0},
        targets: {'a': 4},
        squares: {'a': SquareState.skipped},
      );
      expect(out['a']?[_today], SquareState.skipped,
          reason: 'a deliberate rest must survive a habit merely being counted');
    });

    test('a green square still outranks the count', () {
      final out = run(
        completions: {'a': 1},
        targets: {'a': 4},
        squares: {'a': SquareState.bonus},
      );
      expect(out['a']?[_today], SquareState.bonus,
          reason: 'an explicit mark is a statement about the day and wins');
    });

    test('an ordinary once-a-day habit is completely unchanged', () {
      final out = run(completions: {'a': 1});
      expect(out['a']?[_today], SquareState.complete,
          reason: 'the default target of 1 must behave exactly as before');
    });
  });
}
