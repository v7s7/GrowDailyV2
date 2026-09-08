// The note index: the one document that knows which days carry writing.
//
// It exists because the fact is otherwise unanswerable. A note lives only as
// a map key inside a day document, Firestore cannot filter on map-key
// presence, and the monthly heatmap builds every month section eagerly, so
// reading ground truth per month would be dozens of range queries on every
// open.
//
// Everything here is pure. The index's whole safety argument is that it can
// only ever ROUTE (which cells get a corner mark, which month chips get a
// dot) and never assert, so the parts worth pinning are the fold, the diff,
// and above all the cache guard: reconciling removals against an offline
// snapshot would delete a year of true entries.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/grid/notifiers/note_index_notifier.dart';

void main() {
  group('dayStillHasWriting', () {
    test('a day keeps its mark while another habit still has a note', () {
      // The case that makes an exact answer necessary rather than a
      // heuristic: clearing one of two notes must not unmark the day.
      expect(
        dayStillHasWriting(
          {'fajr': '', 'quran': 'read two pages'},
          'fajr',
          '',
        ),
        isTrue,
      );
    });

    test('clearing the last note unmarks the day', () {
      expect(dayStillHasWriting({'fajr': ''}, 'fajr', ''), isFalse);
    });

    test('writing anything marks the day, whatever else is there', () {
      expect(dayStillHasWriting(const {}, 'fajr', 'felt good'), isTrue);
    });

    test('whitespace is not writing', () {
      expect(dayStillHasWriting({'fajr': '   '}, 'quran', '  \n '), isFalse);
    });

    test('a legacy tombstone on another habit does not hold the day', () {
      // Clearing a note used to store '' rather than deleting the key, so
      // every day anyone ever cleared a note on carries one of these
      // forever. Counting key presence instead of the value would mark them
      // all.
      expect(
        dayStillHasWriting({'fajr': '', 'quran': ''}, 'fajr', ''),
        isFalse,
      );
    });
  });

  group('noteMonthIndexFrom', () {
    test('folds written days into their months', () {
      final index = noteMonthIndexFrom({
        '2026-09-04': {
          'squareNotes': {'fajr': 'alhamdulillah'},
        },
        '2026-09-08': {
          'squareNotes': {'quran': 'two pages'},
        },
        '2026-08-19': {
          'squareNotes': {'gym': 'light session'},
        },
      });
      expect(index, {
        '2026-09': {4, 8},
        '2026-08': {19},
      });
    });

    test('two habits writing on one day yield one day entry', () {
      final index = noteMonthIndexFrom({
        '2026-09-04': {
          'squareNotes': {'fajr': 'a', 'quran': 'b'},
        },
      });
      expect(index['2026-09'], {4});
    });

    test('tombstones, whitespace and note-less days are excluded', () {
      final index = noteMonthIndexFrom({
        '2026-09-01': {
          'squareNotes': {'fajr': ''},
        },
        '2026-09-02': {
          'squareNotes': {'fajr': '   '},
        },
        '2026-09-03': {
          'squareStates': {'fajr': 'complete'},
        },
        '2026-09-05': <String, dynamic>{},
      });
      expect(index, isEmpty,
          reason: 'a day with no real writing must never be marked: the mark '
              'sends the user to a sheet that would show them nothing');
    });

    test('an empty account folds to an empty index', () {
      expect(noteMonthIndexFrom(const {}), isEmpty);
    });

    test('a malformed key cannot crash the fold', () {
      // This runs over a whole Firestore collection during the backfill, and
      // one hand-edited document must not take the index with it.
      final index = noteMonthIndexFrom({
        'garbage': {
          'squareNotes': {'fajr': 'x'},
        },
        '2026-09-04': {
          'squareNotes': {'fajr': 'x'},
        },
      });
      expect(index, {
        '2026-09': {4},
      });
    });
  });

  group('parseNoteIndex', () {
    test('reads the stored shape back', () {
      expect(
        parseNoteIndex({
          'months': {
            '2026-09': [4, 8, 14],
          },
        }),
        {
          '2026-09': {4, 8, 14},
        },
      );
    });

    test('a missing or empty document is an empty index, not an error', () {
      expect(parseNoteIndex(null), isEmpty);
      expect(parseNoteIndex(const {}), isEmpty);
      expect(parseNoteIndex({'months': const {}}), isEmpty);
    });

    test('a month emptied by arrayRemove drops out', () {
      // arrayRemove leaves the key behind with an empty list, and a month
      // with no days must not be reported as a month with writing.
      expect(parseNoteIndex({
        'months': {'2026-09': const []},
      }), isEmpty);
    });
  });

  group('diffNoteDays', () {
    test('nothing to do when the index already agrees', () {
      final diff = diffNoteDays(
        indexed: {4, 8},
        truth: {4, 8},
        trustRemovals: true,
      );
      expect(diff.isEmpty, isTrue,
          reason: 'the healers ride reads that were happening anyway, so the '
              'common case must write nothing at all');
    });

    test('adds what the index missed and removes what it invented', () {
      final diff = diffNoteDays(
        indexed: {4, 8},
        truth: {8, 14},
        trustRemovals: true,
      );
      expect(diff.add, [14]);
      expect(diff.remove, [4]);
    });

    // The one bug in this file that would destroy data.
    test('an offline read never removes anything', () {
      // Nothing in the app configures Firestore Settings, so persistence is
      // on and an offline month resolves happily with every document
      // missing. Reconciling deletes against that would erase a year of true
      // entries.
      final diff = diffNoteDays(
        indexed: {1, 2, 3, 4, 5},
        truth: const {},
        trustRemovals: false,
      );
      expect(diff.remove, isEmpty);
      expect(diff.add, isEmpty);
    });

    test('an offline read may still add what it did see', () {
      // Additions are safe in both directions: a cached day that really does
      // carry writing is still true.
      final diff = diffNoteDays(
        indexed: const {},
        truth: {9},
        trustRemovals: false,
      );
      expect(diff.add, [9]);
      expect(diff.remove, isEmpty);
    });
  });

  group('monthKeyOf', () {
    test('a dateKey maps to its month', () {
      expect(monthKeyOf('2026-09-08'), '2026-09');
      expect(monthKeyOf('2025-12-31'), '2025-12');
    });

    test('agrees with what the fold produces', () {
      // Pinned against each other so the writer, the healer and the reader
      // can never key the same month two ways.
      final index = noteMonthIndexFrom({
        '2026-01-07': {
          'squareNotes': {'fajr': 'x'},
        },
      });
      expect(index.keys.single, monthKeyOf('2026-01-07'));
    });
  });
}
