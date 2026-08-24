import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/core/utils/xp_calculator.dart';
import 'package:grow_daily_v2/features/achievements/models/achievement_model.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import '../../helpers/wait_until.dart';

/// Keeps the surprise-bonus roll out of the arithmetic, so any XP that does
/// move can only have come from the path under test. Same fixture as
/// load_failed_guard_test.dart's.
class _NeverBonusRandom implements Random {
  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 1;

  @override
  int nextInt(int max) => 0;
}

/// Covers the post-load achievement reconciliation sweep.
///
/// `unlockedAchievements` used to be appended to from exactly two places —
/// completeHabit and applyGridSquareChange — i.e. only at the moment a
/// counter moves *through the app*. Any other way a counter could change
/// left the medal stranded forever: a Firestore restore, signing in on a
/// device that had progressed offline, a threshold added below where an
/// existing user already sits, or — the one that actually happened — the
/// IslamicHabitCatalog fix that restored `categoryCompletions['quran']` for
/// habits whose category had been collapsed to 'faith'. The count came back;
/// the Quran tiers it had already passed did not.
///
/// The guest path is the one exercised here because it's the one that runs
/// without Firebase. Both paths call the same `_reconcileAchievements`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Same headless switch the other dashboard tests use: the reward paths
  // fire real local-notification calls as unawaited side effects, and the
  // plugin has no platform implementation under `flutter test`.
  NotificationService.instance.celebrationsEnabled = false;

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp();
    Hive.init(tmp.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
  });

  /// Writes a guest account straight into Hive, bypassing the app — this is
  /// the shape of "numbers arrived from somewhere other than a tap".
  Future<void> seedGuest(Map<String, dynamic> fields) =>
      LocalStoreService.putSettingsMap(
        LocalStoreService.guestDashboardKey,
        fields,
      );

  Future<DashboardNotifier> loadedGuest() async {
    final notifier = DashboardNotifier(null, random: _NeverBonusRandom());
    // Both waits used to be guesses: 200 x 5ms that fell through silently,
    // then a flat 40ms for the sweep's own Hive write. On a loaded machine
    // the first expires with the notifier still loading and every test in
    // this file then asserts against an empty state, which reads as
    // '_reconcileAchievements did nothing'. Worse, 'a blank new account is
    // left completely alone' PASSES in that case, because empty is also what
    // a never-loaded notifier looks like: a green test proving nothing.
    await waitUntil(
      () => !notifier.debugState.isLoading,
      describe: 'the guest dashboard to finish its initial load',
    );
    await LocalStoreService.settleDailyWrites();
    return notifier;
  }

  test('awards every medal the stored numbers already qualify for',
      () async {
    await seedGuest({
      'level': 12,
      'currentLevelXp': 0,
      'cumulativeXp': 6000,
      'gold': 100,
      'totalHabitCompletions': 600,
      'totalGreenSquares': 150,
      'categoryCompletions': {'quran': 30},
      'unlockedAchievements': <String>[],
    });

    final unlocked = (await loadedGuest()).debugState.unlockedAchievements;

    expect(
      unlocked,
      containsAll(<String>[
        'level_10', // level 12
        'completions_50', 'completions_500', // 600 completions
        'green_1', 'green_100', // 150 squares
        'quran_25', // the category-fix case
      ]),
    );
    // Thresholds genuinely not reached stay locked.
    expect(unlocked, isNot(contains('level_25')));
    expect(unlocked, isNot(contains('completions_2000')));
    expect(unlocked, isNot(contains('green_500')));
    expect(unlocked, isNot(contains('quran_100')));
    // Streak is 0 here, so no streak tier may appear.
    expect(unlocked.where((id) => id.startsWith('streak_')), isEmpty);
  });

  test('pays the rewards, and surfaces the medals for celebration',
      () async {
    await seedGuest({
      'level': 1,
      'currentLevelXp': 0,
      'cumulativeXp': 0,
      'gold': 0,
      'totalGreenSquares': 1, // green_1 only: +25 XP, +10 gold
      'unlockedAchievements': <String>[],
    });

    final state = (await loadedGuest()).debugState;
    final green1 = AchievementCatalog.findById('green_1')!;

    expect(state.unlockedAchievements, ['green_1']);
    expect(state.gold, green1.goldReward);
    expect(state.cumulativeXp, green1.xpReward);
    // Handed to the reaction listener so the unlock sheet plays, rather
    // than the medal just appearing in the list with no acknowledgement.
    expect(state.newlyUnlocked.map((a) => a.id), ['green_1']);
  });

  test('is idempotent — a second load re-grants nothing', () async {
    await seedGuest({
      'level': 1,
      'gold': 0,
      'cumulativeXp': 0,
      'totalHabitCompletions': 60,
      'unlockedAchievements': <String>[],
    });

    final first = (await loadedGuest()).debugState;
    expect(first.unlockedAchievements, contains('completions_50'));
    final goldAfterFirst = first.gold;

    // Fresh notifier over the state the first sweep persisted.
    final second = (await loadedGuest()).debugState;
    expect(second.unlockedAchievements, first.unlockedAchievements);
    expect(second.gold, goldAfterFirst,
        reason: 'a reward paid once must not be paid again on every launch');
    expect(second.newlyUnlocked, isEmpty);
  });

  test('an unlock\'s own XP reward can cascade into a level achievement',
      () async {
    // The single-pass bug: `level` used to be tested against the level from
    // *before* achievement bonuses were applied, so a threshold crossed only
    // by way of an achievement's own XP stayed locked until some later,
    // unrelated action happened to re-check it.
    //
    // Sits one XP short of level 10 with 500 completions banked. The
    // completions tiers pay 150 + 750 XP, which carries the level over; a
    // correct resolver notices level_10 in the same sweep.
    final xpToTen = XpCalculator.xpToNextLevel(9);
    await seedGuest({
      'level': 9,
      'currentLevelXp': xpToTen - 1,
      'cumulativeXp': 5000,
      'gold': 0,
      'totalHabitCompletions': 500,
      'unlockedAchievements': <String>[],
    });

    final state = (await loadedGuest()).debugState;

    expect(state.unlockedAchievements,
        containsAll(<String>['completions_50', 'completions_500']));
    expect(state.level, greaterThanOrEqualTo(10));
    expect(state.unlockedAchievements, contains('level_10'),
        reason: 'the achievement XP raised the level, so the level tier it '
            'reached must be awarded in the same pass');
  });

  test('a backfill celebrates a few, but awards all of them', () async {
    // registerDashboardReactions shows one modal sheet per newlyUnlocked
    // entry and awaits each before the next, so an uncapped backfill would
    // open the app onto six sheets to dismiss one at a time.
    await seedGuest({
      'level': 30,
      'gold': 0,
      'cumulativeXp': 0,
      'totalHabitCompletions': 600,
      'totalGreenSquares': 150,
      'categoryCompletions': {'quran': 30},
      'unlockedAchievements': <String>[],
    });

    final state = (await loadedGuest()).debugState;

    expect(state.unlockedAchievements.length, greaterThan(3),
        reason: 'the fixture is meant to strand more medals than the cap');
    expect(state.newlyUnlocked.length, lessThanOrEqualTo(3));
    // Everything is still genuinely earned, celebrated or not.
    for (final a in state.newlyUnlocked) {
      expect(state.unlockedAchievements, contains(a.id));
    }
  });

  test('awardBonus can complete a level achievement on the spot', () async {
    // Lump-sum XP (Focus sessions, Weekly Challenges, Matrix tasks, Quick
    // Wins, room prizes) raises the level like any other XP, but awardBonus
    // was the one XP path that never ran the achievement check — a room
    // prize that carried someone to level 10 left the medal locked.
    await seedGuest({
      'level': 9,
      'currentLevelXp': XpCalculator.xpToNextLevel(9) - 10,
      'cumulativeXp': 5000,
      'gold': 0,
      'unlockedAchievements': <String>[],
    });

    final notifier = await loadedGuest();
    expect(notifier.debugState.unlockedAchievements, isEmpty,
        reason: 'still level 9 at load — nothing earned yet');

    await notifier.awardBonus(xp: 50, gold: 0);

    expect(notifier.debugState.level, 10);
    expect(notifier.debugState.unlockedAchievements, contains('level_10'));
    expect(notifier.debugState.newlyUnlocked.map((a) => a.id),
        contains('level_10'));
    // And its own gold reward was paid with it.
    expect(notifier.debugState.gold,
        AchievementCatalog.findById('level_10')!.goldReward);
  });

  test('a blank new account is left completely alone', () async {
    await seedGuest({'level': 1, 'gold': 0, 'unlockedAchievements': <String>[]});

    final state = (await loadedGuest()).debugState;

    expect(state.unlockedAchievements, isEmpty);
    expect(state.newlyUnlocked, isEmpty);
    expect(state.gold, 0);
    expect(state.cumulativeXp, 0);
  });
}
