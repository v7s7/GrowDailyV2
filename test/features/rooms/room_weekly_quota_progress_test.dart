// Deterministic tests for the two Rooms grading bugs that made a
// weekly-quota habit ("N times a week, any days") read as permanently
// behind, written after a real user report: تمرين, done faithfully, showed
// 3 of 16 days in its room while the Grid showed six green squares in the
// same window.
//
// Two independent causes, both covered here:
//
//  1. Grading counted EVERY day of the week against a weekly-quota habit,
//     because a habit like this has no specific weekdays for the weekday
//     check to rule any day out with. "4x a week" done exactly 4 times
//     scored 4/7 = 57% by construction, while the identical commitment
//     written as four NAMED weekdays scored 100%. See
//     [weeklyQuotaScheduledDays].
//
//  2. The anti-backdating clamp capped a past day at whatever the room had
//     already recorded for it - which is only a fair test on the days a sync
//     actually ran. Every day spent with the app closed, offline, or with a
//     fire-and-forget sync that quietly failed was capped at 0 permanently,
//     with no way to ever recover it. See [RoomParticipant.lastSyncedDay].
//
// Pure model/function tests - no Firestore, no widgets. Every date is a
// fixed calendar date (the reporter's own week: Sat 1 Aug 2026 through Fri 7
// Aug 2026, which really is a Saturday-start grid week) so nothing here
// depends on when the suite happens to run.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';

/// The reporter's week: Saturday 1 Aug 2026 .. Friday 7 Aug 2026.
final _weekDays = List.generate(7, (i) => DateTime(2026, 8, 1 + i));

RoomModel _room({required DateTime start, required DateTime end}) => RoomModel(
      code: 'TEST01',
      name: 'Test Room',
      createdBy: 'leader-uid',
      createdByName: 'Leader',
      createdAt: start,
      habitMode: RoomHabitMode.own,
      duration: RoomDuration.fixed,
      startDate: start,
      endDate: end,
    );

RoomParticipant _participant({
  Map<String, int> dailyDoneCount = const {},
  Map<String, int> dailyScheduledCount = const {},
  String? lastSyncedDay,
}) =>
    RoomParticipant(
      uid: 'member-uid',
      displayName: 'Aziz',
      characterId: 'male_ghutra_blue',
      joinedAt: DateTime(2026, 7, 28),
      linkedHabitIds: const ['h1'],
      dailyDoneCount: dailyDoneCount,
      dailyScheduledCount: dailyScheduledCount,
      lastSyncedDay: lastSyncedDay,
      lastUpdated: DateTime(2026, 8, 12),
    );

/// A habit whose weekday list is exactly [weekdays] - the "named days" way of
/// expressing the same commitment a weekly quota expresses flexibly. Used to
/// pin the two against each other, since scoring them differently for the
/// same number of completions is the whole bug.
IslamicHabitTemplate _namedDaysHabit(List<int> weekdays) =>
    IslamicHabitTemplate(
      id: 'h1',
      name: 'Training',
      description: '',
      category: HabitCategory.fitness,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      scheduledWeekdays: weekdays,
      hasTimer: false,
      xpReward: 10,
      goldReward: 5,
    );

/// Turns one weekly-quota habit's graded week into the sparse per-day maps
/// [RoomsController.syncLinkedHabitsProgress] would store for it, so these
/// tests measure the real scoring end to end rather than hand-picked
/// numbers. Deliberately mirrors that method's own two storage rules: a
/// scheduled count is only written when it differs from the linked-habit
/// total, and a done count only when it is non-zero.
({Map<String, int> done, Map<String, int> scheduled}) _storedForWeek({
  required Set<int> doneDayIndices,
  required int target,
  required bool isWeekClosed,
}) {
  final present = List.generate(_weekDays.length, (i) => i);
  final answerable = weeklyQuotaScheduledDays(
    presentDays: present,
    doneDays: doneDayIndices,
    target: target,
    isWeekClosed: isWeekClosed,
  ).toSet();
  final done = <String, int>{};
  final scheduled = <String, int>{};
  for (final i in present) {
    final key = _weekDays[i].toDateKey();
    final isAnswerable = answerable.contains(i);
    if (!isAnswerable) scheduled[key] = 0; // excused: differs from the total
    if (isAnswerable && doneDayIndices.contains(i)) done[key] = 1;
  }
  return (done: done, scheduled: scheduled);
}

void main() {
  group('weeklyQuotaScheduledDays - which days a quota is answerable for', () {
    test('target met exactly: only the days done count, rest days are excused',
        () {
      // 4x a week, done on 4 days. The other 3 are rest days the quota
      // entitles you to, not misses.
      final result = weeklyQuotaScheduledDays(
        presentDays: const [0, 1, 2, 3, 4, 5, 6],
        doneDays: const {0, 1, 2, 4},
        target: 4,
        isWeekClosed: true,
      );
      expect(result.toSet(), {0, 1, 2, 4});
    });

    test('exceeding the target still counts every day actually done', () {
      final result = weeklyQuotaScheduledDays(
        presentDays: const [0, 1, 2, 3, 4, 5, 6],
        doneDays: const {0, 1, 2, 3, 4, 5},
        target: 4,
        isWeekClosed: true,
      );
      expect(result.toSet(), {0, 1, 2, 3, 4, 5},
          reason: 'six sessions is six done days, not four');
    });

    test('closed week short by one: the shortfall counts, the rest stays rest',
        () {
      // 4x a week, done 3. Exactly one day should be answerable on top of
      // the three done - not all four remaining days.
      final result = weeklyQuotaScheduledDays(
        presentDays: const [0, 1, 2, 3, 4, 5, 6],
        doneDays: const {0, 1, 2},
        target: 4,
        isWeekClosed: true,
      );
      expect(result.length, 4);
      expect(result.toSet().containsAll({0, 1, 2}), isTrue);
    });

    test('closed week with nothing done: exactly the target is answerable', () {
      final result = weeklyQuotaScheduledDays(
        presentDays: const [0, 1, 2, 3, 4, 5, 6],
        doneDays: const {},
        target: 4,
        isWeekClosed: true,
      );
      expect(result.length, 4,
          reason: 'you owed 4 sessions and gave none - 4 misses, not 7');
    });

    test('open week, target not met yet: every day so far still counts', () {
      // The anti-inflation rule. Handing out the week's rest days before the
      // target is met would show a spotless week that decays as the week
      // goes on - the same "credit before the fact" trap quotaOkWeeks
      // documents for streaks.
      final result = weeklyQuotaScheduledDays(
        presentDays: const [0, 1, 2],
        doneDays: const {0},
        target: 4,
        isWeekClosed: false,
      );
      expect(result.toSet(), {0, 1, 2});
    });

    test('open week with the target already met credits immediately', () {
      // Meeting the target early should not make someone wait until the week
      // closes to see it, matching weeklyHabitCreditFor's own ordering.
      final result = weeklyQuotaScheduledDays(
        presentDays: const [0, 1, 2, 3, 4],
        doneDays: const {0, 1, 2, 3},
        target: 4,
        isWeekClosed: false,
      );
      expect(result.toSet(), {0, 1, 2, 3});
    });

    test("a room's short first week can't demand more days than it contains",
        () {
      // Room starts on the 5th day of a calendar week: 3 days present, but
      // the habit's target is 4. The target caps at what's actually there.
      final result = weeklyQuotaScheduledDays(
        presentDays: const [4, 5, 6],
        doneDays: const {4, 5, 6},
        target: 4,
        isWeekClosed: true,
      );
      expect(result.toSet(), {4, 5, 6});
    });

    test('no days present at all returns nothing, never throws', () {
      expect(
        weeklyQuotaScheduledDays(
          presentDays: const [],
          doneDays: const {},
          target: 4,
          isWeekClosed: true,
        ),
        isEmpty,
      );
    });

    test('every day done is answerable in every case', () {
      // The numerator invariant: a day genuinely completed must never be
      // dropped from the answerable set, or its own credit would vanish.
      for (final closed in [true, false]) {
        for (var done = 0; done <= 7; done++) {
          final doneSet = {for (var i = 0; i < done; i++) i};
          final result = weeklyQuotaScheduledDays(
            presentDays: const [0, 1, 2, 3, 4, 5, 6],
            doneDays: doneSet,
            target: 4,
            isWeekClosed: closed,
          ).toSet();
          expect(result.containsAll(doneSet), isTrue,
              reason: 'done=$done closed=$closed dropped a completed day');
        }
      }
    });
  });

  group('the reported bug: a met weekly quota now scores a full week', () {
    // The reporter's own week, read straight off their Grid screenshot:
    // تمرين green on Sat 1, Sun 2, Mon 3, Tue 4 and Thu 6; blank Wed 5 and
    // Fri 7. Five sessions against a 4x-a-week target - target beaten.
    const reporterWeek = {0, 1, 2, 3, 5};
    final week = _room(start: DateTime(2026, 8, 1), end: DateTime(2026, 8, 7));

    test('4x a week, done 5 times -> 100%, not 71%', () {
      final stored = _storedForWeek(
        doneDayIndices: reporterWeek,
        target: 4,
        isWeekClosed: true,
      );
      final p = _participant(
        dailyDoneCount: stored.done,
        dailyScheduledCount: stored.scheduled,
      );

      expect(p.daysCompleted(week), 7.0);
      expect(p.progressRatio(week), 1.0);
      // The old behaviour, asserted as explicitly NOT the answer: every day
      // of the week in the denominator meant the two untouched rest days
      // read as misses, so a beaten target scored 5/7.
      expect(p.progressRatio(week), isNot(closeTo(5 / 7, 0.0001)));
    });

    test('a met quota scores exactly what the same days named would score',
        () {
      // This equivalence is the whole point. "4x a week, any days" and "these
      // 4 weekdays" express the same commitment; scoring them differently for
      // the same completions is the bug.
      final quota = _storedForWeek(
        doneDayIndices: const {0, 1, 2, 3},
        target: 4,
        isWeekClosed: true,
      );
      final quotaP = _participant(
        dailyDoneCount: quota.done,
        dailyScheduledCount: quota.scheduled,
      );

      // The named-weekday equivalent, graded the way that path already
      // works: its 4 days are scheduled and done, its other 3 are excused.
      final named = _namedDaysHabit(
        [for (final i in const [0, 1, 2, 3]) _weekDays[i].weekday],
      );
      final namedDone = <String, int>{};
      final namedScheduled = <String, int>{};
      for (final d in _weekDays) {
        if (named.isScheduledFor(d)) {
          namedDone[d.toDateKey()] = 1;
        } else {
          namedScheduled[d.toDateKey()] = 0;
        }
      }
      final namedP = _participant(
        dailyDoneCount: namedDone,
        dailyScheduledCount: namedScheduled,
      );

      expect(quotaP.progressRatio(week), namedP.progressRatio(week));
      expect(quotaP.progressRatio(week), 1.0);
    });

    test('falling short still costs exactly the shortfall, no more', () {
      // 4x a week, done 3. Three done days credit fully, one day is a real
      // miss, and the three rest days stay excused: 6 of 7.
      final stored = _storedForWeek(
        doneDayIndices: const {0, 1, 2},
        target: 4,
        isWeekClosed: true,
      );
      final p = _participant(
        dailyDoneCount: stored.done,
        dailyScheduledCount: stored.scheduled,
      );
      expect(p.daysCompleted(week), 6.0);
      expect(p.progressRatio(week), closeTo(6 / 7, 0.0001));
    });

    test('an entirely empty week is still scored as a failed quota', () {
      // The guard against over-correcting: excusing rest days must not mean
      // a week with nothing done in it quietly scores well.
      final stored = _storedForWeek(
        doneDayIndices: const {},
        target: 4,
        isWeekClosed: true,
      );
      final p = _participant(
        dailyDoneCount: stored.done,
        dailyScheduledCount: stored.scheduled,
      );
      expect(p.daysCompleted(week), 3.0,
          reason: 'the 4 owed sessions are misses; only the 3 rest days are '
              'excused - the same score a 4-named-weekday habit gets for '
              'doing nothing');
      expect(p.progressRatio(week), lessThan(0.5));
    });
  });

  group('late joiners are scored on the days they were actually here', () {
    // A 10-day room; this participant joined on day 8.
    final room = _room(start: DateTime(2026, 8, 1), end: DateTime(2026, 8, 10));

    RoomParticipant lateJoiner({Map<String, int> done = const {}}) =>
        RoomParticipant(
          uid: 'late-uid',
          displayName: 'Late',
          characterId: 'male_ghutra_blue',
          joinedAt: DateTime(2026, 8, 8, 14, 30), // mid-afternoon on day 8
          linkedHabitIds: const ['h1'],
          dailyDoneCount: done,
          lastUpdated: DateTime(2026, 8, 10),
        );

    test('scoring starts the day they joined, not the day the room did', () {
      expect(lateJoiner().countedStartIn(room), DateTime(2026, 8, 8),
          reason: 'the join time of day must not leak into the date');
    });

    test('their denominator is their own days, not the whole room', () {
      // 8th, 9th, 10th inclusive.
      expect(lateJoiner().daysElapsedIn(room), 3);
    });

    test('days before they joined earn nothing, even with real history', () {
      // Grid history exists for the room's first week, but they weren't in
      // the room for any of it. Before this, that history was credited and a
      // day-8 joiner could land straight at the top of the leaderboard.
      final p = lateJoiner(done: {
        for (var d = 1; d <= 7; d++) '2026-08-0\$d': 1,
      });
      expect(p.daysCompleted(room), 0.0);
      expect(p.progressRatio(room), 0.0);
    });

    test('a perfect run since joining is 100%, not a fraction of the room',
        () {
      final p = lateJoiner(done: const {
        '2026-08-08': 1,
        '2026-08-09': 1,
        '2026-08-10': 1,
      });
      expect(p.daysCompleted(room), 3.0);
      expect(p.progressRatio(room), 1.0,
          reason: 'joining late must not cap what they can reach');
      // The old behaviour divided by the room's 10 days.
      expect(p.progressRatio(room), isNot(closeTo(3 / 10, 0.0001)));
    });

    test('the streak cannot run back through days they were not here', () {
      final p = lateJoiner(done: const {
        '2026-08-08': 1,
        '2026-08-09': 1,
        '2026-08-10': 1,
      });
      expect(p.currentStreak(room), 3,
          reason: 'floors at their join date, not the room start');
    });

    test('someone present from the start is unaffected', () {
      final founder = RoomParticipant(
        uid: 'founder-uid',
        displayName: 'Founder',
        characterId: 'male_ghutra_blue',
        joinedAt: DateTime(2026, 8, 1),
        linkedHabitIds: const ['h1'],
        dailyDoneCount: const {'2026-08-01': 1},
        lastUpdated: DateTime(2026, 8, 10),
      );
      expect(founder.countedStartIn(room), room.startDate);
      expect(founder.daysElapsedIn(room), room.daysElapsed);
    });

    test('joining before the room starts still scores from the room start',
        () {
      // Lobby members join days before the leader presses Start; their
      // window must not begin earlier than the challenge itself.
      final early = RoomParticipant(
        uid: 'early-uid',
        displayName: 'Early',
        characterId: 'male_ghutra_blue',
        joinedAt: DateTime(2026, 7, 20),
        linkedHabitIds: const ['h1'],
        lastUpdated: DateTime(2026, 8, 10),
      );
      expect(early.countedStartIn(room), room.startDate);
    });
  });

  group('RoomParticipant.wasObservedOn - the anti-backdating watermark', () {
    test('a doc written before the watermark existed observed nothing', () {
      // This is what heals the reported data: with no watermark recorded, no
      // past day can be capped against a zero nobody was there to verify, so
      // the next sync re-credits the window from real Grid history once.
      final p = _participant(lastSyncedDay: null);
      expect(p.wasObservedOn('2026-08-01'), isFalse);
      expect(p.wasObservedOn('2026-07-28'), isFalse);
    });

    test('days up to and including the watermark were observed', () {
      final p = _participant(lastSyncedDay: '2026-08-05');
      expect(p.wasObservedOn('2026-08-01'), isTrue);
      expect(p.wasObservedOn('2026-08-05'), isTrue);
    });

    test('days after the watermark were not - nobody was looking', () {
      // The days the app spent closed. Capping these at their stored zero is
      // exactly what permanently erased completions that really happened.
      final p = _participant(lastSyncedDay: '2026-08-05');
      expect(p.wasObservedOn('2026-08-06'), isFalse);
      expect(p.wasObservedOn('2026-08-12'), isFalse);
    });

    test('date-key comparison is chronological across month boundaries', () {
      // YYYY-MM-DD string ordering is relied on rather than parsing; the
      // reported data straddled a month end (room started 28 Jul, credit
      // stopped 1 Aug), so this is the case that has to be right.
      final p = _participant(lastSyncedDay: '2026-07-31');
      expect(p.wasObservedOn('2026-07-30'), isTrue);
      expect(p.wasObservedOn('2026-07-31'), isTrue);
      expect(p.wasObservedOn('2026-08-01'), isFalse);
    });
  });

  group('didCompleteAnythingOn - what a room is actually told about', () {
    // Excusing a met quota's rest days makes isFullyDone true on days
    // nothing happened. That is right for "is anything owed today" and wrong
    // for anything announced to teammates, so the push and the in-app
    // celebration ask this instead.
    test('a day something was completed reads as real activity', () {
      final p = _participant(dailyDoneCount: const {'2026-08-01': 1});
      expect(p.didCompleteAnythingOn('2026-08-01'), isTrue);
    });

    test('an excused rest day is finished, but is NOT activity', () {
      // Exactly the shape the sync stores for a rest day once the weekly
      // target is met: scheduled 0, no done entry.
      final p = _participant(dailyScheduledCount: const {'2026-08-05': 0});
      expect(p.isFullyDone('2026-08-05'), isTrue,
          reason: 'nothing was owed, so nothing is outstanding');
      expect(p.didCompleteAnythingOn('2026-08-05'), isFalse,
          reason: 'resting is not something to announce to the room');
    });

    test('a plain missed day is neither', () {
      final p = _participant();
      expect(p.isFullyDone('2026-08-05'), isFalse);
      expect(p.didCompleteAnythingOn('2026-08-05'), isFalse);
    });

    test('a partly-done multi-habit day still counts as activity', () {
      // 1 of 2 linked habits done: not "finished", but they did do
      // something, so it must not be mistaken for an idle day.
      final p = _participant(
        dailyDoneCount: const {'2026-08-01': 1},
        dailyScheduledCount: const {'2026-08-01': 2},
      );
      expect(p.isFullyDone('2026-08-01'), isFalse);
      expect(p.didCompleteAnythingOn('2026-08-01'), isTrue);
    });
  });

  group('RoomParticipant round-trips the watermark through Firestore', () {
    test('toFirestore omits it entirely when it has never been set', () {
      expect(_participant().toFirestore().containsKey('lastSyncedDay'), isFalse);
    });

    test('toFirestore writes it once it exists', () {
      expect(
        _participant(lastSyncedDay: '2026-08-12').toFirestore()['lastSyncedDay'],
        '2026-08-12',
      );
    });

    test('copyWith preserves it when untouched', () {
      final p = _participant(lastSyncedDay: '2026-08-12');
      expect(p.copyWith(hideDetails: true).lastSyncedDay, '2026-08-12');
    });
  });
}
