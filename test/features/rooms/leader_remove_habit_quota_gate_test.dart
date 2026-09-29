// The quota gates ask the plan the room had that day, not every habit the
// member ever linked to it.
//
// RoomParticipant.habitsInSlotsOn names a slot's habit on every day the
// member's own document links it, and the member's document still links a
// habit the leader removed (the sync grades it on the days before its
// stopsOn). Every question "is this day's plan made of weekly quotas" went
// through it, so a removed habit kept answering for a plan it had left:
//  * a DAILY habit removed from a daily-plus-quota plan kept the met week's
//    rest from running on the days the member's phone had not graded yet
//    (RoomParticipant.recordedScheduledCountFor's quotaOkWeeks arm), so those
//    days read as owed on every board, and the room streak broke on them;
//  * a QUOTA removed beside another quota could lose a week the one left in
//    the plan could still make (quotaWeekIsLost), and the strip crossed out
//    days that were still savable;
//  * a quota removed beside a daily habit held the daily habit's misses open
//    until the week closed (roomStripMissIsFinal).
//
// Measured with the real grader on 2026-09-28, scenario A below: a 21-day
// room, قراءة القرآن daily and تمرين 4x a week, the leader removes the
// Quran on day 11. A met its last week by the Tuesday and stopped opening
// the app; B did the same work and kept opening it; C missed one Quran day.
//
//                    before A's phone     after A's phone      now, before
//                    grades 23-24         grades them          it grades them
//   A                88.2% 15/17, 3rd,    100% 15/15, 1st=,    100% 15/15, 1st=,
//                    streak 0             streak 21            streak 21
//   C                93.3%, 2nd           93.3%, 3rd           93.3%, 3rd
//   team best run    13 (no 14-day prize) 15                   15
//
// The sync writes exactly what it wrote before (every stored document in the
// three scenarios compared byte for byte), and on production that day no
// board, streak, strip or team day moved: no live room had a plan in this
// shape.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_strip_day.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';

import 'room_sync_harness.dart';

String _k(int d) => '2026-07-${d.toString().padLeft(2, '0')}';

typedef _Slot = ({
  String suffix,
  String name,
  HabitFrequencyType type,
  int target,
});

const _Slot _quran = (
  suffix: 'q',
  name: 'قراءة القرآن',
  type: HabitFrequencyType.daily,
  target: 1,
);
const _Slot _train4 = (
  suffix: 'e',
  name: 'تمرين',
  type: HabitFrequencyType.weekly,
  target: 4,
);

IslamicHabitTemplate _habit(String id, _Slot s) => IslamicHabitTemplate(
      id: id,
      name: s.name,
      description: '',
      category: HabitCategory.faith,
      frequencyType: s.type,
      frequencyTarget: s.target,
      hasTimer: false,
      xpReward: 10,
      goldReward: 5,
    );

/// Saturday 4 July to Friday 24 July 2026: three whole Saturday weeks, and
/// over whenever the suite runs, so every score reads the same.
RoomModel _room(String code, List<_Slot> slots) => RoomModel(
      code: code,
      name: code,
      createdBy: 'B',
      createdByName: 'B',
      createdAt: DateTime(2026, 7, 4),
      habitMode: RoomHabitMode.shared,
      duration: RoomDuration.fixed,
      startDate: DateTime(2026, 7, 4),
      endDate: DateTime(2026, 7, 24),
      sharedHabits: [
        for (final s in slots)
          RoomHabitTemplate(
            name: s.name,
            category: HabitCategory.faith,
            frequencyType: s.type,
            frequencyTarget: s.target,
          ),
      ],
    );

/// One room through the real sync: each member marks [done] (uid -> slot
/// suffix -> days) at 20:00 and their phone grades at 22:00 every evening
/// through [lastEvening], the leader B removes slot [removeSlot] at 21:00 on
/// [removeDay], and [extra] are further syncs at the moments given.
/// [snapshots] keep every member's document as it stood at that moment.
class _Run {
  _Run._(this.members, this.snaps);
  final Map<String, RoomSyncHarness> members;
  final Map<DateTime, Map<String, RoomParticipant>> snaps;

  Future<RoomModel> room() => members['B']!.seeRoom();

  Future<List<RoomParticipant>> raw() async =>
      [for (final h in members.values) await h.member()];

  void dispose() {
    for (final h in members.values) {
      h.dispose();
    }
  }

  static Future<_Run> drive({
    required String code,
    required List<_Slot> slots,
    required Map<String, Map<String, Set<int>>> done,
    required Map<String, int> lastEvening,
    required int removeSlot,
    required int removeDay,
    Map<String, List<DateTime>> extra = const {},
    List<DateTime> snapshots = const [],
  }) async {
    final room = _room(code, slots);
    final members = <String, RoomSyncHarness>{};
    for (final uid in done.keys) {
      members[uid] = RoomSyncHarness(
        room: room,
        uid: uid,
        db: members.isEmpty ? null : members.values.first.db,
        habits: [for (final s in slots) _habit('$uid-${s.suffix}', s)],
      );
    }
    final run = _Run._(members, {});
    await members.values.first.createRoom();
    for (final e in members.entries) {
      await e.value.join(
        RoomParticipant(
          uid: e.key,
          displayName: e.key,
          characterId: 'male_ghutra_blue',
          joinedAt: DateTime(2026, 7, 4),
          linkedHabitIds: [for (final s in slots) '${e.key}-${s.suffix}'],
          linkedHabitNames: [for (final s in slots) s.name],
          lastUpdated: DateTime(2026, 7, 4),
        ),
      );
    }
    // Snapshots before a sync at the same moment.
    final events = <(DateTime, String?)>[
      for (final t in snapshots) (t, null),
      for (final e in extra.entries)
        for (final t in e.value) (t, e.key),
    ]..sort((a, b) {
        final c = a.$1.compareTo(b.$1);
        return c != 0 ? c : (a.$2 == null ? 0 : 1) - (b.$2 == null ? 0 : 1);
      });
    Future<void> until(DateTime t) async {
      while (events.isNotEmpty && !events.first.$1.isAfter(t)) {
        final (at, uid) = events.removeAt(0);
        if (uid == null) {
          run.snaps[at] = {
            for (final e in members.entries) e.key: await e.value.member(),
          };
        } else {
          await members[uid]!.seeRoom();
          await members[uid]!.syncAt(at);
        }
      }
    }

    for (var d = 4; d <= 24; d++) {
      await until(DateTime(2026, 7, d, 19, 59));
      for (final e in members.entries) {
        for (final s in slots) {
          if (done[e.key]![s.suffix]!.contains(d)) {
            await e.value.mark(
              _k(d),
              '${e.key}-${s.suffix}',
              SquareState.complete,
              DateTime(2026, 7, d, 20),
            );
          }
        }
      }
      if (d == removeDay) {
        final leader = members['B']!;
        leader.setClock(DateTime(2026, 7, d, 21));
        expect(
          await leader.controller.removeSharedHabit(leader.room, removeSlot),
          RemoveSharedHabitResult.removed,
        );
      }
      for (final e in members.entries) {
        if (d <= lastEvening[e.key]!) {
          await e.value.seeRoom();
          await e.value.syncAt(DateTime(2026, 7, d, 22));
        }
      }
    }
    await until(DateTime(2026, 8));
    return run;
  }
}

/// The roster as gradedRoomParticipantsProvider hands it to the board.
List<RoomParticipant> _graded(
  List<RoomParticipant> raw,
  RoomModel room,
  DateTime now,
) =>
    [
      for (final p in raw)
        p
            .withClosedQuotaWeeksInferred(room, now: now)
            .withUnsyncedPlanInferred(room, now: now)
            .withUnsyncedQuotaRestInferred(room, now: now),
    ];

/// How the strip draws [from]..[to] at [now] (roomRaceDayCode): 'x' crossed,
/// 'r' rest, 'o' still open, a digit a credit level.
String _strip(
  RoomModel room,
  RoomParticipant p,
  DateTime now,
  int from,
  int to,
) =>
    [
      for (var d = from; d <= to; d++)
        roomRaceDayCode(roomStripDayOf(room, p, DateTime(2026, 7, d), now: now)),
    ].join();

/// Everything a board shows of one member, and what decides a place, a
/// streak or a team day.
typedef _Row = ({
  String uid,
  int rank,
  bool shared,
  double room,
  double own,
  int streak,
  String strip,
});

List<_Row> _board(RoomModel room, List<RoomParticipant> graded, DateTime at) {
  final scoring = room.scoringRoster(graded, now: at);
  return [
    for (final s in room.standings(scoring))
      (
        uid: s.participant.uid,
        rank: s.rank,
        shared: s.shared,
        room: s.participant.roomProgressRatio(room, now: at),
        own: s.participant.progressRatio(room, now: at),
        streak: s.participant.currentStreak(room, now: at),
        strip: _strip(room, s.participant, at, 4, 24),
      ),
  ];
}

String _teamDays(RoomModel room, List<RoomParticipant> graded, DateTime at) {
  final scoring = room.scoringRoster(graded, now: at);
  return [
    for (var d = 4; d <= 24; d++)
      switch (room.teamDayResult(_k(d), DateTime(2026, 7, d), scoring)) {
        null => '-',
        true => 'W',
        false => 'L',
      },
  ].join();
}

void main() {
  setUpAll(initHarnessHive);

  group('A: a daily habit removed leaves a 4x quota; A stops opening once '
      'the week is met', () {
    const train = {4, 5, 6, 7, 11, 12, 13, 14, 18, 19, 20, 21};
    final at = DateTime(2026, 7, 25, 12);
    late _Run run;
    late RoomModel room;

    setUp(() async {
      run = await _Run.drive(
        code: 'QGATEA',
        slots: const [_quran, _train4],
        done: {
          'A': {'q': {for (var d = 4; d <= 14; d++) d}, 'e': train},
          'B': {'q': {for (var d = 4; d <= 14; d++) d}, 'e': train},
          'C': {
            'q': {for (var d = 4; d <= 14; d++) if (d != 9) d},
            'e': train,
          },
        },
        // A's phone last grades at 11:00 on Wednesday 22 (the 21st closed,
        // the 22nd still open and already rested by the met week).
        lastEvening: const {'A': 21, 'B': 24, 'C': 24},
        removeSlot: 0,
        removeDay: 14,
        extra: {
          'A': [DateTime(2026, 7, 22, 11)],
          'B': [DateTime(2026, 7, 25, 11)],
          'C': [DateTime(2026, 7, 25, 11)],
        },
      );
      room = await run.room();
    });
    tearDown(() => run.dispose());

    test('the removal counts through the 14th and stops on the 15th', () {
      expect(room.sharedHabits[0].stopsOn, _k(15));
      expect(room.slotLiveOn(0, _k(14)), isTrue);
      expect(room.slotLiveOn(0, _k(15)), isFalse);
    });

    test('the board reads the 23rd and 24th as the rest A\'s phone then '
        'writes', () async {
      final before = await run.raw();
      final a = before.first;
      expect(a.uid, 'A');
      // The record is untouched: no key, and the fallback still counts the
      // removed habit, because the sync compares against it.
      expect(a.dailyScheduledCount.containsKey(_k(23)), isFalse);
      expect(a.recordedScheduledCountFor(_k(23)), 2);
      expect(a.recordedScheduledCountFor(_k(24)), 2);

      final graded = _graded(before, room, at);
      expect(graded.first.unsyncedQuotaRestDays, {_k(23), _k(24)});
      expect(graded.first.scheduledCountFor(_k(23)), 0);
      expect(graded.first.isRestDay(_k(24)), isTrue);
      final boardBefore = _board(room, graded, at);
      final teamBefore = _teamDays(room, graded, at);

      await run.members['A']!.syncAt(DateTime(2026, 7, 25, 11));
      final after = await run.raw();
      expect(after.first.dailyScheduledCount[_k(23)], 0);
      expect(after.first.dailyScheduledCount[_k(24)], 0);
      final gradedAfter = _graded(after, room, at);
      expect(gradedAfter.first.unsyncedQuotaRestDays, isEmpty);

      expect(boardBefore, _board(room, gradedAfter, at));
      expect(teamBefore, _teamDays(room, gradedAfter, at));
    });

    test('the numbers: A shares first, C is third, the team run is 15', () async {
      final graded = _graded(await run.raw(), room, at);
      final board = _board(room, graded, at);
      expect(
        [for (final r in board) (r.uid, r.rank, r.shared)],
        [('A', 1, true), ('B', 1, true), ('C', 3, false)],
      );
      final a = board.first;
      expect(a.room, 1.0);
      expect(a.streak, 21);
      expect(a.strip, '44444444444rrr4444rrr');
      expect(board.last.room, closeTo(14 / 15, 1e-9));
      expect(_teamDays(room, graded, at), 'WWWWWLWWWWWWWWWWWWWWW');
      final scoring = room.scoringRoster(graded, now: at);
      expect(room.teamBestStreakWith(scoring.first, scoring), 15);
      // The 7-day milestone first, and 14 is reachable once it is claimed.
      expect(room.claimableTeamMilestone(scoring.first, scoring), 7);
      final claimed7 = scoring.first.copyWith(teamStreakClaims: const [7]);
      expect(room.claimableTeamMilestone(claimed7, scoring), 14);
    });

    test('an ended room\'s record keeps it, so the podium reads the board',
        () async {
      final graded = _graded(await run.raw(), room, at);
      expect(room.isEndedAt(at), isTrue);
      final recorded = room.scoringRoster(graded, now: at).first;
      expect(recorded.unsyncedQuotaRestDays, {_k(23), _k(24)});
      expect(recorded.asRecorded.scheduledCountFor(_k(23)), 0);
    });

    test('the streak reads the plan the room had, even on the raw record',
        () async {
      // Nothing inferred: the 23rd and 24th still read 2 owed, 0 done. The
      // streak's own quota clause keeps them, as the phone's write will.
      final a = (await run.raw()).first;
      expect(a.isFullyDone(_k(23)), isFalse);
      expect(a.currentStreak(room, now: at), 21);
    });

    test('the sync never reads it: nothing inferred reaches the document',
        () async {
      final graded = _graded(await run.raw(), room, at).first;
      final written = graded.toFirestore();
      expect(written.toString().contains(_k(23)), isFalse);
    });
  });

  test('B: a 5x quota removed beside a 3x one does not lose a week the 3x '
      'can still make', () async {
    const t3 = (
      suffix: 't',
      name: 'تمرين',
      type: HabitFrequencyType.weekly,
      target: 3,
    );
    const walk5 = (
      suffix: 'w',
      name: 'المشي',
      type: HabitFrequencyType.weekly,
      target: 5,
    );
    final thursday = DateTime(2026, 7, 16, 12);
    final run = await _Run.drive(
      code: 'QGATEB',
      slots: const [t3, walk5],
      done: {
        'A': {
          't': {4, 5, 6, 11, 12, 16, 17, 18, 19, 20},
          'w': {4, 5, 6, 7, 8, 11, 12},
        },
        'B': {
          't': {4, 5, 6, 11, 12, 13, 18, 19, 20},
          'w': {4, 5, 6, 7, 8, 11, 12},
        },
      },
      lastEvening: const {'A': 24, 'B': 24},
      removeSlot: 1,
      removeDay: 12,
      snapshots: [thursday],
    );
    addTearDown(run.dispose);
    final room = await run.room();
    expect(room.sharedHabits[1].stopsOn, _k(13));
    // Thursday noon: تمرين has 2 of 3 with Thursday and Friday left, so the
    // week is not lost and Monday to Wednesday stay plain. المشي, removed,
    // could never have made 5, and used to cross all three out.
    final a = _graded([run.snaps[thursday]!['A']!], room, thursday).single;
    expect(a.quotaWeekIsLost(_k(13), room, now: thursday), isFalse);
    expect(_strip(room, a, thursday, 11, 17), '44000oo');
  });

  test('C: a quota removed beside a daily habit: the daily miss is final the '
      'next morning, not at the week\'s close', () async {
    final tuesday = DateTime(2026, 7, 14, 12);
    final run = await _Run.drive(
      code: 'QGATEC',
      slots: const [_quran, _train4],
      done: {
        'A': {
          'q': {for (var d = 4; d <= 24; d++) if (d != 13) d},
          'e': {4, 5, 6, 7, 11},
        },
        'B': {
          'q': {for (var d = 4; d <= 24; d++) d},
          'e': {4, 5, 6, 7, 11},
        },
      },
      lastEvening: const {'A': 24, 'B': 24},
      removeSlot: 1,
      removeDay: 11,
      snapshots: [tuesday],
    );
    addTearDown(run.dispose);
    final room = await run.room();
    expect(room.sharedHabits[1].stopsOn, _k(12));
    final a = _graded([run.snaps[tuesday]!['A']!], room, tuesday).single;
    expect(_strip(room, a, tuesday, 11, 17), '44xoooo');
  });

  test('D: a removed daily habit, a quota week lost and left ungraded: only '
      'the days it broke on are crossed', () async {
    final at = DateTime(2026, 7, 25, 12);
    final run = await _Run.drive(
      code: 'QGATED',
      slots: const [_quran, _train4],
      done: {
        'A': {
          'q': {for (var d = 4; d <= 14; d++) d},
          'e': {4, 5, 6, 7, 11, 12, 13, 14, 18},
        },
        'B': {
          'q': {for (var d = 4; d <= 14; d++) d},
          'e': {4, 5, 6, 7, 11, 12, 13, 14, 18, 19, 20, 21},
        },
      },
      // A's phone last grades on Saturday 18, the week's first day.
      lastEvening: const {'A': 18, 'B': 24},
      removeSlot: 0,
      removeDay: 14,
      extra: {
        'A': [DateTime(2026, 7, 19, 11)],
        'B': [DateTime(2026, 7, 25, 11)],
      },
    );
    addTearDown(run.dispose);
    final room = await run.room();
    final a = _graded(await run.raw(), room, at).first;
    expect(a.uid, 'A');
    // The week of the 18th closed on one session of four: its close rests
    // the three earliest blank days and owes the last three (what A's
    // phone writes when it grades them). Those three were crossed with the
    // rest while the removed daily habit counted as part of the plan.
    expect(_strip(room, a, at, 18, 24), '4000xxx');
    // And before the close: on Thursday noon one session plus Thursday and
    // Friday cannot make four, so the week is lost and Wednesday, the day it
    // broke on, is crossed. The removed daily habit used to keep the plan
    // from reading as a quota plan at all, and the strip waited for Saturday.
    final thursday = DateTime(2026, 7, 23, 12);
    final early = _graded(await run.raw(), room, thursday).first;
    expect(early.quotaWeekIsLost(_k(22), room, now: thursday), isTrue);
    expect(_strip(room, early, thursday, 18, 24), '4000xoo');
  });

  group('unsyncedQuotaRestInference, in the model', () {
    RoomModel roomWith({
      String? stopsOn = '2026-07-15',
      bool removed = true,
      bool thirdDaily = false,
    }) =>
        RoomModel(
          code: 'QGATEM',
          name: 'm',
          createdBy: 'B',
          createdByName: 'B',
          createdAt: DateTime(2026, 7, 4),
          habitMode: RoomHabitMode.shared,
          duration: RoomDuration.fixed,
          startDate: DateTime(2026, 7, 4),
          endDate: DateTime(2026, 7, 24),
          sharedHabits: [
            RoomHabitTemplate(
              name: 'قراءة القرآن',
              category: HabitCategory.faith,
              frequencyType: HabitFrequencyType.daily,
              frequencyTarget: 1,
              removedAt: removed ? DateTime(2026, 7, 14, 21) : null,
              removedBy: removed ? 'B' : null,
              stopsOn: removed ? stopsOn : null,
            ),
            const RoomHabitTemplate(
              name: 'تمرين',
              category: HabitCategory.faith,
              frequencyType: HabitFrequencyType.weekly,
              frequencyTarget: 4,
            ),
            if (thirdDaily)
              const RoomHabitTemplate(
                name: 'الوتر',
                category: HabitCategory.faith,
                frequencyType: HabitFrequencyType.daily,
                frequencyTarget: 1,
              ),
          ],
        );
    RoomParticipant member({
      bool thirdDaily = false,
      Map<String, int> done = const {},
      Map<String, int> scheduled = const {},
      List<String> okWeeks = const ['2026-07-18'],
      DateTime? syncedAt,
    }) {
      final ids = ['q', 'e', if (thirdDaily) 'w'];
      return RoomParticipant(
        uid: 'A',
        displayName: 'A',
        characterId: '',
        joinedAt: DateTime(2026, 7, 4),
        linkedHabitIds: ids,
        habitRules: {
          for (final id in ids)
            id: [
              RoomHabitRule(
                from: '2026-07-04',
                frequencyType: id == 'e'
                    ? HabitFrequencyType.weekly
                    : HabitFrequencyType.daily,
                frequencyTarget: id == 'e' ? 4 : 1,
              ),
            ],
        },
        dailyDoneCount: {
          for (var d = 18; d <= 21; d++) _k(d): 1,
          ...done,
        },
        dailyScheduledCount: {_k(22): 0, ...scheduled},
        quotaOkWeeks: okWeeks,
        lastSyncedDay: _k(22),
        lastSyncedAt: syncedAt ?? DateTime(2026, 7, 22, 11),
        lastUpdated: DateTime(2026, 7, 22, 11),
      );
    }

    final at = DateTime(2026, 7, 25, 12);

    test('the met week\'s blank days no phone has graded', () {
      expect(
        member().unsyncedQuotaRestInference(roomWith(), now: at),
        {_k(23), _k(24)},
      );
    });

    test('nothing where the plan was never edited: the record rests them '
        'or owes them already', () {
      expect(
        member().unsyncedQuotaRestInference(roomWith(removed: false), now: at),
        isEmpty,
      );
    });

    test('nothing while a daily habit is still in the plan', () {
      expect(
        member(thirdDaily: true)
            .unsyncedQuotaRestInference(roomWith(thirdDaily: true), now: at),
        isEmpty,
      );
    });

    test('nothing in a week not met', () {
      expect(
        member(okWeeks: const ['2026-07-11'])
            .unsyncedQuotaRestInference(roomWith(), now: at),
        isEmpty,
      );
    });

    test('nothing on a day a sync observed, or with anything stored on it', () {
      expect(
        member(syncedAt: DateTime(2026, 7, 24, 11))
            .unsyncedQuotaRestInference(roomWith(), now: at),
        {_k(24)},
      );
      expect(
        member(done: {_k(23): 1})
            .unsyncedQuotaRestInference(roomWith(), now: at),
        {_k(24)},
      );
      expect(
        member(scheduled: {_k(24): 1})
            .unsyncedQuotaRestInference(roomWith(), now: at),
        {_k(23)},
      );
    });

    test('from stopsOn, never before: the removal day still counts', () {
      // Removed on the 23rd itself: the Quran still counts that day.
      expect(
        member().unsyncedQuotaRestInference(
          roomWith(stopsOn: _k(24)),
          now: at,
        ),
        {_k(24)},
      );
    });

    test('a legacy removal (no stopsOn) counts on no day', () {
      expect(
        member().unsyncedQuotaRestInference(roomWith(stopsOn: null), now: at),
        {_k(23), _k(24)},
      );
    });

    test('quotaWeekIsLost and the streak ask the same plan', () {
      final m = member(okWeeks: const []);
      // A week with four sessions is never lost, whatever the gate.
      expect(m.quotaWeekIsLost(_k(23), roomWith(), now: at), isFalse);
      // Removed: the plan is all quota, so a met week keeps the streak.
      final met = member();
      expect(met.currentStreak(roomWith(), now: at), greaterThanOrEqualTo(7));
      // Not removed: the Quran was owed on the 23rd and 24th and not done.
      expect(met.currentStreak(roomWith(removed: false), now: at), 0);
    });
  });

  group('the board reads it through both graded providers', () {
    test('a met week\'s ungraded day reads 0 there, and the raw stream '
        'keeps the record', () async {
      // Relative to the real clock: last week, the member met their 4x week
      // by the Tuesday and last synced at 10:30 on the Wednesday; the Quran
      // left the plan before that week began.
      final today = DateTime.now().effectiveDay;
      final lastWeek = today.startOfDisplayWeek.subtract(const Duration(days: 7));
      DateTime day(int n) =>
          DateTime(lastWeek.year, lastWeek.month, lastWeek.day + n);
      final start = day(-7);
      final room = RoomModel(
        code: 'RMVQ',
        name: 'remove',
        createdBy: 'leader',
        createdByName: 'Leader',
        createdAt: start,
        habitMode: RoomHabitMode.shared,
        sharedHabits: [
          RoomHabitTemplate(
            name: 'قراءة القرآن',
            category: HabitCategory.faith,
            frequencyType: HabitFrequencyType.daily,
            frequencyTarget: 1,
            removedAt: DateTime(day(-1).year, day(-1).month, day(-1).day, 15),
            removedBy: 'leader',
            stopsOn: day(0).toDateKey(),
          ),
          const RoomHabitTemplate(
            name: 'تمرين',
            category: HabitCategory.faith,
            frequencyType: HabitFrequencyType.weekly,
            frequencyTarget: 4,
          ),
        ],
        duration: RoomDuration.open,
        startDate: start,
      );
      final member = RoomParticipant(
        uid: 'u',
        displayName: 'u',
        characterId: '',
        joinedAt: start,
        linkedHabitIds: const ['q', 'e'],
        habitRules: {
          'q': [
            RoomHabitRule(
              from: start.toDateKey(),
              frequencyType: HabitFrequencyType.daily,
              frequencyTarget: 1,
            ),
          ],
          'e': [
            RoomHabitRule(
              from: start.toDateKey(),
              frequencyType: HabitFrequencyType.weekly,
              frequencyTarget: 4,
            ),
          ],
        },
        dailyDoneCount: {for (var n = 0; n < 4; n++) day(n).toDateKey(): 1},
        dailyScheduledCount: {
          for (var n = 0; n < 4; n++) day(n).toDateKey(): 1,
        },
        quotaOkWeeks: [lastWeek.toDateKey()],
        lastSyncedDay: day(4).toDateKey(),
        lastSyncedAt: DateTime(day(4).year, day(4).month, day(4).day, 10, 30),
        lastUpdated: day(4),
      );
      final container = ProviderContainer(
        overrides: [
          roomProvider('RMVQ').overrideWith((ref) => Stream.value(room)),
          roomParticipantsProvider('RMVQ')
              .overrideWith((ref) => Stream.value([member])),
          roomRosterHistoryProvider('RMVQ')
              .overrideWith((ref) => Stream.value([member])),
        ],
      );
      addTearDown(container.dispose);
      await container.read(roomProvider('RMVQ').future);
      await container.read(roomParticipantsProvider('RMVQ').future);
      await container.read(roomRosterHistoryProvider('RMVQ').future);

      final thursday = day(5).toDateKey();
      final raw = container.read(roomParticipantsProvider('RMVQ')).value!.single;
      expect(raw.scheduledCountFor(thursday), 2);
      for (final graded in [
        container.read(gradedRoomParticipantsProvider('RMVQ')).value!.single,
        container.read(gradedRoomRosterHistoryProvider('RMVQ')).value!.single,
      ]) {
        expect(graded.scheduledCountFor(thursday), 0);
        expect(graded.scheduledCountFor(day(6).toDateKey()), 0);
        expect(graded.recordedScheduledCountFor(thursday), 2);
      }
    });
  });
}
