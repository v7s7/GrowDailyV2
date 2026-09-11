// The gates on the evening streak note and the Friday note, the facts those
// notes are worded from, and the seed that rotates a habit reminder's ask
// across the mornings armed ahead.
//
// Aziz's picks of 2026-09-11 changed what these say, and the words are only
// true under the gates pinned here: the evening note asks for a streak that
// is still open tonight, and the Friday note's numbered copy counts the week
// it fires in. Everything here is a pure static on NotificationService so it
// can be asserted with no device, no plugin and a simulated clock.
//
// The last three groups are the choices main.dart used to make inline, where
// nothing could reach them: which week the note may speak about at all
// (weeklyNoteBasis), which habit names the numbered copy (weekTopHabit), and
// the three counts behind «سوي عادتين بس» (todayBoardCounts).
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/reminder_copy.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';

void main() {
  group('eveningStreakNoteFor', () {
    // Friday 2026-09-11, and the note's default time of 20:30.
    final sixPm = DateTime(2026, 9, 11, 18);
    final tonight = DateTime(2026, 9, 11, 20, 30);

    ReminderLine? note({
      DateTime? now,
      DateTime? fireTime,
      int streak = 7,
      bool earned = false,
      int done = 2,
      int pending = 3,
      int? pendingBuild,
      int urgent = 0,
    }) =>
        NotificationService.eveningStreakNoteFor(
          now: now ?? sixPm,
          fireTime: fireTime ?? tonight,
          streak: streak,
          streakEarnedToday: earned,
          doneHabitCount: done,
          pendingHabitCount: pending,
          pendingBuildHabitCount: pendingBuild ?? pending,
          urgentTasks: urgent,
          isAr: true,
        );

    test('an evening with the streak still open gets the picked note', () {
      expect(
        note(),
        (
          title: 'سلسلتك ماشية ٧ أيام',
          body: '٢ من ٥ خلّصت 👏🏼 سوي عادتين بس، وتصير ٨ أيام.',
        ),
      );
      expect(
        note(urgent: 2)!.body,
        '٢ من ٥ خلّصت 👏🏼 سوي عادتين بس، وتصير ٨ أيام. وعندك مهمتين عاجلتين.',
      );
    });

    test("silent once today's streak point is earned", () {
      for (var done = 0; done <= 6; done++) {
        for (var pending = 1; pending <= 6; pending++) {
          expect(
            note(earned: true, done: done, pending: pending),
            isNull,
            reason: '$done done, $pending left',
          );
        }
      }
    });

    test("armed only for tonight, never tomorrow with today's counts", () {
      // A recompute after 20:30 resolves the next 20:30 to tomorrow.
      expect(
        note(
          now: DateTime(2026, 9, 11, 21),
          fireTime: DateTime(2026, 9, 12, 20, 30),
        ),
        isNull,
      );
      expect(
        note(
          now: DateTime(2026, 9, 11, 23, 59),
          fireTime: DateTime(2026, 9, 12, 20, 30),
        ),
        isNull,
      );
      expect(note(now: DateTime(2026, 9, 11, 20, 29)), isNotNull);
    });

    test('silent with no streak, nothing left, or nothing more needed', () {
      expect(note(streak: 0), isNull);
      expect(note(done: 5, pending: 0), isNull);
      // 4 of 5 already covers the 80% rule, even before the flag lands.
      expect(note(done: 4, pending: 1), isNull);
    });

    test('silent when the build habits left cannot cover what is needed', () {
      // 1 of 5 done needs 3 more, and two of the four left are quit habits,
      // which their own check-in asks about at the same minute.
      expect(note(done: 1, pending: 4, pendingBuild: 2), isNull);
      expect(
        note(done: 1, pending: 4, pendingBuild: 3)!.body,
        '١ من ٥ خلّصت 👏🏼 سوي ٣ عادات بس، وتصير ٨ أيام.',
      );
    });
  });

  group('weeklyNotePlan', () {
    // 2026-09-11 is a Friday.
    const top = (name: 'أذكار الصباح', greenDays: 5, isQuit: false);
    final numberedBody = weeklyNoteCopy(
      habitName: 'أذكار الصباح',
      greenDays: 5,
      isQuit: false,
      isAr: true,
    )!
        .body;
    final repeat = weeklyRepeatCopy(longestStreak: 14, isAr: true);

    ({List<WeeklyNoteSlot> arm, List<int> cancel}) plan(
      DateTime now, {
      WeekTopHabit? topHabit = top,
    }) =>
        NotificationService.weeklyNotePlan(
          now: now,
          topHabit: topHabit,
          longestStreak: 14,
          isAr: true,
        );

    test('Friday before 19:00: the numbered copy once, for tonight only', () {
      final p = plan(DateTime(2026, 9, 11, 15));
      final numbered =
          p.arm.where((s) => s.copy.body == numberedBody).toList();
      expect(numbered, hasLength(1));
      expect(numbered.single.id, 9001);
      expect(numbered.single.copy.title, 'أذكار الصباح');
      expect(numbered.single.fireAt, DateTime(2026, 9, 11, 19));
      expect(numbered.single.repeatsWeekly, isFalse);
      // No weekly repeat beside it: iOS would fire that tonight as well.
      expect(p.arm.where((s) => s.repeatsWeekly), isEmpty);
      expect(p.cancel, [9000]);
      // Next Friday still hears the claim-free copy, once, and only next
      // Friday: each of these is a pending request against iOS's 64 on the
      // one afternoon the fixed ids are at their widest, and what iOS does
      // past 64 has not been measured (see kMaxPendingHabitSlots).
      final rest = p.arm.where((s) => s.copy.body != numberedBody).toList();
      expect([for (final s in rest) s.fireAt], [DateTime(2026, 9, 18, 19)]);
      expect([for (final s in rest) s.id], [9002]);
      for (final s in rest) {
        expect(s.copy, repeat);
        expect(s.repeatsWeekly, isFalse);
      }
      expect(p.arm, hasLength(2), reason: 'two requests on a Friday, not five');
    });

    test('after 19:00 and on every other day: only the claim-free repeat', () {
      for (final now in [
        DateTime(2026, 9, 11, 19, 1),
        DateTime(2026, 9, 11, 22),
        DateTime(2026, 9, 12, 10),
        DateTime(2026, 9, 16, 8),
        DateTime(2026, 9, 17, 23),
      ]) {
        final p = plan(now);
        expect(p.arm, hasLength(1), reason: '$now');
        final slot = p.arm.single;
        expect(slot.id, 9000);
        expect(slot.repeatsWeekly, isTrue);
        expect(slot.copy, repeat);
        expect(slot.fireAt, DateTime(2026, 9, 18, 19), reason: '$now');
        // The numbered copy, delivered at 19:00, stays in the list.
        expect(p.cancel, isNot(contains(9001)), reason: '$now');
        expect(p.cancel, [9002],
            reason: 'exactly the ids this plan can have armed');
      }
      // On a Thursday the repeat's next Friday is tomorrow.
      expect(
        plan(DateTime(2026, 9, 10, 20)).arm.single.fireAt,
        DateTime(2026, 9, 11, 19),
      );
    });

    test('Friday with no week worth numbering: the repeat, tonight', () {
      for (final topHabit in <WeekTopHabit?>[
        null,
        (name: 'أذكار الصباح', greenDays: 2, isQuit: false),
      ]) {
        final p = plan(DateTime(2026, 9, 11, 15), topHabit: topHabit);
        expect(p.arm, hasLength(1));
        expect(p.arm.single.id, 9000);
        expect(p.arm.single.copy, repeat);
        expect(p.arm.single.fireAt, DateTime(2026, 9, 11, 19));
        // A numbered copy armed earlier today, before an undo, is cleared.
        expect(p.cancel, contains(9001));
      }
    });

    test('the numbered copy is never a repeat, and only for its own evening',
        () {
      // Every recompute hour across a fortnight.
      for (var h = 0; h < 24 * 14; h++) {
        final now = DateTime(2026, 9, 5).add(Duration(hours: h));
        for (final s in plan(now).arm) {
          if (s.copy.body != numberedBody) continue;
          expect(s.repeatsWeekly, isFalse, reason: '$now');
          expect(now.weekday, DateTime.friday, reason: '$now');
          expect(
            s.fireAt,
            DateTime(now.year, now.month, now.day, 19),
            reason: '$now',
          );
          expect(now.isBefore(s.fireAt), isTrue, reason: '$now');
        }
      }
    });

    test('a Grid pinned to another week, and back: one copy for tonight', () {
      // A claim-free basis is a plan with no top habit, which is how a Grid
      // showing another week arms the note (see weeklyNoteBasis). What must
      // never happen is two copies left armed for the same 19:00.
      final friday = DateTime(2026, 9, 11, 15);
      final armed = <int, WeeklyNoteSlot>{};
      void apply(({List<WeeklyNoteSlot> arm, List<int> cancel}) p) {
        for (final id in p.cancel) {
          armed.remove(id);
        }
        for (final slot in p.arm) {
          armed[slot.id] = slot;
        }
      }

      // A weekly repeat fires at the next matching weekday and time, which
      // on a Friday afternoon is tonight; a one-shot fires on its own date.
      Iterable<int> tonight() => [
            for (final s in armed.values)
              if (s.repeatsWeekly || s.fireAt == DateTime(2026, 9, 11, 19))
                s.id,
          ];

      apply(plan(friday));
      expect(tonight(), [9001]);

      apply(plan(friday.add(const Duration(minutes: 10)), topHabit: null));
      expect(tonight(), [9000], reason: 'the claim-free copy takes over');
      expect(armed[9000]!.copy, repeat);

      apply(plan(friday.add(const Duration(minutes: 20))));
      expect(tonight(), [9001], reason: 'the numbered copy is back');
      expect(armed.keys.toSet(), {9001, 9002},
          reason: 'and the repeat that would have doubled it is gone');
    });

    test('a quit habit is counted in التزام', () {
      final p = plan(
        DateTime(2026, 9, 11, 9),
        topHabit: (name: 'ترك التدخين', greenDays: 4, isQuit: true),
      );
      expect(
        p.arm.first.copy,
        (
          title: 'ترك التدخين',
          body: '٤ أيام التزام هذا الأسبوع 👏🏼 والليلة تختم الأسبوع.',
        ),
      );
    });
  });

  group('weeklyNoteBasis', () {
    WeeklyNoteBasis basis({required bool loading, required bool current}) =>
        NotificationService.weeklyNoteBasis(
          gridLoading: loading,
          gridOnCurrentWeek: current,
        );

    test('a Grid mid-load is left alone, whatever week it is opening', () {
      expect(basis(loading: true, current: true), WeeklyNoteBasis.skip);
      expect(basis(loading: true, current: false), WeeklyNoteBasis.skip);
    });

    test('this week is numbered, and any other week is not', () {
      expect(basis(loading: false, current: true), WeeklyNoteBasis.numbered);
      // The case that used to be skipped. A Grid paged back to a past week
      // stays there across recomputes, so skipping left this morning's
      // numbered copy armed with a count a habit finished since had made
      // false, and 19:00 delivered it.
      expect(basis(loading: false, current: false), WeeklyNoteBasis.claimFree);
    });
  });

  group('weekTopHabit', () {
    /// A week of seven squares, the ones given and the rest empty.
    List<SquareState> week(List<SquareState> squares) => [
          ...squares,
          for (var i = squares.length; i < 7; i++) SquareState.none,
        ];
    const green = SquareState.complete;

    test('the most green days names the note, and a tie keeps the first', () {
      expect(
        NotificationService.weekTopHabit([
          (name: 'أذكار الصباح', isQuit: false, squares: week([green, green])),
          (
            name: 'قراءة القرآن',
            isQuit: false,
            squares: week([green, green, green]),
          ),
          (name: 'تمرين', isQuit: false, squares: week([green, green, green])),
        ]),
        (name: 'قراءة القرآن', greenDays: 3, isQuit: false),
        reason: 'habit order decides a tie, and main.dart hands them over in '
            'that order',
      );
    });

    test('only green days count', () {
      expect(
        NotificationService.weekTopHabit([
          (
            name: 'أذكار الصباح',
            isQuit: false,
            squares: week([
              green,
              SquareState.bonus,
              SquareState.partial,
              SquareState.failed,
              SquareState.skipped,
            ]),
          ),
        ]),
        (name: 'أذكار الصباح', greenDays: 2, isQuit: false),
        reason: 'a جزئي day is not a day «٥ أيام خضرا» may count, and bonus '
            'is drawn green',
      );
    });

    test('a quit habit carries its flag, and no habits at all is null', () {
      expect(
        NotificationService.weekTopHabit([
          (
            name: 'ترك التدخين',
            isQuit: true,
            squares: week([green, green, green, green]),
          ),
        ]),
        (name: 'ترك التدخين', greenDays: 4, isQuit: true),
      );
      expect(NotificationService.weekTopHabit([]), isNull);
      // A habit with nothing green is still returned: weeklyNoteCopy is the
      // one that refuses to number a thin week, in one place.
      expect(
        NotificationService.weekTopHabit([
          (name: 'تمرين', isQuit: false, squares: week([])),
        ]),
        (name: 'تمرين', greenDays: 0, isQuit: false),
      );
      expect(
        weeklyNoteCopy(
          habitName: 'تمرين',
          greenDays: 0,
          isQuit: false,
          isAr: true,
        ),
        isNull,
      );
    });
  });

  group('todayBoardCounts', () {
    test('what is done, what is left, and the build habits among them', () {
      expect(
        NotificationService.todayBoardCounts([
          (isDone: true, isQuit: false),
          (isDone: true, isQuit: true),
          (isDone: false, isQuit: false),
          (isDone: false, isQuit: false),
          (isDone: false, isQuit: true),
        ]),
        (done: 2, pending: 3, pendingBuild: 2),
      );
      expect(
        NotificationService.todayBoardCounts([]),
        (done: 0, pending: 0, pendingBuild: 0),
      );
    });

    test('a quit habit left is pending and never a build habit', () {
      // «سوي عادتين بس» asks for habits to be DONE, and a quit habit is
      // answered by its own check-in at the same minute. Counted here, the
      // note would ask for something that cannot be done.
      final counts = NotificationService.todayBoardCounts([
        (isDone: false, isQuit: true),
        (isDone: false, isQuit: true),
      ]);
      expect(counts, (done: 0, pending: 2, pendingBuild: 0));
      expect(
        NotificationService.eveningStreakNoteFor(
          now: DateTime(2026, 9, 11, 18),
          fireTime: DateTime(2026, 9, 11, 20, 30),
          streak: 7,
          streakEarnedToday: false,
          doneHabitCount: counts.done,
          pendingHabitCount: counts.pending,
          pendingBuildHabitCount: counts.pendingBuild,
          urgentTasks: 0,
          isAr: true,
        ),
        isNull,
        reason: 'nothing the note could ask for tonight',
      );
    });
  });

  group('reminderVariantSeed', () {
    test('one seed per fire day, whatever the hour', () {
      expect(
        NotificationService.reminderVariantSeed(
          DateTime(2026, 9, 12, 4, 32),
          'h1',
        ),
        NotificationService.reminderVariantSeed(DateTime(2026, 9, 12, 21), 'h1'),
      );
    });

    test('the mornings armed ahead do not all hear the same ask', () {
      // The copies armed on one evening used to share that evening's seed,
      // so a phone left closed read one ask every morning running.
      final asks = {
        for (var d = 0; d < NotificationService.kOccurrencesPerSlot; d++)
          lateReminderAsk(
            NotificationService.reminderVariantSeed(
              DateTime(2026, 9, 12 + d, 4, 32),
              'sunnah-fajr',
            ),
            true,
          ),
      };
      expect(asks.length, greaterThan(1));
    });
  });
}
