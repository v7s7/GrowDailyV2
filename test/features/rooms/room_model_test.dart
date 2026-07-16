// Deterministic test cases for the Rooms credit/scheduling math - written
// after a real user report: a non-daily habit (specific weekday schedule)
// was showing as "missed" in its Room on a day it was never even supposed
// to happen, because RoomParticipant.creditFor/isFullyDone used to divide
// by the plain count of linked habits with no awareness of which of them
// were actually scheduled that day. See RoomParticipant.dailyScheduledCount
// and RoomsController.syncLinkedHabitsProgress's doc comments for the fix.
//
// These are pure model tests - no Firestore, no widgets, no `DateTime.now()`
// dependency (every "today" here is a fixed, hand-picked calendar date, and
// every room below uses a fixed RoomDuration.fixed endDate safely in the
// past so RoomModel.lastCountedDay/daysElapsed never depend on whenever
// this test actually happens to run).
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';

/// A plain "every day" habit template - the default, unrestricted case.
IslamicHabitTemplate _dailyHabit({String id = 'h1'}) => IslamicHabitTemplate(
      id: id,
      name: 'Quran page',
      description: '',
      category: HabitCategory.faith,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 10,
      goldReward: 5,
    );

/// A Mon/Wed-only habit template, matching this bug report exactly - a
/// habit that only needs doing on specific weekdays, not every day.
IslamicHabitTemplate _monWedHabit({String id = 'h1'}) => IslamicHabitTemplate(
      id: id,
      name: 'Quran page',
      description: '',
      category: HabitCategory.faith,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      scheduledWeekdays: const [DateTime.monday, DateTime.wednesday],
      hasTimer: false,
      xpReward: 10,
      goldReward: 5,
    );

RoomModel _fixedRoom({
  required DateTime start,
  required DateTime end,
}) =>
    RoomModel(
      code: 'TEST01',
      name: 'Test Room',
      createdBy: 'leader-uid',
      createdByName: 'Leader',
      createdAt: start,
      habitMode: RoomHabitMode.own,
      duration: RoomDuration.fixed,
      startDate: start,
      endDate: end,
    );

RoomParticipant _participant({
  List<String> linkedHabitIds = const ['h1'],
  Map<String, int> dailyDoneCount = const {},
  Map<String, int> dailyScheduledCount = const {},
}) =>
    RoomParticipant(
      uid: 'member-uid',
      displayName: 'Member',
      characterId: 'male_ghutra_blue',
      joinedAt: DateTime(2026, 7, 6),
      linkedHabitIds: linkedHabitIds,
      dailyDoneCount: dailyDoneCount,
      dailyScheduledCount: dailyScheduledCount,
      lastUpdated: DateTime(2026, 7, 6),
    );

void main() {
  group('IslamicHabitTemplate.isScheduledFor', () {
    test('empty scheduledWeekdays means every day', () {
      final daily = _dailyHabit();
      final monday = DateTime(2026, 7, 6);
      final sunday = DateTime(2026, 7, 12);
      expect(daily.isScheduledFor(monday), isTrue);
      expect(daily.isScheduledFor(sunday), isTrue);
    });

    test('non-empty scheduledWeekdays restricts to those weekdays', () {
      final habit = _monWedHabit();
      final monday = DateTime(2026, 7, 6);
      final tuesday = DateTime(2026, 7, 7);
      final wednesday = DateTime(2026, 7, 8);
      final sunday = DateTime(2026, 7, 12);
      expect(habit.isScheduledFor(monday), isTrue);
      expect(habit.isScheduledFor(tuesday), isFalse);
      expect(habit.isScheduledFor(wednesday), isTrue);
      expect(habit.isScheduledFor(sunday), isFalse);
    });
  });

  group('RoomParticipant.scheduledCountFor', () {
    test('falls back to linkedHabitIds.length when no override recorded', () {
      final p = _participant(linkedHabitIds: const ['h1', 'h2']);
      expect(p.scheduledCountFor('2026-07-07'), 2);
    });

    test('uses the recorded override when present, even if 0', () {
      final p = _participant(
        linkedHabitIds: const ['h1', 'h2'],
        dailyScheduledCount: const {'2026-07-07': 1},
      );
      expect(p.scheduledCountFor('2026-07-07'), 1);
      // A different, unrecorded date still falls back to the full count.
      expect(p.scheduledCountFor('2026-07-06'), 2);
    });
  });

  group('RoomParticipant.creditFor / isFullyDone - single linked habit', () {
    test('no linked habits at all -> zero credit, never "fully done"', () {
      final p = _participant(linkedHabitIds: const []);
      expect(p.creditFor('2026-07-06'), 0.0);
      expect(p.isFullyDone('2026-07-06'), isFalse);
    });

    test('done on a normally-scheduled day -> full credit', () {
      final p = _participant(dailyDoneCount: const {'2026-07-06': 1});
      expect(p.creditFor('2026-07-06'), 1.0);
      expect(p.isFullyDone('2026-07-06'), isTrue);
    });

    test('not done on a normally-scheduled day -> zero credit', () {
      final p = _participant();
      expect(p.creditFor('2026-07-06'), 0.0);
      expect(p.isFullyDone('2026-07-06'), isFalse);
    });

    test(
        'THE BUG: a day the only linked habit is not scheduled is excused, '
        'not a miss', () {
      // linkedHabitIds.length is 1, but dailyScheduledCount says 0 were
      // actually due this day (e.g. a Mon/Wed-only habit on a Tuesday).
      final p = _participant(
        dailyScheduledCount: const {'2026-07-07': 0},
      );
      expect(p.creditFor('2026-07-07'), 1.0,
          reason: 'nothing was required, so there is nothing to fall short of');
      expect(p.isFullyDone('2026-07-07'), isTrue);
    });
  });

  group('RoomParticipant.creditFor / isFullyDone - multiple linked habits', () {
    test('2 linked, both scheduled, only 1 done -> half credit, not full', () {
      final p = _participant(
        linkedHabitIds: const ['h1', 'h2'],
        dailyDoneCount: const {'2026-07-06': 1},
      );
      expect(p.creditFor('2026-07-06'), 0.5);
      expect(p.isFullyDone('2026-07-06'), isFalse);
    });

    test(
        '2 linked, 1 excused today, the other done -> full credit '
        '(excused habit does not stay in the denominator)', () {
      final p = _participant(
        linkedHabitIds: const ['h1', 'h2'],
        dailyDoneCount: const {'2026-07-07': 1},
        dailyScheduledCount: const {'2026-07-07': 1},
      );
      expect(p.creditFor('2026-07-07'), 1.0);
      expect(p.isFullyDone('2026-07-07'), isTrue);
    });

    test(
        '2 linked, 1 excused today, the SCHEDULED one missed -> zero credit '
        '(an excused sibling must never mask a real miss)', () {
      final p = _participant(
        linkedHabitIds: const ['h1', 'h2'],
        dailyDoneCount: const {}, // nothing done
        dailyScheduledCount: const {'2026-07-07': 1},
      );
      expect(p.creditFor('2026-07-07'), 0.0);
      expect(p.isFullyDone('2026-07-07'), isFalse);
    });
  });

  group('RoomModel.daysElapsed / lastCountedDay (fixed, past end date)', () {
    test('spans start date through end date inclusive', () {
      final room = _fixedRoom(
        start: DateTime(2026, 7, 6), // Monday
        end: DateTime(2026, 7, 8), // Wednesday
      );
      expect(room.lastCountedDay, DateTime(2026, 7, 8));
      expect(room.daysElapsed, 3); // Mon, Tue, Wed
    });
  });

  group('RoomParticipant.daysCompleted / progressRatio - end to end', () {
    test(
        'Mon/Wed-only habit: done Monday, excused Tuesday, missed Wednesday '
        '-> 2 of 3 days, not 1 of 3', () {
      final room = _fixedRoom(
        start: DateTime(2026, 7, 6), // Monday
        end: DateTime(2026, 7, 8), // Wednesday
      );
      // This is exactly what RoomsController.syncLinkedHabitsProgress would
      // write for a Mon/Wed-only habit that was done Monday and missed
      // Wednesday: Tuesday gets a dailyScheduledCount override of 0 (and no
      // dailyDoneCount entry, since nothing was even checked), Monday and
      // Wednesday get no dailyScheduledCount entry at all (both fully
      // scheduled as normal, the sparse-storage default).
      final p = _participant(
        dailyDoneCount: const {'2026-07-06': 1}, // Monday done
        dailyScheduledCount: const {'2026-07-07': 0}, // Tuesday excused
      );

      expect(p.creditFor('2026-07-06'), 1.0, reason: 'Monday: done');
      expect(p.creditFor('2026-07-07'), 1.0, reason: 'Tuesday: excused');
      expect(p.creditFor('2026-07-08'), 0.0, reason: 'Wednesday: missed');

      expect(p.daysCompleted(room), 2.0);
      expect(p.progressRatio(room), closeTo(2 / 3, 0.0001));

      // Before the fix, Tuesday would have used linkedHabitIds.length (1)
      // as the denominator with 0 done, contributing 0.0 instead of 1.0 -
      // daysCompleted would have been 1.0/3 (~0.33) instead of the correct
      // 2.0/3 (~0.67). Asserting the old, wrong number is explicitly NOT
      // what this test expects, on purpose.
      expect(p.progressRatio(room), isNot(closeTo(1 / 3, 0.0001)));
    });
  });

  group('RoomParticipant.currentStreak - ended room (fixed calendar dates)',
      () {
    // These all use a room whose end date is safely in the past (see the
    // file header) so RoomModel.isEnded is always true and
    // RoomModel.lastCountedDay is the fixed endDate below, never dependent
    // on whenever this test actually runs.

    test('no linked habits -> 0, even with done days recorded', () {
      final room = _fixedRoom(start: DateTime(2026, 7, 6), end: DateTime(2026, 7, 8));
      final p = _participant(
        linkedHabitIds: const [],
        dailyDoneCount: const {
          '2026-07-06': 1,
          '2026-07-07': 1,
          '2026-07-08': 1,
        },
      );
      expect(p.currentStreak(room), 0);
    });

    test('final day of the room missed -> 0, nothing carries past it', () {
      final room = _fixedRoom(start: DateTime(2026, 7, 6), end: DateTime(2026, 7, 8));
      final p = _participant(
        dailyDoneCount: const {'2026-07-06': 1, '2026-07-07': 1}, // Jul 8 missed
      );
      expect(p.currentStreak(room), 0,
          reason: 'the room is over and it ended on a miss - not "3 days ago '
              'they had a streak," current streak is 0');
    });

    test('every day of the room done -> streak spans the whole room', () {
      final room = _fixedRoom(start: DateTime(2026, 7, 6), end: DateTime(2026, 7, 8));
      final p = _participant(
        dailyDoneCount: const {
          '2026-07-06': 1,
          '2026-07-07': 1,
          '2026-07-08': 1,
        },
      );
      expect(p.currentStreak(room), 3);
    });

    test('done, then a miss, then done again -> only the tail streak counts',
        () {
      final room = _fixedRoom(start: DateTime(2026, 7, 6), end: DateTime(2026, 7, 10));
      final p = _participant(
        dailyDoneCount: const {
          '2026-07-06': 1, // Mon done
          // Tue missed
          '2026-07-08': 1, // Wed done
          '2026-07-09': 1, // Thu done
          '2026-07-10': 1, // Fri (last day) done
        },
      );
      expect(p.currentStreak(room), 3,
          reason: 'Wed/Thu/Fri are consecutive up to the last day - '
              "Monday is cut off by Tuesday's miss");
    });

    test('an excused (not-scheduled) day does not break the streak', () {
      final room = _fixedRoom(start: DateTime(2026, 7, 6), end: DateTime(2026, 7, 8));
      final p = _participant(
        dailyDoneCount: const {'2026-07-06': 1, '2026-07-08': 1}, // Mon + Wed
        dailyScheduledCount: const {'2026-07-07': 0}, // Tue excused
      );
      expect(p.currentStreak(room), 3,
          reason: 'Mon done, Tue excused (counts as satisfied), Wed done');
    });

    test('the streak never reaches earlier than the room start date', () {
      final room = _fixedRoom(start: DateTime(2026, 7, 7), end: DateTime(2026, 7, 8));
      final p = _participant(
        // A done entry from the day BEFORE the room started must never
        // extend the streak backward past startDate.
        dailyDoneCount: const {
          '2026-07-05': 1,
          '2026-07-06': 1,
          '2026-07-07': 1,
          '2026-07-08': 1,
        },
      );
      expect(p.currentStreak(room), 2,
          reason: 'only Jul 7 and Jul 8 fall within the room');
    });
  });

  group('RoomParticipant.currentStreak - room still active (relative dates)',
      () {
    // Unlike the group above, an in-progress room's lastCountedDay is
    // whatever "now" is (see RoomModel.lastCountedDay), so these tests
    // can't use hand-picked literal dates without becoming dependent on
    // whenever they happen to run. Instead every date here is derived from
    // DateTime.now() itself, same clock the code under test reads - the
    // assertions describe *relative* days (today, yesterday, ...), so
    // pass/fail never depends on today's actual calendar date.
    late DateTime today;
    late RoomModel activeRoom;

    setUp(() {
      today = DateTime.now().effectiveDay;
      activeRoom = _fixedRoom(
        start: today.subtract(const Duration(days: 10)),
        end: today.add(const Duration(days: 30)), // far future -> not ended
      );
    });

    test('today not finished yet still preserves the streak from yesterday',
        () {
      final p = _participant(
        dailyDoneCount: {
          today.subtract(const Duration(days: 1)).toDateKey(): 1, // yesterday
          today.subtract(const Duration(days: 2)).toDateKey(): 1, // day before
          // today itself: no entry yet - the room isn't over, still time.
        },
      );
      expect(p.currentStreak(activeRoom), 2);
    });

    test('neither today nor yesterday done -> 0', () {
      final p = _participant(dailyDoneCount: const {});
      expect(p.currentStreak(activeRoom), 0);
    });

    test('today already done -> counts today too, not just the grace check',
        () {
      final p = _participant(
        dailyDoneCount: {
          today.toDateKey(): 1,
          today.subtract(const Duration(days: 1)).toDateKey(): 1,
        },
      );
      expect(p.currentStreak(activeRoom), 2);
    });
  });
}
