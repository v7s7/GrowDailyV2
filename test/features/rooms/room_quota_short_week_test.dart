// A room week the room only partly covers asks its share of a weekly quota
// (roomQuotaWeekTarget, room_quota_share.dart). Aziz, 2026-09-27, on F8HQKE
// «بزنس مِن»: 30 days from Sunday 27 September to Monday 26 October, تمرين
// four times a week. Its first six days ask 4 and its last three ask 3, three
// workouts in a row; with the share they ask 3 and 2. Weeks before the start
// week keep the whole target, so no week that had already closed moves.
//
// The app ships with the share switched off (kRoomQuotaShareFromWeekKey is
// null until Aziz picks a start week after a release). Every test here but
// the first switches it on from 26 September through
// debugRoomQuotaShareFromWeekKey.
//
// The grader is driven for real (RoomsController.syncLinkedHabitsProgress on a
// fake Firestore, room_sync_harness.dart); the four surfaces that draw a quota
// week are checked against the same numbers.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/models/weekly_quota_plan.dart';
import 'package:grow_daily_v2/features/rooms/models/room_habit_strip.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_quota_share.dart';
import 'package:grow_daily_v2/features/rooms/models/room_quota_week.dart';
import 'package:grow_daily_v2/features/rooms/models/room_strip_day.dart';

import 'room_sync_harness.dart';

final _gym = IslamicHabitTemplate(
  id: 'gym',
  name: 'Gym',
  nameAr: 'تمرين',
  description: '',
  category: HabitCategory.custom,
  frequencyType: HabitFrequencyType.weekly,
  frequencyTarget: 4,
  hasTimer: false,
  xpReward: 10,
  goldReward: 5,
  createdAt: DateTime(2026, 8),
);

final _dhikr = IslamicHabitTemplate(
  id: 'dhikr',
  name: 'Dhikr',
  nameAr: 'أذكار',
  description: '',
  category: HabitCategory.custom,
  frequencyType: HabitFrequencyType.daily,
  frequencyTarget: 1,
  hasTimer: false,
  xpReward: 10,
  goldReward: 5,
  createdAt: DateTime(2026, 8),
);

const _gymSlot = RoomHabitTemplate(
  name: 'تمرين',
  category: HabitCategory.custom,
  frequencyType: HabitFrequencyType.weekly,
  frequencyTarget: 4,
);

/// F8HQKE as it was started: Sunday 27 September to Monday 26 October.
RoomModel _business({
  DateTime? start,
  DateTime? end,
  List<RoomHabitTemplate> plan = const [_gymSlot],
}) =>
    RoomModel(
      code: 'F8HQKE',
      name: 'بزنس مِن',
      createdBy: 'M',
      createdByName: 'Aziz',
      createdAt: DateTime(2026, 9, 27, 10),
      habitMode: RoomHabitMode.shared,
      duration: RoomDuration.fixed,
      startDate: start ?? DateTime(2026, 9, 27),
      endDate: end ?? DateTime(2026, 10, 26),
      sharedHabits: plan,
    );

RoomParticipant _joiner(DateTime joinedAt, {List<String> ids = const ['gym']}) =>
    RoomParticipant(
      uid: 'M',
      displayName: 'M',
      characterId: 'male_ghutra_blue',
      joinedAt: joinedAt,
      linkedHabitIds: ids,
      linkedHabitNames: [for (final id in ids) id],
      lastUpdated: joinedAt,
    );

/// A room running since 1 September with أذكار daily from its start, and
/// تمرين added to the plan on Tuesday 29 September.
RoomModel _addedOnTuesday() => RoomModel(
      code: 'ADDED1',
      name: 'added',
      createdBy: 'M',
      createdByName: 'Aziz',
      createdAt: DateTime(2026, 9),
      habitMode: RoomHabitMode.shared,
      duration: RoomDuration.open,
      startDate: DateTime(2026, 9),
      sharedHabits: const [
        RoomHabitTemplate(
          name: 'أذكار',
          category: HabitCategory.custom,
          frequencyType: HabitFrequencyType.daily,
          frequencyTarget: 1,
        ),
        RoomHabitTemplate(
          name: 'تمرين',
          category: HabitCategory.custom,
          frequencyType: HabitFrequencyType.weekly,
          frequencyTarget: 4,
          addedDay: '2026-09-29',
        ),
      ],
    );

/// أذكار done on every day of the week of 26 September.
final _dhikrAllWeek = {
  for (var d = 26; d <= 30; d++) 'dhikr/2026-09-$d',
  'dhikr/2026-10-01',
  'dhikr/2026-10-02',
};

DateTime _d(String key) => DateTime.parse(key);

/// Lives [from] to [to] the way a phone does: each session stored the evening
/// of its own day, the room synced every night, then once more at [closeAt].
Future<RoomParticipant> _live(
  RoomModel room, {
  required DateTime joined,
  required String from,
  required String to,
  required Set<String> sessions,
  required DateTime closeAt,
  List<IslamicHabitTemplate>? habits,
  List<String> ids = const ['gym'],
}) async {
  final h = RoomSyncHarness(room: room, uid: 'M', habits: habits ?? [_gym]);
  addTearDown(h.dispose);
  await h.createRoom();
  await h.join(_joiner(joined, ids: ids));
  for (var d = _d(from);
      !d.isAfter(_d(to));
      d = DateTime(d.year, d.month, d.day + 1)) {
    final key = d.toDateKey();
    for (final s in sessions) {
      final parts = s.split('/');
      final id = parts.length == 2 ? parts[0] : 'gym';
      if (parts.last == key) {
        await h.mark(
          key,
          id,
          SquareState.complete,
          DateTime(d.year, d.month, d.day, 21),
        );
      }
    }
    await h.syncAt(DateTime(d.year, d.month, d.day, 22));
  }
  await h.syncAt(closeAt);
  return h.member();
}

/// (asked, done) on [key], as stored.
(int, int) _at(RoomParticipant p, String key) =>
    (p.scheduledCountFor(key), p.dailyDoneCount[key] ?? 0);

void main() {
  setUpAll(initHarnessHive);
  // The share on from 26 September for every test but the first, which
  // clears it again to check what the app ships.
  setUp(() => debugRoomQuotaShareFromWeekKey = '2026-09-26');
  tearDown(() => debugRoomQuotaShareFromWeekKey = null);

  test(
      'as the app ships the share is off: a short week asks the whole target, '
      'capped at its days', () async {
    debugRoomQuotaShareFromWeekKey = null;
    expect(kRoomQuotaShareFromWeekKey, isNull);
    expect(roomQuotaWeekHasShare(DateTime(2026, 10, 25)), isFalse);
    expect(
      roomQuotaWeekTarget(
        target: 4,
        day: DateTime(2026, 10, 25),
        firstDay: DateTime(2026, 9, 27),
        lastDay: DateTime(2026, 10, 26),
      ),
      4,
    );
    // F8HQKE's first week, three sessions in its six days: one short of 4,
    // so its Friday, the last day it could have been made, is the miss.
    final p = await _live(
      _business(),
      joined: DateTime(2026, 9, 27, 10),
      from: '2026-09-27',
      to: '2026-10-02',
      sessions: const {'2026-09-27', '2026-09-28', '2026-09-29'},
      closeAt: DateTime(2026, 10, 3, 11),
    );
    expect(_at(p, '2026-10-01'), (0, 0));
    expect(_at(p, '2026-10-02'), (1, 0));
    expect(p.quotaOkWeeks, isNot(contains('2026-09-26')));
  });

  group('roomQuotaWeekTarget', () {
    // The week of Saturday 3 October, the room's days being its last [days].
    int share(int target, int days) => roomQuotaWeekTarget(
          target: target,
          day: DateTime(2026, 10, 3),
          firstDay: DateTime(2026, 10, 3 + 7 - days),
        );

    test('4x over one to seven days asks 1, 1, 2, 2, 3, 3, 4', () {
      expect([for (var d = 1; d <= 7; d++) share(4, d)], [1, 1, 2, 2, 3, 3, 4]);
    });

    test('every target asks at least one and never more than the days', () {
      for (var t = 1; t <= 7; t++) {
        for (var d = 1; d <= 7; d++) {
          final s = share(t, d);
          expect(s, inInclusiveRange(1, d), reason: '${t}x over $d days');
          expect(s, lessThanOrEqualTo(t), reason: '${t}x over $d days');
        }
        expect(share(t, 7), t, reason: 'a whole week asks the whole target');
      }
    });

    test('no target up to 6 over a short week lands on a half', () {
      for (var t = 1; t <= 6; t++) {
        for (var d = 1; d <= 6; d++) {
          expect((t * d * 2) % 7, isNot(0), reason: '${t}x over $d days');
        }
      }
    });

    test("the room's end cuts a week the way its start does", () {
      // Saturday 24 to Monday 26 October, F8HQKE's last three days.
      expect(
        roomQuotaWeekTarget(
          target: 4,
          day: DateTime(2026, 10, 25),
          firstDay: DateTime(2026, 9, 27),
          lastDay: DateTime(2026, 10, 26),
        ),
        2,
      );
    });

    test('a room with no end asks a full week for the whole target', () {
      expect(
        roomQuotaWeekTarget(
          target: 4,
          day: DateTime(2026, 10, 7),
          firstDay: DateTime(2026, 9),
        ),
        4,
      );
    });

    test('times of day do not move a day in or out', () {
      // Joined at 13:00 on the Sunday; a stored end at midnight.
      expect(
        roomQuotaWeekTarget(
          target: 4,
          day: DateTime(2026, 9, 30, 18),
          firstDay: DateTime(2026, 9, 27, 13),
          lastDay: DateTime(2026, 10, 26),
        ),
        3,
      );
    });

    test('a week before 26 September keeps the whole target', () {
      // A room started on Sunday 20 September: six days of the week of the
      // 19th, graded before the share existed, stay at 4.
      expect(
        roomQuotaWeekTarget(
          target: 4,
          day: DateTime(2026, 9, 22),
          firstDay: DateTime(2026, 9, 20),
        ),
        4,
      );
      // The week of the 26th is the first with a share.
      expect(
        roomQuotaWeekTarget(
          target: 4,
          day: DateTime(2026, 9, 29),
          firstDay: DateTime(2026, 9, 27),
        ),
        3,
      );
    });

    test('F8HQKE asks 3, 4, 4, 4, 2: 17 sessions where the cap asked 19', () {
      final weeks = [
        for (var w = 0; w < 5; w++)
          roomQuotaWeekTarget(
            target: 4,
            day: DateTime(2026, 9, 26 + 7 * w),
            firstDay: DateTime(2026, 9, 27),
            lastDay: DateTime(2026, 10, 26),
          ),
      ];
      expect(weeks, [3, 4, 4, 4, 2]);
      expect(weeks.reduce((a, b) => a + b), 17);
    });
  });

  group('the grader', () {
    test(
        "F8HQKE's first week: three sessions in its six days meet it, and "
        'Wednesday to Friday rest', () async {
      final p = await _live(
        _business(),
        joined: DateTime(2026, 9, 27, 10),
        from: '2026-09-27',
        to: '2026-10-02',
        sessions: const {'2026-09-27', '2026-09-28', '2026-09-29'},
        closeAt: DateTime(2026, 10, 3, 11),
      );
      for (final k in ['2026-09-27', '2026-09-28', '2026-09-29']) {
        expect(_at(p, k), (1, 1), reason: k);
      }
      // Under the old cap the week asked 4 and Friday was a miss, (1, 0).
      for (final k in ['2026-09-30', '2026-10-01', '2026-10-02']) {
        expect(_at(p, k), (0, 0), reason: k);
        expect(p.isRestDay(k), isTrue, reason: k);
      }
      expect(p.quotaOkWeeks, contains('2026-09-26'));
    });

    test('a first week still in progress is never handed a rest day early',
        () async {
      // Sunday and Monday done, then Tuesday and Wednesday blank, graded on
      // Wednesday night: 2 of 3, so every day so far is still asked.
      final p = await _live(
        _business(),
        joined: DateTime(2026, 9, 27, 10),
        from: '2026-09-27',
        to: '2026-09-30',
        sessions: const {'2026-09-27', '2026-09-28'},
        closeAt: DateTime(2026, 9, 30, 23),
      );
      expect(_at(p, '2026-09-29'), (1, 0));
      expect(_at(p, '2026-09-30'), (1, 0));
      expect(p.isRestDay('2026-09-29'), isFalse);
      expect(p.quotaOkWeeks, isNot(contains('2026-09-26')));
    });

    test(
        "F8HQKE's last week: Saturday and Sunday meet its three days, and "
        'Monday rests', () async {
      final p = await _live(
        _business(),
        joined: DateTime(2026, 9, 27, 10),
        from: '2026-10-24',
        to: '2026-10-26',
        sessions: const {'2026-10-24', '2026-10-25'},
        // Monday 26 October closes at 10:00 on the 27th; the room has ended.
        closeAt: DateTime(2026, 10, 27, 11),
      );
      expect(_at(p, '2026-10-24'), (1, 1));
      expect(_at(p, '2026-10-25'), (1, 1));
      // Under the old cap the week asked all three days: (1, 0), a miss.
      expect(_at(p, '2026-10-26'), (0, 0));
      expect(p.isRestDay('2026-10-26'), isTrue);
      expect(p.quotaOkWeeks, contains('2026-10-24'));
    });

    test('a week before 26 September keeps the whole target', () async {
      // A room started on Sunday 20 September, three sessions in its first
      // six days: the week asked 4, so it closed one short and its Friday,
      // the last day it could have been made, is the miss. With a share it
      // would have been met.
      final p = await _live(
        _business(start: DateTime(2026, 9, 20), end: DateTime(2026, 10, 19)),
        joined: DateTime(2026, 9, 20, 10),
        from: '2026-09-20',
        to: '2026-09-25',
        sessions: const {'2026-09-20', '2026-09-21', '2026-09-22'},
        closeAt: DateTime(2026, 9, 26, 11),
      );
      expect(_at(p, '2026-09-23'), (0, 0));
      expect(_at(p, '2026-09-24'), (0, 0));
      expect(_at(p, '2026-09-25'), (1, 0));
      expect(p.quotaOkWeeks, isNot(contains('2026-09-19')));
    });

    test('a habit added to the plan on a Tuesday asks its share of the four '
        'days left', () async {
      // Its four days that week ask 2, not 4.
      final p = await _live(
        _addedOnTuesday(),
        joined: DateTime(2026, 9, 1, 10),
        habits: [_dhikr, _gym],
        ids: const ['dhikr', 'gym'],
        from: '2026-09-26',
        to: '2026-10-02',
        sessions: {..._dhikrAllWeek, 'gym/2026-09-29', 'gym/2026-09-30'},
        closeAt: DateTime(2026, 10, 3, 11),
      );
      expect(p.habitRules['gym']!.first.from, '2026-09-29');
      expect(p.dailyHabitMarks['2026-09-29']!['gym'], RoomHabitMark.done);
      expect(p.dailyHabitMarks['2026-09-30']!['gym'], RoomHabitMark.done);
      // Under the old cap both were owed and missed.
      expect(p.dailyHabitMarks['2026-10-01']!['gym'], RoomHabitMark.rest);
      expect(p.dailyHabitMarks['2026-10-02']!['gym'], RoomHabitMark.rest);
      expect(_at(p, '2026-10-01'), (1, 1));
      expect(p.quotaOkWeeks, contains('2026-09-26'));
    });

    test('sessions from before the habit joined the plan do not meet its '
        'share', () async {
      // تمرين done on the Saturday and Sunday, before the leader added it,
      // and not once after. Its four days ask 2 and got none: Thursday and
      // Friday are the misses, and the week does not hold. The streak pass
      // used to count the Saturday and the Sunday toward those 2.
      final p = await _live(
        _addedOnTuesday(),
        joined: DateTime(2026, 9, 1, 10),
        habits: [_dhikr, _gym],
        ids: const ['dhikr', 'gym'],
        from: '2026-09-26',
        to: '2026-10-02',
        sessions: {..._dhikrAllWeek, 'gym/2026-09-26', 'gym/2026-09-27'},
        closeAt: DateTime(2026, 10, 3, 11),
      );
      expect(p.dailyHabitMarks['2026-09-26']!['gym'], isNull);
      expect(p.dailyHabitMarks['2026-09-29']!['gym'], RoomHabitMark.rest);
      expect(p.dailyHabitMarks['2026-09-30']!['gym'], RoomHabitMark.rest);
      expect(p.dailyHabitMarks['2026-10-01']!['gym'], RoomHabitMark.missed);
      expect(p.dailyHabitMarks['2026-10-02']!['gym'], RoomHabitMark.missed);
      expect(p.quotaOkWeeks, isNot(contains('2026-09-26')));
    });

    test(
        'a member who took only the added habit is asked it all week, so its '
        'whole target', () async {
      // أذكار declined at join, تمرين linked when it was added on Tuesday.
      // The grader asks it from the member's first day (joinedPlanBy, before
      // the earliest floor every habit counts), so the week is seven days
      // and 4, not four days and 2: Saturday and Sunday alone do not meet it.
      final p = await _live(
        _addedOnTuesday(),
        joined: DateTime(2026, 9, 1, 10),
        ids: const [kDeclinedSlot, 'gym'],
        from: '2026-09-26',
        to: '2026-10-02',
        sessions: const {'gym/2026-09-26', 'gym/2026-09-27'},
        closeAt: DateTime(2026, 10, 3, 11),
      );
      expect(p.dailyHabitMarks['2026-09-26']!['gym'], RoomHabitMark.done);
      expect(p.dailyHabitMarks['2026-10-01']!['gym'], RoomHabitMark.missed);
      expect(p.dailyHabitMarks['2026-10-02']!['gym'], RoomHabitMark.missed);
      expect(p.quotaOkWeeks, isNot(contains('2026-09-26')));
      // The plan card holds the week to the same 4.
      final s = roomQuotaWeekStanding(
        room: _addedOnTuesday(),
        participant: p,
        slot: 1,
        weekDays: [for (var d = 0; d < 7; d++) DateTime(2026, 9, 26 + d)],
        isDone: (_) => false,
        isHalf: (_) => false,
        target: 4,
        today: DateTime(2026, 10),
      )!;
      expect(s.target, 4);
    });
  });

  group('what the screens draw', () {
    final room = _business();
    RoomParticipant member({
      Map<String, int> done = const {},
      Map<String, Map<String, RoomHabitMark>> marks = const {},
    }) =>
        RoomParticipant(
          uid: 'M',
          displayName: 'M',
          characterId: 'male_ghutra_blue',
          joinedAt: DateTime(2026, 9, 27, 10),
          linkedHabitIds: const ['gym'],
          linkedHabitNames: const ['تمرين'],
          habitRules: const {
            'gym': [
              RoomHabitRule(
                from: '2026-09-27',
                frequencyType: HabitFrequencyType.weekly,
                frequencyTarget: 4,
              ),
            ],
          },
          dailyDoneCount: done,
          dailyScheduledCount: {
            for (var d = 27; d <= 30; d++) '2026-09-$d': 1,
            '2026-10-01': 1,
            '2026-10-02': 1,
          },
          dailyHabitMarks: marks,
          lastUpdated: DateTime(2026, 10, 2),
        );

    test('the last week is not lost for having three days for four', () {
      final p = member();
      // Saturday 24 October, nothing done yet: three days for two.
      expect(
        p.quotaWeekIsLost('2026-10-24', room, now: DateTime(2026, 10, 24, 11)),
        isFalse,
      );
      // Saturday gone blank: Sunday and Monday still make two.
      expect(
        p.quotaWeekIsLost('2026-10-24', room, now: DateTime(2026, 10, 25, 11)),
        isFalse,
      );
      // Saturday and Sunday gone blank: Monday alone cannot.
      expect(
        p.quotaWeekIsLost('2026-10-24', room, now: DateTime(2026, 10, 26, 11)),
        isTrue,
      );
    });

    test(
        'the strip owes only Friday of a first week at 2 of 3 by Monday, '
        'Thursday is spare', () {
      final p = member(done: const {'2026-09-27': 1, '2026-09-28': 1});
      expect(
        roomStripQuotaDemandOn(room, p, DateTime(2026, 10)),
        DayDemand.spare,
      );
      expect(
        roomStripQuotaDemandOn(room, p, DateTime(2026, 10, 2)),
        DayDemand.owed,
      );
    });

    test('the habit strip crosses Friday and leaves Thursday plain', () {
      final p = member(
        // The counts the marks must agree with (habitMarksFor).
        done: const {'2026-09-27': 1, '2026-09-28': 1},
        marks: {
          '2026-09-27': const {'gym': RoomHabitMark.done},
          '2026-09-28': const {'gym': RoomHabitMark.done},
          for (final k in [
            '2026-09-29',
            '2026-09-30',
            '2026-10-01',
            '2026-10-02',
          ])
            k: const {'gym': RoomHabitMark.missed},
        },
      );
      final closed = DateTime(2026, 10, 3, 12);
      expect(
        roomStripSlotDayOf(room, p, 0, DateTime(2026, 10), now: closed)
            .isMissed,
        isFalse,
      );
      expect(
        roomStripSlotDayOf(room, p, 0, DateTime(2026, 10, 2), now: closed)
            .isMissed,
        isTrue,
      );
    });

    test('the plan card reads 0 of 2 for a habit added on Tuesday', () {
      final added = _addedOnTuesday();
      final p = RoomParticipant(
        uid: 'M',
        displayName: 'M',
        characterId: 'male_ghutra_blue',
        joinedAt: DateTime(2026, 9, 1, 10),
        linkedHabitIds: const ['dhikr', 'gym'],
        linkedHabitNames: const ['أذكار', 'تمرين'],
        habitRules: const {
          'dhikr': [
            RoomHabitRule(
              from: '2026-09-01',
              frequencyType: HabitFrequencyType.daily,
              frequencyTarget: 1,
            ),
          ],
          // As the sync seeds it: from the day the slot joined the plan.
          'gym': [
            RoomHabitRule(
              from: '2026-09-29',
              frequencyType: HabitFrequencyType.weekly,
              frequencyTarget: 4,
            ),
          ],
        },
        lastUpdated: DateTime(2026, 9, 29),
      );
      final s = roomQuotaWeekStanding(
        room: added,
        participant: p,
        slot: 1,
        weekDays: [for (var d = 0; d < 7; d++) DateTime(2026, 9, 26 + d)],
        isDone: (_) => false,
        isHalf: (_) => false,
        target: 4,
        today: DateTime(2026, 9, 29),
      )!;
      expect(s.target, 2);
      expect(s.done, 0);
      // Two in Tuesday to Friday: two to spare.
      expect(s.neededToday, isFalse);
    });
  });

  group('the plan card, the weeks room_quota_week_test.dart pins without it',
      () {
    // The Grid week of Saturday 26 September to Friday 2 October, تمرين
    // done on the Saturday.
    final week = [for (var d = 0; d < 7; d++) DateTime(2026, 9, 26 + d)];
    RoomParticipant aziz({DateTime? joined}) => RoomParticipant(
          uid: 'aziz',
          displayName: 'Aziz',
          characterId: 'male_ghutra_blue',
          joinedAt: joined ?? DateTime(2026, 8),
          linkedHabitIds: const ['tamreen'],
          habitRules: const {
            'tamreen': [
              RoomHabitRule(
                from: '2026-08-01',
                frequencyType: HabitFrequencyType.weekly,
                frequencyTarget: 4,
              ),
            ],
          },
          lastUpdated: DateTime(2026, 9, 27),
        );
    ({double done, int target, bool neededToday}) standing(
      RoomModel room,
      RoomParticipant p,
      DateTime today,
    ) =>
        roomQuotaWeekStanding(
          room: room,
          participant: p,
          slot: 0,
          weekDays: week,
          isDone: (d) => d.month == 9 && d.day == 26,
          isHalf: (_) => false,
          target: 4,
          today: today,
        )!;

    test(
        "F8HQKE's six days ask 3: with nothing done, Tuesday still has one to "
        'spare and Wednesday is needed', () {
      final room = _business();
      final p = aziz(joined: DateTime(2026, 9, 27, 13));
      final sunday = standing(room, p, DateTime(2026, 9, 27));
      // Saturday's session is not the room's.
      expect(sunday.done, 0);
      expect(sunday.target, 3);
      expect(sunday.neededToday, isFalse);
      expect(standing(room, p, DateTime(2026, 9, 29)).neededToday, isFalse);
      expect(standing(room, p, DateTime(2026, 9, 30)).neededToday, isTrue);
    });

    test(
        "«Being Better»'s last five days ask 3: after a blank Sunday and "
        'Monday, Tuesday is needed', () {
      final room =
          _business(start: DateTime(2026, 9), end: DateTime(2026, 9, 30));
      final sunday = standing(room, aziz(), DateTime(2026, 9, 27));
      expect(sunday.done, 1);
      expect(sunday.target, 3);
      expect(sunday.neededToday, isFalse);
      final monday = standing(room, aziz(), DateTime(2026, 9, 28));
      expect(monday.neededToday, isFalse);
      final tuesday = standing(room, aziz(), DateTime(2026, 9, 29));
      expect(tuesday.neededToday, isTrue);
    });

    test('a room with three days that week asks two, its share of four', () {
      final room =
          _business(start: DateTime(2026, 9), end: DateTime(2026, 9, 28));
      expect(standing(room, aziz(), DateTime(2026, 9, 27)).target, 2);
    });
  });
}
