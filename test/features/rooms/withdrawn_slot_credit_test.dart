// The withdrawn-slot denominator bug, and the invariant that prevents it.
//
// A room's leader can withdraw a shared-plan slot. Two counts then disagree
// about how many habits a participant has:
//
//   countedHabitIdsIn(room)  drops withdrawn slots
//   countedHabitCount        does not
//
// That divergence is correct and deliberate: countedHabitCount is the
// allocation-free size check used inside per-day loops, and it has no room to
// consult. The bug was that the two sync paths compared their computed
// scheduled count against the FIRST one while [RoomParticipant.scheduledCountFor]
// falls back to the SECOND.
//
// The consequence was quiet and permanent. With two shared slots and one
// withdrawn, a fully done day computed scheduled == 1, compared it to
// habitIds.length == 1, decided "same as the total, no key needed", wrote
// nothing, and then read back a denominator of 2. Every day in the resync
// window sat at 0.5 credit with isFullyDone false, and the numerator clamp
// pinned it there so it never healed.
//
// Both sync paths now compare against countedHabitCount, which is what
// room_model.dart:805-809 always claimed the invariant was.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';

const _day = '2026-08-19';

RoomHabitTemplate _template(String name, {DateTime? removedAt}) =>
    RoomHabitTemplate(
      name: name,
      category: HabitCategory.faith,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      addedAt: DateTime(2026, 8, 1),
      removedAt: removedAt,
    );

RoomModel _sharedRoom({required bool secondWithdrawn}) => RoomModel(
      code: 'A8GEL7',
      name: 'الإلتزام',
      createdBy: 'leader-uid',
      createdByName: 'Leader',
      createdAt: DateTime(2026, 8, 1),
      habitMode: RoomHabitMode.shared,
      duration: RoomDuration.fixed,
      startDate: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 10, 30),
      sharedHabits: [
        _template('صلاة الوتر'),
        _template(
          'قراءة القرآن',
          removedAt: secondWithdrawn ? DateTime(2026, 8, 10) : null,
        ),
      ],
    );

RoomParticipant _participant({
  Map<String, int> dailyDoneCount = const {},
  Map<String, int> dailyScheduledCount = const {},
}) =>
    RoomParticipant(
      uid: 'member-uid',
      displayName: 'Aziz',
      characterId: 'male_ghutra_blue',
      joinedAt: DateTime(2026, 8, 1),
      linkedHabitIds: const ['h1', 'h2'],
      dailyDoneCount: dailyDoneCount,
      dailyScheduledCount: dailyScheduledCount,
      lastUpdated: DateTime(2026, 8, 19),
    );

void main() {
  group('the two counts genuinely diverge after a withdrawal', () {
    test('countedHabitIdsIn drops the withdrawn slot, countedHabitCount does not',
        () {
      final p = _participant();
      final room = _sharedRoom(secondWithdrawn: true);
      expect(p.countedHabitIdsIn(room).length, 1);
      expect(p.countedHabitCount, 2);
    });

    test('they agree while nothing is withdrawn', () {
      final p = _participant();
      final room = _sharedRoom(secondWithdrawn: false);
      expect(p.countedHabitIdsIn(room).length, p.countedHabitCount);
    });
  });

  group('what the old comparison produced', () {
    test('omitting the key leaves a fully done day at half credit', () {
      // The exact broken state: one habit remained, it was done, and no
      // dailyScheduledCount key was written because the old threshold
      // compared against the withdrawn-aware length.
      final p = _participant(dailyDoneCount: const {_day: 1});
      expect(p.scheduledCountFor(_day), 2,
          reason: 'the fallback does not know about the withdrawal');
      expect(p.creditFor(_day), 0.5);
      expect(p.isFullyDone(_day), isFalse,
          reason: 'and so the room streak died on a day that was finished');
    });
  });

  group('what the aligned comparison produces', () {
    test('the key is written and the day reads as finished', () {
      // scheduled (1) != countedHabitCount (2), so both sync paths now write
      // the key, and the denominator is the truth.
      final p = _participant(
        dailyDoneCount: const {_day: 1},
        dailyScheduledCount: const {_day: 1},
      );
      expect(p.scheduledCountFor(_day), 1);
      expect(p.creditFor(_day), 1.0);
      expect(p.isFullyDone(_day), isTrue);
    });

    test('a day still short of its remaining habit is still short', () {
      // The fix must not hand out credit, only stop withholding it.
      final p = _participant(
        dailyDoneCount: const {},
        dailyScheduledCount: const {_day: 1},
      );
      expect(p.creditFor(_day), 0.0);
      expect(p.isFullyDone(_day), isFalse);
    });

    test('with nothing withdrawn, a full day still needs both habits', () {
      final p = _participant(dailyDoneCount: const {_day: 1});
      // No key, fallback of 2, one of two done. Unchanged by the fix.
      expect(p.creditFor(_day), 0.5);
      expect(p.isFullyDone(_day), isFalse);
    });
  });
}
