// The comeback bonus, and the one route that used to forfeit it.
//
// A broken streak leaves DashboardState.previousStreak > 0, which is the
// only thing that makes the comeback card appear. The card offers 50 XP.
// There are exactly two ways for that offer to end:
//
//   1. Tapping the card's button (acknowledgeComeback), which has always
//      granted the 50 XP.
//   2. Ignoring the card and going and finishing today's habits, which
//      cleared the offer and granted NOTHING.
//
// Route 2 is the behaviour the card is asking for in writing, and it was
// the one that paid nothing, so the person who came back and did the work
// was worse off than the person who tapped a button and closed the app.
// These tests pin both routes to the same 50 XP.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';

import '../../helpers/wait_until.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Same headless switch grid_progression_test uses: completeHabit fires
  // notification side effects that have no platform to talk to here.
  NotificationService.instance.celebrationsEnabled = false;

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('comeback_bonus_test_');
    Hive.init(tmp.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  /// A guest container whose dashboard has already loaded [seed].
  Future<ProviderContainer> containerWith(Map<String, dynamic> seed) async {
    await LocalStoreService.putSettingsMap(
      LocalStoreService.guestDashboardKey,
      seed,
    );
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
      ],
    );
    await container.read(authStateProvider.future);
    await waitUntil(
      () => !container.read(dashboardProvider).isLoading,
      describe: 'the dashboard to finish its initial load',
    );
    return container;
  }

  group('a pending comeback', () {
    test('finishing today pays the bonus instead of quietly dropping it',
        () async {
      final container = await containerWith({
        'currentStreak': 0,
        'previousStreak': 5,
        // No banked freeze: this is the pure "continue pays" route. With a
        // freeze the card is instead offering a streak RESTORE, which finishing
        // habits must not silently spend — that case is its own test below.
        'streakFreezes': 0,
        'cumulativeXp': 0,
        'currentLevelXp': 0,
        'level': 1,
      });
      addTearDown(container.dispose);

      final before = container.read(dashboardProvider);
      expect(before.showComebackBonus, isTrue,
          reason: 'a lost 5-day streak is exactly when the card appears');

      const habitXp = 5;
      await container.read(dashboardProvider.notifier).completeHabit(
            habitId: 'h1',
            xpReward: habitXp,
            goldReward: 2,
            frequencyTarget: 1,
            allHabitsDoneAfter: true, // the comeback: today is finished
            category: 'custom',
            habitName: 'تمرين',
          );

      final after = container.read(dashboardProvider);
      expect(after.showComebackBonus, isFalse,
          reason: 'the offer is spent, not left dangling');
      // The habit's own XP plus the comeback bonus. Asserted as a floor
      // rather than an exact total because finishing a day can also fire a
      // streak milestone or a surprise bonus, and this test is not about
      // those; what matters is that the 50 is in there at all, which it
      // was not before.
      expect(
        after.cumulativeXp,
        greaterThanOrEqualTo(habitXp + DashboardNotifier.comebackBonusXp),
        reason: 'continuing IS the comeback, so continuing pays for it',
      );
    });

    test('restoring the streak with a freeze pays the advertised bonus',
        () async {
      // The card shows "+50 XP" above the restore layout too, and promises it
      // arrives "either way". Restoring used to grant no XP at all, so the one
      // action that layout leads with silently forfeited the bonus it displayed.
      final container = await containerWith({
        'currentStreak': 0,
        'previousStreak': 30,
        'streakFreezes': 1,
        'cumulativeXp': 0,
        'currentLevelXp': 0,
        'level': 1,
      });
      addTearDown(container.dispose);

      expect(container.read(dashboardProvider).showComebackBonus, isTrue);

      await container.read(dashboardProvider.notifier).useStreakFreeze();

      final after = container.read(dashboardProvider);
      expect(after.streak, 30, reason: 'the freeze restores the lost streak');
      expect(after.streakFreezes, 0, reason: 'and spends the one freeze');
      expect(after.showComebackBonus, isFalse, reason: 'the offer is settled');
      expect(after.cumulativeXp, DashboardNotifier.comebackBonusXp,
          reason: 'restore is a route the card promises pays the bonus');
    });

    test('finishing today with a banked freeze keeps the restore available',
        () async {
      // Someone with a banked freeze who does their habits first must not lose
      // the multi-day restore: clearing it on all-done would trade a 30-day
      // streak for 50 XP they never chose, and useStreakFreeze then can never
      // run again (it guards on previousStreak > 0).
      final container = await containerWith({
        'currentStreak': 0,
        'previousStreak': 30,
        'streakFreezes': 1,
        'cumulativeXp': 0,
        'currentLevelXp': 0,
        'level': 1,
      });
      addTearDown(container.dispose);

      await container.read(dashboardProvider.notifier).completeHabit(
            habitId: 'h1',
            xpReward: 5,
            goldReward: 2,
            frequencyTarget: 1,
            allHabitsDoneAfter: true,
            category: 'custom',
            habitName: 'تمرين',
          );

      final after = container.read(dashboardProvider);
      expect(after.showComebackBonus, isTrue,
          reason: 'a banked freeze means the card is offering a real restore');
      expect(after.previousStreak, 30,
          reason: 'the restore offer survives finishing the day');

      // And the restore still works afterward, still paying the bonus.
      await container.read(dashboardProvider.notifier).useStreakFreeze();
      expect(container.read(dashboardProvider).streak, 30);
    });

    test('the card button pays the same bonus', () async {
      final container = await containerWith({
        'currentStreak': 0,
        'previousStreak': 5,
        'cumulativeXp': 0,
        'currentLevelXp': 0,
        'level': 1,
      });
      addTearDown(container.dispose);

      await container.read(dashboardProvider.notifier).acknowledgeComeback();

      final after = container.read(dashboardProvider);
      expect(after.showComebackBonus, isFalse);
      expect(after.cumulativeXp, DashboardNotifier.comebackBonusXp,
          reason: 'the two routes must be worth the same, or one is a trap');
    });
  });

  test('a normal finished day with no comeback pending pays no bonus',
      () async {
    // The guard on the fix: comebackBonusXp rides on previousStreak > 0, so
    // an ordinary day must be completely untouched by it.
    final container = await containerWith({
      'currentStreak': 3,
      'previousStreak': 0,
      'cumulativeXp': 0,
      'currentLevelXp': 0,
      'level': 1,
    });
    addTearDown(container.dispose);

    const habitXp = 5;
    await container.read(dashboardProvider.notifier).completeHabit(
          habitId: 'h1',
          xpReward: habitXp,
          goldReward: 2,
          frequencyTarget: 1,
          allHabitsDoneAfter: true,
          category: 'custom',
          habitName: 'أذكار الصباح',
        );

    expect(
      container.read(dashboardProvider).cumulativeXp,
      lessThan(DashboardNotifier.comebackBonusXp),
      reason: 'no comeback was pending, so no comeback bonus is owed',
    );
  });
}
