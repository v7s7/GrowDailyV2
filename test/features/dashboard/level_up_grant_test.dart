// Gold paid for reaching a level that opens nothing else.
//
// Eleven levels between 2 and 25 award nothing at all: every other rung in
// that range opens a character, an accessory, a prestige rank or a medal.
// These fill that drought. (Level 15 used to be one of the eleven too, until
// a prestige rank landed there 2026-09-21 - see PrestigeCatalog.)
//
// The whole design rests on one property: levelGrantPaidThrough is a
// MONOTONE HIGH-WATER MARK, not a counter. Every payment covers the span
// (mark, newLevel] and then moves the mark. That is what makes a multi-level
// jump pay each crossed level once, a reload pay nothing, and an account
// that already sits at level 60 collect nothing retroactively. These tests
// pin each of those, because the failure mode is paying real money twice.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/core/utils/xp_calculator.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/square_audit.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';
import 'package:hive/hive.dart';

import '../../helpers/never_bonus_random.dart';
import '../../helpers/wait_until.dart';

void main() {
  group('the grant map', () {
    test('it covers only levels that award nothing else', () {
      // Levels 5, 8, 10, 12, 14, 15, 16, 18, 20, 21, 23, 24, 25 all open a
      // character, an accessory, a prestige rank or a medal. A grant there
      // would be paying twice for one level-up.
      const alreadyOccupied = [
        1, 5, 8, 10, 12, 14, 15, 16, 18, 20, 21, 23, 24, 25,
      ];
      for (final l in alreadyOccupied) {
        expect(
          DashboardNotifier.levelUpGoldGrants.containsKey(l),
          isFalse,
          reason: 'level $l already awards something',
        );
      }
    });

    test('no grant outshines the medal at a comparable level', () {
      // level_10 pays 50 gold. A grant worth more would make an unremarkable
      // level-up feel bigger than a medal.
      for (final g in DashboardNotifier.levelUpGoldGrants.values) {
        expect(g, lessThan(50));
      }
    });

    test('the amounts only ever climb with the level', () {
      final keys = DashboardNotifier.levelUpGoldGrants.keys.toList()..sort();
      var last = 0;
      for (final k in keys) {
        final v = DashboardNotifier.levelUpGoldGrants[k]!;
        expect(
          v,
          greaterThanOrEqualTo(last),
          reason: 'level $k pays less than a lower level',
        );
        last = v;
      }
    });

    test('the lifetime total stays modest', () {
      // Gold is the oversupplied currency. If this ever climbs far, the
      // grants have stopped being filler and started being income.
      final total =
          DashboardNotifier.levelUpGoldGrants.values.fold(0, (a, b) => a + b);
      expect(total, lessThanOrEqualTo(500));
    });
  });

  group('against real storage', () {
    late Directory tmp;
    final containers = <ProviderContainer>[];

    Future<ProviderContainer> launch() async {
      final c = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
          dashboardProvider.overrideWith(
            (ref) => DashboardNotifier(null, random: NeverBonusRandom()),
          ),
        ],
      );
      containers.add(c);
      await c.read(authStateProvider.future);
      c.read(dashboardProvider);
      await waitUntil(
        () => !c.read(dashboardProvider).isLoading,
        describe: 'the dashboard to load',
      );
      await c.read(dashboardProvider.notifier).ready;
      return c;
    }

    /// Gold the grants owe for every level in (from, to].
    int grantsAcross(int from, int to) {
      var g = 0;
      for (var l = from + 1; l <= to; l++) {
        g += DashboardNotifier.levelUpGoldGrants[l] ?? 0;
      }
      return g;
    }

    /// One completion to get the first-completion medals out of the way.
    /// green_1 fires on the very first green square and pays 10 gold, which
    /// would otherwise be counted as grant money.
    Future<void> warmUp(ProviderContainer c) async {
      await c.read(dashboardProvider.notifier).completeHabit(
            habitId: 'warmup',
            xpReward: 1,
            goldReward: 0,
            frequencyTarget: 1,
            allHabitsDoneAfter: false,
            category: 'quran',
          );
    }

    Future<void> earnXp(ProviderContainer c, int xp) async {
      await c.read(dashboardProvider.notifier).completeHabit(
            habitId: 'x-${DateTime.now().microsecondsSinceEpoch}',
            xpReward: xp,
            goldReward: 0,
            frequencyTarget: 1,
            allHabitsDoneAfter: false,
            category: 'quran',
          );
    }

    setUp(() async {
      NotificationService.instance.celebrationsEnabled = false;
      tmp = await Directory.systemTemp.createTemp('level_grant_');
      Hive.init(tmp.path);
    });

    tearDown(() async {
      for (final c in containers) {
        c.dispose();
      }
      containers.clear();
      await LocalStoreService.settleDailyWrites();
      await Hive.deleteFromDisk();
      await tmp.delete(recursive: true);
    });

    test('crossing a level pays that level its grant', () async {
      final c = await launch();
      await warmUp(c);
      final before = c.read(dashboardProvider);

      await earnXp(c, 400);

      final after = c.read(dashboardProvider);
      expect(after.level, greaterThan(before.level));
      expect(
        after.gold - before.gold,
        grantsAcross(before.level, after.level),
        reason: 'gold moved by exactly the grants for the levels crossed',
      );
      expect(after.levelGrantPaidThrough, after.level);
    });

    test('a jump across several levels pays each one exactly once', () async {
      // The span property, which is the whole reason the mark is a
      // high-water mark rather than a counter.
      final c = await launch();
      await warmUp(c);
      final before = c.read(dashboardProvider);

      await earnXp(c, 1500);

      final after = c.read(dashboardProvider);
      expect(
        after.level - before.level,
        greaterThanOrEqualTo(3),
        reason: 'this has to cross several levels to mean anything',
      );
      expect(
        after.gold - before.gold,
        grantsAcross(before.level, after.level),
      );
      expect(after.levelGrantPaidThrough, after.level);
    });

    test('earning more without levelling pays nothing further', () async {
      final c = await launch();
      await warmUp(c);
      await earnXp(c, 400);
      final afterLevelUp = c.read(dashboardProvider).gold;

      await earnXp(c, 10);

      expect(
        c.read(dashboardProvider).gold,
        afterLevelUp,
        reason: 'no level crossed, so no grant owed',
      );
    });

    test('a relaunch does not pay the same level again', () async {
      // The mark rides the same write map as `level`, so the two cannot land
      // apart. If this ever fails, the grant has become a repeatable income.
      final first = await launch();
      await warmUp(first);
      await earnXp(first, 400);
      final goldAfter = first.read(dashboardProvider).gold;
      final markAfter = first.read(dashboardProvider).levelGrantPaidThrough;
      await LocalStoreService.settleDailyWrites();

      final second = await launch();
      final s = second.read(dashboardProvider);
      expect(s.level, greaterThan(1));
      expect(s.levelGrantPaidThrough, markAfter);
      expect(s.gold, goldAfter, reason: 'a relaunch must not re-pay');
    });

    test('a brand new account starts with its mark at its own level',
        () async {
      // Seeded to the CURRENT level, never to 1. On an established account
      // this is what stops all twelve grants being collected retroactively
      // the first time this code runs.
      final c = await launch();
      final s = c.read(dashboardProvider);
      expect(s.levelGrantPaidThrough, s.level);
    });

    // ── A level reached on the Grid ───────────────────────────────────
    //
    // A جزئي's flat five XP can be what crosses a level. The Grid's reward
    // path paid that level's grant and wrote the moved mark to the account,
    // but left the mark in memory where it was, so every later resolution in
    // the session started from the old mark and paid the same level again:
    // the next square, the next completion, and for a guest the next launch,
    // since its save wrote the old mark back.

    /// The Grid, loaded. A square set before the week's first read lands is
    /// replaced by that read.
    Future<WeeklyGridNotifier> gridOf(ProviderContainer c) async {
      c.read(weeklyGridProvider);
      await waitUntil(
        () => !c.read(weeklyGridProvider).isLoading,
        describe: 'the grid to load',
      );
      return c.read(weeklyGridProvider.notifier);
    }

    /// Five XP short of the next level, so one جزئي is what crosses it.
    Future<void> fiveShortOfNextLevel(ProviderContainer c) async {
      final s = c.read(dashboardProvider);
      await earnXp(
        c,
        XpCalculator.xpToNextLevel(s.level) - s.currentLevelXp - 5,
      );
    }

    /// A جزئي picked on today's square, as the palette picks it, with the
    /// guest save that runs behind it landed.
    Future<void> partialOn(ProviderContainer c, String habitId) async {
      final grid = await gridOf(c);
      grid.setSquare(
        habitId,
        DateTime.now().effectiveDay,
        SquareState.partial,
        source: kSquareSourcePalette,
      );
      final xp = c.read(dashboardProvider).cumulativeXp;
      await waitUntilAsync(
        () async =>
            (await LocalStoreService.getSettingsMap(
              LocalStoreService.guestDashboardKey,
            ))['cumulativeXp'] ==
            xp,
        describe: 'the square\'s guest save',
      );
    }

    test('a level a square reaches moves the mark with it', () async {
      final c = await launch();
      await warmUp(c);
      await fiveShortOfNextLevel(c);
      final before = c.read(dashboardProvider);

      await partialOn(c, 'square-a');

      final after = c.read(dashboardProvider);
      expect(
        after.level,
        before.level + 1,
        reason: 'the جزئي is what crosses the level',
      );
      expect(after.gold - before.gold, grantsAcross(before.level, after.level));
      expect(
        after.levelGrantPaidThrough,
        after.level,
        reason: 'the grant was paid, so the mark has to say so',
      );
    });

    test('the next square after it pays no second grant', () async {
      final c = await launch();
      await warmUp(c);
      await fiveShortOfNextLevel(c);
      await partialOn(c, 'square-a');
      final afterLevelUp = c.read(dashboardProvider);

      await partialOn(c, 'square-b');

      expect(c.read(dashboardProvider).level, afterLevelUp.level);
      expect(
        c.read(dashboardProvider).gold,
        afterLevelUp.gold,
        reason: 'no level crossed, so no grant owed',
      );
    });

    test('the next completion after it pays no second grant', () async {
      final c = await launch();
      await warmUp(c);
      await fiveShortOfNextLevel(c);
      await partialOn(c, 'square-a');
      final afterLevelUp = c.read(dashboardProvider);

      await earnXp(c, 10);

      expect(c.read(dashboardProvider).level, afterLevelUp.level);
      expect(
        c.read(dashboardProvider).gold,
        afterLevelUp.gold,
        reason: 'no level crossed, so no grant owed',
      );
    });

    test('a relaunch after it pays nothing again', () async {
      final first = await launch();
      await warmUp(first);
      await fiveShortOfNextLevel(first);
      await partialOn(first, 'square-a');
      final afterLevelUp = first.read(dashboardProvider);
      await LocalStoreService.settleDailyWrites();

      final second = await launch();
      final s = second.read(dashboardProvider);
      expect(s.level, afterLevelUp.level);
      expect(s.levelGrantPaidThrough, afterLevelUp.level);
      expect(
        s.gold,
        afterLevelUp.gold,
        reason: 'the save wrote the old mark back, so the launch paid the '
            'level again',
      );
    });
  });
}

/// [waitUntil] for a condition that has to read storage to answer.
Future<void> waitUntilAsync(
  Future<bool> Function() ready, {
  required String describe,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    if (await ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for: $describe.');
}
