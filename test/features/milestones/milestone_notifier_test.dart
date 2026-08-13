// Pure-logic tests for the two collection-level MilestoneEvent transforms —
// see groupMilestonesByMonth and tallyMilestonesByType (milestone_notifier.
// dart). Both are read by JourneyPage, MonthlyStoryScreen, and/or Life
// Timeline; pinning them down here means those screens don't each need their
// own coverage of the same grouping/counting logic.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/milestones/models/milestone_event.dart';
import 'package:grow_daily_v2/features/milestones/notifiers/milestone_notifier.dart';

void main() {
  MilestoneEvent event(MilestoneType type, DateTime occurredAt) =>
      MilestoneEvent(id: '', type: type, occurredAt: occurredAt);

  group('groupMilestonesByMonth', () {
    test('buckets events into their calendar month, most recent month first',
        () {
      final events = [
        event(MilestoneType.levelUp, DateTime(2026, 7, 20)),
        event(MilestoneType.perfectDay, DateTime(2026, 7, 2)),
        event(MilestoneType.streakMilestone, DateTime(2026, 5, 15)),
      ];
      final grouped = groupMilestonesByMonth(events);

      expect(grouped.keys.toList(), [DateTime(2026, 7), DateTime(2026, 5)]);
      expect(grouped[DateTime(2026, 7)]!.length, 2);
      expect(grouped[DateTime(2026, 5)]!.length, 1);
    });

    test('preserves each event\'s relative order within its own month', () {
      final newer = event(MilestoneType.levelUp, DateTime(2026, 7, 20));
      final older = event(MilestoneType.perfectDay, DateTime(2026, 7, 2));
      // Passed in newest-first, the same order milestoneEventsProvider's
      // Firestore query already returns.
      final grouped = groupMilestonesByMonth([newer, older]);
      expect(grouped[DateTime(2026, 7)], [newer, older]);
    });

    test('empty input produces an empty map, not an error', () {
      expect(groupMilestonesByMonth(const []), isEmpty);
    });
  });

  group('tallyMilestonesByType', () {
    test('counts each type independently across a mixed list', () {
      final events = [
        event(MilestoneType.levelUp, DateTime(2026, 1, 1)),
        event(MilestoneType.levelUp, DateTime(2026, 1, 2)),
        event(MilestoneType.perfectDay, DateTime(2026, 1, 3)),
      ];
      final tally = tallyMilestonesByType(events);
      expect(tally[MilestoneType.levelUp], 2);
      expect(tally[MilestoneType.perfectDay], 1);
      // A type with zero hits is simply absent, not present with a 0 —
      // callers use `tally[t] ?? 0`, same convention as
      // DashboardState.categoryCompletions.
      expect(tally.containsKey(MilestoneType.perfectWeek), isFalse);
    });

    test('accepts a lazy Iterable (e.g. a .where() result), not just a List',
        () {
      final events = [
        event(MilestoneType.levelUp, DateTime(2026, 1, 1)),
        event(MilestoneType.perfectDay, DateTime(2026, 2, 1)),
      ];
      final tally =
          tallyMilestonesByType(events.where((e) => e.occurredAt.month == 1));
      expect(tally, {MilestoneType.levelUp: 1});
    });

    test('empty input produces an empty map', () {
      expect(tallyMilestonesByType(const []), isEmpty);
    });
  });
}
