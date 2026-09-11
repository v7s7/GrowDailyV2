// A banked quota week must never pay for a daily habit's day.
//
// Written from room ELQVF8 on 2026-09-11. Hoor's plan mixes a 4x-a-week
// habit (تمرين) with two daily ones (صلاة الوتر, and قراءة القرآن from the
// 8th). She reached four sessions in the week of Saturday 2026-09-05, so that
// week is in quotaOkWeeks. At 02:30 on Friday the 11th nothing was marked and
// both daily habits were still owed, yet her leaderboard flame read 7: the
// streak kept the 11th on the strength of quotaOkWeeks alone.
//
// That list attests to the weekly habits and to nothing else. The grader
// that writes it skips every non-weekly habit before deciding a week held
// (syncLinkedHabitsProgress, pass 2), so on a mixed plan it says nothing
// about whether the daily habits were done. scheduledCountFor and
// quotaWeekIsLost already refuse to let it speak over a daily habit
// (_everyCountedHabitIsWeeklyOn). The streak was the one reader that did not.
//
// Pure model tests: no Firestore, no widgets. The live-room cases pass their
// clock in, and the rest use a room that ended in August 2026, so nothing
// here depends on the day the suite runs.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';

// ELQVF8 / Hoor, as her document stood after the 2026-09-10 sync.

const _kTamreen = '93bfae4a-8c6c-4a53-8bd9-bf41f0efe1c7'; // تمرين, 4x a week
const _kWitr = '64954035-f900-4891-90cd-62e861e3155b'; // صلاة الوتر, daily
const _kQuran = 'd6a6b8a8-9f7a-4541-8820-1c6f7ead3d1c'; // قراءة القرآن, daily

RoomModel _elqvf8() => RoomModel(
      code: 'ELQVF8',
      name: 'ELQVF8',
      createdBy: 'leader-uid',
      createdByName: 'Leader',
      createdAt: DateTime(2026, 9),
      habitMode: RoomHabitMode.shared,
      duration: RoomDuration.fixed,
      startDate: DateTime(2026, 9),
      endDate: DateTime(2026, 9, 30),
    );

/// Hoor's participant document, field for field, as read on 2026-09-11.
/// [doneToday] and [scheduledToday] add what a sync writes for the 11th once
/// something is marked on it.
RoomParticipant _hoor({
  int? doneToday,
  int? scheduledToday,
  String lastSyncedDay = '2026-09-10',
  DateTime? lastSyncedAt,
}) =>
    RoomParticipant(
      uid: 'PfEu8y09LdYlxXS1ZswnNQKuPQl1',
      displayName: 'Hoor',
      characterId: 'female_abaya_navy',
      joinedAt: DateTime(2026, 9, 1, 15, 11),
      linkedHabitIds: const [_kTamreen, _kWitr, _kQuran],
      habitRules: const {
        _kTamreen: [
          RoomHabitRule(
            from: '2026-09-01',
            frequencyType: HabitFrequencyType.weekly,
            frequencyTarget: 4,
          ),
        ],
        _kWitr: [
          RoomHabitRule(
            from: '2026-09-01',
            frequencyType: HabitFrequencyType.daily,
            frequencyTarget: 1,
          ),
        ],
        _kQuran: [
          RoomHabitRule(
            from: '2026-09-08',
            frequencyType: HabitFrequencyType.daily,
            frequencyTarget: 1,
          ),
        ],
      },
      dailyDoneCount: {
        '2026-09-01': 1,
        '2026-09-02': 1,
        '2026-09-05': 2,
        '2026-09-06': 2,
        '2026-09-07': 2,
        '2026-09-08': 3,
        '2026-09-09': 3,
        '2026-09-10': 2,
        if (doneToday != null) '2026-09-11': doneToday,
      },
      dailyScheduledCount: {
        '2026-09-01': 2,
        '2026-09-02': 2,
        '2026-09-03': 2,
        '2026-09-04': 2,
        '2026-09-05': 2,
        '2026-09-06': 2,
        '2026-09-07': 2,
        '2026-09-10': 2,
        if (scheduledToday != null) '2026-09-11': scheduledToday,
      },
      quotaOkWeeks: const ['2026-09-05'],
      lastSyncedDay: lastSyncedDay,
      lastSyncedAt: lastSyncedAt ?? DateTime(2026, 9, 10, 19, 55, 42),
      lastUpdated: DateTime(2026, 9, 10, 19, 55, 42),
    );

// YW68B9 / m7md: one 4x-a-week habit and nothing else.

const _kM7mdTamreen = 'e7c64d39-0443-4a72-b679-36d906050f31';

RoomModel _yw68b9() => RoomModel(
      code: 'YW68B9',
      name: 'YW68B9',
      createdBy: 'leader-uid',
      createdByName: 'Leader',
      createdAt: DateTime(2026, 8, 21),
      habitMode: RoomHabitMode.shared,
      duration: RoomDuration.fixed,
      startDate: DateTime(2026, 8, 21),
      endDate: DateTime(2026, 10, 2),
    );

/// m7md's participant document, field for field, as read on 2026-09-11.
RoomParticipant _m7md({List<String> quotaOkWeeks = const ['2026-08-22']}) =>
    RoomParticipant(
      uid: 'MVsfLW0Lh9h9fqZfBy5VVaP9hJb2',
      displayName: 'm7md',
      characterId: 'male_ghutra_blue',
      joinedAt: DateTime(2026, 8, 21, 20, 34),
      linkedHabitIds: const [_kM7mdTamreen],
      habitRules: const {
        _kM7mdTamreen: [
          RoomHabitRule(
            from: '2026-08-21',
            frequencyType: HabitFrequencyType.weekly,
            frequencyTarget: 4,
          ),
        ],
      },
      dailyDoneCount: const {
        '2026-08-21': 1,
        '2026-08-22': 1,
        '2026-08-28': 1,
        '2026-08-31': 1,
        '2026-09-01': 1,
      },
      dailyScheduledCount: const {
        '2026-08-23': 0,
        '2026-08-26': 0,
        '2026-08-27': 0,
      },
      quotaOkWeeks: quotaOkWeeks,
      lastSyncedDay: '2026-09-04',
      lastUpdated: DateTime(2026, 9, 5, 0, 55),
    );

// A closed Saturday week, 1 to 7 Aug 2026, in a room that ended on the
// Friday, so lastCountedDay is that Friday whenever the suite runs.

final _week = List.generate(7, (i) => DateTime(2026, 8, 1 + i));
const _allDays = {0, 1, 2, 3, 4, 5, 6};
const _kQuota = 'quota-habit';
const _kSecond = 'second-habit';

RoomModel _endedWeekRoom() => RoomModel(
      code: 'TEST01',
      name: 'Test Room',
      createdBy: 'leader-uid',
      createdByName: 'Leader',
      createdAt: _week.first,
      habitMode: RoomHabitMode.own,
      duration: RoomDuration.fixed,
      startDate: _week.first,
      endDate: _week.last,
    );

/// Two habits over [_week], stored the way syncLinkedHabitsProgress stores a
/// closed week: a scheduled count only where it differs from the plan's 2, a
/// done count only where it is not 0, and the week in quotaOkWeeks when every
/// weekly habit reached 4 green squares.
///
/// The first habit is always 4x a week, green on [quotaDone]. The second is
/// [second]: daily, or another 4x quota. [clamped] are days whose squares are
/// green but were painted after the day closed, so the anti-backdating clamp
/// held the done count at 0 while pass 2 still counted them toward the week.
RoomParticipant _twoHabitWeek({
  required HabitFrequencyType second,
  required Set<int> quotaDone,
  required Set<int> secondDone,
  Set<int> clamped = const {},
}) {
  Set<int> quotaAsked(Set<int> done) => weeklyQuotaScheduledDays(
        presentDays: const [0, 1, 2, 3, 4, 5, 6],
        doneDays: done,
        target: 4,
        isWeekClosed: true,
      ).toSet();
  final firstAsked = quotaAsked(quotaDone);
  final secondAsked = second == HabitFrequencyType.weekly
      ? quotaAsked(secondDone)
      : _allDays;
  final done = <String, int>{};
  final scheduled = <String, int>{};
  for (var i = 0; i < _week.length; i++) {
    final key = _week[i].toDateKey();
    final asked =
        (firstAsked.contains(i) ? 1 : 0) + (secondAsked.contains(i) ? 1 : 0);
    final did = clamped.contains(i)
        ? 0
        : (firstAsked.contains(i) && quotaDone.contains(i) ? 1 : 0) +
            (secondAsked.contains(i) && secondDone.contains(i) ? 1 : 0);
    if (asked != 2) scheduled[key] = asked;
    if (did > 0) done[key] = did;
  }
  final banked = quotaDone.length >= 4 &&
      (second != HabitFrequencyType.weekly || secondDone.length >= 4);
  return RoomParticipant(
    uid: 'member-uid',
    displayName: 'Aziz',
    characterId: 'male_ghutra_blue',
    joinedAt: _week.first,
    linkedHabitIds: const [_kQuota, _kSecond],
    habitRules: {
      _kQuota: const [
        RoomHabitRule(
          from: '2026-08-01',
          frequencyType: HabitFrequencyType.weekly,
          frequencyTarget: 4,
        ),
      ],
      _kSecond: [
        RoomHabitRule(
          from: '2026-08-01',
          frequencyType: second,
          frequencyTarget: second == HabitFrequencyType.weekly ? 4 : 1,
        ),
      ],
    },
    dailyDoneCount: done,
    dailyScheduledCount: scheduled,
    quotaOkWeeks: banked ? const ['2026-08-01'] : const [],
    lastSyncedDay: '2026-08-08',
    lastSyncedAt: DateTime(2026, 8, 8, 12),
    lastUpdated: DateTime(2026, 8, 8, 12),
  );
}

void main() {
  group('ELQVF8, Hoor: a banked week does not pay a daily habit\'s day', () {
    test('02:30 on the 11th, nothing marked yet: 6, not 7', () {
      final p = _hoor();
      // The strip already reads the 11th as owed: three habits asked, none
      // done. Only the streak disagreed.
      expect(p.scheduledCountFor('2026-09-11'), 3);
      expect(p.isRestDay('2026-09-11'), isFalse);
      expect(p.isFullyDone('2026-09-11'), isFalse);
      // A live room steps over an unfinished today, so the streak is the six
      // finished days from Thursday the 10th back to Saturday the 5th. The
      // 4th is a real miss in a week that was never banked.
      expect(p.currentStreak(_elqvf8(), now: DateTime(2026, 9, 11, 2, 30)), 6);
    });

    test('the 11th left blank: noon on the 12th reads 0, not 7', () {
      // Why the old answer was more than cosmetic. Once the 11th is
      // yesterday, the quota clause kept it for good: two missed daily habits
      // forgiven permanently, and the flame still reading 7.
      expect(
        _hoor().currentStreak(_elqvf8(), now: DateTime(2026, 9, 12, 12)),
        0,
      );
    });

    test('both daily habits marked on the 11th: 7, and تمرين still rests', () {
      // What the sync writes once both are done. Four تمرين sessions are
      // already in, so the 11th asks only the two daily habits (2, not 3).
      // The gate must not cost her the rest day the grader already excused.
      final p = _hoor(
        doneToday: 2,
        scheduledToday: 2,
        lastSyncedDay: '2026-09-11',
        lastSyncedAt: DateTime(2026, 9, 11, 21),
      );
      expect(p.isFullyDone('2026-09-11'), isTrue);
      expect(p.currentStreak(_elqvf8(), now: DateTime(2026, 9, 11, 23, 30)), 7);
    });

    test('one daily habit marked, the other still owed: 6', () {
      final p = _hoor(
        doneToday: 1,
        scheduledToday: 2,
        lastSyncedDay: '2026-09-11',
        lastSyncedAt: DateTime(2026, 9, 11, 21),
      );
      expect(p.currentStreak(_elqvf8(), now: DateTime(2026, 9, 11, 23, 30)), 6);
    });
  });

  // The other half of the contract. Where every counted habit IS on a weekly
  // quota, the attestation covers the whole plan and the streak reads exactly
  // what it read before the gate.
  group('a plan of weekly habits only keeps its streak exactly', () {
    test('YW68B9, m7md: the two clamped days still hold, 8', () {
      // His real document. The squares on the 24th and 25th were painted
      // after those days closed, so the clamp held their done counts at 0
      // while pass 2 counted the same greens and banked the week of the 22nd.
      // Only the quota clause keeps those two days. Read from the evening of
      // Friday the 28th, before his later misses end the walk. Whether a
      // back-painted day should keep a streak at all is a separate question;
      // this pins that the gate does not answer it.
      expect(
        _m7md().currentStreak(_yw68b9(), now: DateTime(2026, 8, 28, 23)),
        8,
      );
    });

    test('the same document without the banked week: 3', () {
      // Control: the 8 above rests on quotaOkWeeks, so that test really does
      // exercise the clause the gate has to leave alone.
      expect(
        _m7md(quotaOkWeeks: const [])
            .currentStreak(_yw68b9(), now: DateTime(2026, 8, 28, 23)),
        3,
      );
    });

    test('two weekly habits, no daily: the gate asks cadence, not count', () {
      final p = _twoHabitWeek(
        second: HabitFrequencyType.weekly,
        quotaDone: const {0, 1, 2, 4},
        secondDone: const {0, 1, 2, 4},
        clamped: const {4},
      );
      expect(p.isFullyDone(_week[4].toDateKey()), isFalse);
      expect(p.currentStreak(_endedWeekRoom()), 7);
    });
  });

  group('a mixed plan, week banked, room ended', () {
    test('daily habit done every day: 7, the quota\'s rest days still excused',
        () {
      final p = _twoHabitWeek(
        second: HabitFrequencyType.daily,
        quotaDone: const {0, 1, 2, 4},
        secondDone: _allDays,
      );
      expect(p.currentStreak(_endedWeekRoom()), 7);
    });

    test('daily habit missed on the last day: 0, not 7', () {
      final p = _twoHabitWeek(
        second: HabitFrequencyType.daily,
        quotaDone: const {0, 1, 2, 4},
        secondDone: const {0, 1, 2, 3, 4, 5},
      );
      expect(p.currentStreak(_endedWeekRoom()), 0);
    });

    test('daily habit missed on a quota rest day mid-week: 3, not 7', () {
      final p = _twoHabitWeek(
        second: HabitFrequencyType.daily,
        quotaDone: const {0, 1, 2, 4},
        secondDone: const {0, 1, 2, 4, 5, 6},
      );
      expect(p.currentStreak(_endedWeekRoom()), 3);
    });

    test('a clamped day no longer keeps the streak: 2, not 7', () {
      // Wednesday's squares were painted after it closed. The clamp holds
      // its done count at 0; pass 2 still banks the week. On a plan with a
      // daily habit that attestation no longer rescues the day, which is
      // what rooms_notifier.dart's clamp comment always said would happen.
      final p = _twoHabitWeek(
        second: HabitFrequencyType.daily,
        quotaDone: const {0, 1, 2, 4},
        secondDone: _allDays,
        clamped: const {4},
      );
      expect(p.currentStreak(_endedWeekRoom()), 2);
    });
  });
}
