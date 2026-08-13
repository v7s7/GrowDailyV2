// Pure-logic tests for RoomsController.leaveRoom's leadership-handoff
// helper - see nextLeaderAfter's own doc comment for why this is a plain
// top-level function rather than a RoomsController method: it needs no
// Firestore to test, unlike leaveRoom/deleteRoom themselves (which this
// codebase doesn't attempt to unit test directly - same reasoning as
// PrayerTimesService.calculate's live half not being unit tested, only
// its pure building blocks).
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
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

  // Pure-logic tests for RoomsHubScreen's "starred rooms float to the top"
  // ordering - see sortStarredFirst's doc comment for why this is a stable
  // partition (each group keeps its original relative order) rather than a
  // full re-sort.
  group('sortStarredFirst', () {
    test('a starred room already at the bottom moves to the top', () {
      final result = sortStarredFirst(['a', 'b', 'c'], {'c'});
      expect(result, ['c', 'a', 'b']);
    });

    test('multiple starred rooms keep their own relative order, up front', () {
      final result = sortStarredFirst(['a', 'b', 'c', 'd'], {'d', 'b'});
      expect(result, ['b', 'd', 'a', 'c']);
    });

    test('the unstarred remainder also keeps its own relative order', () {
      final result = sortStarredFirst(['a', 'b', 'c', 'd', 'e'], {'e'});
      expect(result, ['e', 'a', 'b', 'c', 'd']);
    });

    test('no starred rooms at all leaves the original order untouched', () {
      final result = sortStarredFirst(['a', 'b', 'c'], {});
      expect(result, ['a', 'b', 'c']);
    });

    test('every room starred also leaves the original order untouched', () {
      final result = sortStarredFirst(['a', 'b', 'c'], {'a', 'b', 'c'});
      expect(result, ['a', 'b', 'c']);
    });

    test('an empty room list returns empty, even with a non-empty starred set',
        () {
      expect(sortStarredFirst(const [], {'a'}), isEmpty);
    });

    test(
        'a starred code that is not actually in the room list is simply '
        'ignored, not inserted - e.g. a room left after being starred, '
        'whose stale starredRoomCodes entry has not been cleaned up yet', () {
      final result = sortStarredFirst(['a', 'b'], {'z'});
      expect(result, ['a', 'b']);
    });

    test('a single-room list with that room starred is unaffected', () {
      expect(sortStarredFirst(['a'], {'a'}), ['a']);
    });
  });

  // Pure-logic tests for syncLinkedHabitsProgress's flexible weekly-quota
  // helper - see weeklyHabitCreditFor's own doc comment for why a "sport,
  // 4x/week" habit done 5 times while skipping 2 other days is a perfect
  // week, not 2 misses.
  group('weeklyHabitCreditFor', () {
    test(
        'meeting the target exactly, week already closed, credits - the '
        'reported bug: 4x/week target, done 5 times, 2 days skipped, week '
        'over', () {
      final result = weeklyHabitCreditFor(
        completions: 5,
        target: 4,
        isWeekClosed: true,
      );
      expect(result, WeeklyHabitCredit.credited);
    });

    test(
        'exceeding the target, week closed, still just credits (no bonus '
        'state for going over)', () {
      final result = weeklyHabitCreditFor(
        completions: 7,
        target: 4,
        isWeekClosed: true,
      );
      expect(result, WeeklyHabitCredit.credited);
    });

    test('falling short with the week closed - a genuine miss', () {
      final result = weeklyHabitCreditFor(
        completions: 2,
        target: 4,
        isWeekClosed: true,
      );
      expect(result, WeeklyHabitCredit.missed);
    });

    test(
        'falling short but the week is still open - too soon to call it a '
        'miss, so it reads as pending instead', () {
      final result = weeklyHabitCreditFor(
        completions: 2,
        target: 4,
        isWeekClosed: false,
      );
      expect(result, WeeklyHabitCredit.pending);
    });

    test(
        'hitting the target early, before the week is even over, credits '
        'immediately rather than waiting for the week to close', () {
      final result = weeklyHabitCreditFor(
        completions: 4,
        target: 4,
        isWeekClosed: false,
      );
      expect(result, WeeklyHabitCredit.credited);
    });

    test('zero completions with the week still open is pending, not missed',
        () {
      final result = weeklyHabitCreditFor(
        completions: 0,
        target: 4,
        isWeekClosed: false,
      );
      expect(result, WeeklyHabitCredit.pending);
    });

    test('zero completions with the week closed is a clear miss', () {
      final result = weeklyHabitCreditFor(
        completions: 0,
        target: 4,
        isWeekClosed: true,
      );
      expect(result, WeeklyHabitCredit.missed);
    });

    test(
        'a target of 1 (habit set to once a week) behaves the same as any '
        'other target', () {
      expect(
        weeklyHabitCreditFor(completions: 1, target: 1, isWeekClosed: false),
        WeeklyHabitCredit.credited,
      );
      expect(
        weeklyHabitCreditFor(completions: 0, target: 1, isWeekClosed: true),
        WeeklyHabitCredit.missed,
      );
    });
  });

  // Effective-dated rule lookup - the mechanism that stops editing a habit
  // from re-scoring finished days (see RoomParticipant.habitRules).
  group('roomRuleAt', () {
    RoomHabitRule rule(String from, int target) => RoomHabitRule(
          from: from,
          frequencyType: HabitFrequencyType.weekly,
          frequencyTarget: target,
        );

    test('a single rule applies to every day, before and after its own start',
        () {
      final rules = [rule('2026-07-06', 4)];
      expect(roomRuleAt(rules, '2026-07-01').frequencyTarget, 4);
      expect(roomRuleAt(rules, '2026-07-06').frequencyTarget, 4);
      expect(roomRuleAt(rules, '2026-12-31').frequencyTarget, 4);
    });

    test(
        'the reported scenario: a day before the change keeps the OLD target, '
        'a day on or after it gets the new one', () {
      final rules = [rule('2026-07-06', 4), rule('2026-07-20', 7)];
      expect(roomRuleAt(rules, '2026-07-19').frequencyTarget, 4,
          reason: 'finished history must not be re-scored');
      expect(roomRuleAt(rules, '2026-07-20').frequencyTarget, 7,
          reason: 'the new rule starts the day it says');
      expect(roomRuleAt(rules, '2026-07-21').frequencyTarget, 7);
    });

    test('a day before every recorded rule falls back to the earliest', () {
      final rules = [rule('2026-07-20', 7), rule('2026-07-06', 4)];
      expect(roomRuleAt(rules, '2026-01-01').frequencyTarget, 4);
    });

    test('unordered input is handled - latest applicable still wins', () {
      final rules = [
        rule('2026-07-20', 7),
        rule('2026-07-06', 4),
        rule('2026-07-13', 5)
      ];
      expect(roomRuleAt(rules, '2026-07-14').frequencyTarget, 5);
      expect(roomRuleAt(rules, '2026-07-25').frequencyTarget, 7);
    });

    test('three periods resolve to the right one at each boundary', () {
      final rules = [
        rule('2026-07-06', 4),
        rule('2026-07-13', 5),
        rule('2026-07-20', 7)
      ];
      expect(roomRuleAt(rules, '2026-07-12').frequencyTarget, 4);
      expect(roomRuleAt(rules, '2026-07-13').frequencyTarget, 5);
      expect(roomRuleAt(rules, '2026-07-19').frequencyTarget, 5);
      expect(roomRuleAt(rules, '2026-07-20').frequencyTarget, 7);
    });
  });

  group('RoomHabitRule.differsFrom', () {
    test('identical settings do not differ, so no warning is raised', () {
      const r = RoomHabitRule(
        from: '2026-07-06',
        frequencyType: HabitFrequencyType.weekly,
        frequencyTarget: 4,
        scheduledWeekdays: [1, 3, 5],
      );
      expect(
        r.differsFrom(
          frequencyType: HabitFrequencyType.weekly,
          frequencyTarget: 4,
          scheduledWeekdays: [5, 3, 1], // order must not matter
        ),
        isFalse,
      );
    });

    test('a changed target differs - the reported 4x to 7x edit', () {
      const r = RoomHabitRule(
        from: '2026-07-06',
        frequencyType: HabitFrequencyType.weekly,
        frequencyTarget: 4,
      );
      expect(
        r.differsFrom(
          frequencyType: HabitFrequencyType.weekly,
          frequencyTarget: 7,
          scheduledWeekdays: const [],
        ),
        isTrue,
      );
    });

    test('a changed cadence type differs', () {
      const r = RoomHabitRule(
        from: '2026-07-06',
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
      );
      expect(
        r.differsFrom(
          frequencyType: HabitFrequencyType.weekly,
          frequencyTarget: 1,
          scheduledWeekdays: const [],
        ),
        isTrue,
      );
    });

    test('changed weekdays differ, including adding or dropping one', () {
      const r = RoomHabitRule(
        from: '2026-07-06',
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
        scheduledWeekdays: [1, 3, 5],
      );
      expect(
        r.differsFrom(
          frequencyType: HabitFrequencyType.daily,
          frequencyTarget: 1,
          scheduledWeekdays: const [1, 3],
        ),
        isTrue,
      );
      expect(
        r.differsFrom(
          frequencyType: HabitFrequencyType.daily,
          frequencyTarget: 1,
          scheduledWeekdays: const [],
        ),
        isTrue,
      );
    });
  });
}
