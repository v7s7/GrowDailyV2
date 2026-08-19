// Pure-logic tests for computeMonthlyStory (monthly_story_screen.dart) — the
// monthly-grain sibling of computeWeeklyRecap (see weekly_recap_test.dart for
// that one). Covers the month-boundary filtering (both for green-square
// counts and for milestone tallies), the year-rollover previous-month
// lookup, and the hasAnything/milestoneCount derived getters the empty-state
// branch and the tally grid both depend on.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/milestones/models/milestone_event.dart';
import 'package:grow_daily_v2/features/milestones/screens/monthly_story_screen.dart';

void main() {
  final july = DateTime(2026, 7);

  MilestoneEvent event(MilestoneType type, DateTime occurredAt) =>
      MilestoneEvent(id: '', type: type, occurredAt: occurredAt);

  group('computeMonthlyStory — green squares', () {
    test('sums only days inside the target month', () {
      final counts = {
        DateTime(2026, 7, 1).toDateKey(): 2,
        DateTime(2026, 7, 31).toDateKey(): 3,
        DateTime(2026, 6, 30).toDateKey(): 99, // just before — must not leak
        DateTime(2026, 8, 1).toDateKey(): 99, // just after — must not leak
      };
      final data = computeMonthlyStory(
          dailyGreenCounts: counts, month: july, allMilestones: const []);
      expect(data.totalGreenSquares, 5);
      expect(data.activeDays, 2);
    });

    test('bestDay is the single highest-count day in the month', () {
      final counts = {
        DateTime(2026, 7, 5).toDateKey(): 2,
        DateTime(2026, 7, 12).toDateKey(): 6,
        DateTime(2026, 7, 20).toDateKey(): 4,
      };
      final data = computeMonthlyStory(
          dailyGreenCounts: counts, month: july, allMilestones: const []);
      expect(data.bestDay, DateTime(2026, 7, 12));
      expect(data.bestDayCount, 6);
    });

    test('prevMonthTotal reads the actual previous calendar month', () {
      final counts = {
        DateTime(2026, 6, 15).toDateKey(): 10,
        DateTime(2026, 7, 15).toDateKey(): 4,
      };
      final data = computeMonthlyStory(
          dailyGreenCounts: counts, month: july, allMilestones: const []);
      expect(data.prevMonthTotal, 10);
      expect(data.delta, 4 - 10);
    });

    test('prevMonthTotal rolls back across a year boundary correctly', () {
      final january = DateTime(2026, 1);
      final counts = {
        DateTime(2025, 12, 31).toDateKey(): 7, // Dec of the prior year
        DateTime(2026, 1, 1).toDateKey(): 1,
      };
      final data = computeMonthlyStory(
          dailyGreenCounts: counts, month: january, allMilestones: const []);
      expect(data.prevMonthTotal, 7);
    });

    test('an empty month has zero totals and no best day', () {
      final data = computeMonthlyStory(
          dailyGreenCounts: const {}, month: july, allMilestones: const []);
      expect(data.totalGreenSquares, 0);
      expect(data.activeDays, 0);
      expect(data.bestDay, isNull);
    });
  });

  group('computeMonthlyStory — milestone tallies', () {
    test('counts each tracked type only within the target month', () {
      final milestones = [
        event(MilestoneType.levelUp, DateTime(2026, 7, 3)),
        event(MilestoneType.levelUp, DateTime(2026, 7, 18)),
        event(MilestoneType.perfectDay, DateTime(2026, 7, 9)),
        event(MilestoneType.perfectWeek, DateTime(2026, 7, 9)),
        event(MilestoneType.streakMilestone, DateTime(2026, 7, 9)),
        event(MilestoneType.achievementUnlocked, DateTime(2026, 7, 9)),
        // Outside July — must not be counted.
        event(MilestoneType.levelUp, DateTime(2026, 6, 30)),
        event(MilestoneType.levelUp, DateTime(2026, 8, 1)),
      ];
      final data = computeMonthlyStory(
          dailyGreenCounts: const {}, month: july, allMilestones: milestones);
      expect(data.levelUps, 2);
      expect(data.perfectDays, 1);
      expect(data.perfectWeeks, 1);
      expect(data.streakMilestones, 1);
      expect(data.achievementsUnlocked, 1);
      expect(data.milestoneCount, 2 + 1 + 1 + 1 + 1);
    });

    test('joined and roomChallengeComplete events don\'t affect any tally',
        () {
      final milestones = [
        event(MilestoneType.joined, DateTime(2026, 7, 1)),
        event(MilestoneType.roomChallengeComplete, DateTime(2026, 7, 1)),
      ];
      final data = computeMonthlyStory(
          dailyGreenCounts: const {}, month: july, allMilestones: milestones);
      expect(data.milestoneCount, 0);
    });
  });

  group('computeMonthlyStory — hasAnything', () {
    test('false when the month has no green squares and no milestones', () {
      final data = computeMonthlyStory(
          dailyGreenCounts: const {}, month: july, allMilestones: const []);
      expect(data.hasAnything, isFalse);
    });

    test('true from green squares alone, even with zero milestones', () {
      final data = computeMonthlyStory(
        dailyGreenCounts: {DateTime(2026, 7, 1).toDateKey(): 1},
        month: july,
        allMilestones: const [],
      );
      expect(data.hasAnything, isTrue);
    });

    test('true from a milestone alone, even with zero green squares', () {
      final data = computeMonthlyStory(
        dailyGreenCounts: const {},
        month: july,
        allMilestones: [event(MilestoneType.perfectDay, DateTime(2026, 7, 1))],
      );
      expect(data.hasAnything, isTrue);
    });
  });

  // ── Month navigation bounds ────────────────────────────────────────
  //
  // The bug these guard: `createdAt` is written only when a user doc is
  // first created, so accounts predating that field have none at all (23
  // of 25 production docs on 2026-08-18). The old bounds treated a missing
  // createdAt as "this month", which made canGoBack and canGoForward both
  // false and froze the screen on the current month with months of real
  // data unreachable.
  group('earliestStoryMonth', () {
    final august = DateTime(2026, 8);

    test('falls back to the first month with data when createdAt is null',
        () {
      final counts = {
        DateTime(2026, 6, 13).toDateKey(): 1,
        DateTime(2026, 7, 4).toDateKey(): 3,
        DateTime(2026, 8, 18).toDateKey(): 2,
      };
      expect(
        earliestStoryMonth(
          dailyGreenCounts: counts,
          accountCreatedAt: null,
          currentMonth: august,
        ),
        DateTime(2026, 6),
      );
    });

    test('a null createdAt with data no longer freezes the screen', () {
      // The exact regression: same inputs as the real account that
      // reported it. If this returns August, both arrows go dead again.
      final counts = {DateTime(2026, 6, 13).toDateKey(): 1};
      final earliest = earliestStoryMonth(
        dailyGreenCounts: counts,
        accountCreatedAt: null,
        currentMonth: august,
      );
      expect(august.isAfter(earliest), isTrue,
          reason: 'canGoBack must be true from the current month');
    });

    test('data older than createdAt still wins', () {
      // A guest whose local history is merged into a brand-new account.
      final counts = {DateTime(2026, 3, 2).toDateKey(): 4};
      expect(
        earliestStoryMonth(
          dailyGreenCounts: counts,
          accountCreatedAt: DateTime(2026, 7, 21),
          currentMonth: august,
        ),
        DateTime(2026, 3),
      );
    });

    test('createdAt older than any data still wins', () {
      // Someone who signed up in January and only started logging in June
      // can still look back at the months they missed.
      final counts = {DateTime(2026, 6, 1).toDateKey(): 1};
      expect(
        earliestStoryMonth(
          dailyGreenCounts: counts,
          accountCreatedAt: DateTime(2026, 1, 9),
          currentMonth: august,
        ),
        DateTime(2026, 1),
      );
    });

    test('zero-count days are not treated as data', () {
      final counts = {
        DateTime(2026, 5, 1).toDateKey(): 0,
        DateTime(2026, 7, 1).toDateKey(): 2,
      };
      expect(
        earliestStoryMonth(
          dailyGreenCounts: counts,
          accountCreatedAt: null,
          currentMonth: august,
        ),
        DateTime(2026, 7),
      );
    });

    test('a brand-new account with nothing yet sits on the current month',
        () {
      expect(
        earliestStoryMonth(
          dailyGreenCounts: const {},
          accountCreatedAt: null,
          currentMonth: august,
        ),
        august,
      );
    });

    test('a future createdAt cannot push the floor above the ceiling', () {
      // Clock skew or a bad import. The old code could not produce this,
      // but the new minimum could, and it would re-freeze the screen.
      final earliest = earliestStoryMonth(
        dailyGreenCounts: const {},
        accountCreatedAt: DateTime(2027, 4, 1),
        currentMonth: august,
      );
      expect(earliest, august);
      expect(earliest.isAfter(august), isFalse);
    });

    test('unparseable date keys are ignored rather than throwing', () {
      final counts = {'not-a-date': 5, DateTime(2026, 7, 1).toDateKey(): 1};
      expect(
        earliestStoryMonth(
          dailyGreenCounts: counts,
          accountCreatedAt: null,
          currentMonth: august,
        ),
        DateTime(2026, 7),
      );
    });
  });

  group('storyMonthsBetween', () {
    test('lists every month inclusive, newest first', () {
      final months =
          storyMonthsBetween(DateTime(2026, 6), DateTime(2026, 8));
      expect(months, [
        DateTime(2026, 8),
        DateTime(2026, 7),
        DateTime(2026, 6),
      ]);
    });

    test('crosses a year boundary without gaps or repeats', () {
      final months =
          storyMonthsBetween(DateTime(2025, 11), DateTime(2026, 2));
      expect(months, [
        DateTime(2026, 2),
        DateTime(2026, 1),
        DateTime(2025, 12),
        DateTime(2025, 11),
      ]);
    });

    test('a single month yields exactly one entry', () {
      expect(storyMonthsBetween(DateTime(2026, 8), DateTime(2026, 8)),
          [DateTime(2026, 8)]);
    });

    test('an inverted range degrades to the current month, never empty', () {
      // An empty list would render a picker with nothing in it.
      expect(storyMonthsBetween(DateTime(2027, 1), DateTime(2026, 8)),
          [DateTime(2026, 8)]);
    });

    test('day-of-month on either end is normalised away', () {
      expect(
        storyMonthsBetween(DateTime(2026, 7, 29), DateTime(2026, 8, 3)),
        [DateTime(2026, 8), DateTime(2026, 7)],
      );
    });
  });

  // ── The delta, and what it is compared against ─────────────────────
  //
  // The screenshot that prompted this showed "34" beside an amber "-48":
  // 18 days of August measured against all 31 days of July. Both figures
  // were right and the comparison was not, and it misreads that way for
  // almost every user on almost every day of the month.
  group('computeMonthlyStory — delta baseline', () {
    Map<String, int> everyDay(int year, int month, int days, int perDay) => {
          for (var d = 1; d <= days; d++)
            DateTime(year, month, d).toDateKey(): perDay,
        };

    test('a month in progress compares against the same stretch', () {
      final counts = {
        ...everyDay(2026, 7, 31, 2), // 62 across all of July
        ...everyDay(2026, 8, 18, 2), // 36 across August so far
      };
      final data = computeMonthlyStory(
        dailyGreenCounts: counts,
        month: DateTime(2026, 8),
        allMilestones: const [],
        today: DateTime(2026, 8, 18),
      );
      expect(data.totalGreenSquares, 36);
      // July's first 18 days, not all 31. An identical month reads as a
      // dead heat, which is the truth.
      expect(data.prevMonthTotal, 36);
      expect(data.delta, 0);
      expect(data.showsDelta, isFalse);
    });

    test('without the fix the same month would read as a large deficit', () {
      // The old behaviour, reproduced by omitting `today`: a finished
      // month is still compared whole, which is correct for a PAST month
      // and is exactly what made the current month look bad.
      final counts = {
        ...everyDay(2026, 7, 31, 2),
        ...everyDay(2026, 8, 18, 2),
      };
      final whole = computeMonthlyStory(
        dailyGreenCounts: counts,
        month: DateTime(2026, 8),
        allMilestones: const [],
      );
      expect(whole.prevMonthTotal, 62);
      expect(whole.delta, -26);
    });

    test('a finished month still compares against the whole month', () {
      final counts = {
        ...everyDay(2026, 6, 30, 1),
        ...everyDay(2026, 7, 31, 1),
      };
      final data = computeMonthlyStory(
        dailyGreenCounts: counts,
        month: DateTime(2026, 7),
        allMilestones: const [],
        today: DateTime(2026, 8, 18), // browsing back, not the live month
      );
      expect(data.prevMonthTotal, 30);
      expect(data.delta, 1);
    });

    test('the 31st clamps against a 30-day previous month', () {
      final counts = {
        ...everyDay(2026, 4, 30, 1), // April has 30 days
        ...everyDay(2026, 5, 31, 1),
      };
      final data = computeMonthlyStory(
        dailyGreenCounts: counts,
        month: DateTime(2026, 5),
        allMilestones: const [],
        today: DateTime(2026, 5, 31),
      );
      // Not an out-of-range read of a 31st that April does not have.
      expect(data.prevMonthTotal, 30);
    });

    test('the earliest month shows no delta at all', () {
      // Its "previous month" predates the account, so the total is zero
      // and the delta used to print as a green +N identical to the number
      // beside it.
      final counts = everyDay(2026, 6, 30, 1);
      final data = computeMonthlyStory(
        dailyGreenCounts: counts,
        month: DateTime(2026, 6),
        allMilestones: const [],
        earliestMonth: DateTime(2026, 6),
      );
      expect(data.totalGreenSquares, 30);
      expect(data.delta, 30, reason: 'the raw delta is unchanged');
      expect(data.showsDelta, isFalse, reason: 'but it is not shown');
    });

    test('a later month still shows its delta', () {
      final counts = {
        ...everyDay(2026, 6, 30, 1),
        ...everyDay(2026, 7, 31, 1),
      };
      final data = computeMonthlyStory(
        dailyGreenCounts: counts,
        month: DateTime(2026, 7),
        allMilestones: const [],
        earliestMonth: DateTime(2026, 6),
      );
      expect(data.showsDelta, isTrue);
    });

    test('omitting both new arguments preserves the old behaviour exactly',
        () {
      // Every existing caller and test passes neither, so the pure tally
      // must be untouched by this change.
      final counts = {
        ...everyDay(2026, 6, 30, 1),
        ...everyDay(2026, 7, 31, 2),
      };
      final data = computeMonthlyStory(
        dailyGreenCounts: counts,
        month: DateTime(2026, 7),
        allMilestones: const [],
      );
      expect(data.prevMonthTotal, 30);
      expect(data.hasBaseline, isTrue);
    });
  });

  group('earliestStoryMonth — safety cap', () {
    test('a bogus ancient date cannot open thousands of month cells', () {
      // dailyGreenCounts is user-doc data. One corrupt key must not make
      // the picker try to render 20,000 chips.
      final counts = {DateTime(1900, 1, 1).toDateKey(): 1};
      final earliest = earliestStoryMonth(
        dailyGreenCounts: counts,
        accountCreatedAt: null,
        currentMonth: DateTime(2026, 8),
      );
      expect(earliest, DateTime(2006, 9));
      expect(storyMonthsBetween(earliest, DateTime(2026, 8)).length, 240);
    });

    test('a genuine long history is untouched by the cap', () {
      final counts = {DateTime(2020, 3, 4).toDateKey(): 1};
      expect(
        earliestStoryMonth(
          dailyGreenCounts: counts,
          accountCreatedAt: null,
          currentMonth: DateTime(2026, 8),
        ),
        DateTime(2020, 3),
      );
    });
  });
}
