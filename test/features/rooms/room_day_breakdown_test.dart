import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_day_breakdown.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';

/// What a tapped day is allowed to say about itself.
///
/// The day card shows a score out of what was asked and, when it can, names
/// which habit did what. The room stores COUNTS per day, never which habit
/// each count was, so the naming is only honest on a day the counts pin
/// down. These tests are mostly about the days where they do not.
const _day = '2026-09-08';

RoomModel _room({
  List<String> plan = const ['تمرين'],
  RoomHabitMode mode = RoomHabitMode.shared,
  List<DateTime?> removedAt = const [],
}) =>
    RoomModel(
      code: 'YW68B9',
      name: 'NO STOOOOP',
      createdBy: 'leader-uid',
      createdByName: 'Leader',
      createdAt: DateTime(2026, 8, 21),
      habitMode: mode,
      duration: RoomDuration.fixed,
      startDate: DateTime(2026, 8, 21),
      endDate: DateTime(2026, 12, 31),
      sharedHabits: [
        for (var i = 0; i < plan.length; i++)
          RoomHabitTemplate(
            name: plan[i],
            category: HabitCategory.custom,
            frequencyType: HabitFrequencyType.daily,
            frequencyTarget: 1,
            removedAt: i < removedAt.length ? removedAt[i] : null,
          ),
      ],
    );

RoomParticipant _p({
  List<String> linked = const ['h1'],
  Map<String, int> done = const {},
  Map<String, int> partial = const {},
  Map<String, int> rested = const {},
  Map<String, int> scheduled = const {},
  Map<int, String> declinedFrom = const {},
}) =>
    RoomParticipant(
      uid: 'member-uid',
      displayName: 'Aziz',
      characterId: 'male_ghutra_blue',
      joinedAt: DateTime(2026, 8, 21),
      linkedHabitIds: linked,
      dailyDoneCount: done,
      dailyPartialCount: partial,
      dailyRestedCount: rested,
      dailyScheduledCount: scheduled,
      slotDeclinedFrom: declinedFrom,
      lastUpdated: DateTime(2026, 9, 10),
    );

void main() {
  group('the score', () {
    test('a done day is 1 of 1', () {
      final b = roomDayBreakdown(
        room: _room(),
        participant: _p(done: const {_day: 1}),
        dateKey: _day,
      );
      expect(b.credited, 1);
      expect(b.scheduled, 1);
      expect(b.missed, 0);
      expect(b.ratio, 1);
    });

    test('a missed day is 0 of 1', () {
      final b = roomDayBreakdown(
        room: _room(),
        participant: _p(),
        dateKey: _day,
      );
      expect(b.credited, 0);
      expect(b.scheduled, 1);
      expect(b.missed, 1);
      expect(b.ratio, 0);
    });

    test('a جزئي is half a habit, the same half it is worth everywhere', () {
      // Aziz's own case: "if the train give him 0.5, show that with the done
      // mark". SquareState.xpValue pays it 5 against 10, the Grid's day ratio
      // scores it 0.5, and creditFor counts it 0.5. So does this.
      final b = roomDayBreakdown(
        room: _room(),
        participant: _p(partial: const {_day: 1}),
        dateKey: _day,
      );
      expect(b.credited, 0.5);
      expect(b.ratio, 0.5);
    });

    test('a rest counts for the display and never for the score', () {
      // dailyRestedCount is a display field behind a wall: subtracting a
      // rested habit from the denominator would let somebody mark تخطّي on
      // what they skipped and settle a half day at full credit.
      final b = roomDayBreakdown(
        room: _room(plan: const ['تمرين', 'قراءة']),
        participant: _p(
          linked: const ['h1', 'h2'],
          done: const {_day: 1},
          rested: const {_day: 1},
        ),
        dateKey: _day,
      );
      expect(b.rested, 1);
      expect(b.scheduled, 2);
      expect(b.credited, 1);
    });

    test('a day that asked nothing is a whole day, as creditFor has it', () {
      final b = roomDayBreakdown(
        room: _room(),
        participant: _p(scheduled: const {_day: 0}),
        dateKey: _day,
      );
      expect(b.asksNothing, isTrue);
      expect(b.ratio, 1);
      expect(b.credited, 0);
    });
  });

  group('naming the habit', () {
    test('a one-habit plan can always be named', () {
      final b = roomDayBreakdown(
        room: _room(),
        participant: _p(done: const {_day: 1}),
        dateKey: _day,
      );
      expect(b.slots, hasLength(1));
      expect(b.slots.single.name, 'تمرين');
      expect(b.slots.single.outcome, RoomSlotOutcome.done);
    });

    test('an all-done day names every habit', () {
      final b = roomDayBreakdown(
        room: _room(plan: const ['تمرين', 'قراءة']),
        participant: _p(linked: const ['h1', 'h2'], done: const {_day: 2}),
        dateKey: _day,
      );
      expect(b.slots.map((e) => e.outcome),
          everyElement(RoomSlotOutcome.done));
      expect(b.slots.map((e) => e.name), ['تمرين', 'قراءة']);
    });

    test('an all-missed day names every habit', () {
      final b = roomDayBreakdown(
        room: _room(plan: const ['تمرين', 'قراءة']),
        participant: _p(linked: const ['h1', 'h2']),
        dateKey: _day,
      );
      expect(b.slots.map((e) => e.outcome),
          everyElement(RoomSlotOutcome.missed));
    });

    test('a MIXED day names nothing, because the room cannot tell', () {
      // Two habits asked for, one done. The document records the counts and
      // not which habit each was, so saying "تمرين 1/1, قراءة 0/1" would be
      // the room telling somebody they skipped a habit they may have done.
      final b = roomDayBreakdown(
        room: _room(plan: const ['تمرين', 'قراءة']),
        participant: _p(linked: const ['h1', 'h2'], done: const {_day: 1}),
        dateKey: _day,
      );
      expect(b.slots, isEmpty);
      expect(b.done, 1);
      expect(b.missed, 1);
    });

    test('a day where something was excused names nothing either', () {
      // Two live slots, one scheduled: which one was excused is exactly the
      // fact the document does not carry.
      final b = roomDayBreakdown(
        room: _room(plan: const ['تمرين', 'قراءة']),
        participant: _p(
          linked: const ['h1', 'h2'],
          done: const {_day: 1},
          scheduled: const {_day: 1},
        ),
        dateKey: _day,
      );
      expect(b.slots, isEmpty);
    });

    test('a day that asked nothing rests every habit by name', () {
      final b = roomDayBreakdown(
        room: _room(plan: const ['تمرين', 'قراءة']),
        participant: _p(
          linked: const ['h1', 'h2'],
          scheduled: const {_day: 0},
        ),
        dateKey: _day,
      );
      expect(b.slots.map((e) => e.outcome),
          everyElement(RoomSlotOutcome.rest));
    });

    test('a declined slot is named, because that one IS certain', () {
      final b = roomDayBreakdown(
        room: _room(plan: const ['تمرين', 'قراءة']),
        participant: _p(
          linked: const ['h1', kDeclinedSlot],
          declinedFrom: const {1: '2026-08-21'},
          done: const {_day: 1},
        ),
        dateKey: _day,
      );
      expect(b.slots, hasLength(2));
      expect(b.slots.first.outcome, RoomSlotOutcome.done);
      expect(b.slots.last.name, 'قراءة');
      expect(b.slots.last.outcome, RoomSlotOutcome.declined);
    });

    test('a slot the leader withdrew is left out entirely', () {
      // The stored scheduled count is what the sync writes once a slot is
      // withdrawn; the participant document alone cannot know about it,
      // because the withdrawal lives on the room (see scheduledCountFor).
      final b = roomDayBreakdown(
        room: _room(
          plan: const ['تمرين', 'قراءة'],
          removedAt: [null, DateTime(2026, 9, 1)],
        ),
        participant: _p(
          linked: const ['h1', 'h2'],
          done: const {_day: 1},
          scheduled: const {_day: 1},
        ),
        dateKey: _day,
      );
      expect(b.slots, hasLength(1));
      expect(b.slots.single.name, 'تمرين');
    });

    test("an 'own'-mode room has no names to give", () {
      // Every member picks their own habits there and the document carries
      // ids, not names.
      final b = roomDayBreakdown(
        room: _room(mode: RoomHabitMode.own),
        participant: _p(done: const {_day: 1}),
        dateKey: _day,
      );
      expect(b.slots, isEmpty);
      expect(b.credited, 1);
    });
  });
}
