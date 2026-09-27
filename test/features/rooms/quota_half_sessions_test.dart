// A جزئي on a flexible weekly quota is a session that holds one of the week's
// places at half credit, and whole sessions take the places first. Aziz,
// 2026-09-26, on his own week of 19 September: "0.5 is a day count, unless
// it's overwritten with a full day". Driven through the real grader
// (RoomsController.syncLinkedHabitsProgress) on a fake Firestore, one member,
// تمرين four times a week, the week Saturday 19 to Friday 25 September.
//
// Before this, the grader read a half as an empty day when it chose which
// days of a closed short week were owed, so the week put its misses on its
// four LAST days and excused the two halves as rest: his real week scored
// 0 of 4 in both rooms, where it is 1 of 4.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/models/weekly_quota_plan.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_strip_day.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';

import 'room_sync_harness.dart';

String _k(int d) => '2026-09-${d.toString().padLeft(2, '0')}';

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
  createdAt: DateTime(2026, 9),
);

RoomModel _room() => RoomModel(
      code: 'HALF01',
      name: 'half',
      createdBy: 'L',
      createdByName: 'Leader',
      createdAt: DateTime(2026, 9, 18),
      habitMode: RoomHabitMode.shared,
      duration: RoomDuration.fixed,
      // Saturday: the room's first week is exactly the week under test.
      startDate: DateTime(2026, 9, 19),
      endDate: DateTime(2026, 10, 30),
      sharedHabits: const [
        RoomHabitTemplate(
          name: 'تمرين',
          category: HabitCategory.custom,
          frequencyType: HabitFrequencyType.weekly,
          frequencyTarget: 4,
        ),
      ],
    );

RoomParticipant _member() => RoomParticipant(
      uid: 'M',
      displayName: 'M',
      characterId: 'male_ghutra_blue',
      joinedAt: DateTime(2026, 9, 18),
      linkedHabitIds: const ['gym'],
      linkedHabitNames: const ['تمرين'],
      lastUpdated: DateTime(2026, 9, 18),
    );

/// One week lived the way a phone lives it: each mark stored the evening of
/// its own day, the room synced every night, and once more the Saturday
/// morning after the week has closed (10:00, see isQuotaWeekClosed).
Future<RoomParticipant> _liveWeek(Map<int, SquareState> marks) async {
  final h = RoomSyncHarness(room: _room(), uid: 'M', habits: [_gym]);
  addTearDown(h.dispose);
  await h.createRoom();
  await h.join(_member());
  for (var d = 19; d <= 25; d++) {
    final mark = marks[d];
    if (mark != null) {
      await h.mark(_k(d), 'gym', mark, DateTime(2026, 9, d, 21));
    }
    await h.syncAt(DateTime(2026, 9, d, 22));
  }
  await h.syncAt(DateTime(2026, 9, 26, 11));
  return h.member();
}

/// (asked, whole, half) for each day of the week, as stored.
Map<String, (int, int, int)> _week(RoomParticipant p) => {
      for (var d = 19; d <= 25; d++)
        _k(d): (
          p.scheduledCountFor(_k(d)),
          p.dailyDoneCount[_k(d)] ?? 0,
          p.partialCountFor(_k(d)),
        ),
    };

/// What the week is worth and what it asked, in days, from the stored
/// counts: the sum over the days it asked for.
(double, int) _score(RoomParticipant p) {
  var credit = 0.0;
  var asked = 0;
  for (var d = 19; d <= 25; d++) {
    if (p.isRestDay(_k(d))) continue;
    asked += p.scheduledCountFor(_k(d));
    credit += p.creditFor(_k(d)) * p.scheduledCountFor(_k(d));
  }
  return (credit, asked);
}

void main() {
  setUpAll(initHarnessHive);

  const half = SquareState.partial;
  const whole = SquareState.complete;

  test(
      "Aziz's week: two halves then nothing is 1 of 4, with three rest days "
      'and the last two missed', () async {
    final p = await _liveWeek({19: half, 20: half});
    expect(_week(p), {
      _k(19): (1, 0, 1),
      _k(20): (1, 0, 1),
      _k(21): (0, 0, 0),
      _k(22): (0, 0, 0),
      _k(23): (0, 0, 0),
      _k(24): (1, 0, 0),
      _k(25): (1, 0, 0),
    });
    expect(_score(p), (1.0, 4));
    expect(p.creditFor(_k(19)), 0.5);
    for (final d in [21, 22, 23]) {
      expect(p.isRestDay(_k(d)), isTrue, reason: '$d is a rest day');
    }
    // The dots on the strip: the same three rest days, the same two misses.
    final room = _room();
    final now = DateTime(2026, 9, 26, 11);
    for (final d in [24, 25]) {
      expect(
        roomStripMissIsFinal(room, p, DateTime(2026, 9, d), now: now),
        isTrue,
        reason: '$d is crossed out',
      );
    }
  });

  test('two halves then four whole sessions counts the whole ones: 4 of 4',
      () async {
    final p = await _liveWeek({
      19: half,
      20: half,
      21: whole,
      22: whole,
      23: whole,
      24: whole,
    });
    expect(_week(p), {
      _k(19): (0, 0, 0),
      _k(20): (0, 0, 0),
      _k(21): (1, 1, 0),
      _k(22): (1, 1, 0),
      _k(23): (1, 1, 0),
      _k(24): (1, 1, 0),
      _k(25): (0, 0, 0),
    });
    expect(_score(p), (4.0, 4));
    // Met in full, so the week is banked for the streak.
    expect(p.quotaOkWeeks, contains(_k(19)));
  });

  test('two whole sessions and two halves is 3 of 4, the rest rest', () async {
    final p = await _liveWeek({19: whole, 20: whole, 21: half, 22: half});
    expect(_week(p), {
      _k(19): (1, 1, 0),
      _k(20): (1, 1, 0),
      _k(21): (1, 0, 1),
      _k(22): (1, 0, 1),
      _k(23): (0, 0, 0),
      _k(24): (0, 0, 0),
      _k(25): (0, 0, 0),
    });
    expect(_score(p), (3.0, 4));
    // Its places are held, but not in full: not a week the streak may keep.
    expect(p.quotaOkWeeks, isNot(contains(_k(19))));
  });

  test('three whole and two halves: the earlier half keeps the last place',
      () async {
    final p = await _liveWeek({
      19: half,
      20: half,
      21: whole,
      22: whole,
      23: whole,
    });
    expect(_week(p)[_k(19)], (1, 0, 1));
    expect(_week(p)[_k(20)], (0, 0, 0), reason: 'no place left for it');
    expect(_score(p), (3.5, 4));
  });

  test('halves late in the week count the same as halves early in it',
      () async {
    // Where a half falls no longer decides what it is worth. The halves on
    // Thursday and Friday were worth 0.5 each before this too; the ones on
    // Saturday and Sunday were worth nothing.
    final early = await _liveWeek({19: half, 20: half});
    final late = await _liveWeek({24: half, 25: half});
    expect(_score(early), (1.0, 4));
    expect(_score(late), (1.0, 4));
  });

  test('a week with nothing in it is still 0 of 4 on its last four days',
      () async {
    final p = await _liveWeek(const {});
    expect(_score(p), (0.0, 4));
    for (final d in [19, 20, 21]) {
      expect(p.isRestDay(_k(d)), isTrue);
    }
  });

  group('weeklyQuotaScheduledDays with halves', () {
    List<int> answerable(
      Set<int> whole,
      Set<int> half, {
      bool closed = true,
    }) =>
        weeklyQuotaScheduledDays(
          presentDays: const [0, 1, 2, 3, 4, 5, 6],
          doneDays: whole,
          halfDays: half,
          target: 4,
          isWeekClosed: closed,
        );

    test('the places, once every place is held', () {
      expect(answerable({2, 3, 4, 5}, {0, 1}), [2, 3, 4, 5]);
      expect(answerable({0, 1}, {2, 3}), [0, 1, 2, 3]);
      expect(answerable({2, 3, 4}, {0, 1}), [0, 2, 3, 4]);
      // A week held by halves alone rests its other days at once, open or
      // closed: nothing more is asked of it, and it can still rise.
      expect(answerable({}, {0, 1, 2, 3}, closed: false), [0, 1, 2, 3]);
    });

    test('a closed short week: the sessions and its owed days', () {
      expect(answerable({}, {0, 1}), [0, 1, 5, 6]);
      expect(answerable({}, {5, 6}), [3, 4, 5, 6]);
    });

    test('an open short week still counts every day so far', () {
      expect(answerable({}, {0, 1}, closed: false), [0, 1, 2, 3, 4, 5, 6]);
    });

    test('without halves, exactly as before', () {
      expect(answerable({0, 2, 3, 5, 6}, {}), [0, 2, 3, 5]);
      expect(answerable({1, 3}, {}), [1, 3, 5, 6]);
    });
  });

  group('the strip reads a stored half as a session', () {
    RoomParticipant stored(Map<String, int> partial) => RoomParticipant(
          uid: 'M',
          displayName: 'M',
          characterId: 'male_ghutra_blue',
          joinedAt: DateTime(2026, 9, 18),
          linkedHabitIds: const ['gym'],
          linkedHabitNames: const ['تمرين'],
          lastUpdated: DateTime(2026, 9, 18),
          dailyPartialCount: partial,
          habitRules: {
            'gym': [
              RoomHabitRule(
                from: _k(19),
                frequencyType: HabitFrequencyType.weekly,
                frequencyTarget: 4,
              ),
            ],
          },
        );

    test('two halves by Sunday: the week is not lost on Tuesday', () {
      final p = stored({_k(19): 1, _k(20): 1});
      // Wednesday 23rd, 11:00: Monday and Tuesday are closed and blank.
      // Two halves held, and Wednesday to Friday can still hold the other
      // two sessions, so nothing may be crossed out yet.
      expect(
        p.quotaWeekIsLost(_k(22), _room(), now: DateTime(2026, 9, 23, 11)),
        isFalse,
      );
      // Saturday the 25th's close would have been the answer with the halves
      // read as blank: lost since Tuesday.
      final blank = stored(const {});
      expect(
        blank.quotaWeekIsLost(_k(22), _room(), now: DateTime(2026, 9, 23, 11)),
        isTrue,
      );
    });

    test(
        "a week its halves filled is not crossed out on other members' boards "
        'before the member syncs again', () {
      // Halves Saturday to Tuesday, each synced while the week was open, and
      // then nothing from this member's phone: Wednesday to Friday were
      // never graded, so the record still has them as due. The halves hold
      // all four places, so those days are rest (earned), never misses.
      final p = stored({_k(19): 1, _k(20): 1, _k(21): 1, _k(22): 1});
      final now = DateTime(2026, 9, 26, 11);
      for (final d in [23, 24, 25]) {
        expect(
          roomStripQuotaDemandOn(_room(), p, DateTime(2026, 9, d)),
          DayDemand.earned,
        );
        expect(
          roomStripMissIsFinal(_room(), p, DateTime(2026, 9, d), now: now),
          isFalse,
          reason: '$d is a rest day of a week its halves filled',
        );
      }
    });

    test('its owed days are the last two, and the three between are spare',
        () {
      final p = stored({_k(19): 1, _k(20): 1});
      final demand = [
        for (var d = 19; d <= 25; d++)
          roomStripQuotaDemandOn(_room(), p, DateTime(2026, 9, d)),
      ];
      expect(demand, [
        DayDemand.half,
        DayDemand.half,
        DayDemand.spare,
        DayDemand.spare,
        DayDemand.spare,
        DayDemand.owed,
        DayDemand.owed,
      ]);
    });
  });
}
