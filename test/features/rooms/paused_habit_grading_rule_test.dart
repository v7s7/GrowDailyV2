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
          reason: 'callers must fall back to scheduled-and-never-done here');
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

    test('scores zero for every paused day, not a free full day', () {
      final p = RoomParticipant(
        uid: 'member-uid',
        displayName: 'Aziz',
        characterId: 'male_ghutra_blue',
        joinedAt: DateTime(2026, 8, 19),
        linkedHabitIds: const ['h-train'],
        // What the fallback writes: the one habit back in the denominator.
        dailyDoneCount: const {'2026-08-26': 0},
        dailyScheduledCount: const {'2026-08-26': 1},
        lastUpdated: DateTime(2026, 8, 26),
      );
      expect(p.creditFor('2026-08-26'), 0.0);
      expect(p.isFullyDone('2026-08-26'), isFalse);
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

    test('pausing everything scores zero, not a free full day', () {
      // The fallback in action: all three counted as scheduled, none done.
      final p = participant(done: {day: 0}, scheduled: {day: 3});
      expect(p.creditFor(day), 0.0,
          reason: 'pausing your whole commitment is not a 100% day');
    });
  });
}
