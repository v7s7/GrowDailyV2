// A Grid square on yesterday spends yesterday's allowance.
//
// The daily ceiling belongs to a calendar DAY (see _allowedOn): while
// yesterday is still payable, until kDayCutoffHour, catching up on it must
// not eat into today's allowance, and today's must not cap it. completeHabit
// has charged each day its own since the overlap model landed, keeping a
// grace day's spend on that day's document (dayEarnedXp). The Grid's
// flat-rate path, applyGridSquareChange, still charged every square to
// today's slot: a جزئي on yesterday moved today's XP figure, never reached
// yesterday's ledger, and was capped by what TODAY had spent.
//
// The last group is the undo's half of the same ledger. uncompleteHabit gave
// a grace day's room back from `state`, which only ever holds today's figure,
// so any undo on yesterday wrote yesterday's ledger down to zero whatever else
// that day had spent.
//
// Every assertion is a delta off the state after load, as in
// grace_window_completion_test: loading can hand out XP of its own.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/habits/models/habit_schedule.dart'
    show dayPlus;
import 'package:hive/hive.dart';

import '../../helpers/never_bonus_random.dart';
import '../../helpers/wait_until.dart';

void main() {
  late Directory tmp;
  final containers = <ProviderContainer>[];

  /// 02:18 on today's real date, inside yesterday's grace tail whatever time
  /// this suite runs at. The date stays the real one for the reason
  /// grace_window_completion_test gives: the guest store keys today off the
  /// real clock.
  DateTime preCutoff() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, 2, 18);
  }

  final todayKey = preCutoff().effectiveDay.toDateKey();
  final yesterday = dayPlus(preCutoff().effectiveDay, -1);
  final yesterdayKey = yesterday.toDateKey();

  Future<ProviderContainer> launch() async {
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        dashboardProvider.overrideWith(
          (ref) => DashboardNotifier(
            null,
            random: NeverBonusRandom(),
            clock: preCutoff,
          ),
        ),
      ],
    );
    containers.add(container);
    await container.read(authStateProvider.future);
    container.read(dashboardProvider);
    await waitUntil(
      () => !container.read(dashboardProvider).isLoading,
      describe: 'the dashboard to finish its initial load',
    );
    await container.read(dashboardProvider.notifier).ready;
    return container;
  }

  setUp(() async {
    NotificationService.instance.celebrationsEnabled = false;
    tmp = await Directory.systemTemp.createTemp('grid_grace_cap_');
    Hive.init(tmp.path);
  });

  tearDown(() async {
    for (final container in containers) {
      container.dispose();
    }
    containers.clear();
    await LocalStoreService.settleDailyWrites();
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  /// One square's flat-rate change, as WeeklyGridNotifier.setSquare makes it,
  /// with its writes landed.
  Future<void> square(ProviderContainer c, int xpDelta, String dateKey) async {
    await c
        .read(dashboardProvider.notifier)
        .applyGridSquareChange(
          xpDelta: xpDelta,
          greenDelta: 0,
          dateKey: dateKey,
        )
        .written;
    await LocalStoreService.settleDailyWrites();
  }

  Future<Map<String, dynamic>> storedDay(String dateKey) async {
    await LocalStoreService.settleDailyWrites();
    return LocalStoreService.getDailyMap(dateKey);
  }

  int earnedToday(ProviderContainer c) =>
      c.read(dashboardProvider).earnedXpOn(todayKey);
  int xp(ProviderContainer c) => c.read(dashboardProvider).cumulativeXp;

  group('a square on yesterday', () {
    test('spends yesterday\'s allowance, not today\'s', () async {
      final c = await launch();
      await c.read(dashboardProvider.notifier).awardBonus(xp: 40, gold: 0);
      final todaySpent = earnedToday(c);
      final before = xp(c);

      await square(c, 5, yesterdayKey);

      expect(xp(c), before + 5);
      expect(
        earnedToday(c),
        todaySpent,
        reason: 'today\'s XP figure moved for a square on yesterday',
      );
      expect(
        (await storedDay(yesterdayKey))['dayEarnedXp'],
        5,
        reason: 'yesterday\'s own ledger never heard about it',
      );
    });

    test('gives yesterday\'s room back when cleared, not today\'s', () async {
      final c = await launch();
      await square(c, 5, yesterdayKey);
      await c.read(dashboardProvider.notifier).awardBonus(xp: 40, gold: 0);
      final todaySpent = earnedToday(c);

      await square(c, -5, yesterdayKey);

      expect(
        earnedToday(c),
        todaySpent,
        reason: 'clearing yesterday\'s square handed today room it had '
            'never spent',
      );
      expect((await storedDay(yesterdayKey))['dayEarnedXp'] ?? 0, 0);
    });

    test('is capped by what yesterday spent', () async {
      // Yesterday's grace tail has two XP of room left. The load reads that
      // figure with yesterday's counts, so the square knows it.
      await LocalStoreService.updateDailyMap(yesterdayKey, (d) {
        d['dayEarnedXp'] = dailyXpCapFor(0) - 2;
      });
      final c = await launch();
      final before = xp(c);

      await square(c, 5, yesterdayKey);

      expect(xp(c), before + 2, reason: 'yesterday had two XP of room left');
      expect((await storedDay(yesterdayKey))['dayEarnedXp'], dailyXpCapFor(0));
    });

    test('is not capped by what today spent', () async {
      final c = await launch();
      await c
          .read(dashboardProvider.notifier)
          .awardBonus(xp: dailyXpCapFor(0), gold: 0);
      expect(earnedToday(c), dailyXpCapFor(0), reason: 'today is full');
      final before = xp(c);

      await square(c, 5, yesterdayKey);

      expect(
        xp(c),
        before + 5,
        reason: 'a full today withheld a square that belongs to yesterday',
      );
    });

    test('sees what a completion on yesterday just spent', () async {
      // The square prices against the spend it holds for yesterday, so every
      // writer of that figure has to hand it on: here the completion takes
      // yesterday to two XP short of its ceiling.
      await LocalStoreService.updateDailyMap(yesterdayKey, (d) {
        d['dayEarnedXp'] = dailyXpCapFor(0) - 12;
      });
      final c = await launch();
      await c.read(dashboardProvider.notifier).completeHabit(
            habitId: 'h1',
            xpReward: 10,
            goldReward: 0,
            frequencyTarget: 1,
            allHabitsDoneAfter: false,
            category: 'quran',
            day: yesterday,
          );
      final before = xp(c);

      await square(c, 5, yesterdayKey);

      expect(
        xp(c),
        before + 2,
        reason: 'the square read yesterday\'s spend from before the '
            'completion and paid past the ceiling',
      );
    });
  });

  group('an undo on yesterday', () {
    test('keeps the rest of yesterday\'s ledger', () async {
      final c = await launch();
      final n = c.read(dashboardProvider.notifier);
      Future<void> complete(String id, int xpReward) => n.completeHabit(
            habitId: id,
            xpReward: xpReward,
            goldReward: 5,
            frequencyTarget: 1,
            allHabitsDoneAfter: false,
            category: 'quran',
            day: yesterday,
          );
      await complete('a', 10);
      await complete('b', 20);
      final spent = await storedDay(yesterdayKey);
      expect(spent['dayEarnedXp'], 30);
      expect(spent['dayEarnedGold'], 10);

      await n.uncompleteHabit(
        habitId: 'a',
        xpReward: 10,
        goldReward: 5,
        category: 'quran',
        day: yesterday,
      );

      final after = await storedDay(yesterdayKey);
      expect(
        after['dayEarnedXp'],
        20,
        reason: 'the undo gave back a\'s 10 and wrote the rest of the day '
            'off with it',
      );
      expect(after['dayEarnedGold'], 5);
    });
  });
}
