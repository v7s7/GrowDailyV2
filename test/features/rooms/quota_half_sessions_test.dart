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

/// What the week is worth and what it asked, in days, as the room reads it:
/// the weights where a day carries them (a shared half asks half a day), the
/// counts everywhere else.
(double, double) _score(RoomParticipant p) {
  var credit = 0.0;
  var asked = 0.0;
  for (var d = 19; d <= 25; d++) {
    if (p.isRestDay(_k(d))) continue;
    asked += p.scheduledWeightFor(_k(d));
    credit += p.doneWeightFor(_k(d));
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
    expect(_score(p), (1.0, 4.0));
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
    expect(_score(p), (4.0, 4.0));
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
    expect(_score(p), (3.0, 4.0));
    // Its places are held, but not in full: not a week the streak may keep.
    expect(p.quotaOkWeeks, isNot(contains(_k(19))));
  });

  test(
      'three whole and two halves add up to 4 of 4: both half days count, '
      'each asking half a day', () async {
    // Aziz, 2026-10-03: "make halves add up, 3 + 0.5 + 0.5 = 4". It read
    // 3.5, with the later half graded as a rest.
    final p = await _liveWeek({
      19: half,
      20: half,
      21: whole,
      22: whole,
      23: whole,
    });
    expect(_week(p)[_k(19)], (1, 0, 1));
    expect(_week(p)[_k(20)], (1, 0, 1),
        reason: 'a day he trained is never a rest');
    for (final d in [19, 20]) {
      expect(p.sharedHalfCountFor(_k(d)), 1);
      expect(p.scheduledWeightFor(_k(d)), 0.5);
      expect(p.doneWeightFor(_k(d)), 0.5);
      expect(p.creditFor(_k(d)), 1.0);
      expect(p.isFullyDone(_k(d)), isTrue,
          reason: 'finished for its share, so it keeps the streak');
    }
    expect(_score(p), (4.0, 4.0));
    expect(p.quotaOkWeeks, contains(_k(19)), reason: 'the week held');
  });

  test(
      "Aziz's 26 September, played as it happened: W W - ½ ½ W - is 4 of 4, "
      'the Monday and the Friday rest', () async {
    // Sat whole, Sun whole, Mon nothing, Tue half, Wed half, Thu whole,
    // Fri nothing, each synced the night it happened.
    final p = await _liveWeek({
      19: whole,
      20: whole,
      22: half,
      23: half,
      24: whole,
    });
    expect(_week(p), {
      _k(19): (1, 1, 0),
      _k(20): (1, 1, 0),
      _k(21): (0, 0, 0),
      _k(22): (1, 0, 1),
      _k(23): (1, 0, 1),
      _k(24): (1, 1, 0),
      _k(25): (0, 0, 0),
    });
    expect(_score(p), (4.0, 4.0));
    expect(p.isRestDay(_k(21)), isTrue);
    expect(p.isRestDay(_k(25)), isTrue);
    expect(p.isRestDay(_k(23)), isFalse, reason: 'he trained on the 30th');
    expect(p.quotaOkWeeks, contains(_k(19)));
  });

  test('two whole and three halves: one half keeps a whole place, two share',
      () async {
    // 2 + 0.5 x 3 = 3.5 of 4, exactly: the earliest half asks a whole day
    // and gets half, the two later ones share the last place.
    final p = await _liveWeek({
      19: whole,
      20: whole,
      21: half,
      22: half,
      23: half,
    });
    expect(p.sharedHalfCountFor(_k(21)), 0);
    expect(p.sharedHalfCountFor(_k(22)), 1);
    expect(p.sharedHalfCountFor(_k(23)), 1);
    expect(_score(p), (3.5, 4.0));
    expect(p.quotaOkWeeks, isNot(contains(_k(19))), reason: 'short of 4');
  });

  test('halves late in the week count the same as halves early in it',
      () async {
    // Where a half falls no longer decides what it is worth. The halves on
    // Thursday and Friday were worth 0.5 each before this too; the ones on
    // Saturday and Sunday were worth nothing.
    final early = await _liveWeek({19: half, 20: half});
    final late = await _liveWeek({24: half, 25: half});
    expect(_score(early), (1.0, 4.0));
    expect(_score(late), (1.0, 4.0));
  });

  test('a week with nothing in it is still 0 of 4 on its last four days',
      () async {
    final p = await _liveWeek(const {});
    expect(_score(p), (0.0, 4.0));
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
      // Halves add up: both share the place the three wholes left.
      expect(answerable({2, 3, 4}, {0, 1}), [0, 1, 2, 3, 4]);
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
    RoomParticipant stored(
      Map<String, int> partial, {
      Map<String, int> done = const {},
      String? lastSyncedDay,
      DateTime? lastSyncedAt,
    }) =>
        RoomParticipant(
          uid: 'M',
          displayName: 'M',
          characterId: 'male_ghutra_blue',
          joinedAt: DateTime(2026, 9, 18),
          linkedHabitIds: const ['gym'],
          linkedHabitNames: const ['تمرين'],
          lastUpdated: DateTime(2026, 9, 18),
          dailyPartialCount: partial,
          dailyDoneCount: done,
          lastSyncedDay: lastSyncedDay,
          lastSyncedAt: lastSyncedAt,
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
      // never graded. The halves hold all four places, so the phone rests
      // those days the moment the fourth lands, and the record says so
      // without it: rest, never misses.
      final p = stored({_k(19): 1, _k(20): 1, _k(21): 1, _k(22): 1});
      final now = DateTime(2026, 9, 26, 11);
      for (final d in [23, 24, 25]) {
        expect(p.scheduledCountFor(_k(d)), 0, reason: '$d');
        expect(
          roomStripDayOf(_room(), p, DateTime(2026, 9, d), now: now).look,
          RoomStripDayLook.rest,
          reason: '$d is a rest day of a week its halves filled',
        );
      }
    });

    test(
        'two whole sessions and two halves hold every place, worth 3: the '
        "days after the last sync rest on other members' boards", () {
      // A week that holds its four places and is worth 3 never reaches
      // quotaOkWeeks, so before this the days the phone had not graded yet
      // fell back to due, and the strip crossed them out once the week
      // closed. The phone itself rests them (weeklyQuotaScheduledDays).
      final p = stored(
        {_k(21): 1, _k(22): 1},
        done: {_k(19): 1, _k(20): 1},
        lastSyncedDay: _k(22),
        lastSyncedAt: DateTime(2026, 9, 22, 21),
      );
      final now = DateTime(2026, 9, 26, 11);
      expect(p.quotaOkWeeks, isEmpty);
      for (final d in [23, 24, 25]) {
        expect(p.scheduledCountFor(_k(d)), 0, reason: '$d');
        final look =
            roomStripDayOf(_room(), p, DateTime(2026, 9, d), now: now).look;
        expect(look, RoomStripDayLook.rest, reason: '$d');
      }
      // The week reads what it is worth: 3 of 4.
      var credit = 0.0;
      var asked = 0.0;
      for (var d = 19; d <= 25; d++) {
        if (p.isRestDay(_k(d))) continue;
        asked += p.scheduledWeightFor(_k(d));
        credit += p.doneWeightFor(_k(d));
      }
      expect((credit, asked), (3.0, 4.0));
    });

    test('three sessions are not every place: the unsynced days stay due',
        () {
      final p = stored(
        {_k(21): 1},
        done: {_k(19): 1, _k(20): 1},
        lastSyncedDay: _k(21),
        lastSyncedAt: DateTime(2026, 9, 21, 21),
      );
      for (final d in [22, 23, 24, 25]) {
        expect(p.scheduledCountFor(_k(d)), 1, reason: '$d');
      }
    });

    test(
        'a closed week of two halves, unsynced since Monday, is graded on '
        "other members' boards as the phone grades it: 1 of 4", () {
      // Halves on Saturday and Sunday, a sync on Monday evening, and then
      // nothing. The phone's close rests Monday to Wednesday and owes
      // Thursday and Friday; the board used to keep all five due until the
      // phone came back, because a stored half stopped the inference.
      final p = stored(
        {_k(19): 1, _k(20): 1},
        lastSyncedDay: _k(21),
        lastSyncedAt: DateTime(2026, 9, 21, 20),
      );
      final now = DateTime(2026, 9, 28, 12);
      expect(p.closedQuotaWeekInference(_room(), now: now), {
        _k(21): 0,
        _k(22): 0,
        _k(23): 0,
      });
      final graded = p.withClosedQuotaWeeksInferred(_room(), now: now);
      var credit = 0.0;
      var asked = 0.0;
      for (var d = 19; d <= 25; d++) {
        if (graded.isRestDay(_k(d))) continue;
        asked += graded.scheduledWeightFor(_k(d));
        credit += graded.doneWeightFor(_k(d));
      }
      expect((credit, asked), (1.0, 4.0));
      for (final d in [24, 25]) {
        expect(
          roomStripDayOf(_room(), graded, DateTime(2026, 9, d), now: now).look,
          RoomStripDayLook.missed,
          reason: '$d is owed',
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
