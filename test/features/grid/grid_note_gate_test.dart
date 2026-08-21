// Reading an old square's note on the Grid board.
//
// ── The narrow thing this gates, and the wide thing it must not ───────────
// Past WEEKS are free on the Grid, deliberately and on the record: _pickWeek
// says "the Grid has never gated past weeks ... a picker is not the place to
// introduce a paywall that did not exist a moment ago". None of that changes.
//
// What leaked is one sentence. Grid Journal paywalls notes older than
// kFreeHistoryMonths, and long-pressing the very same square on the board
// handed the same note over for free. Two screens, one Firestore field, two
// prices.
//
// ── Why "only when a note already exists" is a safety rule ────────────────
// The editor swaps its text field AND its Save button out together, and only
// when this returns true. That coupling is what makes withholding safe: a
// blanked field whose Save button still wrote through would erase the note it
// was meant to protect. Returning false for an empty note also keeps writing
// a fresh note on an old day open, because this is about reading what is
// stored, not about renting the keyboard.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';

void main() {
  final now = DateTime(2026, 8, 21); // free floor: 2026-06-01

  bool walled({
    String note = 'felt good today',
    required DateTime day,
    bool isPremium = false,
  }) =>
      WeeklyGridState.noteIsWalled(
        note: note,
        day: day,
        now: now,
        isPremium: isPremium,
      );

  group('noteIsWalled', () {
    test('a note inside the free window is readable', () {
      expect(walled(day: DateTime(2026, 8, 3)), isFalse);
      expect(walled(day: DateTime(2026, 7, 15)), isFalse);
      expect(walled(day: DateTime(2026, 6, 1)), isFalse,
          reason: 'the floor month itself is free');
    });

    test('a note behind the free window is withheld', () {
      expect(walled(day: DateTime(2026, 5, 31)), isTrue,
          reason: 'one day before the floor is already walled');
      expect(walled(day: DateTime(2026, 1, 4)), isTrue);
      expect(walled(day: DateTime(2025, 11, 20)), isTrue);
    });

    test('premium is never withheld', () {
      expect(walled(day: DateTime(2019, 1, 1), isPremium: true), isFalse);
    });

    // The safety property. Everything above is a paywall; this one is what
    // stops the paywall from eating data.
    test('an EMPTY note is never walled, however old the day', () {
      expect(walled(note: '', day: DateTime(2019, 1, 1)), isFalse,
          reason: 'the editor keeps its text field and Save button in this '
              'case, so writing a fresh note on an old day still works');
    });

    test('the walled window matches every other history surface', () {
      // Same predicate, so the Grid note and the Grid Journal can never
      // disagree about which months are readable.
      for (var back = 0; back < 8; back++) {
        final day = DateTime(2026, 8 - back, 15);
        final journalAllows = canBrowseHistoryMonth(
          monthStart: DateTime(day.year, day.month),
          now: now,
          isPremium: false,
        );
        expect(walled(day: day), !journalAllows,
            reason: 'month $back back: the board and the journal must agree');
      }
    });

    test('kFreeHistoryMonths is what defines the boundary', () {
      // Pinned so moving the constant moves this gate with it rather than
      // silently leaving the board more generous than the journal.
      final lastFree = DateTime(now.year, now.month - (kFreeHistoryMonths - 1));
      expect(walled(day: lastFree), isFalse);
      expect(walled(day: DateTime(lastFree.year, lastFree.month, 0)), isTrue,
          reason: 'day 0 of the floor month is the last day of the one before');
    });
  });
}
