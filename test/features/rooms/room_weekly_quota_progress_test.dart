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
import 'package:grow_daily_v2/features/habits/models/weekly_quota_plan.dart';
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
  _quotaWriterInvariant();
  _extendIsScoreNeutral();
  _unlinkKeepsSlots();
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
      expect(
        result.toSet(),
        {0, 1, 2, 3, 4, 5},
        reason: 'six sessions is six done days, not four',
      );
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
      expect(
        result.length,
        4,
        reason: 'you owed 4 sessions and gave none - 4 misses, not 7',
      );
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
          expect(
            result.containsAll(doneSet),
            isTrue,
            reason: 'done=$done closed=$closed dropped a completed day',
          );
        }
      }
    });
  });

  group('the reported bug: a met weekly quota now scores a full week', () {
    // The reporter's own week, read straight off their Grid screenshot:
    // تمرين green on Sat 1, Sun 2, Mon 3, Tue 4 and Thu 6; blank Wed 5 and
    // Fri 7. Five sessions against a 4x-a-week target - target beaten.
    const reporterWeek = {0, 1, 2, 3, 5};
    final week = _room(start: DateTime(2026, 8), end: DateTime(2026, 8, 7));

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

    test('a met quota scores exactly what the same days named would score', () {
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
        [
          for (final i in const [0, 1, 2, 3]) _weekDays[i].weekday,
        ],
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
      expect(
        p.daysCompleted(week),
        3.0,
        reason: 'the 4 owed sessions are misses; only the 3 rest days are '
            'excused - the same score a 4-named-weekday habit gets for '
            'doing nothing',
      );
      expect(p.progressRatio(week), lessThan(0.5));
    });
  });

  group('late joiners are scored on the days they were actually here', () {
    // A 10-day room; this participant joined on day 8.
    final room = _room(start: DateTime(2026, 8), end: DateTime(2026, 8, 10));

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
      expect(
        lateJoiner().countedStartIn(room),
        DateTime(2026, 8, 8),
        reason: 'the join time of day must not leak into the date',
      );
    });

    test('their denominator is their own days, not the whole room', () {
      // 8th, 9th, 10th inclusive.
      expect(lateJoiner().daysElapsedIn(room), 3);
    });

    test('days before they joined earn nothing, even with real history', () {
      // Grid history exists for the room's first week, but they weren't in
      // the room for any of it. Before this, that history was credited and a
      // day-8 joiner could land straight at the top of the leaderboard.
      final p = lateJoiner(
        done: {
          for (var d = 1; d <= 7; d++) '2026-08-0\$d': 1,
        },
      );
      expect(p.daysCompleted(room), 0.0);
      expect(p.progressRatio(room), 0.0);
    });

    test('a perfect run since joining is 100%, not a fraction of the room', () {
      final p = lateJoiner(
        done: const {
          '2026-08-08': 1,
          '2026-08-09': 1,
          '2026-08-10': 1,
        },
      );
      expect(p.daysCompleted(room), 3.0);
      expect(
        p.progressRatio(room),
        1.0,
        reason: 'joining late must not cap what they can reach',
      );
      // The old behaviour divided by the room's 10 days.
      expect(p.progressRatio(room), isNot(closeTo(3 / 10, 0.0001)));
    });

    test('the streak cannot run back through days they were not here', () {
      final p = lateJoiner(
        done: const {
          '2026-08-08': 1,
          '2026-08-09': 1,
          '2026-08-10': 1,
        },
      );
      expect(
        p.currentStreak(room),
        3,
        reason: 'floors at their join date, not the room start',
      );
    });

    test('someone present from the start is unaffected', () {
      final founder = RoomParticipant(
        uid: 'founder-uid',
        displayName: 'Founder',
        characterId: 'male_ghutra_blue',
        joinedAt: DateTime(2026, 8),
        linkedHabitIds: const ['h1'],
        dailyDoneCount: const {'2026-08-01': 1},
        lastUpdated: DateTime(2026, 8, 10),
      );
      expect(founder.countedStartIn(room), room.startDate);
      expect(founder.daysElapsedIn(room), room.daysElapsed);
    });

    test('joining before the room starts still scores from the room start', () {
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
      final p = _participant();
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
      expect(
        p.isFullyDone('2026-08-05'),
        isTrue,
        reason: 'nothing was owed, so nothing is outstanding',
      );
      expect(
        p.didCompleteAnythingOn('2026-08-05'),
        isFalse,
        reason: 'resting is not something to announce to the room',
      );
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
      expect(
        _participant().toFirestore().containsKey('lastSyncedDay'),
        isFalse,
      );
    });

    test('toFirestore writes it once it exists', () {
      expect(
        _participant(lastSyncedDay: '2026-08-12')
            .toFirestore()['lastSyncedDay'],
        '2026-08-12',
      );
    });

    test('copyWith preserves it when untouched', () {
      final p = _participant(lastSyncedDay: '2026-08-12');
      expect(p.copyWith(hideDetails: true).lastSyncedDay, '2026-08-12');
    });
  });

  // What a room streak actually does for each of the three cadences, pinned
  // because only one of them is obvious. RoomParticipant._keepsStreak is
  // `isFullyDone(day) || quotaOkWeeks.contains(weekStart)`, and isFullyDone
  // answers TRUE for a day nothing was scheduled on — so an excused rest day
  // keeps a streak through the first clause, before quotaOkWeeks is even
  // consulted. That is the whole reason weekly and named-weekday habits
  // behave unlike a daily one here.
  group('currentStreak across the three cadences', () {
    // The whole test week is in the past relative to any plausible run date,
    // so the room is always ended and currentStreak's "an unfinished today
    // doesn't break it yet" branch never fires. Keeps these deterministic.
    final room = _room(start: _weekDays.first, end: _weekDays.last);

    test('daily habit: one missed day ends the streak there', () {
      // Every day answerable, done on all but Wednesday (index 3).
      final done = <String, int>{};
      final scheduled = <String, int>{};
      for (var i = 0; i < _weekDays.length; i++) {
        scheduled[_weekDays[i].toDateKey()] = 1;
        if (i != 3) done[_weekDays[i].toDateKey()] = 1;
      }
      final p =
          _participant(dailyDoneCount: done, dailyScheduledCount: scheduled);

      // Counts back Fri, Thu — then Wednesday is a real miss and stops it.
      expect(p.currentStreak(room), 3);
    });

    test('weekly quota met: the 3 rest days keep the streak, so it reads 7',
        () {
      // 4x a week, done exactly 4 times on Sat/Sun/Mon/Wed. The other three
      // days are rest the quota entitled them to.
      final stored = _storedForWeek(
        doneDayIndices: const {0, 1, 2, 4},
        target: 4,
        isWeekClosed: true,
      );
      final p = _participant(
        dailyDoneCount: stored.done,
        dailyScheduledCount: stored.scheduled,
      );

      // Every day of the week keeps it: 4 genuinely done, 3 excused. Doing a
      // habit on 4 days and being credited a 7-day streak is the designed
      // behaviour, not a bug — but it is worth stating out loud, because the
      // number has no relationship to how many squares the Grid shows.
      expect(p.currentStreak(room), 7);
    });

    test(
        'weekly quota still short mid-week: no rest days yet, so the streak '
        'collapses to the trailing run of real completions', () {
      // Same habit, same 4x target, but only 2 done and the week still open —
      // weeklyQuotaScheduledDays hands out no rest days in advance, so every
      // day is answerable and the not-yet-done ones read as plain misses.
      final stored = _storedForWeek(
        doneDayIndices: const {0, 1},
        target: 4,
        isWeekClosed: false,
      );
      final p = _participant(
        dailyDoneCount: stored.done,
        dailyScheduledCount: stored.scheduled,
      );

      // Walking back from Friday: Fri/Thu/Wed/Tue are all answerable-and-not-
      // done, so it stops immediately. The same person, same habit, same two
      // workouts, will read 7 the moment the 4th lands. That jump is the
      // thing users notice, and it is why a weekly streak cannot be read as
      // "days in a row" the way a daily one can.
      expect(p.currentStreak(room), 0);
    });

    test('named-weekday habit: an off-day is excused, exactly like rest', () {
      // Sun/Tue/Thu only (weekday 7/2/4 → indices 1, 3, 5 of a Sat-start
      // week), all three done. The four off-days were never owed.
      final done = <String, int>{};
      final scheduled = <String, int>{};
      for (var i = 0; i < _weekDays.length; i++) {
        final key = _weekDays[i].toDateKey();
        final isDue = i == 1 || i == 3 || i == 5;
        if (!isDue) {
          scheduled[key] = 0; // excused — same shape the sync stores
        } else {
          scheduled[key] = 1;
          done[key] = 1;
        }
      }
      final p =
          _participant(dailyDoneCount: done, dailyScheduledCount: scheduled);

      // Also 7: three real completions plus four excused days. Confirms the
      // two cadences agree with each other — the earlier bug this file was
      // written for was precisely them disagreeing.
      expect(p.currentStreak(room), 7);
    });

    test('an excused day and a completed day are indistinguishable downstream',
        () {
      // The root of the "room squares don't match the Grid" report: creditFor
      // returns a flat 1.0 for a day nothing was scheduled on, which is the
      // same value a fully completed day returns. The leaderboard strip
      // colours cells straight off this, so rest days render in the same full
      // emerald as training days while the Grid square for them is empty.
      final stored = _storedForWeek(
        doneDayIndices: const {0, 1, 2, 4},
        target: 4,
        isWeekClosed: true,
      );
      final p = _participant(
        dailyDoneCount: stored.done,
        dailyScheduledCount: stored.scheduled,
      );

      final completed = _weekDays[0].toDateKey(); // actually trained
      final excused = _weekDays[3].toDateKey(); // rest day
      expect(p.creditFor(completed), 1.0);
      expect(p.creditFor(excused), 1.0);
      expect(p.isFullyDone(excused), isTrue);
    });
  });

  // Where a closed week's shortfall LANDS. The count was always right (done
  // + shortfall answerable, rest excused) but the placement used to be
  // "earliest empty days first", while the Grid's red squares come from
  // weeklyQuotaDemand's day-local verdicts — so for the الإلتزااام report
  // (تمرين, 4x, done Sun & Thu) the room blamed Saturday and Monday while
  // the Grid, correctly, showed Wednesday and Friday red. Same score, two
  // screens contradicting each other about which days went wrong.
  group('closed-week misses land on the same days the Grid paints red', () {
    test('the reported تمرين week: misses are Wed and Fri, not Sat and Mon',
        () {
      // Sat-start week, done on Sun (1) and Thu (5), 4x target, week over.
      // Day-local: Sat/Mon/Tue passed while the target was still reachable
      // without them (spare → excused rest). Wednesday was the first day
      // skipping which made 4 impossible, Friday the second — those two ARE
      // the shortfall, and they are exactly the squares the Grid reds.
      final result = weeklyQuotaScheduledDays(
        presentDays: const [0, 1, 2, 3, 4, 5, 6],
        doneDays: const {1, 5},
        target: 4,
        isWeekClosed: true,
      );
      expect(
        result.toSet(),
        {1, 4, 5, 6},
        reason: 'answerable = the 2 done days + the 2 days the week '
            'actually broke on (Wed=4, Fri=6)',
      );
    });

    test('rooms and Grid can never disagree about which days were missed', () {
      // The drift-proof property, over every completion pattern of a 7-day
      // week and every target: the days this grader holds answerable-but-not-
      // done in a closed week are exactly weeklyQuotaDemand's owed-and-empty
      // days — the Grid's red squares. One shared verdict, two screens.
      for (var target = 1; target <= 7; target++) {
        for (var mask = 0; mask < 128; mask++) {
          final done = {
            for (var i = 0; i < 7; i++)
              if (mask & (1 << i) != 0) i,
          };
          final answerable = weeklyQuotaScheduledDays(
            presentDays: const [0, 1, 2, 3, 4, 5, 6],
            doneDays: done,
            target: target,
            isWeekClosed: true,
          ).toSet();
          final demand = weeklyQuotaDemand(
            dayCount: 7,
            doneDays: done,
            target: target,
          );
          final gridRed = {
            for (var i = 0; i < 7; i++)
              if (demand[i] == DayDemand.owed && !done.contains(i)) i,
          };
          final roomMisses = answerable.difference(done);
          expect(
            roomMisses,
            gridRed,
            reason: 'target=$target done=$done: the room blames '
                '$roomMisses, the Grid reds $gridRed',
          );
        }
      }
    });

    test('a short week under the wrong side of the clamp still matches', () {
      // Room's first week is 3 days against a 4x rule: target clamps to 3.
      final result = weeklyQuotaScheduledDays(
        presentDays: const [4, 5, 6],
        doneDays: const {5},
        target: 4,
        isWeekClosed: true,
      );
      // Clamped target 3 over 3 days: every day was load-bearing, so both
      // empty days are genuine misses alongside the one done day.
      expect(result.toSet(), {4, 5, 6});
    });
  });

  // The week-closed boundary. The old inline check (`!weekEnd.isAfter(
  // lastCountedDay)`) graded a week as closed the moment its LAST day
  // arrived — all day Friday on a Sat-start week — which pinned the
  // shortfall onto past days, excused Friday itself as rest, and told the
  // person "Done for today" on the one day that was their last chance to
  // act. Seen live in the الإلتزااام room on Friday 2026-08-14.
  group('isQuotaWeekClosed - a week stays open through its own last day', () {
    final weekStart = DateTime(2026, 8, 8); // a real Saturday

    test('open while any of its days is still today', () {
      for (var d = 0; d < 7; d++) {
        expect(
          isQuotaWeekClosed(
            weekStart: weekStart,
            lastCountedDay: weekStart.add(Duration(days: d)),
            roomEnded: false,
          ),
          isFalse,
          reason: 'day $d of the week is still in progress — grading it as '
              'final hands out verdicts while the person can still act',
        );
      }
    });

    test('closed from the first day after it', () {
      expect(
        isQuotaWeekClosed(
          weekStart: weekStart,
          lastCountedDay: weekStart.add(const Duration(days: 7)),
          roomEnded: false,
        ),
        isTrue,
      );
    });

    test('an ended room closes its weeks regardless of the calendar', () {
      expect(
        isQuotaWeekClosed(
          weekStart: weekStart,
          lastCountedDay: weekStart.add(const Duration(days: 3)),
          roomEnded: true,
        ),
        isTrue,
        reason: 'grading stopped at endDate; nothing can change anymore',
      );
    });
  });

  // The streak consequence of day-local placement, stated out loud: it can
  // be harsher than earliest-first, and that is correct. For the تمرين week
  // the old placement excused Friday (the shortfall was pinned on Sat/Mon),
  // so a week that genuinely fell 2 short of its quota still ended on a
  // 4-day streak. Day-local, Friday itself is one of the misses — the Grid
  // shows it red — so the streak the week ends on is 0, exactly what a
  // named-weekday habit missing its final scheduled day would score.
  group('streak with day-local misses', () {
    test('a week ending on a missed owed day ends its streak', () {
      final room = _room(start: _weekDays.first, end: _weekDays.last);
      final stored = _storedForWeek(
        doneDayIndices: const {1, 5},
        target: 4,
        isWeekClosed: true,
      );
      final p = _participant(
        dailyDoneCount: stored.done,
        dailyScheduledCount: stored.scheduled,
      );
      expect(
        p.currentStreak(room),
        0,
        reason: 'Friday was owed and empty — the same Friday the Grid '
            'paints red. A 2-of-4 week must not end on a live streak.',
      );
    });
  });
}

/// The production bug this file's arithmetic was already correct about, and
/// which shipped anyway because nothing checked the STATE OF THE INPUTS.
///
/// Room A8GEL7: two members on the same shared 4x/week habit, both with 11
/// green squares over the same 21 days. One read 76%, the other 57%. The
/// difference was entirely bookkeeping — one participant's doc had
/// dailyScheduledCount and quotaOkWeeks populated, the other's were empty,
/// so every rest day she had earned by hitting her target scored as a miss.
///
/// The cause was syncLinkedHabitsProgress grading against a habit list that
/// had not loaded. Its "linked habit not found" branch fails OPEN — right
/// for a habit genuinely deleted from Grid, catastrophic for one that is
/// merely still loading. It credits every day as scheduled=1/done=1 and
/// skips both the weekly branch and pass 2, so dailyScheduledCount computes
/// dense (every key removed) and quotaOkWeeks computes empty (banked weeks
/// revoked) — all written in one atomic update that leaves the doc looking
/// freshly synced. _resyncMyRooms fires on app resume with no UI involved,
/// and habitListProvider is empty until its sources settle, so the race was
/// routine rather than exotic.
///
/// The fix gates the sync on habitsStillLoadingProvider and on every linked
/// id resolving, deferring instead of failing open. These tests pin the two
/// halves of the invariant that must hold whatever the inputs did: a met
/// week excuses its rest days, and an empty stored map must never be read
/// as "nothing was excused".
void _quotaWriterInvariant() {
  group('a met quota week excuses its rest days, whoever computed it', () {
    // Perla's real week from room A8GEL7: Saturday 2026-08-01 through
    // Friday 2026-08-07, target 4, done on the 3rd, 4th, 5th and 7th.
    final weekStart = DateTime(2026, 8);
    final present = List.generate(7, (i) => i);
    const done = {2, 3, 4, 6}; // 08-03, 08-04, 08-05, 08-07

    test('four of four answers only the four days actually trained', () {
      final answerable = weeklyQuotaScheduledDays(
        presentDays: present,
        doneDays: done,
        target: 4,
        isWeekClosed: true,
      );
      // The other three days are not answerable, which is what makes them
      // rest days worth full credit rather than misses worth nothing.
      expect(
        answerable.toSet(),
        done,
        reason: 'a met target must excuse the untrained days',
      );
      expect(answerable.length, 4);
    });

    test('the week is closed, so this is settled and cannot change', () {
      expect(
        isQuotaWeekClosed(
          weekStart: weekStart,
          lastCountedDay: DateTime(2026, 8, 17),
          roomEnded: false,
        ),
        isTrue,
      );
    });

    test('an empty stored map must not read as "nothing was excused"', () {
      // The exact shape of the corrupted doc left behind by a warm-up sync:
      // done-counts present, quota bookkeeping wiped. scheduledCountFor
      // falls back to countedHabitCount for an absent key, so every one of
      // those days reads as owed — 4 credited days instead of 7, i.e. 57%
      // where the member earned 76%. This asserts the SYMPTOM so an empty
      // map is never mistaken for correct data.
      final corrupted = RoomParticipant(
        uid: 'perla',
        displayName: 'Perla',
        joinedAt: DateTime(2026, 7, 28),
        characterId: 'female_abaya_rose',
        lastUpdated: DateTime(2026, 8, 17),
        linkedHabitIds: const ['h1'],
        linkedHabitNames: const ['تمرين'],
        dailyDoneCount: const {
          '2026-08-03': 1,
          '2026-08-04': 1,
          '2026-08-05': 1,
          '2026-08-07': 1,
        },
      );
      // 08-01 was a rest day she earned; with the map empty it is owed.
      expect(
        corrupted.isRestDay('2026-08-01'),
        isFalse,
        reason: 'documents the corrupted state — an empty map cannot '
            'express an excusal, which is why the sync must defer rather '
            'than grade against a habit list that has not loaded',
      );
      expect(corrupted.creditFor('2026-08-01'), 0.0);
      // And the days she did train still count, so the failure is silent:
      // the number is wrong but nothing looks broken.
      expect(corrupted.creditFor('2026-08-03'), 1.0);
    });
  });
}

/// Extending a finished room must not cost anyone a single point.
///
/// Before paused spans, extendRoom simply pushed endDate out from today,
/// which swept every dead day straight into the denominator: a room that
/// ended on the 14th and was extended on the 17th handed every member three
/// fresh misses for days the room did not exist. The percentage dropped the
/// instant the leader tapped extend, which made extending feel like a
/// punishment for the group — the opposite of what it is for.
///
/// A paused day is excluded from BOTH sides. Nobody was asked for anything,
/// so nobody owes anything.
void _extendIsScoreNeutral() {
  RoomModel roomWith({
    required DateTime endDate,
    List<({String from, String to})> paused = const [],
  }) =>
      RoomModel(
        code: 'TEST01',
        name: 'test',
        createdBy: 'leader',
        createdByName: 'Leader',
        createdAt: DateTime(2026, 7, 28),
        startDate: DateTime(2026, 7, 28),
        endDate: endDate,
        duration: RoomDuration.fixed,
        habitMode: RoomHabitMode.shared,
        pausedSpans: paused,
      );

  // Trained on four of the room's first seven days, then the room ended.
  final participant = RoomParticipant(
    uid: 'u1',
    displayName: 'Member',
    characterId: 'male_ghutra_blue',
    joinedAt: DateTime(2026, 7, 28),
    lastUpdated: DateTime(2026, 8, 3),
    linkedHabitIds: const ['h1'],
    linkedHabitNames: const ['تمرين'],
    dailyDoneCount: const {
      '2026-07-28': 1,
      '2026-07-29': 1,
      '2026-07-30': 1,
      '2026-07-31': 1,
    },
  );

  group('extending a finished room is score-neutral', () {
    // Room ran 07-28 .. 08-03 (7 days), 4 of them trained.
    final ended = roomWith(endDate: DateTime(2026, 8, 3));

    test('baseline before any extension', () {
      expect(participant.daysElapsedIn(ended), 7);
      expect(participant.daysCompleted(ended), 4.0);
    });

    test('the dead days are excluded, so the ratio is unchanged', () {
      // Leader extends on 08-11, resuming that day: 08-04..08-10 was dead.
      final extended = roomWith(
        endDate: DateTime(2026, 8, 20),
        paused: const [(from: '2026-08-04', to: '2026-08-10')],
      );
      // Seven dead days sit inside the window and must not appear on either
      // side of the fraction.
      final elapsed = participant.daysElapsedIn(extended);
      final done = participant.daysCompleted(extended);
      expect(
        elapsed,
        lessThan(24),
        reason: 'paused days leaked into the denominator',
      );
      expect(done, 4.0, reason: 'paused days must not be graded');
      // Without exclusion this member would read 4/24 = 17%. The pause keeps
      // the seven dead days out entirely.
      expect(
        participant.progressRatio(ended),
        greaterThan(participant.progressRatio(extended)),
        reason: 'live days after the resume are genuinely still owed',
      );
    });

    test('a room never extended is completely unaffected', () {
      // The field is additive: an empty pausedSpans list must reproduce the
      // old arithmetic exactly, or this change would silently move every
      // existing room's numbers.
      expect(ended.pausedSpans, isEmpty);
      expect(participant.daysElapsedIn(ended), 7);
      expect(participant.daysCompleted(ended), 4.0);
      expect(participant.progressRatio(ended), closeTo(4 / 7, 0.0001));
    });

    test('the team denominator agrees with each member row', () {
      // These are rendered on the same screen — the team card above the
      // rows. Dividing a pause-aware numerator by a raw calendar span made
      // the card read 47% over rows reading 88%.
      final extended = roomWith(
        endDate: DateTime(2026, 8, 20),
        paused: const [(from: '2026-08-04', to: '2026-08-10')],
      );
      expect(
        extended.daysElapsed,
        participant.daysElapsedIn(extended),
        reason: 'the room-level and per-member elapsed counts must not '
            'disagree about paused days',
      );
    });

    test('a future-dated pause is clipped, never carried forward', () {
      // A leader who resumes on a future date leaves a pause covering days
      // about to become live. Extending again before that date must trim it,
      // or those live days stay permanently unscored.
      final withFuturePause = roomWith(
        endDate: DateTime(2026, 9, 7),
        paused: const [(from: '2026-08-15', to: '2026-08-24')],
      );
      // Days inside the stale span read as paused until it is clipped —
      // which is exactly why extendRoom must clip rather than append.
      expect(withFuturePause.isPausedOn('2026-08-20'), isTrue);
      // And the clip boundary is inclusive at the resume day itself.
      expect(withFuturePause.isPausedOn('2026-08-25'), isFalse);
    });

    test('isPausedOn covers the span inclusively at both ends', () {
      final extended = roomWith(
        endDate: DateTime(2026, 8, 20),
        paused: const [(from: '2026-08-04', to: '2026-08-10')],
      );
      expect(extended.isPausedOn('2026-08-03'), isFalse);
      expect(extended.isPausedOn('2026-08-04'), isTrue);
      expect(extended.isPausedOn('2026-08-10'), isTrue);
      expect(extended.isPausedOn('2026-08-11'), isFalse);
    });
  });
}

/// Unlinking a habit from a SHARED plan must keep its slot.
///
/// linkedHabitIds is index-for-index parallel with RoomModel.sharedHabits and
/// every read site relies on it (see kDeclinedSlot). removeAt shifted every
/// later slot down one, so unlinking the first of three shared habits made
/// slots 2 and 3 be graded against the wrong frozen rules — silently, and
/// permanently. It also shortened the list, which the unresolved-plan banner
/// reads as "hasn't decided yet", so the slot came back as a fresh prompt.
void _unlinkKeepsSlots() {
  group('removeLinkedHabit', () {
    const ids = ['a', 'b', 'c'];
    const names = ['A', 'B', 'C'];

    test('shared plan: the slot is kept as a declined sentinel', () {
      final (newIds, newNames) =
          removeLinkedHabit(ids, names, 'a', preserveSlots: true);
      expect(
        newIds,
        [kDeclinedSlot, 'b', 'c'],
        reason: 'positions must not shift',
      );
      expect(newNames, ['', 'B', 'C']);
      // The parallel arrays stay the same length as the plan they mirror.
      expect(newIds.length, ids.length);
    });

    test('own room: the entry is genuinely removed', () {
      final (newIds, newNames) = removeLinkedHabit(ids, names, 'a');
      expect(newIds, ['b', 'c']);
      expect(newNames, ['B', 'C']);
    });

    test('a habit that is not linked is a no-op either way', () {
      expect(removeLinkedHabit(ids, names, 'zz', preserveSlots: true).$1, ids);
      expect(removeLinkedHabit(ids, names, 'zz').$1, ids);
    });

    test('the middle of a multi-habit plan keeps its neighbours in place', () {
      final (newIds, _) =
          removeLinkedHabit(ids, names, 'b', preserveSlots: true);
      expect(newIds, ['a', kDeclinedSlot, 'c']);
    });
  });
}
