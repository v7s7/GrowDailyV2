// What "4 times a day" costs the XP economy, driven through the real
// notifier rather than the arithmetic helper.
//
// The rule the whole feature stands on: a habit counted N times a day is
// worth exactly what it was worth at one time a day. Paying xpReward per TAP
// instead of per DAY would have made the stepper an XP printer — pick a
// bigger number, earn more for the same habit — and the number people chose
// would then be decided by the payout rather than by the habit. So the day's
// price is split across its taps.
//
// The other half, and the one worth guarding hardest, is that nothing
// changed for anyone who never touches the stepper: at a target of 1 the
// slice IS the whole reward, so every habit that existed before this feature
// is paid to the byte what it always was.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/features/achievements/models/achievement_model.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';

import '../../helpers/wait_until.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  NotificationService.instance.celebrationsEnabled = false;

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('times_per_day_economy_');
    Hive.init(tmp.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  Future<ProviderContainer> loadedContainer() async {
    await LocalStoreService.putSettingsMap(
      LocalStoreService.guestDashboardKey,
      // Streak 0, and deliberately so: GameConstants.streakBonuses pays 25
      // XP the moment a streak reaches 3, and seeding a 3 put the account one
      // completion away from collecting it — which landed in the totals this
      // file exists to measure and made a 10 XP habit look like a 35 XP one.
      // From 0 the next streak is 1, which no bonus table has an entry for.
      {
        'currentStreak': 0,
        'previousStreak': 0,
        'cumulativeXp': 0,
        'currentLevelXp': 0,
        'level': 1,
        'gold': 0,
        // Every achievement pre-unlocked. A first completion otherwise trips
        // the first-completion family, which pays its own XP and gold into
        // the very totals this file is measuring — a 10 XP habit read as 35.
        // Unlocking them up front removes the variable instead of trying to
        // predict it.
        'unlockedAchievements': [
          for (final a in AchievementCatalog.all) a.id,
        ],
      },
    );
    final container = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
    ]);
    await container.read(authStateProvider.future);
    await waitUntil(
      () => !container.read(dashboardProvider).isLoading,
      describe: 'the dashboard to finish its initial load',
    );
    return container;
  }

  /// Taps [habitId] to completion and reports what the day actually paid.
  ///
  /// Bonuses are excluded rather than tolerated: a surprise bonus is random,
  /// and a test about exact totals cannot be at the mercy of a dice roll.
  /// lastCompletionBonusXp/Gold carry whatever the tap just rolled, so
  /// subtracting them leaves the deterministic part.
  Future<({int xp, int gold})> tapAllDay(
    ProviderContainer c, {
    required String habitId,
    required int target,
    required int xpReward,
    required int goldReward,
  }) async {
    var bonusXp = 0;
    var bonusGold = 0;
    for (var i = 0; i < target; i++) {
      final gridSyncable =
          await c.read(dashboardProvider.notifier).completeHabit(
            habitId: habitId,
            xpReward: xpReward,
            goldReward: goldReward,
            frequencyTarget: target,
            allHabitsDoneAfter: false,
            category: 'custom',
            habitName: habitId,
          );
      // NOT a success flag: completeHabit returns isGridSyncable, which is
      // `frequencyTarget == 1` — it tells Today whether its completion should
      // also paint the Grid square. Asserting it as success is why an earlier
      // version of this test "failed" on completions that had plainly landed.
      expect(gridSyncable, target == 1,
          reason: 'the return value means grid-syncable, not succeeded');
      final s = c.read(dashboardProvider);
      expect(s.completions[habitId], i + 1,
          reason: 'tap ${i + 1} of $target did not register');
      bonusXp += s.lastCompletionBonusXp;
      bonusGold += s.lastCompletionBonusGold;
    }
    final s = c.read(dashboardProvider);
    return (xp: s.cumulativeXp - bonusXp, gold: s.gold - bonusGold);
  }

  test('a habit at one a day is paid exactly what it always was', () async {
    final c = await loadedContainer();
    addTearDown(c.dispose);
    final paid = await tapAllDay(c,
        habitId: 'once', target: 1, xpReward: 10, goldReward: 4);
    expect(paid.xp, 10);
    expect(paid.gold, 4);
  });

  test('four times a day pays one day, not four', () async {
    final c = await loadedContainer();
    addTearDown(c.dispose);
    final paid = await tapAllDay(c,
        habitId: 'four', target: 4, xpReward: 10, goldReward: 4);
    expect(paid.xp, 10,
        reason: 'paying per tap would have made this 40 — the stepper would '
            'be an XP dial, not a habit setting');
    expect(paid.gold, 4);
  });

  // One test per target rather than a loop: each needs its own Hive box, and
  // sharing one across iterations let a previous iteration's stored day make
  // the next one's first tap a same-day no-op.
  for (final target in [2, 3, 5, 12]) {
    test('$target times a day is still worth one day', () async {
      final c = await loadedContainer();
      addTearDown(c.dispose);
      final paid = await tapAllDay(c,
          habitId: 'h$target', target: target, xpReward: 10, goldReward: 6);
      expect(paid.xp, 10, reason: 'target $target paid ${paid.xp} XP, not 10');
      expect(paid.gold, 6,
          reason: 'target $target paid ${paid.gold} gold, not 6');
    });
  }

  test('a part-done day has been paid only part of the day', () async {
    final c = await loadedContainer();
    addTearDown(c.dispose);
    await c.read(dashboardProvider.notifier).completeHabit(
          habitId: 'half',
          xpReward: 10,
          goldReward: 4,
          frequencyTarget: 4,
          allHabitsDoneAfter: false,
          category: 'custom',
          habitName: 'half',
        );
    final s = c.read(dashboardProvider);
    expect(s.completions['half'], 1);
    expect(s.cumulativeXp - s.lastCompletionBonusXp, lessThan(10),
        reason: 'one of four taps must not pay the whole day');
    expect(s.cumulativeXp - s.lastCompletionBonusXp, greaterThan(0),
        reason: 'but it must pay something, or progress feels inert');
  });

  test('a counted habit still refuses the tap past its target', () async {
    final c = await loadedContainer();
    addTearDown(c.dispose);
    await tapAllDay(c, habitId: 'cap', target: 3, xpReward: 9, goldReward: 3);
    final xpBefore = c.read(dashboardProvider).cumulativeXp;
    await c.read(dashboardProvider.notifier).completeHabit(
          habitId: 'cap',
          xpReward: 9,
          goldReward: 3,
          frequencyTarget: 3,
          allHabitsDoneAfter: false,
          category: 'custom',
          habitName: 'cap',
        );
    expect(c.read(dashboardProvider).completions['cap'], 3,
        reason: 'a finished day cannot be finished again');
    expect(c.read(dashboardProvider).cumulativeXp, xpBefore,
        reason: 'and the refused tap must not pay for the privilege');
  });

  test('clearing a finished day gives back exactly what it paid', () async {
    final c = await loadedContainer();
    addTearDown(c.dispose);
    final before = c.read(dashboardProvider).cumulativeXp;
    final paid = await tapAllDay(c,
        habitId: 'clear', target: 4, xpReward: 10, goldReward: 4);
    expect(paid.xp, 10);

    await c.read(dashboardProvider.notifier).uncompleteHabit(
          habitId: 'clear',
          xpReward: 10,
          goldReward: 4,
          frequencyTarget: 4,
          clearWholeDay: true,
          category: 'custom',
        );
    final after = c.read(dashboardProvider);
    expect(after.completions.containsKey('clear'), isFalse,
        reason: 'tapping a full square empties it — the whole day, not one tap');
    // Back to exactly where the day started. The surprise bonus is refunded
    // through the completion's own snapshot, so this is an equality and not
    // a floor: a full lap of tap-to-full then clear must sum to zero, or the
    // lap is an XP printer.
    expect(after.cumulativeXp, before,
        reason: 'a cleared day must give back everything it was paid');
  });

  test('clearing a half-done day refunds only the half that was paid',
      () async {
    final c = await loadedContainer();
    addTearDown(c.dispose);
    for (var i = 0; i < 2; i++) {
      await c.read(dashboardProvider.notifier).completeHabit(
            habitId: 'partial',
            xpReward: 10,
            goldReward: 4,
            frequencyTarget: 4,
            allHabitsDoneAfter: false,
            category: 'custom',
            habitName: 'partial',
          );
    }
    expect(c.read(dashboardProvider).completions['partial'], 2);

    await c.read(dashboardProvider.notifier).uncompleteHabit(
          habitId: 'partial',
          xpReward: 10,
          goldReward: 4,
          frequencyTarget: 4,
          clearWholeDay: true,
          category: 'custom',
        );
    final after = c.read(dashboardProvider);
    expect(after.completions.containsKey('partial'), isFalse);
    expect(after.cumulativeXp, 0,
        reason: 'two of four taps earned half the day; clearing must give '
            'back that half exactly — no more, which would mint XP, and no '
            'less, which would quietly fine the user for changing their mind');
  });

  group('a one-tap undo of a counted habit keeps the day it did not empty', () {
    // completeHabit writes the day's first-tap fields — the per-habit streak,
    // its lifetime completion counter, and the undo snapshot — ONCE, on the tap
    // that starts the day. A one-tap undo that leaves taps behind (4/4 → 3/4)
    // must not reverse them, or correcting a single tap silently resets the
    // streak, claws every tap's bonus back against one slice, and drops the
    // lifetime counter the day still owns.
    test('the streak and lifetime counter survive undoing one of four taps',
        () async {
      final c = await loadedContainer();
      addTearDown(c.dispose);

      await tapAllDay(c, habitId: 'h4', target: 4, xpReward: 10, goldReward: 5);
      final full = c.read(dashboardProvider);
      expect(full.completions['h4'], 4);
      expect(full.habitStreakCounts['h4'], 1,
          reason: "the day's first tap bumped the per-habit streak");
      expect(full.habitTotalCompletions['h4'], 1,
          reason: 'one habit-day, not four taps');

      // clearWholeDay omitted: one tap off a day that still stands, the shape
      // the cell editor's "completed by mistake" correction produces.
      await c.read(dashboardProvider.notifier).uncompleteHabit(
            habitId: 'h4',
            xpReward: 10,
            goldReward: 5,
            frequencyTarget: 4,
            category: 'custom',
          );

      final after = c.read(dashboardProvider);
      expect(after.completions['h4'], 3, reason: 'one tap came off, three remain');
      expect(after.habitStreakCounts['h4'], 1,
          reason: 'the streak reverts only when the whole day is undone');
      expect(after.habitTotalCompletions['h4'], 1,
          reason: 'the lifetime counter is per day, and the day still stands');
      expect(after.habitLastCompletedDate.containsKey('h4'), isTrue,
          reason: 'the habit is still done today');
    });

    test('two one-tap undos do not double-drop the lifetime counter', () async {
      final c = await loadedContainer();
      addTearDown(c.dispose);
      await tapAllDay(c, habitId: 'h4', target: 4, xpReward: 10, goldReward: 5);
      for (var i = 0; i < 2; i++) {
        await c.read(dashboardProvider.notifier).uncompleteHabit(
              habitId: 'h4',
              xpReward: 10,
              goldReward: 5,
              frequencyTarget: 4,
              category: 'custom',
            );
      }
      final after = c.read(dashboardProvider);
      expect(after.completions['h4'], 2);
      expect(after.habitTotalCompletions['h4'], 1,
          reason: 'still one habit-day; the counter tracks days, not taps');
    });
  });

  group('a completion is a day, not a tap', () {
    // These four counters feed the lifetime stats on Profile, the Monthly
    // Heatmap, and the achievement thresholds. Every one of them means
    // "days", so a habit counted four times a day must not advance them four
    // times as fast — that is the same leak as paying XP per tap, wearing a
    // different hat: pick a bigger number, unlock medals sooner.
    test('four taps add one completion, one green square, one category',
        () async {
      final c = await loadedContainer();
      addTearDown(c.dispose);
      final before = c.read(dashboardProvider);
      await tapAllDay(c,
          habitId: 'day', target: 4, xpReward: 10, goldReward: 4);
      final after = c.read(dashboardProvider);
      expect(after.totalCompletions, before.totalCompletions + 1,
          reason: 'four taps of one habit is one completed habit-day');
      expect(after.totalGreenSquares, before.totalGreenSquares + 1,
          reason: 'a counted habit turns exactly one square green per day');
      expect(after.categoryCompletions['custom'] ?? 0,
          (before.categoryCompletions['custom'] ?? 0) + 1);
    });

    test('a part-done day has earned no completion at all', () async {
      final c = await loadedContainer();
      addTearDown(c.dispose);
      final before = c.read(dashboardProvider);
      for (var i = 0; i < 2; i++) {
        await c.read(dashboardProvider.notifier).completeHabit(
              habitId: 'half',
              xpReward: 10,
              goldReward: 4,
              frequencyTarget: 4,
              allHabitsDoneAfter: false,
              category: 'custom',
              habitName: 'half',
            );
      }
      final after = c.read(dashboardProvider);
      expect(after.totalCompletions, before.totalCompletions,
          reason: '2 of 4 is not a finished day');
      expect(after.totalGreenSquares, before.totalGreenSquares,
          reason: 'and it has turned no square green');
    });

    test('a once-a-day habit still counts exactly one of each', () async {
      final c = await loadedContainer();
      addTearDown(c.dispose);
      final before = c.read(dashboardProvider);
      await tapAllDay(c,
          habitId: 'once', target: 1, xpReward: 10, goldReward: 4);
      final after = c.read(dashboardProvider);
      expect(after.totalCompletions, before.totalCompletions + 1);
      expect(after.totalGreenSquares, before.totalGreenSquares + 1);
    });

    test('clearing a finished day gives the day back, once', () async {
      final c = await loadedContainer();
      addTearDown(c.dispose);
      final before = c.read(dashboardProvider);
      await tapAllDay(c,
          habitId: 'undo', target: 4, xpReward: 10, goldReward: 4);
      await c.read(dashboardProvider.notifier).uncompleteHabit(
            habitId: 'undo',
            xpReward: 10,
            goldReward: 4,
            frequencyTarget: 4,
            clearWholeDay: true,
            category: 'custom',
          );
      final after = c.read(dashboardProvider);
      expect(after.totalCompletions, before.totalCompletions);
      expect(after.totalGreenSquares, before.totalGreenSquares);
    });

    test('clearing a part-done day takes nothing away', () async {
      final c = await loadedContainer();
      addTearDown(c.dispose);
      final before = c.read(dashboardProvider);
      await c.read(dashboardProvider.notifier).completeHabit(
            habitId: 'p',
            xpReward: 10,
            goldReward: 4,
            frequencyTarget: 4,
            allHabitsDoneAfter: false,
            category: 'custom',
            habitName: 'p',
          );
      await c.read(dashboardProvider.notifier).uncompleteHabit(
            habitId: 'p',
            xpReward: 10,
            goldReward: 4,
            frequencyTarget: 4,
            clearWholeDay: true,
            category: 'custom',
          );
      final after = c.read(dashboardProvider);
      expect(after.totalCompletions, before.totalCompletions,
          reason: 'the day never earned a completion, so undoing it must not '
              'bill the user for one');
      expect(after.totalGreenSquares, before.totalGreenSquares);
    });
  });

  group('completeHabit\'s return value is a trap', () {
    // It is named for what it answers — isGridSyncable, "should the caller
    // ALSO paint the Grid square as a one-tap completion" — and that is
    // `frequencyTarget == 1`. It is NOT a success flag, and reading it as one
    // is a bug that hides well: the completion lands, the count moves, and
    // the caller bails out of everything it was supposed to do afterwards.
    //
    // That happened. _addOneToday treated it as success, so every tap of a
    // counted habit showed "still loading, try again" and returned before
    // painting the square — leaving the stored SquareState empty all day
    // while the count and the fill (which read `completions` directly)
    // rendered perfectly. The room sync, the day percentage and the heatmap
    // all read the STORED square, so all three silently disagreed with what
    // was on screen.
    test('a successful counted completion still returns false', () async {
      final c = await loadedContainer();
      addTearDown(c.dispose);
      final returned = await c.read(dashboardProvider.notifier).completeHabit(
            habitId: 'trap',
            xpReward: 10,
            goldReward: 4,
            frequencyTarget: 4,
            allHabitsDoneAfter: false,
            category: 'custom',
            habitName: 'trap',
          );
      expect(returned, isFalse,
          reason: 'the flag is isGridSyncable, and a counted habit never is');
      expect(c.read(dashboardProvider).completions['trap'], 1,
          reason: 'yet the completion plainly landed — which is the trap');
    });

    test('the finishing tap of a counted habit returns false too', () async {
      final c = await loadedContainer();
      addTearDown(c.dispose);
      for (var i = 0; i < 3; i++) {
        await c.read(dashboardProvider.notifier).completeHabit(
              habitId: 'last',
              xpReward: 10,
              goldReward: 4,
              frequencyTarget: 4,
              allHabitsDoneAfter: false,
              category: 'custom',
              habitName: 'last',
            );
      }
      final returned = await c.read(dashboardProvider.notifier).completeHabit(
            habitId: 'last',
            xpReward: 10,
            goldReward: 4,
            frequencyTarget: 4,
            allHabitsDoneAfter: false,
            category: 'custom',
            habitName: 'last',
          );
      expect(returned, isFalse,
          reason: 'even the tap that finishes the day is not grid-syncable, '
              'so a caller cannot use this to detect completion of the day');
      expect(c.read(dashboardProvider).completions['last'], 4);
    });

    test('a once-a-day habit returns true, which is why the trap hid',
        () async {
      final c = await loadedContainer();
      addTearDown(c.dispose);
      final returned = await c.read(dashboardProvider.notifier).completeHabit(
            habitId: 'single',
            xpReward: 10,
            goldReward: 4,
            frequencyTarget: 1,
            allHabitsDoneAfter: false,
            category: 'custom',
            habitName: 'single',
          );
      expect(returned, isTrue,
          reason: 'every habit behaved this way before counting existed, so '
              'nothing caught the misreading until a counted habit appeared');
    });

    test('the honest test of whether a tap landed is the count itself',
        () async {
      final c = await loadedContainer();
      addTearDown(c.dispose);
      final before = c.read(dashboardProvider).completions['count'] ?? 0;
      await c.read(dashboardProvider.notifier).completeHabit(
            habitId: 'count',
            xpReward: 10,
            goldReward: 4,
            frequencyTarget: 4,
            allHabitsDoneAfter: false,
            category: 'custom',
            habitName: 'count',
          );
      final after = c.read(dashboardProvider).completions['count'] ?? 0;
      expect(after, greaterThan(before),
          reason: 'this is what _addOneToday now measures, and it works for '
              'both counted and once-a-day habits');
    });
  });

  group('raising the target mid-day cannot bank the same day twice', () {
    // Finish at 4/4 (day-counters banked once), raise times-per-day to 6 the
    // same day, tap to 6/6. The tap reaching 6 "finishes the day" again by
    // the live target, and used to bump totalCompletions, category counts,
    // totalGreenSquares and dailyGreenCounts a SECOND time for the same
    // habit-day — once per raise, feeding every lifetime stat and
    // achievement threshold. The banked-day receipt
    // (DashboardState.dayCountedHabitIds) is what refuses the repeat.
    test('the four day-counters move exactly once for the habit-day',
        () async {
      final c = await loadedContainer();
      addTearDown(c.dispose);
      Future<void> tap(int target) =>
          c.read(dashboardProvider.notifier).completeHabit(
                habitId: 'raise',
                xpReward: 12,
                goldReward: 4,
                frequencyTarget: target,
                allHabitsDoneAfter: false,
                category: 'custom',
                habitName: 'raise',
              );
      for (var i = 0; i < 4; i++) {
        await tap(4);
      }
      final banked = c.read(dashboardProvider);
      expect(banked.totalCompletions, 1);
      expect(banked.totalGreenSquares, 1);
      expect(banked.categoryCompletions['custom'], 1);
      expect(banked.dailyGreenCounts.values.fold(0, (a, b) => a + b), 1);
      expect(banked.dayCountedHabitIds, contains('raise'));

      // The stepper moves to 6; the two extra taps land under the new target.
      await tap(6);
      await tap(6);
      final after = c.read(dashboardProvider);
      expect(after.completions['raise'], 6);
      expect(after.totalCompletions, 1,
          reason: 'the same habit-day must never count twice');
      expect(after.totalGreenSquares, 1);
      expect(after.categoryCompletions['custom'], 1);
      expect(after.dailyGreenCounts.values.fold(0, (a, b) => a + b), 1);
    });

    test('undoing the finished day hands the receipt back', () async {
      final c = await loadedContainer();
      addTearDown(c.dispose);
      for (var i = 0; i < 2; i++) {
        await c.read(dashboardProvider.notifier).completeHabit(
              habitId: 'redo',
              xpReward: 10,
              goldReward: 4,
              frequencyTarget: 2,
              allHabitsDoneAfter: false,
              category: 'custom',
              habitName: 'redo',
            );
      }
      expect(c.read(dashboardProvider).dayCountedHabitIds, contains('redo'));
      await c.read(dashboardProvider.notifier).uncompleteHabit(
            habitId: 'redo',
            xpReward: 10,
            goldReward: 4,
            frequencyTarget: 2,
            clearWholeDay: true,
            category: 'custom',
          );
      final undone = c.read(dashboardProvider);
      expect(undone.dayCountedHabitIds, isNot(contains('redo')),
          reason: 'an undo that took the counters back must un-bank, so a '
              'genuine re-finish can bank again');
      expect(undone.totalCompletions, 0);
    });
  });
}
