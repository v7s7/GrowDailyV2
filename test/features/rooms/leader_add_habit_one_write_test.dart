// The leader adding a habit to a running room's plan, through the REAL
// RoomsController.addSharedHabit on a fake Firestore.
//
// Room A8GEL7, 2026-10-02: Aziz added «صلاة الوتر» and was at once asked to
// link it («عادة جديدة في الخطة», «ربط: صلاة الوتر»). «ربط الآن» then said
// «ما تغيّر الربط. جرّب مرة ثانية.», although the habit was linked. The slot
// and the leader's own link to it were two writes, the link awaited after the
// slot, so for one server round trip the leader's phone held a plan one slot
// longer than their links: the shape HomeShell prompts a member about. The
// prompt opened, the link landed under it, and the sheet's save was refused
// as a stale slot. They are one batch now.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';

import 'room_sync_harness.dart';

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

  final room = RoomModel(
    code: 'ONEW01',
    name: 'one write',
    createdBy: 'L',
    createdByName: 'Leader',
    createdAt: DateTime(2026, 9),
    habitMode: RoomHabitMode.shared,
    duration: RoomDuration.fixed,
    startDate: DateTime(2026, 9),
    endDate: DateTime(2026, 10, 30),
    sharedHabits: [_slot('تمرين'), _slot('قراءة القرآن')],
  );

  RoomSyncHarness leader() => RoomSyncHarness(
        room: room,
        uid: 'L',
        habits: [
          _habit('L-e', 'تمرين'),
          _habit('L-q', 'قراءة القرآن'),
          _habit('L-w', 'صلاة الوتر'),
        ],
      );

  Future<void> joined(RoomSyncHarness h) async {
    await h.createRoom();
    await h.join(RoomParticipant(
      uid: 'L',
      displayName: 'Aziz',
      characterId: 'male_ghutra_blue',
      joinedAt: DateTime(2026, 9),
      linkedHabitIds: const ['L-e', 'L-q'],
      linkedHabitNames: const ['تمرين', 'قراءة القرآن'],
      lastUpdated: DateTime(2026, 9),
    ));
    await h.container.read(authStateProvider.future);
    h.setClock(DateTime(2026, 10, 2, 21));
  }

  test('the new slot and the leader\'s own link to it are one write', () async {
    final h = leader();
    addTearDown(h.dispose);
    await joined(h);

    final outcome = await h.controller.addSharedHabit(h.room, 'L-w');
    expect(outcome.result, AddSharedHabitResult.added);

    // Both documents in the same commit: no moment, on this phone or on the
    // server, when the plan has the slot and the leader has no link to it.
    final withSlot = h.batchCommits
        .where((paths) => paths.contains('rooms/ONEW01'))
        .toList();
    expect(withSlot, hasLength(1));
    expect(withSlot.single, contains('rooms/ONEW01/participants/L'));

    final grown = await h.seeRoom();
    expect(grown.sharedHabits.map((t) => t.name),
        ['تمرين', 'قراءة القرآن', 'صلاة الوتر']);
    final me = await h.member();
    expect(me.linkedHabitIds, ['L-e', 'L-q', 'L-w']);
    expect(me.linkedHabitNames, ['تمرين', 'قراءة القرآن', 'صلاة الوتر']);
    // Exactly what HomeShell and the room's banner ask about: nothing.
    expect(me.pendingPlanSlotsIn(grown), isEmpty);
  });

  test('a habit the leader cannot link still adds the slot, alone', () async {
    // The guard's other side: a habit another slot held is not linked, and
    // the slot is added for everyone, the leader included, to link like any
    // member (relink_past_days_test has the grading reason).
    final h = leader();
    addTearDown(h.dispose);
    await joined(h);
    await h.memberDoc.set({
      'slotHabitHistory': {
        '0': [
          {'habitId': 'L-w', 'until': '2026-09-10'},
        ],
      },
    }, SetOptions(merge: true));

    final outcome = await h.controller.addSharedHabit(h.room, 'L-w');
    expect(outcome.result, AddSharedHabitResult.added);
    final withSlot = h.batchCommits
        .where((paths) => paths.contains('rooms/ONEW01'))
        .toList();
    expect(withSlot.single, isNot(contains('rooms/ONEW01/participants/L')));
    final grown = await h.seeRoom();
    expect(grown.sharedHabits, hasLength(3));
    expect((await h.member()).pendingPlanSlotsIn(grown), [2]);
  });
}
