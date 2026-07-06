import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

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
  });
}
