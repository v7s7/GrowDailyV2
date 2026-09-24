// The leader removing a habit from a running room, through the REAL
// RoomsController (removeSharedHabit, restoreSharedHabit, addSharedHabit)
// and the REAL syncLinkedHabitsProgress, on a fake Firestore, three members.
//
// The board is the one traced on 2026-09-22 before the fix: a 30-day room,
// قراءة القرآن and تمرين, the leader removes تمرين on day 19 at 22:30.
//
//                        before   old remove   now
//   Leader  Q 19/19, E 5/19  63.2%   100% (1st)  63.2%
//   B       Q 12/19, E 19/19 81.6%   63.2%       81.6%
//   C       both 15/19       78.9%   78.9%       78.9%
//
// Aziz's rule: it still counts on the removal day, for nobody from the next
// day, and every day before stays exactly as it was played.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';

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

RoomModel _room({List<RoomHabitTemplate>? slots}) => RoomModel(
      code: 'TRACE2',
      name: 'trace',
      createdBy: 'L',
      createdByName: 'Leader',
      createdAt: DateTime(2026, 7, 1),
      habitMode: RoomHabitMode.shared,
      duration: RoomDuration.fixed,
      startDate: DateTime(2026, 7, 1),
      endDate: DateTime(2026, 7, 30),
      sharedHabits: slots ?? [_slot('قراءة القرآن'), _slot('تمرين')],
    );

/// (quran done?, exercise done?) for days 1..19.
final _plans = <String, List<(bool, bool)>>{
  'L': [for (var d = 1; d <= 19; d++) (true, d <= 5)],
  'B': [for (var d = 1; d <= 19; d++) (d <= 12, true)],
  'C': [for (var d = 1; d <= 19; d++) (d <= 15, d <= 15)],
};

class _Board {
  _Board(this.members);
  final Map<String, RoomSyncHarness> members;
  RoomSyncHarness get leader => members['L']!;

  static Future<_Board> start({RoomModel? room}) async {
    final r = room ?? _room();
    final leader = RoomSyncHarness(
      room: r,
      uid: 'L',
      habits: [_habit('L-q', 'قراءة القرآن'), _habit('L-e', 'تمرين')],
    );
    final board = _Board({
      'L': leader,
      for (final uid in ['B', 'C'])
        uid: RoomSyncHarness(
          room: r,
          uid: uid,
          db: leader.db,
          habits: [_habit('$uid-q', 'قراءة القرآن'), _habit('$uid-e', 'تمرين')],
        ),
    });
    await leader.createRoom();
    for (final e in board.members.entries) {
      final uid = e.key;
      final h = e.value;
      await h.join(RoomParticipant(
        uid: uid,
        displayName: uid,
        characterId: 'male_ghutra_blue',
        joinedAt: DateTime(2026, 7, 1),
        linkedHabitIds: ['$uid-q', '$uid-e'],
        linkedHabitNames: const ['قراءة القرآن', 'تمرين'],
        lastUpdated: DateTime(2026, 7, 1),
      ));
      final days = _plans[uid]!;
      for (var i = 0; i < days.length; i++) {
        final at = DateTime(2026, 7, i + 1, 20);
        if (days[i].$1) {
          await h.mark(_k(i + 1), '$uid-q', SquareState.complete, at);
        }
        if (days[i].$2) {
          await h.mark(_k(i + 1), '$uid-e', SquareState.complete, at);
        }
      }
      await h.syncAt(DateTime(2026, 7, 19, 22));
    }
    return board;
  }

  /// Every member's phone sees the room as it now stands and syncs at [at].
  Future<void> everyoneSyncsAt(DateTime at) async {
    for (final h in members.values) {
      await h.seeRoom();
      await h.syncAt(at);
    }
  }

  Future<Map<String, double>> scores(DateTime at) async => {
        for (final e in members.entries)
          e.key: (await e.value.member()).roomProgressRatio(e.value.room, now: at),
      };

  Future<Map<String, (Map<String, int>, Map<String, int>)>> stored() async => {
        for (final e in members.entries)
          e.key: (
            (await e.value.member()).dailyDoneCount,
            (await e.value.member()).dailyScheduledCount,
          ),
      };

  void dispose() {
    for (final h in members.values) {
      h.dispose();
    }
  }
}

Map<String, int> _upTo19(Map<String, int> m) => {
      for (final e in m.entries)
        if (e.key.compareTo(_k(20)) < 0) e.key: e.value,
    };

void main() {
  setUpAll(initHarnessHive);

  test('removing on day 19 moves nobody: every day before stays as played',
      () async {
    final board = await _Board.start();
    addTearDown(board.dispose);
    final at = DateTime(2026, 7, 20, 12);
    final before = await board.scores(at);
    final storedBefore = await board.stored();

    board.leader.setClock(DateTime(2026, 7, 19, 22, 30));
    final result =
        await board.leader.controller.removeSharedHabit(board.leader.room, 1);
    expect(result, RemoveSharedHabitResult.removed);
    final slot = (await board.leader.seeRoom()).sharedHabits[1];
    expect(slot.stopsOn, _k(20));
    expect(slot.removedBy, 'L');

    await board.everyoneSyncsAt(DateTime(2026, 7, 20, 11));
    final after = await board.scores(at);
    for (final uid in ['L', 'B', 'C']) {
      expect(after[uid], closeTo(before[uid]!, 1e-9), reason: uid);
      final (doneBefore, schedBefore) = storedBefore[uid]!;
      final (doneAfter, schedAfter) = (await board.stored())[uid]!;
      expect(_upTo19(doneAfter), _upTo19(doneBefore), reason: '$uid done');
      expect(_upTo19(schedAfter), _upTo19(schedBefore), reason: '$uid asked');
    }
    expect(after['L'], closeTo(12 / 19, 1e-9));
    expect(after['B'], closeTo(15.5 / 19, 1e-9));
    expect(after['C'], closeTo(15 / 19, 1e-9));
  });

  test('the day after, only what is left in the plan is asked', () async {
    final board = await _Board.start();
    addTearDown(board.dispose);
    board.leader.setClock(DateTime(2026, 7, 19, 22, 30));
    await board.leader.controller.removeSharedHabit(board.leader.room, 1);

    // Day 20: the leader reads Quran and still trains; B trains only.
    final l = board.members['L']!;
    final b = board.members['B']!;
    await l.mark(_k(20), 'L-q', SquareState.complete, DateTime(2026, 7, 20, 7));
    await l.mark(_k(20), 'L-e', SquareState.complete, DateTime(2026, 7, 20, 8));
    await b.mark(_k(20), 'B-e', SquareState.complete, DateTime(2026, 7, 20, 8));
    await board.everyoneSyncsAt(DateTime(2026, 7, 21, 11));

    final lm = await l.member();
    final bm = await b.member();
    // One habit asked on the 20th; the removed one pays nothing and asks
    // nothing, done or not.
    expect(lm.scheduledCountFor(_k(20)), 1);
    expect(lm.dailyDoneCount[_k(20)], 1);
    expect(bm.scheduledCountFor(_k(20)), 1);
    expect(bm.dailyDoneCount[_k(20)] ?? 0, 0);
    // And the removal day itself still asked both.
    expect(bm.scheduledCountFor(_k(19)), 2);
    expect(bm.dailyDoneCount[_k(19)], 1);
  });

  test('undo right after puts it back as if never removed', () async {
    final board = await _Board.start();
    addTearDown(board.dispose);
    final c = board.leader.controller;
    board.leader.setClock(DateTime(2026, 7, 19, 22, 30));
    await c.removeSharedHabit(board.leader.room, 1);
    board.leader.setClock(DateTime(2026, 7, 19, 22, 31));
    expect(await c.restoreSharedHabit(board.leader.room, 1, undo: true), isTrue);

    final slot = (await board.leader.seeRoom()).sharedHabits[1];
    expect(slot.isRemoved, isFalse);
    expect(slot.stopsOn, isNull);
    expect(slot.offSpans, isEmpty);
    expect(slot.restoredAt, isNull);
  });

  test('brought back later: counts again from that day, the days out stay out',
      () async {
    final board = await _Board.start();
    addTearDown(board.dispose);
    final c = board.leader.controller;
    board.leader.setClock(DateTime(2026, 7, 19, 22, 30));
    await c.removeSharedHabit(board.leader.room, 1);

    // Day 22, noon: the leader picks تمرين again in «إضافة عادة».
    await board.leader.seeRoom();
    board.leader.setClock(DateTime(2026, 7, 22, 12));
    final added = await c.addSharedHabit(board.leader.room, 'L-e');
    expect(added.result, AddSharedHabitResult.restored);
    // The SLOT's name, which is what every member sees in the plan.
    expect(added.habitName, 'تمرين');
    final slot = (await board.leader.seeRoom()).sharedHabits[1];
    expect(slot.isRemoved, isFalse);
    expect(slot.offSpans, [(from: _k(20), to: _k(21))]);
    expect(slot.restoredBy, 'L');
    expect(slot.addedDay, isNull, reason: 'an original slot keeps its shape');
    expect((await board.leader.seeRoom()).sharedHabits, hasLength(2),
        reason: 'no second تمرين slot');

    final b = board.members['B']!;
    for (final d in [20, 21, 22]) {
      await b.mark(_k(d), 'B-e', SquareState.complete, DateTime(2026, 7, d, 8));
    }
    await board.everyoneSyncsAt(DateTime(2026, 7, 23, 11));
    final bm = await b.member();
    expect(bm.scheduledCountFor(_k(20)), 1);
    expect(bm.scheduledCountFor(_k(21)), 1);
    expect(bm.scheduledCountFor(_k(22)), 2);
    expect(bm.dailyDoneCount[_k(22)], 1);
  });

  test('removing and picking it again the same day leaves no trace', () async {
    final board = await _Board.start();
    addTearDown(board.dispose);
    final c = board.leader.controller;
    board.leader.setClock(DateTime(2026, 7, 19, 22, 30));
    await c.removeSharedHabit(board.leader.room, 1);
    await board.leader.seeRoom();
    board.leader.setClock(DateTime(2026, 7, 19, 22, 40));
    final back = await c.addSharedHabit(board.leader.room, 'L-e');
    expect(back.result, AddSharedHabitResult.restored);
    final slot = (await board.leader.seeRoom()).sharedHabits[1];
    expect(slot.isRemoved, isFalse);
    expect(slot.offSpans, isEmpty);
    // Nothing counted in between, so nobody is told anything happened.
    expect(slot.restoredAt, isNull);
  });

  test('a member who deletes the habit afterwards keeps their past days',
      () async {
    final board = await _Board.start();
    addTearDown(board.dispose);
    board.leader.setClock(DateTime(2026, 7, 19, 22, 30));
    await board.leader.controller.removeSharedHabit(board.leader.room, 1);
    final b = board.members['B']!;
    await b.seeRoom();
    await b.syncAt(DateTime(2026, 7, 20, 11));
    final before = await b.member();

    // What unlinkHabitEverywhere writes when B deletes تمرين on day 22.
    await b.memberDoc.set({
      'linkedHabitIds': ['B-q', kDeclinedSlot],
      'slotDeclinedFrom': {'1': _k(22)},
      'slotPriorHabitIds': {'1': 'B-e'},
    }, SetOptions(merge: true));
    final gone = RoomSyncHarness(
      room: b.room,
      uid: 'B',
      db: b.db,
      habits: [_habit('B-q', 'قراءة القرآن')],
    );
    addTearDown(gone.dispose);
    await gone.syncAt(DateTime(2026, 7, 23, 11));
    final after = await gone.member();
    expect(_upTo19(after.dailyDoneCount), _upTo19(before.dailyDoneCount));
    expect(_upTo19(after.dailyScheduledCount),
        _upTo19(before.dailyScheduledCount));
    expect(after.roomProgressRatio(b.room, now: DateTime(2026, 7, 20, 12)),
        closeTo(15.5 / 19, 1e-9));
  });

  test('a removal never unmarks the days a member had stood down', () async {
    // The member declined قراءة القرآن and paused their تمرين on the 5th, so
    // the 6th to the 19th are stand-down days: the room asked them for
    // nothing and their percentage holds still. The leader then removes
    // تمرين, which leaves them nothing live at all.
    //
    // The gate that decides stand-down days used to be one question for the
    // whole window ("do the links that count NOW resolve?"), which a member
    // with nothing live answers no. Every stand-down day in the window was
    // then unmarked and re-graded as a miss: the exact A8GEL7 damage
    // standDownDays exists to prevent.
    final leader = RoomSyncHarness(
      room: _room(),
      uid: 'L',
      habits: [_habit('L-q', 'قراءة القرآن'), _habit('L-e', 'تمرين')],
    );
    addTearDown(leader.dispose);
    await leader.createRoom();
    await leader.join(RoomParticipant(
      uid: 'L',
      displayName: 'L',
      characterId: 'male_ghutra_blue',
      joinedAt: DateTime(2026, 7, 1),
      linkedHabitIds: const ['L-q', 'L-e'],
      linkedHabitNames: const ['قراءة القرآن', 'تمرين'],
      lastUpdated: DateTime(2026, 7, 1),
    ));

    final paused = IslamicHabitTemplate(
      id: 'M-e',
      name: 'تمرين',
      description: '',
      category: HabitCategory.faith,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 10,
      goldReward: 5,
      createdAt: DateTime(2026, 7, 1),
      archivedAt: DateTime(2026, 7, 5),
    );
    final m = RoomSyncHarness(
      room: leader.room,
      uid: 'M',
      db: leader.db,
      habits: const [],
      paused: [paused],
    );
    addTearDown(m.dispose);
    await m.join(RoomParticipant(
      uid: 'M',
      displayName: 'M',
      characterId: 'male_ghutra_blue',
      joinedAt: DateTime(2026, 7, 1),
      linkedHabitIds: const [kDeclinedSlot, 'M-e'],
      linkedHabitNames: const ['قراءة القرآن', 'تمرين'],
      slotDeclinedFrom: const {0: '2026-07-01'},
      lastUpdated: DateTime(2026, 7, 1),
    ));
    for (var d = 1; d <= 5; d++) {
      await m.mark(_k(d), 'M-e', SquareState.complete, DateTime(2026, 7, d, 20));
    }
    await m.syncAt(DateTime(2026, 7, 19, 22));
    final before = await m.member();
    expect(before.standDownDays, contains(_k(10)),
        reason: 'paused days are stood down, not missed');

    leader.setClock(DateTime(2026, 7, 19, 22, 30));
    await leader.controller.removeSharedHabit(leader.room, 1);
    await m.seeRoom();
    await m.syncAt(DateTime(2026, 7, 20, 11));

    final after = await m.member();
    for (var d = 6; d <= 19; d++) {
      expect(after.standDownDays, contains(_k(d)), reason: 'day $d');
      expect(after.dailyScheduledCount[_k(d)] ?? 0, 0, reason: 'day $d');
    }
    expect(_upTo19(after.dailyDoneCount), _upTo19(before.dailyDoneCount));
  });

  test('the guards: last habit, finished room, twice, not the leader',
      () async {
    final one = await _Board.start(room: _room(slots: [
      _slot('قراءة القرآن'),
      _slot('تمرين'),
    ]));
    addTearDown(one.dispose);
    final c = one.leader.controller;
    one.leader.setClock(DateTime(2026, 7, 19, 12));
    expect(await c.removeSharedHabit(one.leader.room, 1),
        RemoveSharedHabitResult.removed);
    expect(await c.removeSharedHabit(one.leader.room, 1),
        RemoveSharedHabitResult.alreadyRemoved);
    expect(await c.removeSharedHabit(one.leader.room, 0),
        RemoveSharedHabitResult.lastHabit);

    final member = one.members['B']!;
    member.setClock(DateTime(2026, 7, 19, 12));
    expect(await member.controller.removeSharedHabit(member.room, 0),
        RemoveSharedHabitResult.refused);

    one.leader.setClock(DateTime(2026, 8, 2, 12));
    expect(await c.removeSharedHabit(one.leader.room, 0),
        RemoveSharedHabitResult.roomEnded);
  });
}
