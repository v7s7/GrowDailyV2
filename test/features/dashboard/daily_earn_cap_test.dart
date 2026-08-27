// The daily earn ceiling: how much one day is allowed to pay out from
// sources a user can repeat at will.
//
// The cap exists because three of the app's earning paths can be ground:
// creating and completing habits, ticking freshly created Matrix tasks, and
// re-colouring grid squares. None of them is bounded by anything the user
// does not control, so without a ceiling an evening of tapping is worth more
// than a year of honest use.
//
// Two properties are load-bearing and both are tested here. The ceiling must
// sit far above any real day, so nobody who simply had a very good day ever
// meets it. And it must apply ONLY to repeatable sources: streak milestones,
// achievements and one-time claims are paid in full however full the day is,
// because a withheld one of those can never be re-offered.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:hive/hive.dart';

import '../../helpers/never_bonus_random.dart';
import '../../helpers/wait_until.dart';

void main() {
  group('the ceiling itself', () {
    test('a small board is never capped below the floor', () {
      // The whole point of the floor. Someone running one habit must not have
      // a tighter ceiling than someone running ten, because the cap is an
      // anti-farming bound and not a difficulty setting.
      expect(dailyXpCapFor(0), kDailyXpCapFloor);
      expect(dailyXpCapFor(1), kDailyXpCapFloor);
      expect(dailyXpCapFor(5), kDailyXpCapFloor);
      expect(dailyGoldCapFor(0), kDailyGoldCapFloor);
      expect(dailyGoldCapFor(5), kDailyGoldCapFloor);
    });

    test('a large roster raises its own ceiling', () {
      // 150 XP per habit overtakes the 3000 floor at 21 habits, and 50 gold
      // per habit overtakes the 1000 floor at the same point. Below that the
      // floor is doing the work; above it the roster is.
      expect(dailyXpCapFor(20), kDailyXpCapFloor);
      expect(dailyXpCapFor(21), 3150);
      expect(dailyXpCapFor(40), 6000);
      expect(dailyGoldCapFor(20), kDailyGoldCapFloor);
      expect(dailyGoldCapFor(21), 1050);
    });

    test('the ceiling clears the heaviest honest day measured', () {
      // The heaviest realistic day found in the economy audit: fifteen
      // room-boosted habits at the top reward tier plus twenty tasks, with
      // every surprise bonus landing, was about 2,200 XP and 835 gold when
      // measured. The task half of that has since halved (matrixTaskXpReward
      // 20 to 10), so a real heavy day is now lower and this guard is more
      // conservative than when it was written, which is the safe direction.
      // If it ever fails, the cap has drifted into punishing real users.
      expect(dailyXpCapFor(15), greaterThan(2200));
      expect(dailyGoldCapFor(15), greaterThan(835));
    });
  });

  group('the running total', () {
    test('reads zero for any day that is not the stamped one', () {
      // This IS the reset. Yesterday's figure is never cleared, it simply
      // stops being readable, so an app left open across the cutoff sees a fresh
      // allowance rather than yesterday's spent one.
      const s = DashboardState(
        level: 1,
        currentLevelXp: 0,
        cumulativeXp: 0,
        gold: 0,
        streak: 0,
        completions: {},
        earnedDayKey: '2026-08-25',
        earnedXpToday: 2900,
        earnedGoldToday: 900,
      );
      expect(s.earnedXpOn('2026-08-25'), 2900);
      expect(s.earnedGoldOn('2026-08-25'), 900);
      expect(s.earnedXpOn('2026-08-26'), 0);
      expect(s.earnedGoldOn('2026-08-26'), 0);
    });

    test('an account that has never earned reads zero', () {
      const s = DashboardState(
        level: 1,
        currentLevelXp: 0,
        cumulativeXp: 0,
        gold: 0,
        streak: 0,
        completions: {},
      );
      expect(s.earnedXpOn('2026-08-26'), 0);
      expect(s.earnedGoldOn('2026-08-26'), 0);
    });
  });

  group('against real storage', () {
    late Directory tmp;
    final containers = <ProviderContainer>[];

    Future<ProviderContainer> launch() async {
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
          // Every assertion below is an exact number, and completeHabit rolls
          // a surprise bonus on every tap. See NeverBonusRandom.
          dashboardProvider.overrideWith(
            (ref) => DashboardNotifier(null, random: NeverBonusRandom()),
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
      tmp = await Directory.systemTemp.createTemp('daily_earn_cap_');
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

    test('one oversized completion is paid only up to the ceiling', () async {
      final container = await launch();
      final notifier = container.read(dashboardProvider.notifier);

      // Far past the ceiling in a single tap, which is what a farm looks like
      // once it is going: the shape of the abuse is a lot of reward arriving
      // in one day, not any particular habit being wrong.
      await notifier.completeHabit(
        habitId: 'huge',
        xpReward: 99999,
        goldReward: 99999,
        frequencyTarget: 1,
        allHabitsDoneAfter: false,
        category: 'quran',
      );

      final s = container.read(dashboardProvider);
      expect(s.earnedXpToday, kDailyXpCapFloor);
      expect(s.earnedGoldToday, kDailyGoldCapFloor);
    });

    test('a second completion on a full day pays nothing more', () async {
      final container = await launch();
      final notifier = container.read(dashboardProvider.notifier);

      await notifier.completeHabit(
        habitId: 'huge',
        xpReward: 99999,
        goldReward: 99999,
        frequencyTarget: 1,
        allHabitsDoneAfter: false,
        category: 'quran',
      );
      final full = container.read(dashboardProvider);

      await notifier.completeHabit(
        habitId: 'another',
        xpReward: 500,
        goldReward: 200,
        frequencyTarget: 1,
        allHabitsDoneAfter: false,
        category: 'quran',
      );
      final after = container.read(dashboardProvider);

      expect(
        after.earnedXpToday,
        kDailyXpCapFloor,
        reason: 'the allowance was already spent',
      );
      expect(after.earnedGoldToday, kDailyGoldCapFloor);
      expect(after.gold, full.gold, reason: 'no gold may arrive past the cap');
    });

    test('the completion still lands even when the payout is withheld',
        () async {
      // The property that keeps a capped day from reading as a broken app.
      // Room grading, the day percentage and the heatmap all read the stored
      // square and the completion counters, never the XP, so the cap must
      // withhold money and nothing else.
      final container = await launch();
      final notifier = container.read(dashboardProvider.notifier);

      await notifier.completeHabit(
        habitId: 'huge',
        xpReward: 99999,
        goldReward: 99999,
        frequencyTarget: 1,
        allHabitsDoneAfter: false,
        category: 'quran',
      );
      final full = container.read(dashboardProvider);

      final landed = await notifier.completeHabit(
        habitId: 'another',
        xpReward: 500,
        goldReward: 200,
        frequencyTarget: 1,
        allHabitsDoneAfter: false,
        category: 'quran',
      );
      final after = container.read(dashboardProvider);

      expect(landed, isTrue, reason: 'the square still has to be paintable');
      expect(after.totalCompletions, full.totalCompletions + 1);
      expect(after.completions['another'], 1);
      expect(after.totalGreenSquares, full.totalGreenSquares + 1);
    });

    test('the task allowance runs out after fifteen and stays out', () async {
      // The tighter bound on the cheapest thing in the app to manufacture.
      final container = await launch();
      final notifier = container.read(dashboardProvider.notifier);

      for (var i = 0; i < kDailyRewardedTaskCap; i++) {
        expect(notifier.claimTaskReward(), isTrue, reason: 'claim ${i + 1}');
      }
      expect(notifier.claimTaskReward(), isFalse);
      expect(
        notifier.claimTaskReward(),
        isFalse,
        reason: 'a refusal must not itself advance the counter',
      );
      expect(
        container.read(dashboardProvider).rewardedTasksToday,
        kDailyRewardedTaskCap,
      );
    });

    test('the task allowance survives a restart', () async {
      final first = await launch();
      for (var i = 0; i < kDailyRewardedTaskCap; i++) {
        first.read(dashboardProvider.notifier).claimTaskReward();
      }
      await LocalStoreService.settleDailyWrites();

      final second = await launch();
      expect(
        second.read(dashboardProvider.notifier).claimTaskReward(),
        isFalse,
        reason: 'relaunching must not hand back a spent task allowance',
      );
    });

    test('the allowance survives a restart', () async {
      // Without this the ceiling is a suggestion: quit, relaunch, earn again.
      final first = await launch();
      await first.read(dashboardProvider.notifier).completeHabit(
            habitId: 'huge',
            xpReward: 99999,
            goldReward: 99999,
            frequencyTarget: 1,
            allHabitsDoneAfter: false,
            category: 'quran',
          );
      expect(first.read(dashboardProvider).earnedXpToday, kDailyXpCapFloor);
      await LocalStoreService.settleDailyWrites();

      final second = await launch();
      final s = second.read(dashboardProvider);
      expect(
        s.earnedXpToday,
        kDailyXpCapFloor,
        reason: 'a relaunch must not hand back a spent allowance',
      );
      expect(s.earnedGoldToday, kDailyGoldCapFloor);
    });
  });
}
