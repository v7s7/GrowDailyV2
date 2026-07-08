import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/utils/xp_calculator.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SquareState', () {
    test('tap cycle follows white → yellow → green → white', () {
      expect(SquareState.none.next, SquareState.partial);
      expect(SquareState.partial.next, SquareState.complete);
      expect(SquareState.complete.next, SquareState.none);
      // Advanced colors tap back to a clean slate.
      expect(SquareState.failed.next, SquareState.none);
      expect(SquareState.bonus.next, SquareState.none);
      expect(SquareState.skipped.next, SquareState.none);
    });

    test('fixed XP values match the spec', () {
      expect(SquareState.complete.xpValue, 10);
      expect(SquareState.partial.xpValue, 5);
      expect(SquareState.bonus.xpValue, 15);
      expect(SquareState.failed.xpValue, -3);
      expect(SquareState.none.xpValue, 0);
      expect(SquareState.skipped.xpValue, 0);
    });

    test('green means complete or bonus, nothing else', () {
      expect(
        SquareState.values.where((s) => s.isGreen),
        [SquareState.complete, SquareState.bonus],
      );
    });
  });

  group('XpCalculator.applyXpDelta', () {
    test('negative delta trims XP but never de-levels', () {
      final r = XpCalculator.applyXpDelta(
        currentLevel: 3,
        currentLevelXp: 2,
        cumulativeXp: 302,
        xpDelta: -10,
      );
      expect(r.newLevel, 3);
      expect(r.newCurrentLevelXp, 0);
      expect(r.newCumulativeXp, 292);
    });

    test('positive delta still multi-levels through applyXpGain', () {
      final r = XpCalculator.applyXpDelta(
        currentLevel: 1,
        currentLevelXp: 95,
        cumulativeXp: 95,
        xpDelta: 10,
      );
      expect(r.newLevel, 2);
      expect(r.newCurrentLevelXp, 5);
    });
  });

  group('startOfGridWeek', () {
    test('always returns the Saturday on or before the date', () {
      // 2026-07-05 is a Sunday → week starts Saturday 2026-07-04.
      expect(
        startOfGridWeek(DateTime(2026, 7, 5)),
        DateTime(2026, 7, 4),
      );
      // A Saturday is its own week start.
      expect(
        startOfGridWeek(DateTime(2026, 7, 4)),
        DateTime(2026, 7, 4),
      );
      // A Friday belongs to the previous Saturday's week.
      expect(
        startOfGridWeek(DateTime(2026, 7, 10)),
        DateTime(2026, 7, 4),
      );
    });
  });

  group('grid → dashboard progression pipeline (guest path)', () {
    late Directory tmp;
    late ProviderContainer container;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('grid_test_');
      Hive.init(tmp.path);
      container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        ],
      );
      // Resolve auth first so dependent notifiers are created exactly once —
      // otherwise the stream's async emission rebuilds them mid-test and
      // mutations land on a notifier that's about to be discarded.
      await container.read(authStateProvider.future);
      // Wait until the guest notifiers actually finish loading — a fixed
      // delay races the first (cold) Hive open and the late load result
      // would clobber XP earned by the test's own mutations.
      container.read(weeklyGridProvider);
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while ((container.read(dashboardProvider).isLoading ||
              container.read(weeklyGridProvider).isLoading) &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(container.read(dashboardProvider).isLoading, isFalse);
    });

    tearDown(() async {
      container.dispose();
      await Hive.deleteFromDisk();
      await tmp.delete(recursive: true);
    });

    test(
        'the first green square awards +10 XP, the First Victory achievement, and today\'s streak',
        () async {
      final today = DateTime.now();
      container
          .read(weeklyGridProvider.notifier)
          .setSquare('habit_a', today, SquareState.complete);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final dash = container.read(dashboardProvider);
      // +10 for the square, +25 from the First Victory unlock.
      expect(dash.cumulativeXp, 35);
      expect(dash.unlockedAchievements, contains('green_1'));
      expect(dash.gold, 10);
      expect(dash.totalGreenSquares, 1);
      expect(dash.streak, 1);
      expect(dash.gridActivityToday, isTrue);

      final key =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      expect(dash.dailyGreenCounts[key], 1);
    });

    test('cycling a square back and forth cannot farm XP or streaks',
        () async {
      final today = DateTime.now();
      final grid = container.read(weeklyGridProvider.notifier);

      grid.setSquare('habit_a', today, SquareState.complete);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      grid.setSquare('habit_a', today, SquareState.none);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      grid.setSquare('habit_a', today, SquareState.complete);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final dash = container.read(dashboardProvider);
      // Net effect identical to coloring it green once (+10 square, +25
      // one-time First Victory) — the achievement never re-unlocks.
      expect(dash.cumulativeXp, 35);
      expect(dash.totalGreenSquares, 1);
      // The streak bumped exactly once despite three changes.
      expect(dash.streak, 1);
    });

    test('a red square costs 3 XP but the floor is zero', () async {
      final today = DateTime.now();
      container
          .read(weeklyGridProvider.notifier)
          .setSquare('habit_a', today, SquareState.failed);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final dash = container.read(dashboardProvider);
      expect(dash.cumulativeXp, 0); // 0 - 3 floors at 0
      expect(dash.totalGreenSquares, 0);
      expect(dash.streak, 0); // red never earns a streak
    });

    test(
        'coloring a past day green persists visually but awards zero XP, gold, or achievement credit',
        () async {
      final pastDay = DateTime.now().subtract(const Duration(days: 3));
      final grid = container.read(weeklyGridProvider.notifier);

      grid.setSquare('habit_a', pastDay, SquareState.complete);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Visual record still updates — Grid stays an honest "what did I do"
      // log even for a day logged after the fact.
      expect(
        container.read(weeklyGridProvider).squareFor('habit_a', pastDay),
        SquareState.complete,
      );

      // But nothing reaches the reward system: no free XP/gold/achievement
      // farming by backdating squares to a day that was never lived through.
      final dash = container.read(dashboardProvider);
      expect(dash.cumulativeXp, 0);
      expect(dash.gold, 0);
      expect(dash.totalGreenSquares, 0);
      expect(dash.unlockedAchievements, isNot(contains('green_1')));
      expect(dash.streak, 0);

      final key = pastDay.toDateKey();
      expect(dash.dailyGreenCounts[key], isNull);
    });

    test('grid state cycles and persists square + note per habit per day',
        () async {
      final today = DateTime.now();
      final grid = container.read(weeklyGridProvider.notifier);

      grid.cycleSquare('habit_a', today); // → partial
      expect(
        container.read(weeklyGridProvider).squareFor('habit_a', today),
        SquareState.partial,
      );
      grid.cycleSquare('habit_a', today); // → complete
      expect(
        container.read(weeklyGridProvider).squareFor('habit_a', today),
        SquareState.complete,
      );

      grid.setNote('habit_a', today, '  felt great  ');
      expect(
        container.read(weeklyGridProvider).noteFor('habit_a', today),
        'felt great',
      );
    });

    test(
        "Today's habit-list completion (DashboardNotifier.completeHabit) "
        'awards XP, gold, and a streak point', () async {
      final ok = await container.read(dashboardProvider.notifier).completeHabit(
            habitId: 'habit_today',
            xpReward: 20,
            goldReward: 8,
            frequencyTarget: 1,
            category: 'custom',
            habitName: 'Test Habit',
          );

      final dash = container.read(dashboardProvider);
      expect(ok, isTrue); // single-tap habit → Grid should mirror it
      // Single-tap completions also count as a green square (same field
      // Grid itself writes), so this is also the very first one — it earns
      // +20 for the habit plus +25/+10 from the one-time "First Victory"
      // achievement, exactly like coloring the first Grid square does.
      expect(dash.cumulativeXp, 45);
      expect(dash.gold, 18);
      expect(dash.unlockedAchievements, contains('green_1'));
      expect(dash.streak, 1);
      expect(dash.completions['habit_today'], 1);
      expect(dash.categoryCompletions['custom'], 1);
    });

    test('completing the same habit twice today does not double-pay',
        () async {
      final notifier = container.read(dashboardProvider.notifier);
      await notifier.completeHabit(
        habitId: 'habit_once',
        xpReward: 20,
        goldReward: 8,
        frequencyTarget: 1,
        category: 'custom',
        habitName: 'Test Habit',
      );
      final afterFirst = container.read(dashboardProvider);
      final second = await notifier.completeHabit(
        habitId: 'habit_once',
        xpReward: 20,
        goldReward: 8,
        frequencyTarget: 1,
        category: 'custom',
        habitName: 'Test Habit',
      );

      expect(second, isFalse); // already-done guard, no new reward
      final dash = container.read(dashboardProvider);
      expect(dash.cumulativeXp, afterFirst.cumulativeXp);
      expect(dash.gold, afterFirst.gold);
    });

    test(
        'completing two different habits the same day bumps the streak at '
        'most once', () async {
      final notifier = container.read(dashboardProvider.notifier);
      await notifier.completeHabit(
        habitId: 'habit_1',
        xpReward: 10,
        goldReward: 5,
        frequencyTarget: 1,
        category: 'custom',
        habitName: 'Habit One',
      );
      final afterFirst = container.read(dashboardProvider);
      await notifier.completeHabit(
        habitId: 'habit_2',
        xpReward: 10,
        goldReward: 5,
        frequencyTarget: 1,
        category: 'custom',
        habitName: 'Habit Two',
      );

      final dash = container.read(dashboardProvider);
      expect(dash.streak, 1);
      expect(afterFirst.streak, 1); // the streak point came from habit_1...
      // ...and habit_2 still pays its own +10 XP/+5 gold, just with no
      // second streak point and no repeat of the one-time achievement bonus.
      expect(dash.cumulativeXp, afterFirst.cumulativeXp + 10);
      expect(dash.gold, afterFirst.gold + 5);
    });
  });
}
