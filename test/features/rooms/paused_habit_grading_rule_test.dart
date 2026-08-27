// How a room grades a linked habit it cannot resolve, and why both sync
// paths must now give the same answer.
//
// ── The bug this closes ─────────────────────────────────────────────────
// A paused habit leaves habitListProvider exactly as a deleted one does, so
// both sync paths met a linked id they could not resolve, and they disagreed
// about it:
//
//   syncLinkedHabitsProgress  scheduled++ AND done++   (counted as a PASS)
//   syncTodayForHabit         scheduled++ only          (counted as a MISS)
//
// Both comments described themselves as "failing open". A member's
// percentage therefore depended on which path wrote their participant doc
// last: tapping a Grid square scored a paused habit as a miss, and opening
// Room Detail regraded the same 45 days as a pass. The number moved on its
// own with nothing having happened.
//
// ── The rule now ────────────────────────────────────────────────────────
// An unresolvable habit leaves the numerator AND the denominator, so a
// member is graded on what they can actually do. The single exception is
// when NOTHING is resolvable, which must not become a free empty day.
//
// That exception used to be answered by scoring those days ZERO. It closed
// the hole and did far more besides: on room A8GEL7, pausing a 4x-a-week
// habit on 2 Aug read 13% against 93%, ended a 26-day streak, and crossed out
// a month of days the room had never asked about. Pausing was worse than
// never opening the app, which is the opposite of what pausing promises.
//
// Those days are now STAND-DOWN days (RoomParticipant.standDownDays): out of
// the numerator and out of the denominator, so the percentage holds still.
// The hole stays shut because a stand-down day is not a rest day — creditFor
// returns 0 for it and isFullyDone is false — so it can never be farmed as a
// free finished day either. The group at the bottom of this file pins both
// halves, because a change that satisfies one and breaks the other is exactly
// the failure this rule has already had once.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';

void main() {
  group('roomHasGradableHabit', () {
    test('one paused habit among three still leaves the room gradable', () {
      // Aziz's real case: تمرين paused for a broken leg, سورة الملك and
      // صلاة الوتر still live. He is graded out of two, so doing both is
      // 100% and doing neither is 0%.
      final gradable = roomHasGradableHabit(
        ['h-mulk', 'h-witr', 'h-train'],
        {'h-mulk', 'h-witr'}, // h-train is paused, so not resolvable
      );
      expect(gradable, isTrue);
    });

    test('pausing every linked habit is NOT gradable', () {
      // The exploit the exception exists for. If every habit dropped out of
      // the denominator, the day would ask nothing, and a day that asks
      // nothing is full credit by design (see creditFor and
      // paused_habit_room_grading_test). Pausing everything would then pay
      // 100% a day, forever, in a competitive room.
      final gradable = roomHasGradableHabit(
        ['h-mulk', 'h-witr', 'h-train'],
        const <String>{},
      );
      expect(gradable, isFalse,
          reason: 'callers must record a stand-down day here rather than '
              'letting the day go free');
    });

    test('a single surviving habit is enough', () {
      expect(roomHasGradableHabit(['a', 'b', 'c'], {'c'}), isTrue);
    });

    test('an empty plan is not gradable', () {
      expect(roomHasGradableHabit(const [], {'a'}), isFalse);
    });

    test('a resolvable set holding unrelated ids does not count', () {
      // Guards against asking the question the wrong way round: what matters
      // is whether MY linked habits resolve, not whether the account has any
      // habits at all.
      expect(roomHasGradableHabit(['a', 'b'], {'x', 'y', 'z'}), isFalse);
    });
  });

  group('a room whose ONLY habit is paused', () {
    // The case where option C stops helping, because with one linked habit
    // "pause that habit" and "pause everything" are the same act.
    test('is not gradable, so the anti-gaming fallback applies', () {
      expect(roomHasGradableHabit(['h-train'], const <String>{}), isFalse);
    });

    test('records a STAND-DOWN day, which is neither a pass nor a fail', () {
      // What the closing pass writes now: no counts at all for that day, and
      // the day listed in standDownDays. Both halves matter — the counts are
      // absent so nothing can read a result off them, and the list is what
      // stops the absence being read as a rest.
      final p = RoomParticipant(
        uid: 'member-uid',
        displayName: 'Aziz',
        characterId: 'male_ghutra_blue',
        joinedAt: DateTime(2026, 8, 19),
        linkedHabitIds: const ['h-train'],
        standDownDays: const ['2026-08-26'],
        lastUpdated: DateTime(2026, 8, 26),
      );
      // Not a finished day. This is the guard Aziz asked for by name: a pause
      // must never be usable as a way to bank a done day.
      expect(p.creditFor('2026-08-26'), 0.0,
          reason: 'a paused day is worth nothing, so it cannot be farmed');
      expect(p.isFullyDone('2026-08-26'), isFalse);
      expect(p.isRestDay('2026-08-26'), isFalse,
          reason: 'a rest day pays 1.0 here — a stand-down day must not '
              'borrow that door');
      expect(p.isDeclaredRest('2026-08-26'), isFalse);
      expect(p.didCompleteAnythingOn('2026-08-26'), isFalse);
    });

    test('...and is not a fail either: it leaves BOTH sides of the ratio', () {
      // The half the old rule got wrong. Same room, same member, same real
      // history — one paused on day three, one not.
      final start = DateTime(2026, 8, 1);
      final room = RoomModel(
        code: 'A8GEL7',
        name: 'الإلتزااام',
        createdBy: 'leader-uid',
        createdByName: 'Leader',
        createdAt: start,
        habitMode: RoomHabitMode.own,
        duration: RoomDuration.fixed,
        startDate: start,
        endDate: DateTime(2026, 8, 10),
      );
      RoomParticipant member({List<String> standDown = const []}) =>
          RoomParticipant(
            uid: 'member-uid',
            displayName: 'Aziz',
            characterId: 'male_ghutra_blue',
            joinedAt: start,
            linkedHabitIds: const ['h-train'],
            // Two real finished days before anything was paused.
            dailyDoneCount: const {'2026-08-01': 1, '2026-08-02': 1},
            standDownDays: standDown,
            lastUpdated: DateTime(2026, 8, 10),
          );

      // Never paused: eight of the ten days were simply missed.
      final ran = member();
      expect(ran.daysElapsedIn(room), 10);
      expect(ran.daysCompleted(room), 2.0);
      expect(ran.progressRatio(room), closeTo(0.2, 0.001));

      // Paused from the 3rd. The eight stood-down days leave the numerator
      // AND the denominator, so the ratio holds at the 2-of-2 they had
      // actually earned instead of collapsing toward zero.
      final paused = member(standDown: const [
        '2026-08-03', '2026-08-04', '2026-08-05', '2026-08-06',
        '2026-08-07', '2026-08-08', '2026-08-09', '2026-08-10',
      ]);
      expect(paused.daysElapsedIn(room), 2,
          reason: 'a stood-down day was never theirs to answer for');
      expect(paused.daysCompleted(room), 2.0,
          reason: 'and it adds nothing, so pausing cannot manufacture credit');
      expect(paused.progressRatio(room), 1.0);
    });

    test('a stand-down stretch cannot lift a percentage above what was earned',
        () {
      // The exploit check, stated as arithmetic rather than as intent: the
      // ratio after a pause is exactly the ratio at the moment of the pause.
      // Somebody sitting at 40% gains nothing by standing down — the same
      // property concededDaysIn relies on.
      final start = DateTime(2026, 8, 1);
      final room = RoomModel(
        code: 'A8GEL7',
        name: 'الإلتزااام',
        createdBy: 'leader-uid',
        createdByName: 'Leader',
        createdAt: start,
        habitMode: RoomHabitMode.own,
        duration: RoomDuration.fixed,
        startDate: start,
        endDate: DateTime(2026, 8, 20),
      );
      final p = RoomParticipant(
        uid: 'member-uid',
        displayName: 'Aziz',
        characterId: 'male_ghutra_blue',
        joinedAt: start,
        linkedHabitIds: const ['h-train'],
        // Two of the first five days done, then paused.
        dailyDoneCount: const {'2026-08-01': 1, '2026-08-04': 1},
        standDownDays: [
          for (var d = 6; d <= 20; d++) '2026-08-${d.toString().padLeft(2, '0')}',
        ],
        lastUpdated: DateTime(2026, 8, 20),
      );
      expect(p.daysElapsedIn(room), 5);
      expect(p.daysCompleted(room), 2.0);
      expect(p.progressRatio(room), closeTo(0.4, 0.001),
          reason: 'frozen at what they had, not raised toward 100%');
    });

    test('a day with real work on it is never blanked by the pause', () {
      // Aziz's catch: "I already did it yesterday." A stand-down day must
      // never land on a day the member actually trained, or the rule that
      // exists to stop a pause costing anything would start erasing the last
      // thing they did before it. The sync's closing pass skips any day with
      // a green or partial square (see syncLinkedHabitsProgress); this pins
      // the consequence at the model level, which is that such a day keeps
      // its credit and stays in both sides of the ratio.
      final start = DateTime(2026, 8, 1);
      final room = RoomModel(
        code: 'A8GEL7',
        name: 'الإلتزااام',
        createdBy: 'leader-uid',
        createdByName: 'Leader',
        createdAt: start,
        habitMode: RoomHabitMode.own,
        duration: RoomDuration.fixed,
        startDate: start,
        endDate: DateTime(2026, 8, 5),
      );
      final p = RoomParticipant(
        uid: 'member-uid',
        displayName: 'Aziz',
        characterId: 'male_ghutra_blue',
        joinedAt: start,
        linkedHabitIds: const ['h-train'],
        // The 4th was trained, and it sits inside the paused stretch.
        dailyDoneCount: const {'2026-08-04': 1},
        standDownDays: const ['2026-08-03', '2026-08-05'],
        lastUpdated: DateTime(2026, 8, 5),
      );
      expect(p.isStoodDownOn('2026-08-04'), isFalse);
      expect(p.creditFor('2026-08-04'), 1.0,
          reason: 'the day they trained keeps every bit of its credit');
      expect(p.isFullyDone('2026-08-04'), isTrue);
      // Three days answerable (1, 2, 4); the 3rd and 5th stood down.
      expect(p.daysElapsedIn(room), 3);
      expect(p.daysCompleted(room), 1.0);
    });

    test('the streak is HELD across the gap, not reset and not grown', () {
      final start = DateTime(2026, 8, 1);
      final room = RoomModel(
        code: 'A8GEL7',
        name: 'الإلتزااام',
        createdBy: 'leader-uid',
        createdByName: 'Leader',
        createdAt: start,
        habitMode: RoomHabitMode.own,
        duration: RoomDuration.fixed,
        startDate: start,
        endDate: DateTime(2026, 8, 10),
      );
      final p = RoomParticipant(
        uid: 'member-uid',
        displayName: 'Aziz',
        characterId: 'male_ghutra_blue',
        joinedAt: start,
        linkedHabitIds: const ['h-train'],
        // Three finished days, then a pause covering the rest of the room.
        dailyDoneCount: const {
          '2026-08-01': 1,
          '2026-08-02': 1,
          '2026-08-03': 1,
        },
        standDownDays: const [
          '2026-08-04', '2026-08-05', '2026-08-06', '2026-08-07',
          '2026-08-08', '2026-08-09', '2026-08-10',
        ],
        lastUpdated: DateTime(2026, 8, 10),
      );
      expect(p.currentStreak(room), 3,
          reason: 'the walk passes through the gap to the three real days, '
              'and counts neither the gap nor anything beyond it');
    });
  });

  group('pausing does not rewrite history', () {
    // The bug in the first cut of this change, caught on device: grading
    // resolved linked ids against the ACTIVE habit list only, so a habit
    // paused today became unresolvable for every day in the 45-day resync
    // window, including the days before the pause when it was live and
    // being completed. Someone who did تمرين all week and paused it on
    // Friday would have Monday through Thursday regraded as though the
    // habit had never been in their plan, silently discarding four real
    // finished days.
    //
    // Both sync paths now resolve paused habits too, and habitExistedOn
    // draws the line, so these two assertions are the contract.
    final paused = IslamicHabitTemplate(
      id: 'h-train',
      name: 'Exercise',
      nameAr: 'تمرين',
      description: '',
      category: HabitCategory.custom,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 10,
      goldReward: 5,
      createdAt: DateTime(2026, 8, 19),
      archivedAt: DateTime(2026, 8, 25),
    );

    test('days before the pause still count the habit', () {
      // It was alive and answerable on the 22nd, so it belongs in that
      // day's denominator and its square belongs in the numerator.
      expect(habitExistedOn(paused, DateTime(2026, 8, 22)), isTrue);
    });

    test('the pause day itself still counts', () {
      // Pausing at 9pm must not blank out squares already earned that day,
      // which is the same rule the Grid row follows.
      expect(habitExistedOn(paused, DateTime(2026, 8, 25)), isTrue);
    });

    test('days after the pause do not', () {
      expect(habitExistedOn(paused, DateTime(2026, 8, 26)), isFalse);
    });

    test('days before it ever existed do not', () {
      expect(habitExistedOn(paused, DateTime(2026, 8, 18)), isFalse);
    });
  });

  group('the scoring that rule produces', () {
    // These pin the arithmetic the rule is chosen for, using the real
    // participant model rather than restating the formula.
    RoomParticipant participant({
      required Map<String, int> done,
      required Map<String, int> scheduled,
    }) =>
        RoomParticipant(
          uid: 'member-uid',
          displayName: 'Aziz',
          characterId: 'male_ghutra_blue',
          joinedAt: DateTime(2026, 8, 19),
          linkedHabitIds: const ['h-mulk', 'h-witr', 'h-train'],
          dailyDoneCount: done,
          dailyScheduledCount: scheduled,
          lastUpdated: DateTime(2026, 8, 25),
        );

    const day = '2026-08-25';

    test('two of two, with the third paused, is a full day', () {
      // The whole point of the choice: an injury does not cap the score.
      final p = participant(done: {day: 2}, scheduled: {day: 2});
      expect(p.creditFor(day), 1.0);
      expect(p.isFullyDone(day), isTrue);
    });

    test('the old behaviour capped the same effort at two thirds', () {
      // What syncTodayForHabit used to write: تمرين in the denominator and
      // never in the numerator. Kept as a contrast so the change is legible.
      final p = participant(done: {day: 2}, scheduled: {day: 3});
      expect(p.creditFor(day), closeTo(0.667, 0.001));
      expect(p.isFullyDone(day), isFalse);
    });

    test('doing nothing while one habit is paused still scores zero', () {
      // Excusing the paused habit must not excuse the two that were simply
      // not done. This is the guard against the rule being read as "paused
      // means the day is forgiven".
      final p = participant(done: {day: 0}, scheduled: {day: 2});
      expect(p.creditFor(day), 0.0);
      expect(p.isFullyDone(day), isFalse);
    });

    test('a day with everything owed and nothing done is still zero', () {
      // Not the pause case any more — that is a stand-down day now, tested
      // above. Kept because it is the shape the formula must keep answering
      // for: three habits owed, none done, no excuse recorded.
      final p = participant(done: {day: 0}, scheduled: {day: 3});
      expect(p.creditFor(day), 0.0);
    });
  });
}
