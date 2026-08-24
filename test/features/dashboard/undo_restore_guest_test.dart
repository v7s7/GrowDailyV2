// The whole undo-then-redo round trip, run against real storage.
//
// The pure rules live in undo_restore_test.dart. This is the other half: that
// an undo really writes a receipt, that the receipt really survives a restart,
// that redeeming it really puts the numbers and the day back, and that it can
// only ever be redeemed once.
//
// Every assertion is a DELTA off the state as it stands after load, never an
// absolute. Loading runs _reconcileAchievements, which can hand out XP and
// gold of its own for medals a seeded account already qualifies for, and
// pinning absolutes would make these tests fail the day someone adds an
// achievement.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/models/undone_completion.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';

import '../../helpers/wait_until.dart';

void main() {
  late Directory tmp;
  final containers = <ProviderContainer>[];

  /// A fresh app launch against the same store — what makes the
  /// no-snapshot path reachable, since _lastHabitCompletion is deliberately
  /// in-memory only and a real restart is the one thing that clears it.
  Future<ProviderContainer> launch() async {
    final container = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
    ]);
    containers.add(container);
    await container.read(authStateProvider.future);
    container.read(dashboardProvider);
    await waitUntil(
      () => !container.read(dashboardProvider).isLoading,
      describe: 'the dashboard to finish its initial load',
    );
    return container;
  }

  setUp(() async {
    // Without this the completion path reaches into
    // flutter_local_notifications, which has no platform behind it in a test.
    NotificationService.instance.celebrationsEnabled = false;
    tmp = await Directory.systemTemp.createTemp('undo_restore_');
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

  String keyFor(DateTime d) => d.toDateKey();

  test('undoing a completion leaves a receipt for that exact habit-day',
      () async {
    final container = await launch();
    final notifier = container.read(dashboardProvider.notifier);
    final today = DateTime.now().effectiveDay;

    await notifier.completeHabit(
      habitId: 'h1',
      xpReward: 10,
      goldReward: 5,
      frequencyTarget: 1,
      allHabitsDoneAfter: false,
      category: 'quran',
    );
    await notifier.uncompleteHabit(
      habitId: 'h1',
      xpReward: 10,
      goldReward: 5,
      category: 'quran',
    );

    final receipt =
        container.read(dashboardProvider).undoneFor('h1', keyFor(today));
    expect(receipt, isNotNull, reason: 'the undo must leave proof behind');
    expect(receipt!.xp, 10);
    expect(receipt.gold, 5);
    expect(receipt.category, 'quran');
    expect(receipt.dateKey, keyFor(today));
    // The streak this completion produced, which is the half nothing else
    // could recover once the completion was gone.
    expect(receipt.streakAtCompletion, 1);
  });

  test('a habit still done that day leaves no receipt', () async {
    // A 3x habit dropping from 3/3 to 2/3 is still a done day. There is no
    // completion to put back, and a receipt would pay a second time for one
    // that was never given back.
    final container = await launch();
    final notifier = container.read(dashboardProvider.notifier);
    final today = DateTime.now().effectiveDay;

    for (var i = 0; i < 3; i++) {
      await notifier.completeHabit(
        habitId: 'h3',
        xpReward: 10,
        goldReward: 5,
        frequencyTarget: 3,
        allHabitsDoneAfter: false,
      );
    }
    await notifier.uncompleteHabit(
      habitId: 'h3',
      xpReward: 10,
      goldReward: 5,
    );

    expect(container.read(dashboardProvider).completions['h3'], 2);
    expect(container.read(dashboardProvider).undoneFor('h3', keyFor(today)),
        isNull);
  });

  test('re-ticking the same day today spends the receipt', () async {
    final container = await launch();
    final notifier = container.read(dashboardProvider.notifier);
    final today = DateTime.now().effectiveDay;

    await notifier.completeHabit(
      habitId: 'h1',
      xpReward: 10,
      goldReward: 5,
      frequencyTarget: 1,
      allHabitsDoneAfter: false,
    );
    await notifier.uncompleteHabit(
      habitId: 'h1',
      xpReward: 10,
      goldReward: 5,
    );
    await notifier.completeHabit(
      habitId: 'h1',
      xpReward: 10,
      goldReward: 5,
      frequencyTarget: 1,
      allHabitsDoneAfter: false,
    );

    // Spent, so re-painting this same square after the day rolls over can
    // never redeem it a second time.
    expect(container.read(dashboardProvider).undoneFor('h1', keyFor(today)),
        isNull);
  });

  test('undo and redo across a restart no longer resets the habit streak',
      () async {
    // The exact shape a person hits: complete a habit, close the app, reopen
    // it, clear the mark by mistake, mark it again. The undo finds no
    // same-session snapshot so it leaves the streak fields alone on purpose,
    // which left habitLastCompletedDate reading today. The re-tick then
    // measured a gap of 0 days against that and restarted the streak at 1.
    final yesterday = DateTime.now().effectiveDay.subtract(
          const Duration(days: 1),
        );
    await LocalStoreService.putSettingsMap(
      LocalStoreService.guestDashboardKey,
      {
        'habitStreakCounts': {'h1': 5},
        'habitLongestStreaks': {'h1': 5},
        'habitTotalCompletions': {'h1': 5},
        'habitLastCompletedDate': {'h1': keyFor(yesterday)},
      },
    );

    final first = await launch();
    await first.read(dashboardProvider.notifier).completeHabit(
          habitId: 'h1',
          xpReward: 10,
          goldReward: 5,
          frequencyTarget: 1,
          allHabitsDoneAfter: false,
        );
    expect(first.read(dashboardProvider).habitStreakCounts['h1'], 6);

    // The restart. _lastHabitCompletion is in-memory only, so the new
    // notifier has no snapshot of that completion to reverse against.
    final second = await launch();
    final notifier = second.read(dashboardProvider.notifier);
    expect(notifier.state.habitStreakCounts['h1'], 6,
        reason: 'the streak must survive the restart itself');

    await notifier.uncompleteHabit(
      habitId: 'h1',
      xpReward: 10,
      goldReward: 5,
    );
    await notifier.completeHabit(
      habitId: 'h1',
      xpReward: 10,
      goldReward: 5,
      frequencyTarget: 1,
      allHabitsDoneAfter: false,
    );

    expect(second.read(dashboardProvider).habitStreakCounts['h1'], 6,
        reason: 'a mis-tap and a restart must not cost five days');
    expect(second.read(dashboardProvider).habitLongestStreaks['h1'], 6);
  });

  test('restoring a past day pays back what the undo took, once', () async {
    // The case that started this: the mark was cleared while the day was
    // still today, and the square is only re-painted two days later, by which
    // time the anti-backdating rule keeps that square out of the reward
    // system entirely. The receipt is what makes it a correction instead.
    final today = DateTime.now().effectiveDay;
    final twoDaysAgo = today.subtract(const Duration(days: 2));
    final yesterday = today.subtract(const Duration(days: 1));

    await LocalStoreService.putSettingsMap(
      LocalStoreService.guestDashboardKey,
      {
        'totalHabitCompletions': 40,
        'totalGreenSquares': 40,
        'habitTotalCompletions': {'h1': 20},
        // The run built AFTER the mistake: yesterday and today, which could
        // only ever score as a fresh 2-day run while the day in between was a
        // hole.
        'habitStreakCounts': {'h1': 2},
        'habitLongestStreaks': {'h1': 10},
        'habitLastCompletedDate': {'h1': keyFor(today)},
        'categoryCompletions': {'quran': 12},
        'undoneCompletions': {
          UndoneCompletion.keyFor('h1', keyFor(twoDaysAgo)): {
            'habitId': 'h1',
            'dateKey': keyFor(twoDaysAgo),
            'category': 'quran',
            'xp': 30,
            'gold': 12,
            'streak': 10,
            'longest': 10,
            'undoneOn': keyFor(twoDaysAgo),
          },
        },
      },
    );
    // The run that has to merge with the receipt's: yesterday is the day
    // right after the restored one.
    expect(keyFor(yesterday), isNot(keyFor(twoDaysAgo)));

    final container = await launch();
    final notifier = container.read(dashboardProvider.notifier);
    final before = container.read(dashboardProvider);
    expect(before.undoneFor('h1', keyFor(twoDaysAgo)), isNotNull,
        reason: 'the receipt has to survive storage');

    final restored = await notifier.restoreUndoneCompletion(
      habitId: 'h1',
      day: twoDaysAgo,
    );
    expect(restored, isTrue);

    final after = container.read(dashboardProvider);
    expect(after.cumulativeXp - before.cumulativeXp, 30);
    expect(after.gold - before.gold, 12);
    expect(after.totalCompletions - before.totalCompletions, 1);
    expect(after.totalGreenSquares - before.totalGreenSquares, 1);
    expect(after.habitTotalCompletions['h1'], 21);
    expect(after.categoryCompletions['quran'], 13);
    // Ten days ending on the restored one, plus the two built since. Filling
    // the hole makes them one run of twelve.
    expect(after.habitStreakCounts['h1'], 12);
    expect(after.habitLongestStreaks['h1'], 12);
    // Restoring an older day must never drag the newest completion backwards.
    expect(after.habitLastCompletedDate['h1'], keyFor(today));
    expect(after.undoneFor('h1', keyFor(twoDaysAgo)), isNull);

    // The day itself, so a restored day is indistinguishable from one that
    // was never touched: dayMark's completion arm reads this field directly.
    final storedDay = await LocalStoreService.getDailyMap(keyFor(twoDaysAgo));
    expect((storedDay['habitCompletions'] as Map?)?['h1'], 1);

    // Single use. Painting the square green, white and green again cannot
    // farm the same day twice.
    final second = await notifier.restoreUndoneCompletion(
      habitId: 'h1',
      day: twoDaysAgo,
    );
    expect(second, isFalse);
    expect(container.read(dashboardProvider).cumulativeXp, after.cumulativeXp);
    expect(container.read(dashboardProvider).gold, after.gold);
  });

  test('a past day with no receipt pays nothing', () async {
    // The anti-backdating rule, still exactly as strict as it was: a day
    // nobody ever completed has no receipt, so colouring it in is worth
    // nothing at all. This is the property that keeps the whole thing
    // unfarmable.
    final container = await launch();
    final notifier = container.read(dashboardProvider.notifier);
    final before = container.read(dashboardProvider);

    final restored = await notifier.restoreUndoneCompletion(
      habitId: 'never_done',
      day: DateTime.now().effectiveDay.subtract(const Duration(days: 3)),
    );

    expect(restored, isFalse);
    final after = container.read(dashboardProvider);
    expect(after.cumulativeXp, before.cumulativeXp);
    expect(after.gold, before.gold);
    expect(after.totalCompletions, before.totalCompletions);
    expect(after.totalGreenSquares, before.totalGreenSquares);
  });

  test('a receipt older than the retention window is swept on load', () async {
    final stale = DateTime.now()
        .effectiveDay
        .subtract(const Duration(days: kUndoneCompletionRetentionDays + 5));
    await LocalStoreService.putSettingsMap(
      LocalStoreService.guestDashboardKey,
      {
        'undoneCompletions': {
          UndoneCompletion.keyFor('h1', keyFor(stale)): {
            'habitId': 'h1',
            'dateKey': keyFor(stale),
            'xp': 30,
            'gold': 12,
            'streak': 10,
            'longest': 10,
            'undoneOn': keyFor(stale),
          },
          // Junk sits in the same map and must cost only itself.
          'garbage': 'not a record',
        },
      },
    );

    final container = await launch();
    expect(container.read(dashboardProvider).undoneCompletions, isEmpty);
  });
}
