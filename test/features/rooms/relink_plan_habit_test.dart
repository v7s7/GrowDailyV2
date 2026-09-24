// Changing which habit fills a room's plan slot (Aziz, 2026-09-25: "edit
// the connection if one make mistake"), through the REAL RoomsController
// (relinkPlanHabit, resolvePlanHabit) and the REAL syncLinkedHabitsProgress
// on a fake Firestore.
//
// The room: two slots, «الضحى» and «قراءة القرآن», July 2026. The member
// linked «تمرين» to «الضحى» by mistake and did «صلاة الضحى» every day
// anyway. On day 11 they change the link.
//
// The rule, the one a skip and a removal already follow: the change counts
// from the day it is made, and every day before keeps exactly what the
// habit in the slot then earned. The newly linked habit's rule starts at
// the slot's plan floor (the room's start), so without the slot's history
// the new habit would be read back over days 1 to 10; the stored numbers of
// those days are the thing pinned here.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/widgets/relink_plan_habit_sheet.dart';

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

RoomModel _room({RoomHabitMode mode = RoomHabitMode.shared}) => RoomModel(
      code: 'RELINK',
      name: 'relink',
      createdBy: 'L',
      createdByName: 'Leader',
      createdAt: DateTime(2026, 7, 1),
      habitMode: mode,
      duration: RoomDuration.fixed,
      startDate: DateTime(2026, 7, 1),
      endDate: DateTime(2026, 7, 30),
      sharedHabits: [_slot('الضحى'), _slot('قراءة القرآن')],
    );

final _wrong = _habit('m-wrong', 'تمرين');
final _duha = _habit('m-duha', 'صلاة الضحى');
final _quran = _habit('m-q', 'قراءة القرآن');
final _witr = _habit('m-witr', 'صلاة الوتر');

/// Joined on day 1 with «تمرين» in the «الضحى» slot. «تمرين» done on days
/// 1 to 5, «صلاة الضحى» and «قراءة القرآن» on days 1 to 10, then graded
/// on day 10 at 22:00.
Future<RoomSyncHarness> _tenDaysIn({
  List<IslamicHabitTemplate>? habits,
  RoomModel? room,
}) async {
  final h = RoomSyncHarness(
    room: room ?? _room(),
    uid: 'M',
    habits: habits ?? [_wrong, _duha, _quran, _witr],
  );
  await h.createRoom();
  await h.join(RoomParticipant(
    uid: 'M',
    displayName: 'M',
    characterId: 'male_ghutra_blue',
    joinedAt: DateTime(2026, 7, 1),
    linkedHabitIds: const ['m-wrong', 'm-q'],
    linkedHabitNames: const ['تمرين', 'قراءة القرآن'],
    lastUpdated: DateTime(2026, 7, 1),
  ));
  for (var d = 1; d <= 10; d++) {
    final at = DateTime(2026, 7, d, 20);
    if (d <= 5) await h.mark(_k(d), 'm-wrong', SquareState.complete, at);
    await h.mark(_k(d), 'm-duha', SquareState.complete, at);
    await h.mark(_k(d), 'm-q', SquareState.complete, at);
  }
  await h.syncAt(DateTime(2026, 7, 10, 22));
  return h;
}

Map<String, int> _days(Map<String, int> m, int from, int to) => {
      for (var d = from; d <= to; d++)
        if (m.containsKey(_k(d))) _k(d): m[_k(d)]!,
    };

void main() {
  setUpAll(initHarnessHive);

  test('the new habit counts from the day of the change, and days 1 to 10 '
      'keep exactly what they were', () async {
    final h = await _tenDaysIn();
    addTearDown(h.dispose);
    final before = await h.member();
    // What the mistake cost, graded before the change: days 6 to 10 had one
    // of two habits.
    expect(_days(before.dailyDoneCount, 1, 10), {
      for (var d = 1; d <= 10; d++) _k(d): d <= 5 ? 2 : 1,
    });

    // Day 11, 12:00, past the 10:00 cutoff: the change.
    h.setClock(DateTime(2026, 7, 11, 12));
    expect(await h.controller.relinkPlanHabit(h.room, 0, 'm-duha'), isTrue);
    await h.mark(_k(11), 'm-duha', SquareState.complete,
        DateTime(2026, 7, 11, 13));
    await h.mark(_k(11), 'm-q', SquareState.complete,
        DateTime(2026, 7, 11, 13));
    await h.syncAt(DateTime(2026, 7, 11, 22));

    final after = await h.member();
    expect(after.linkedHabitIds, ['m-duha', 'm-q']);
    expect(after.linkedHabitNames, ['صلاة الضحى', 'قراءة القرآن']);
    expect(after.slotHabitHistory, {
      0: [(habitId: 'm-wrong', until: _k(10))],
    });
    // Nothing before the change moved, in either direction: «صلاة الضحى»
    // was done on days 6 to 10, and that does not pay days it was not in
    // the slot.
    expect(_days(after.dailyDoneCount, 1, 10),
        _days(before.dailyDoneCount, 1, 10));
    expect(_days(after.dailyScheduledCount, 1, 10),
        _days(before.dailyScheduledCount, 1, 10));
    // The day of the change is the new habit's.
    expect(after.dailyDoneCount[_k(11)], 2);
    // Each past day names the habit that was in the slot then.
    expect(after.habitInSlotOn(0, _k(3)), 'm-wrong');
    expect(after.habitInSlotOn(0, _k(10)), 'm-wrong');
    expect(after.habitInSlotOn(0, _k(11)), 'm-duha');
  });

  test('a later resync still never lets the new habit reach back', () async {
    final h = await _tenDaysIn();
    addTearDown(h.dispose);
    final before = await h.member();
    h.setClock(DateTime(2026, 7, 11, 12));
    await h.controller.relinkPlanHabit(h.room, 0, 'm-duha');
    for (final at in [
      DateTime(2026, 7, 12, 9),
      DateTime(2026, 7, 13, 22),
      DateTime(2026, 7, 20, 22),
    ]) {
      await h.syncAt(at);
    }
    final after = await h.member();
    expect(_days(after.dailyDoneCount, 1, 10),
        _days(before.dailyDoneCount, 1, 10));
  });

  test('going back to the habit a slot had before keeps both stretches',
      () async {
    final h = await _tenDaysIn();
    addTearDown(h.dispose);
    h.setClock(DateTime(2026, 7, 11, 12));
    await h.controller.relinkPlanHabit(h.room, 0, 'm-duha');
    await h.mark(_k(11), 'm-duha', SquareState.complete,
        DateTime(2026, 7, 11, 13));
    await h.mark(_k(12), 'm-duha', SquareState.complete,
        DateTime(2026, 7, 12, 13));
    await h.syncAt(DateTime(2026, 7, 12, 22));
    final mid = await h.member();

    // Day 13: back to «تمرين». Its own slot's history, so allowed.
    h.setClock(DateTime(2026, 7, 13, 12));
    expect(await h.controller.relinkPlanHabit(h.room, 0, 'm-wrong'), isTrue);
    await h.syncAt(DateTime(2026, 7, 13, 22));
    final after = await h.member();
    expect(after.slotHabitHistory[0], [
      (habitId: 'm-wrong', until: _k(10)),
      (habitId: 'm-duha', until: _k(12)),
    ]);
    expect(after.habitInSlotOn(0, _k(5)), 'm-wrong');
    expect(after.habitInSlotOn(0, _k(11)), 'm-duha');
    expect(after.habitInSlotOn(0, _k(13)), 'm-wrong');
    expect(_days(after.dailyDoneCount, 1, 12), _days(mid.dailyDoneCount, 1, 12));
  });

  test('a change on the day the habit was linked leaves no record', () async {
    final h = RoomSyncHarness(
      room: _room(),
      uid: 'M',
      habits: [_wrong, _duha, _quran],
    );
    addTearDown(h.dispose);
    await h.createRoom();
    await h.join(RoomParticipant(
      uid: 'M',
      displayName: 'M',
      characterId: 'male_ghutra_blue',
      joinedAt: DateTime(2026, 7, 11, 12),
      linkedHabitIds: const ['m-wrong', 'm-q'],
      linkedHabitNames: const ['تمرين', 'قراءة القرآن'],
      lastUpdated: DateTime(2026, 7, 11, 12),
    ));
    h.setClock(DateTime(2026, 7, 11, 12, 30));
    expect(await h.controller.relinkPlanHabit(h.room, 0, 'm-duha'), isTrue);
    final after = await h.member();
    expect(after.linkedHabitIds, ['m-duha', 'm-q']);
    expect(after.slotHabitHistory, isEmpty);
  });

  test('a habit that was replaced and then deleted keeps its days', () async {
    final h = await _tenDaysIn();
    h.setClock(DateTime(2026, 7, 11, 12));
    await h.controller.relinkPlanHabit(h.room, 0, 'm-duha');
    await h.syncAt(DateTime(2026, 7, 11, 22));
    final before = await h.member();
    h.dispose();

    // «تمرين» deleted from the Grid: the same member, a habit list without it.
    final later = RoomSyncHarness(
      room: _room(),
      uid: 'M',
      db: h.db,
      habits: [_duha, _quran, _witr],
    );
    addTearDown(later.dispose);
    await later.syncAt(DateTime(2026, 7, 12, 22));
    final after = await later.member();
    expect(_days(after.dailyDoneCount, 1, 11),
        _days(before.dailyDoneCount, 1, 11));
    // Not frozen: the room kept grading.
    expect(after.lastSyncedDay, isNot(before.lastSyncedDay));
  });

  group('refused, and nothing written', () {
    Future<void> refused(
      RoomSyncHarness h,
      int slot,
      String habitId, {
      RoomModel? room,
    }) async {
      final before = await h.member();
      h.setClock(DateTime(2026, 7, 11, 12));
      expect(
        await h.controller.relinkPlanHabit(room ?? h.room, slot, habitId),
        isFalse,
      );
      final after = await h.member();
      expect(after.linkedHabitIds, before.linkedHabitIds);
      expect(after.linkedHabitNames, before.linkedHabitNames);
      expect(after.slotHabitHistory, before.slotHabitHistory);
    }

    test('the habit already there', () async {
      final h = await _tenDaysIn();
      addTearDown(h.dispose);
      await refused(h, 0, 'm-wrong');
    });

    test('a habit another slot holds now', () async {
      final h = await _tenDaysIn();
      addTearDown(h.dispose);
      await refused(h, 0, 'm-q');
    });

    test('a habit another slot held before', () async {
      final h = await _tenDaysIn();
      addTearDown(h.dispose);
      h.setClock(DateTime(2026, 7, 11, 12));
      await h.controller.relinkPlanHabit(h.room, 0, 'm-duha');
      // «تمرين» filled slot 0 until day 10: it cannot fill slot 1 now.
      await refused(h, 1, 'm-wrong');
    });

    test('a habit this account does not have', () async {
      final h = await _tenDaysIn();
      addTearDown(h.dispose);
      await refused(h, 0, 'someone-elses');
    });

    test('a slot out of range', () async {
      final h = await _tenDaysIn();
      addTearDown(h.dispose);
      await refused(h, 5, 'm-duha');
    });

    test('a room that has ended', () async {
      final h = await _tenDaysIn();
      addTearDown(h.dispose);
      final before = await h.member();
      h.setClock(DateTime(2026, 8, 5, 12));
      expect(await h.controller.relinkPlanHabit(h.room, 0, 'm-duha'), isFalse);
      expect((await h.member()).linkedHabitIds, before.linkedHabitIds);
    });

    test('an own-habits room, which has no plan slots', () async {
      final h = await _tenDaysIn(room: _room(mode: RoomHabitMode.own));
      addTearDown(h.dispose);
      await refused(h, 0, 'm-duha');
    });
  });

  test('a new plan habit cannot be linked to a habit another slot held '
      'before', () async {
    final h = await _tenDaysIn();
    addTearDown(h.dispose);
    h.setClock(DateTime(2026, 7, 11, 12));
    await h.controller.relinkPlanHabit(h.room, 0, 'm-duha');
    // The leader adds a third habit; the member tries to fill it with
    // «تمرين», which slot 0 held until day 10 and is graded through.
    final third = RoomModel(
      code: h.room.code,
      name: h.room.name,
      createdBy: h.room.createdBy,
      createdByName: h.room.createdByName,
      createdAt: h.room.createdAt,
      habitMode: h.room.habitMode,
      duration: h.room.duration,
      startDate: h.room.startDate,
      endDate: h.room.endDate,
      sharedHabits: [
        ...h.room.sharedHabits,
        RoomHabitTemplate(
          name: 'تمرين',
          category: HabitCategory.health,
          frequencyType: HabitFrequencyType.daily,
          frequencyTarget: 1,
          addedAt: DateTime(2026, 7, 11, 11),
        ),
      ],
    );
    await h.roomDoc.set(third.toFirestore());
    await h.seeRoom();
    await h.controller.resolvePlanHabit(h.room, 2, existingHabitId: 'm-wrong');
    expect((await h.member()).linkedHabitIds, ['m-duha', 'm-q'],
        reason: 'refused: the slot stays unanswered');
    // Its own habit is fine.
    await h.controller.resolvePlanHabit(h.room, 2, existingHabitId: 'm-witr');
    expect((await h.member()).linkedHabitIds, ['m-duha', 'm-q', 'm-witr']);
  });

  test('the sheet offers only habits the slot may take, closest name first',
      () {
    final mine = RoomParticipant(
      uid: 'M',
      displayName: 'M',
      characterId: 'male_ghutra_blue',
      joinedAt: DateTime(2026, 7, 1),
      linkedHabitIds: const ['m-wrong', 'm-q'],
      linkedHabitNames: const ['تمرين', 'قراءة القرآن'],
      lastUpdated: DateTime(2026, 7, 1),
      slotHabitHistory: const {
        1: [(habitId: 'm-old-q', until: '2026-07-04')],
      },
    );
    final offered = relinkCandidates(
      room: _room(),
      mine: mine,
      slot: 0,
      myHabits: [
        _witr,
        _habit('m-old-q', 'ورد القرآن'),
        _quran,
        _wrong,
        _duha,
      ],
    ).map((h) => h.id).toList();
    // Not the habit already there, not slot 1's current or earlier habit;
    // «صلاة الضحى» first for the «الضحى» slot, the rest in list order.
    expect(offered, ['m-duha', 'm-witr']);
  });

  group('the record itself', () {
    RoomParticipant member({
      Map<int, List<({String habitId, String until})>> history = const {},
      List<String> ids = const ['a', 'b', 'c'],
      Map<int, String> prior = const {},
    }) =>
        RoomParticipant(
          uid: 'M',
          displayName: 'M',
          characterId: 'male_ghutra_blue',
          joinedAt: DateTime(2026, 7, 1),
          linkedHabitIds: ids,
          lastUpdated: DateTime(2026, 7, 1),
          slotHabitHistory: history,
          slotPriorHabitIds: prior,
        );

    test('each day reads the habit that filled the slot then', () {
      final m = member(history: {
        0: [
          (habitId: 'x', until: _k(4)),
          (habitId: 'y', until: _k(9)),
        ],
      });
      expect(m.habitInSlotOn(0, _k(1)), 'x');
      expect(m.habitInSlotOn(0, _k(4)), 'x');
      expect(m.habitInSlotOn(0, _k(5)), 'y');
      expect(m.habitInSlotOn(0, _k(9)), 'y');
      expect(m.habitInSlotOn(0, _k(10)), 'a');
      expect(m.habitInSlotOn(1, _k(1)), 'b', reason: 'other slots untouched');
    });

    test('it survives a round trip through Firestore, oldest first, and '
        'drops what is not a habit and a day', () async {
      final m = member(history: {
        0: [(habitId: 'x', until: _k(4))],
        2: [(habitId: 'z', until: _k(8))],
      });
      final data = m.toFirestore();
      final raw = data['slotHabitHistory'] as Map;
      expect(raw.keys.every((k) => k is String && !k.contains('.')), isTrue,
          reason: 'slot keys are map keys, never dotted field paths');
      // Out of order and with junk, as a hand edit might leave it.
      data['slotHabitHistory'] = {
        '0': [
          {'habitId': 'y', 'until': _k(9)},
          {'habitId': 'x', 'until': _k(4)},
          {'habitId': '', 'until': _k(2)},
          {'habitId': 'q'},
          'junk',
        ],
        'not-a-slot': [
          {'habitId': 'w', 'until': _k(1)},
        ],
      };
      final doc = FakeFirebaseFirestore().collection('participants').doc('M');
      await doc.set(data);
      final back = RoomParticipant.fromFirestore(await doc.get());
      expect(back.slotHabitHistory, {
        0: [
          (habitId: 'x', until: _k(4)),
          (habitId: 'y', until: _k(9)),
        ],
      });
    });

    test('a habit held by another slot, now or before, is off limits', () {
      final m = member(
        ids: ['a', kDeclinedSlot, 'c'],
        prior: {1: 'p'},
        history: {
          0: [(habitId: 'x', until: _k(4))],
          2: [(habitId: 'z', until: _k(8))],
        },
      );
      expect(m.habitsHeldBySlotsOtherThan(0), {'c', 'p', 'z'});
      expect(m.habitsHeldBySlotsOtherThan(2), {'a', 'p', 'x'});
      expect(m.habitsHeldBySlotsOtherThan(null), {'a', 'c', 'p', 'x', 'z'});
    });
  });
}
