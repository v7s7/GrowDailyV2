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
}
