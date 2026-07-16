// Pure-logic tests for RoomsController.leaveRoom's leadership-handoff
// helper - see nextLeaderAfter's own doc comment for why this is a plain
// top-level function rather than a RoomsController method: it needs no
// Firestore to test, unlike leaveRoom/deleteRoom themselves (which this
// codebase doesn't attempt to unit test directly - same reasoning as
// PrayerTimesService.calculate's live half not being unit tested, only
// its pure building blocks).
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';

RoomParticipant _p(String uid, DateTime joinedAt) => RoomParticipant(
      uid: uid,
      displayName: uid,
      characterId: 'male_ghutra_blue',
      joinedAt: joinedAt,
      lastUpdated: joinedAt,
    );

void main() {
  group('nextLeaderAfter', () {
    test(
        'picks the longest-standing remaining participant, not just '
        'whichever happens to be first in the list', () {
      final roster = [
        _p('leader', DateTime(2026, 1, 1)),
        _p('second', DateTime(2026, 1, 5)),
        _p('third', DateTime(2026, 1, 10)),
      ];
      final successor = nextLeaderAfter('leader', roster);
      expect(successor?.uid, 'second');
    });

    test('the leaving uid does not have to be first in the given list', () {
      // Deliberately NOT pre-sorted here, unlike RoomsController.leaveRoom's
      // real Firestore query (which always orders by joinedAt) - this
      // documents that nextLeaderAfter itself does no sorting of its own,
      // it just returns the first non-matching entry in whatever order
      // it's handed. So this test also doubles as a guard: if that
      // ordering contract ever gets dropped from the real query, this
      // function's behavior won't quietly compensate for it.
      final roster = [
        _p('second', DateTime(2026, 1, 5)),
        _p('leader', DateTime(2026, 1, 1)),
        _p('third', DateTime(2026, 1, 10)),
      ];
      final successor = nextLeaderAfter('leader', roster);
      expect(successor?.uid, 'second');
    });

    test(
        'a lone leader with no other participants returns null - the '
        'signal RoomsController.leaveRoom uses to delete the room instead '
        'of handing off to no one', () {
      final roster = [_p('leader', DateTime(2026, 1, 1))];
      expect(nextLeaderAfter('leader', roster), isNull);
    });

    test('an empty roster also returns null', () {
      expect(nextLeaderAfter('leader', const []), isNull);
    });

    test(
        'a non-leader uid that happens to not be in the roster at all '
        'still just returns the first entry, same as if it were absent '
        'for any other reason', () {
      final roster = [
        _p('second', DateTime(2026, 1, 5)),
        _p('third', DateTime(2026, 1, 10)),
      ];
      final successor = nextLeaderAfter('someone-else', roster);
      expect(successor?.uid, 'second');
    });
  });

  // Pure-logic tests for RoomsController.unlinkHabitEverywhere's own
  // index-matching helper - see removeLinkedHabit's doc comment for why a
  // deleted habit needs to come out of both parallel arrays at the same
  // index, not just linkedHabitIds alone.
  group('removeLinkedHabit', () {
    test('removes the id and its same-index name together', () {
      final (ids, names) = removeLinkedHabit(
        ['a', 'b', 'c'],
        ['Fajr', 'Quran', 'Dhikr'],
        'b',
      );
      expect(ids, ['a', 'c']);
      expect(names, ['Fajr', 'Dhikr']);
    });

    test('removing the first entry shifts the rest down correctly', () {
      final (ids, names) = removeLinkedHabit(
        ['a', 'b', 'c'],
        ['Fajr', 'Quran', 'Dhikr'],
        'a',
      );
      expect(ids, ['b', 'c']);
      expect(names, ['Quran', 'Dhikr']);
    });

    test('removing the only entry leaves both arrays empty', () {
      final (ids, names) = removeLinkedHabit(['a'], ['Fajr'], 'a');
      expect(ids, isEmpty);
      expect(names, isEmpty);
    });

    test('an id that is not present is a no-op on both arrays', () {
      final (ids, names) = removeLinkedHabit(
        ['a', 'b'],
        ['Fajr', 'Quran'],
        'does-not-exist',
      );
      expect(ids, ['a', 'b']);
      expect(names, ['Fajr', 'Quran']);
    });

    test('an empty ids list is a no-op, never throws', () {
      final (ids, names) = removeLinkedHabit(const [], const [], 'a');
      expect(ids, isEmpty);
      expect(names, isEmpty);
    });

    test(
        'a names list already shorter than ids (a legacy out-of-sync doc) '
        'is left untouched instead of throwing a RangeError', () {
      final (ids, names) = removeLinkedHabit(
        ['a', 'b'],
        ['Fajr'], // no entry for 'b' at all
        'b',
      );
      expect(ids, ['a']);
      expect(names, ['Fajr']); // unchanged - nothing at index 1 to remove
    });
  });
}
