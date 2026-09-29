// A habit the leader removed must not count on a day the member's phone has
// not graded yet.
//
// Room PBYAS5, 2026-09-28: the leader took «سنة الظهر البعدية» and «الوتر»
// out of a seven-habit plan on the 26th, so from the 27th five habits count.
// A member whose phone had last synced on the 27th opened on the 28th in
// somebody else's view, and the day card said «0 من 7 عادات» and «ما أُنجز 7».
// The sync writes a day's count only when it differs from
// RoomParticipant.countedHabitCountOn, which cannot see the room, and a day
// nobody has synced has no count at all, so it fell back to seven.
//
// The fix is read-side only (RoomParticipant.unsyncedPlanInference, chained
// into the graded providers). What the sync writes, and what it compares
// against, is left exactly as it was: older builds, other phones,
// room_health.js and the admin tool all read those written counts.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_day_breakdown.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';

import 'room_sync_harness.dart';

String _k(int d) => '2026-07-${d.toString().padLeft(2, '0')}';

RoomHabitTemplate _slot(
  String name, {
  DateTime? removedAt,
  String? stopsOn,
  List<({String from, String to})> offSpans = const [],
  HabitFrequencyType type = HabitFrequencyType.daily,
  int target = 1,
}) =>
    RoomHabitTemplate(
      name: name,
      category: HabitCategory.faith,
      frequencyType: type,
      frequencyTarget: target,
      removedAt: removedAt,
      removedBy: removedAt == null ? null : 'leader',
      stopsOn: stopsOn,
      offSpans: offSpans,
    );

RoomModel _room(
  List<RoomHabitTemplate> slots, {
  RoomHabitMode mode = RoomHabitMode.shared,
}) =>
    RoomModel(
      code: 'PBYAS5',
      name: 'اذكار الصباح',
      createdBy: 'leader',
      createdByName: 'نور',
      createdAt: DateTime(2026, 7, 1),
      habitMode: mode,
      duration: RoomDuration.fixed,
      startDate: DateTime(2026, 7, 1),
      endDate: DateTime(2026, 7, 30),
      sharedHabits: mode == RoomHabitMode.shared ? slots : const [],
    );

/// PBYAS5's plan as it stood on the 28th, moved to July: slots 3 and 6
/// removed on the 19th in the afternoon, so the 19th is their last day.
final _removedAt = DateTime(2026, 7, 19, 14, 50);
const _names = [
  'أذكار الصباح',
  'سورة الملك',
  'صدقة',
  'سنة الظهر البعدية',
  'سنة الفجر',
  'الضحى',
  'الوتر',
];
const _ids = ['a', 'm', 's', 'z', 'f', 'd', 'w'];
final _pbyas5 = _room([
  for (var i = 0; i < _names.length; i++)
    i == 3 || i == 6
        ? _slot(_names[i], removedAt: _removedAt, stopsOn: _k(20))
        : _slot(_names[i]),
]);

RoomHabitRule _rule(
  String from, {
  HabitFrequencyType type = HabitFrequencyType.daily,
  int target = 1,
}) =>
    RoomHabitRule(from: from, frequencyType: type, frequencyTarget: target);

RoomParticipant _member({
  String uid = 'noor',
  List<String> linked = _ids,
  Map<String, int> done = const {},
  Map<String, int> partial = const {},
  Map<String, int> rested = const {},
  Map<String, int> scheduled = const {},
  Map<String, double> scheduledWeight = const {},
  Map<String, Map<String, RoomHabitMark>> marks = const {},
  List<String> quotaOkWeeks = const [],
  HabitFrequencyType ruleType = HabitFrequencyType.daily,
  DateTime? joinedAt,
  Map<int, String> declinedFrom = const {},
  String? lastSyncedDay,
  DateTime? lastSyncedAt,
}) =>
    RoomParticipant(
      uid: uid,
      displayName: uid,
      characterId: 'male_ghutra_blue',
      joinedAt: joinedAt ?? DateTime(2026, 7, 1),
      linkedHabitIds: linked,
      linkedHabitNames: [
        for (var i = 0; i < linked.length; i++)
          i < _names.length ? _names[i] : '',
      ],
      dailyDoneCount: done,
      dailyPartialCount: partial,
      dailyRestedCount: rested,
      dailyScheduledCount: scheduled,
      dailyScheduledWeight: scheduledWeight,
      dailyHabitMarks: marks,
      quotaOkWeeks: quotaOkWeeks,
      habitRules: {
        for (final id in linked)
          if (id != kDeclinedSlot)
            id: [_rule('2026-07-01', type: ruleType, target: 4)],
      },
      slotDeclinedFrom: declinedFrom,
      lastSyncedDay: lastSyncedDay,
      lastSyncedAt: lastSyncedAt,
      lastUpdated: lastSyncedAt ?? DateTime(2026, 7, 1),
    );

/// نور as PBYAS5 read her: synced on the 20th, the first day without the two
/// removed habits (key 5), and not since.
RoomParticipant _noor({Map<String, int> done = const {}}) => _member(
      done: {_k(19): 3, _k(20): 3, ...done},
      scheduled: {_k(20): 5},
      lastSyncedDay: _k(20),
      lastSyncedAt: DateTime(2026, 7, 20, 12, 23),
    );

final _noon21 = DateTime(2026, 7, 21, 12);

void main() {
  group('a day no sync has written reads the plan the leader left', () {
    test('PBYAS5: 5 of 7 on the unsynced day, the record untouched', () {
      final raw = _noor();
      expect(raw.unsyncedPlanInference(_pbyas5, now: _noon21), {_k(21): 5});

      final graded = raw.withUnsyncedPlanInferred(_pbyas5, now: _noon21);
      // The bug, pinned on the record alone: the document still says 7.
      expect(raw.scheduledCountFor(_k(21)), 7);
      expect(graded.recordedScheduledCountFor(_k(21)), 7);
      // The board reads 5.
      expect(graded.scheduledCountFor(_k(21)), 5);
      expect(graded.scheduledWeightFor(_k(21)), 5);
      // The synced day keeps its key; the day before the removal took
      // effect still counts all seven, as the rule says.
      expect(graded.scheduledCountFor(_k(20)), 5);
      expect(graded.scheduledCountFor(_k(19)), 7);
    });

    test('the day card: «من 5 عادات», named rows, no removed habit', () {
      final raw = _noor();
      final graded = raw.withUnsyncedPlanInferred(_pbyas5, now: _noon21);

      final before =
          roomDayBreakdown(room: _pbyas5, participant: raw, dateKey: _k(21));
      expect(before.scheduled, 7);
      expect(before.slots, isEmpty, reason: 'the card fell back to counts');

      final after = roomDayBreakdown(
        room: _pbyas5,
        participant: graded,
        dateKey: _k(21),
      );
      expect(after.scheduled, 5);
      expect(after.done, 0);
      expect([for (final r in after.slots) r.name], [
        'أذكار الصباح',
        'سورة الملك',
        'صدقة',
        'سنة الفجر',
        'الضحى',
      ]);
      expect(
        after.slots.every((r) => r.outcome == RoomSlotOutcome.missed),
        isTrue,
      );
    });

    test('several unsynced days: only the ones after the removal change', () {
      final raw = _member(
        lastSyncedDay: _k(15),
        lastSyncedAt: DateTime(2026, 7, 16, 20),
      );
      // Observed through the 15th; the 16th to the 19th still had all seven.
      expect(
        raw.unsyncedPlanInference(_pbyas5, now: _noon21),
        {_k(20): 5, _k(21): 5},
      );
    });

    test('a day with anything recorded on it is the sync\'s to answer', () {
      final cases = <String, RoomParticipant>{
        'done': _member(done: {_k(21): 1}),
        'half done': _member(partial: {_k(21): 1}),
        'rested': _member(rested: {_k(21): 1}),
        'a weight': _member(scheduledWeight: {_k(21): 5}),
        'marks': _member(marks: {
          _k(21): {'a': RoomHabitMark.missed},
        }),
      };
      for (final e in cases.entries) {
        final inferred = e.value.unsyncedPlanInference(_pbyas5, now: _noon21);
        expect(inferred.containsKey(_k(21)), isFalse, reason: e.key);
        expect(inferred.containsKey(_k(20)), isTrue, reason: e.key);
      }
    });

    test('an observed day with no key keeps its record; the walk stops', () {
      final raw = _member(
        lastSyncedDay: _k(22),
        lastSyncedAt: DateTime(2026, 7, 22, 11),
      );
      final inferred = raw.unsyncedPlanInference(
        _pbyas5,
        now: DateTime(2026, 7, 22, 12),
      );
      // The 21st closed at 10:00 on the 22nd and a sync saw it after that.
      expect(inferred, {_k(22): 5});
    });

    test('never zero: a member with nothing live keeps the plain total', () {
      final room = _room([
        _slot('قراءة القرآن'),
        _slot('تمرين', removedAt: _removedAt, stopsOn: _k(20)),
      ]);
      final raw = _member(
        linked: const [kDeclinedSlot, 'e'],
        declinedFrom: {0: _k(1)},
      );
      expect(raw.unsyncedPlanInference(room, now: _noon21), isEmpty);
      final graded = raw.withUnsyncedPlanInferred(room, now: _noon21);
      expect(graded.scheduledCountFor(_k(21)), 1);
      expect(graded.creditFor(_k(21)), 0);
    });

    test('a met quota week\'s blank day keeps the record\'s own rest', () {
      final room = _room([
        _slot('تمرين', type: HabitFrequencyType.weekly, target: 4),
        _slot(
          'مشي',
          type: HabitFrequencyType.weekly,
          target: 4,
          removedAt: _removedAt,
          stopsOn: _k(20),
        ),
      ]);
      final raw = _member(
        linked: const ['t', 'm'],
        ruleType: HabitFrequencyType.weekly,
        // Saturday 18 July opens the week.
        quotaOkWeeks: [_k(18)],
        lastSyncedDay: _k(20),
        lastSyncedAt: DateTime(2026, 7, 20, 12),
      );
      expect(raw.recordedScheduledCountFor(_k(21)), 0);
      expect(raw.unsyncedPlanInference(room, now: _noon21), isEmpty);
      final graded = raw.withUnsyncedPlanInferred(room, now: _noon21);
      expect(graded.scheduledCountFor(_k(21)), 0);
    });

    test('a stretch out of the plan (offSpans) reads the same way', () {
      final room = _room([
        _slot('قراءة القرآن'),
        _slot('تمرين', offSpans: [(from: _k(20), to: _k(21))]),
      ]);
      final raw = _member(
        linked: const ['q', 'e'],
        lastSyncedDay: _k(19),
        lastSyncedAt: DateTime(2026, 7, 19, 20),
      );
      expect(
        raw.unsyncedPlanInference(room, now: DateTime(2026, 7, 23, 12)),
        {_k(20): 1, _k(21): 1},
      );
    });

    test('a legacy removal (no stopsOn) counts on no unsynced day', () {
      final room = _room([
        _slot('قراءة القرآن'),
        _slot('تمرين', removedAt: DateTime(2026, 7, 5)),
      ]);
      final raw = _member(linked: const ['q', 'e'], lastSyncedDay: _k(10));
      final graded =
          raw.withUnsyncedPlanInferred(room, now: DateTime(2026, 7, 12, 12));
      expect(graded.planInferredScheduledCount, {_k(11): 1, _k(12): 1});
      // Observed days keep what their sync recorded.
      expect(graded.scheduledCountFor(_k(5)), 2);
    });

    test('a member who joined after the removal: nothing to infer', () {
      final raw = _member(
        linked: const ['a', 'm', 's', kDeclinedSlot, 'f', 'd', kDeclinedSlot],
        joinedAt: DateTime(2026, 7, 19, 23),
      );
      expect(raw.unsyncedPlanInference(_pbyas5, now: _noon21), isEmpty);
      expect(raw.scheduledCountFor(_k(21)), 5);
    });

    test('a plan nobody edited, or an own-mode room: the same instance', () {
      final plain = _room([for (final n in _names) _slot(n)]);
      final raw = _member();
      expect(raw.unsyncedPlanInference(plain, now: _noon21), isEmpty);
      expect(
        identical(raw.withUnsyncedPlanInferred(plain, now: _noon21), raw),
        isTrue,
      );
      final own = _room(const [], mode: RoomHabitMode.own);
      expect(raw.unsyncedPlanInference(own, now: _noon21), isEmpty);
    });
  });

  group('it pays nothing', () {
    // Three members through the whole (ended) room, read raw and graded on
    // every number that decides a place, a streak, a prize or a team day.
    // The room ended on 30 July, so "now" is the same whatever day the suite
    // runs.
    final noor = _member(
      done: {
        for (var d = 1; d <= 19; d++) _k(d): d % 3 == 0 ? 0 : 2,
        _k(20): 3,
        // Work with no key after the removal, as only a hand repair writes
        // it: left to the record, so it still reads 7 either way.
        _k(23): 2,
      },
      scheduled: {_k(20): 5},
      lastSyncedDay: _k(20),
      lastSyncedAt: DateTime(2026, 7, 20, 12, 23),
    );
    final aziz = _member(
      uid: 'aziz',
      done: {
        for (var d = 1; d <= 19; d++) _k(d): 7,
        for (var d = 20; d <= 25; d++) _k(d): 5,
      },
      scheduled: {for (var d = 20; d <= 25; d++) _k(d): 5},
      lastSyncedDay: _k(26),
      lastSyncedAt: DateTime(2026, 7, 26, 12),
    );
    final hoor = _member(
      uid: 'hoor',
      linked: const ['a', 'm', 's', kDeclinedSlot, 'f', 'd', 'w'],
      declinedFrom: {3: _k(1)},
      done: {for (var d = 1; d <= 14; d++) _k(d): 6},
      lastSyncedDay: _k(14),
      lastSyncedAt: DateTime(2026, 7, 15, 11),
    );
    final raw = [noor, aziz, hoor];
    final graded = [for (final p in raw) p.withUnsyncedPlanInferred(_pbyas5)];

    test('the inference is really there', () {
      expect(graded[0].planInferredScheduledCount[_k(21)], 5);
      expect(graded[0].planInferredScheduledCount.containsKey(_k(23)), isFalse);
      expect(graded[1].planInferredScheduledCount[_k(30)], 5);
      expect(graded[2].planInferredScheduledCount[_k(22)], 5);
      expect(graded[2].recordedScheduledCountFor(_k(22)), 6);
    });

    test('every score, streak and place reads the same', () {
      for (var i = 0; i < raw.length; i++) {
        final r = raw[i];
        final g = graded[i];
        expect(g.progressRatio(_pbyas5), r.progressRatio(_pbyas5));
        expect(g.roomProgressRatio(_pbyas5), r.roomProgressRatio(_pbyas5));
        expect(g.daysCompleted(_pbyas5), r.daysCompleted(_pbyas5));
        expect(g.currentStreak(_pbyas5), r.currentStreak(_pbyas5));
        expect(g.concededDaysIn(_pbyas5), r.concededDaysIn(_pbyas5));
        for (var d = 1; d <= 30; d++) {
          final k = _k(d);
          expect(g.creditFor(k), r.creditFor(k), reason: '${r.uid} $k');
          expect(g.roomCreditFor(_pbyas5, k), r.roomCreditFor(_pbyas5, k),
              reason: '${r.uid} $k');
          expect(g.isFullyDone(k), r.isFullyDone(k), reason: '${r.uid} $k');
          expect(g.isRestDay(k), r.isRestDay(k), reason: '${r.uid} $k');
          expect(g.isDeclaredRest(k), r.isDeclaredRest(k),
              reason: '${r.uid} $k');
        }
      }
      List<(String, int, bool)> places(List<RoomParticipant> ps) => [
            for (final s in _pbyas5.standings(ps))
              (s.participant.uid, s.rank, s.shared),
          ];
      expect(places(graded), places(raw));
    });

    test('team days and team milestones read the same', () {
      for (var d = 1; d <= 30; d++) {
        final day = DateTime(2026, 7, d);
        expect(
          _pbyas5.teamDayResult(day.toDateKey(), day, graded),
          _pbyas5.teamDayResult(day.toDateKey(), day, raw),
          reason: _k(d),
        );
      }
      for (var i = 0; i < raw.length; i++) {
        expect(
          _pbyas5.teamBestStreakWith(graded[i], graded),
          _pbyas5.teamBestStreakWith(raw[i], raw),
        );
        expect(
          _pbyas5.claimableTeamMilestone(graded[i], graded),
          _pbyas5.claimableTeamMilestone(raw[i], raw),
        );
      }
    });

    test('asRecorded keeps it, so an ended room\'s day cards read 5', () {
      expect(graded[0].asRecorded.scheduledCountFor(_k(21)), 5);
      expect(
        _pbyas5.scoringRoster(graded).first.scheduledCountFor(_k(21)),
        5,
      );
    });
  });

  group('the board reads it, the roster streams do not', () {
    test('both graded providers read today without the removed habit',
        () async {
      // Relative to the real clock: the removal took effect yesterday, the
      // member synced yesterday, and today has no count yet.
      final today = DateTime.now().effectiveDay;
      DateTime back(int n) => DateTime(today.year, today.month, today.day - n);
      final room = RoomModel(
        code: 'RMV',
        name: 'remove',
        createdBy: 'leader',
        createdByName: 'Leader',
        createdAt: back(10),
        habitMode: RoomHabitMode.shared,
        sharedHabits: [
          _slot('قراءة القرآن'),
          _slot('تمرين'),
          _slot(
            'الوتر',
            removedAt: DateTime(back(2).year, back(2).month, back(2).day, 15),
            stopsOn: back(1).toDateKey(),
          ),
        ],
        duration: RoomDuration.open,
        startDate: back(10),
      );
      final member = RoomParticipant(
        uid: 'u',
        displayName: 'u',
        characterId: '',
        joinedAt: back(10),
        linkedHabitIds: const ['q', 'e', 'w'],
        dailyScheduledCount: {back(1).toDateKey(): 2},
        habitRules: {
          for (final id in const ['q', 'e', 'w'])
            id: [_rule(back(10).toDateKey())],
        },
        lastSyncedDay: back(1).toDateKey(),
        lastUpdated: back(1),
      );
      final container = ProviderContainer(
        overrides: [
          roomProvider('RMV').overrideWith((ref) => Stream.value(room)),
          roomParticipantsProvider('RMV')
              .overrideWith((ref) => Stream.value([member])),
          roomRosterHistoryProvider('RMV')
              .overrideWith((ref) => Stream.value([member])),
        ],
      );
      addTearDown(container.dispose);
      await container.read(roomProvider('RMV').future);
      await container.read(roomParticipantsProvider('RMV').future);
      await container.read(roomRosterHistoryProvider('RMV').future);

      final todayKey = today.toDateKey();
      final rawBoard =
          container.read(roomParticipantsProvider('RMV')).value!.single;
      expect(rawBoard.scheduledCountFor(todayKey), 3);
      for (final graded in [
        container.read(gradedRoomParticipantsProvider('RMV')).value!.single,
        container.read(gradedRoomRosterHistoryProvider('RMV')).value!.single,
      ]) {
        expect(graded.scheduledCountFor(todayKey), 2);
        expect(graded.recordedScheduledCountFor(todayKey), 3);
      }
    });
  });

  group('the plan card says nothing about a habit the room left', () {
    IslamicHabitTemplate habit(
      String id,
      String nameAr, {
      HabitFrequencyType type = HabitFrequencyType.daily,
      DateTime? archivedAt,
    }) =>
        IslamicHabitTemplate(
          id: id,
          name: id,
          nameAr: nameAr,
          description: '',
          category: HabitCategory.custom,
          frequencyType: type,
          frequencyTarget: type == HabitFrequencyType.weekly ? 3 : 1,
          hasTimer: false,
          xpReward: 10,
          goldReward: 5,
          archivedAt: archivedAt,
        );

    final today = DateTime.now().effectiveDay;
    DateTime back(int n) => DateTime(today.year, today.month, today.day - n);
    final room = RoomModel(
      code: 'RMV',
      name: 'remove',
      createdBy: 'leader',
      createdByName: 'Leader',
      createdAt: back(10),
      habitMode: RoomHabitMode.shared,
      sharedHabits: [
        _slot('قراءة القرآن'),
        _slot(
          'الوتر',
          removedAt: DateTime(back(2).year, back(2).month, back(2).day, 15),
          stopsOn: back(1).toDateKey(),
        ),
      ],
      duration: RoomDuration.open,
      startDate: back(10),
    );
    final mine = RoomParticipant(
      uid: 'u',
      displayName: 'u',
      characterId: '',
      joinedAt: back(10),
      linkedHabitIds: const ['q', 'w'],
      habitRules: {
        for (final id in const ['q', 'w']) id: [_rule(back(10).toDateKey())],
      },
      lastUpdated: back(1),
    );
    final quran = habit('q', 'قراءة القرآن');

    test('pausing the removed habit is no pause in this room', () {
      final paused = habit('w', 'الوتر', archivedAt: back(0));
      final before = roomUnresolvedLinks(mine, [quran], [paused], isAr: true);
      expect(before.pausedNames, ['الوتر']);
      final after = roomUnresolvedLinks(
        mine,
        [quran],
        [paused],
        isAr: true,
        room: room,
      );
      expect(after.pausedNames, isEmpty);
      expect(after.hasDeleted, isFalse);
    });

    test('editing the removed habit is no rule change in this room', () {
      final edited = habit('w', 'الوتر', type: HabitFrequencyType.weekly);
      final todayKey = today.toDateKey();
      expect(roomRuleMismatches(mine, [quran, edited], todayKey), ['w']);
      expect(
        roomRuleMismatches(mine, [quran, edited], todayKey, room: room),
        isEmpty,
      );
    });

    group('the button under the warning', () {
      setUpAll(initHarnessHive);

      test('relocks only the habits the warning lists', () async {
        // Both of the member's habits edited to 3x a week in the Grid. The
        // warning names قراءة القرآن only, since الوتر left the plan
        // yesterday, so «تطبيق» must not quietly relock الوتر: if the leader
        // ever brings it back, its frozen daily rule is what the member
        // agreed to, and the warning is where they get to change it.
        final h = RoomSyncHarness(
          room: room,
          habits: [
            habit('q', 'قراءة القرآن', type: HabitFrequencyType.weekly),
            habit('w', 'الوتر', type: HabitFrequencyType.weekly),
          ],
          uid: 'u',
        );
        addTearDown(h.dispose);
        await h.createRoom();
        await h.join(mine);
        h.setClock(DateTime.now());
        await h.controller.relockHabitRules(room);

        final after = await h.member();
        final todayKey = today.toDateKey();
        expect(
          after.habitRules['q']!.map((r) => r.from),
          [back(10).toDateKey(), todayKey],
        );
        expect(
          after.ruleFor('q', todayKey)!.frequencyType,
          HabitFrequencyType.weekly,
        );
        expect(
          after.habitRules['w']!.map((r) => r.from),
          [back(10).toDateKey()],
        );
      });
    });
  });
}
