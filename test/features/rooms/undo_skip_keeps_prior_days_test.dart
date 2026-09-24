// A slot emptied by deleting its habit (unlinkHabitEverywhere: declined from
// that day, the habit kept as its prior) and then filled again: the days
// before the decline were graded on the old habit and must stay as they
// were, whatever habit fills the slot afterwards.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';

import 'room_sync_harness.dart';

String _k(int d) => '2026-07-${d.toString().padLeft(2, '0')}';

IslamicHabitTemplate _habit(String id, String name) => IslamicHabitTemplate(
      id: id,
      name: name,
      description: '',
      category: HabitCategory.faith,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 10,
      goldReward: 5,
    );

RoomHabitTemplate _slot(String name) => RoomHabitTemplate(
      name: name,
      category: HabitCategory.faith,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
    );

void main() {
  setUpAll(initHarnessHive);

  test('filling a slot again keeps the days its deleted habit earned',
      () async {
    final room = RoomModel(
      code: 'UNDO01',
      name: 'undo',
      createdBy: 'L',
      createdByName: 'Leader',
      createdAt: DateTime(2026, 7, 1),
      habitMode: RoomHabitMode.shared,
      duration: RoomDuration.fixed,
      startDate: DateTime(2026, 7, 1),
      endDate: DateTime(2026, 7, 30),
      sharedHabits: [_slot('الضحى'), _slot('قراءة القرآن')],
    );
    final h = RoomSyncHarness(
      room: room,
      uid: 'M',
      habits: [_habit('m-old', 'صلاة الضحى'), _habit('m-q', 'قراءة القرآن'),
        _habit('m-new', 'الضحى')],
    );
    addTearDown(h.dispose);
    await h.createRoom();
    await h.join(RoomParticipant(
      uid: 'M',
      displayName: 'M',
      characterId: 'male_ghutra_blue',
      joinedAt: DateTime(2026, 7, 1),
      linkedHabitIds: const ['m-old', 'm-q'],
      linkedHabitNames: const ['صلاة الضحى', 'قراءة القرآن'],
      lastUpdated: DateTime(2026, 7, 1),
    ));
    for (var d = 1; d <= 7; d++) {
      final at = DateTime(2026, 7, d, 20);
      await h.mark(_k(d), 'm-old', SquareState.complete, at);
      await h.mark(_k(d), 'm-q', SquareState.complete, at);
    }
    await h.syncAt(DateTime(2026, 7, 7, 22));
    final before = await h.member();

    // Day 8: the habit is deleted from the Grid, exactly the fields
    // unlinkHabitEverywhere writes.
    await h.memberDoc.set({
      'linkedHabitIds': [kDeclinedSlot, 'm-q'],
      'slotDeclinedFrom': {'0': _k(8)},
      'slotPriorHabitIds': {'0': 'm-old'},
    }, SetOptions(merge: true));
    await h.syncAt(DateTime(2026, 7, 9, 22));

    // Day 11: the slot is filled again.
    h.setClock(DateTime(2026, 7, 11, 12));
    await h.controller.resolvePlanHabit(h.room, 0, existingHabitId: 'm-new');
    await h.syncAt(DateTime(2026, 7, 11, 22));
    final after = await h.member();

    Map<String, int> days(Map<String, int> m) =>
        {for (var d = 1; d <= 7; d++) _k(d): m[_k(d)] ?? -1};
    expect(days(after.dailyDoneCount), days(before.dailyDoneCount));
    expect(days(after.dailyScheduledCount), days(before.dailyScheduledCount));
    expect(after.habitInSlotOn(0, _k(3)), 'm-old');
  });
}
