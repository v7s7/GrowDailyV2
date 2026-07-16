// Pure-logic tests for the Habit Notes journal's inclusion rule - see
// isJournalWorthy's own doc comment for why a plain, note-less
// complete/partial/none square never qualifies while any of the three
// "advanced" palette states always does, note or not.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/grid_journal_notifier.dart';

void main() {
  group('isJournalWorthy', () {
    test('a note with real text qualifies regardless of state', () {
      expect(isJournalWorthy(SquareState.complete, 'Great day'), isTrue);
      expect(isJournalWorthy(SquareState.partial, 'Half effort'), isTrue);
      expect(isJournalWorthy(SquareState.none, 'Forgot entirely'), isTrue);
    });

    test('whitespace-only note does not count as real text', () {
      expect(isJournalWorthy(SquareState.complete, '   '), isFalse);
      expect(isJournalWorthy(SquareState.complete, ''), isFalse);
    });

    test('skipped/failed/bonus always qualify, even with an empty note', () {
      expect(isJournalWorthy(SquareState.skipped, ''), isTrue);
      expect(isJournalWorthy(SquareState.failed, ''), isTrue);
      expect(isJournalWorthy(SquareState.bonus, ''), isTrue);
    });

    test('plain complete/partial/none with no note never qualifies', () {
      expect(isJournalWorthy(SquareState.complete, ''), isFalse);
      expect(isJournalWorthy(SquareState.partial, ''), isFalse);
      expect(isJournalWorthy(SquareState.none, ''), isFalse);
    });
  });
}
