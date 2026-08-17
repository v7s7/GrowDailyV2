import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';

/// Keeps the surprise-bonus roll out of the arithmetic, so any XP that does
/// move can only have come from the call under test.
class _NeverBonusRandom implements Random {
  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 1;

  @override
  int nextInt(int max) => 0;
}

/// Every signed-in writer that persists progression as an ABSOLUTE value must
/// refuse to run while [DashboardState.loadFailed] is set.
///
/// The danger these guards exist for: `_loadToday` throwing leaves `state` at
/// `DashboardState.initial()` — level 1, 0 XP, 0 gold, no achievements — none
/// of which came from the server. Any writer that then persists `state` with
/// `SetOptions(merge: true)` puts those zeros over the account's real
/// document, and the real numbers are gone for good. Declining the write is
/// recoverable (the person taps again after the next good load); overwriting
/// is not.
///
/// `completeHabit` has carried this guard for a while. These tests exist
/// because `applyGridSquareChange` did not, and it is the writer a plain
/// square tap actually reaches: WeeklyGridNotifier.setSquare sends every
/// *non-green* colour straight there, bypassing completeHabit entirely, so
/// one tap on a partial colour after a failed load was enough to flatten the
/// document.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Same headless switch grid_progression_test.dart uses: the reward paths
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

  /// A signed-in notifier whose load has already failed.
  ///
  /// Nothing needs to be stubbed to get there: `_loadToday` reaches for
  /// `FirebaseFirestore.instance` inside its own try, Firebase is never
  /// initialised under `flutter test`, so the read throws and the catch sets
  /// the flag — the exact production state, arrived at the production way.
  Future<DashboardNotifier> failedLoadNotifier() async {
    final notifier = DashboardNotifier('test-uid', random: _NeverBonusRandom());
    for (var i = 0; i < 200 && !notifier.debugState.loadFailed; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(
      notifier.debugState.loadFailed,
      isTrue,
      reason: 'the fixture itself is broken: the signed-in load was supposed '
          'to fail here, so nothing below is actually testing the guard',
    );
    return notifier;
  }

  test('applyGridSquareChange awards nothing after a failed load', () async {
    final notifier = await failedLoadNotifier();

    await notifier.applyGridSquareChange(
      xpDelta: 10,
      greenDelta: 1,
      dateKey: '2026-08-14',
    );

    final s = notifier.debugState;
    // Unguarded, the square's XP and green count land in state and are then
    // written to the user doc as absolutes alongside level/gold/achievements.
    expect(s.cumulativeXp, 0, reason: 'XP moved while the load was known bad');
    expect(s.currentLevelXp, 0);
    expect(s.level, 1);
    expect(s.gold, 0);
    expect(s.totalGreenSquares, 0,
        reason: 'green-square counter moved while the load was known bad');
    expect(s.dailyGreenCounts, isEmpty);
  });

  test('a partial (non-green) square is refused too', () async {
    final notifier = await failedLoadNotifier();

    // greenDelta 0 is the yellow/partial tap — the one that never goes
    // through completeHabit's guard, and so the one that used to get through.
    await notifier.applyGridSquareChange(
      xpDelta: 5,
      greenDelta: 0,
      dateKey: '2026-08-14',
    );

    expect(notifier.debugState.cumulativeXp, 0);
    expect(notifier.debugState.level, 1);
  });

  test('awardBonus writes nothing after a failed load', () async {
    // The gap this closes: every other absolute-value writer either carried
    // this guard or was turned away by a precondition of its own (spendGold
    // can't afford anything against 0 gold; useStreakFreeze has no freeze to
    // spend). awardBonus has no precondition at all — it just adds — so
    // finishing a Focus session, tapping a Quick Win, ticking a Matrix task
    // or collecting a room prize after a failed load wrote `gold: 0 + reward`
    // straight over the real balance, and level/XP with it.
    final notifier = await failedLoadNotifier();

    await notifier.awardBonus(xp: 500, gold: 250);

    final s = notifier.debugState;
    expect(s.gold, 0, reason: 'gold moved while the load was known bad');
    expect(s.cumulativeXp, 0);
    expect(s.currentLevelXp, 0);
    expect(s.level, 1);
    expect(s.unlockedAchievements, isEmpty,
        reason: 'the zeroed state must not mint achievements either');
  });

  test('uncompleteHabit writes nothing after a failed load', () async {
    final notifier = await failedLoadNotifier();

    await notifier.uncompleteHabit(
      habitId: 'habit-1',
      xpReward: 10,
      goldReward: 5,
    );

    expect(notifier.debugState.cumulativeXp, 0);
    expect(notifier.debugState.gold, 0);
    expect(notifier.debugState.totalCompletions, 0);
  });

  test('a guest is unaffected — no server document to overwrite', () async {
    // The guards are all `_uid != null && loadFailed`. A guest has no user
    // doc to destroy and owns its own failure path, so the same call must
    // still award normally rather than being caught by the new checks.
    final guest = DashboardNotifier(null, random: _NeverBonusRandom());
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final before = guest.debugState.cumulativeXp;
    await guest.applyGridSquareChange(
      xpDelta: 10,
      greenDelta: 1,
      dateKey: '2026-08-14',
    );

    // At least the square's own 10 XP. Not an exact figure: the first green
    // square also crosses a greenSquares achievement, whose reward is added
    // on top — which is itself proof the whole reward path ran rather than
    // being turned away.
    expect(guest.debugState.cumulativeXp, greaterThanOrEqualTo(before + 10));
    expect(guest.debugState.totalGreenSquares, 1);
  });
}
