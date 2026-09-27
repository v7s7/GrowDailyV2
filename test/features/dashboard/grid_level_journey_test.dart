// A level or a medal reached through a Grid square, on a signed-in account.
//
// The Journey page, Monthly Story and the Legacy Shelf read one log,
// users/{uid}/milestones, and only completeHabit and
// earnStreakFromPartialCredit ever wrote to it. A جزئي's flat five XP that
// crossed a level (or a square that unlocked a medal) moved the level bar and
// paid the level's gold, and the story never heard about it.
//
// Run against a fake Firestore through DashboardNotifier's `firestore:` seam,
// so the real signed-in load and write paths are the ones under test. The
// guest half of the same bug (the grant mark left stale in memory) is pinned
// in level_up_grant_test.dart.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/habits/models/habit_schedule.dart'
    show dayPlus;
import 'package:grow_daily_v2/features/milestones/models/milestone_event.dart';

import '../../helpers/never_bonus_random.dart';

const _uid = 'journey-user';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  NotificationService.instance.celebrationsEnabled = false;

  late FakeFirebaseFirestore db;
  final containers = <ProviderContainer>[];

  DocumentReference<Map<String, dynamic>> userDoc() =>
      db.collection('users').doc(_uid);

  setUp(() {
    db = FakeFirebaseFirestore();
  });

  tearDown(() {
    for (final c in containers) {
      c.dispose();
    }
    containers.clear();
  });

  /// An account five XP short of level 2, green_1 already earned so no medal
  /// muddies the gold, loaded the way the app loads it.
  Future<ProviderContainer> launch({
    Map<String, dynamic> account = const {},
    DateTime Function()? clock,
  }) async {
    await userDoc().set({
      'level': 1,
      'currentLevelXp': 95,
      'cumulativeXp': 95,
      'gold': 0,
      'levelGrantPaidThrough': 1,
      'totalGreenSquares': 1,
      'unlockedAchievements': ['green_1'],
      ...account,
    });
    final c = ProviderContainer(
      overrides: [
        dashboardProvider.overrideWith(
          (ref) => DashboardNotifier(
            _uid,
            random: NeverBonusRandom(),
            clock: clock,
            firestore: db,
          ),
        ),
      ],
    );
    containers.add(c);
    await c.read(dashboardProvider.notifier).ready;
    expect(
      c.read(dashboardProvider).loadFailed,
      isFalse,
      reason: 'the fixture is broken: the load was meant to succeed',
    );
    return c;
  }

  /// The batch is committed without being awaited, as in the app; give the
  /// fake a moment to apply it.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  Future<List<MilestoneEvent>> journey() async {
    await settle();
    final snap = await userDoc().collection('milestones').get();
    return snap.docs.map(MilestoneEvent.fromFirestore).toList();
  }

  Future<Map<String, dynamic>> account() async {
    await settle();
    return (await userDoc().get()).data()!;
  }

  String todayKey() => DateTime.now().effectiveDay.toDateKey();

  test('a level a square reaches is written to the Journey log', () async {
    final c = await launch();

    await c
        .read(dashboardProvider.notifier)
        .applyGridSquareChange(
          xpDelta: 5,
          greenDelta: 0,
          dateKey: todayKey(),
        )
        .written;

    expect(c.read(dashboardProvider).level, 2);
    final levelUps =
        (await journey()).where((e) => e.type == MilestoneType.levelUp);
    expect(
      levelUps.map((e) => e.level).toList(),
      [2],
      reason: 'the جزئي crossed level 2 and the story never heard of it',
    );
  });

  test('once, and paid once, however often a square crosses back and forth',
      () async {
    // Exact reversal (2026-09-07) means one tap takes the level back and the
    // next gives it again. The level's gold is paid the first time only, and
    // the story has one level-up to tell, not one per lap.
    final c = await launch();
    Future<void> square(int xp) => c
        .read(dashboardProvider.notifier)
        .applyGridSquareChange(
          xpDelta: xp,
          greenDelta: 0,
          dateKey: todayKey(),
        )
        .written;

    await square(5);
    await square(-5);
    await square(5);
    await square(5);

    expect(
      c.read(dashboardProvider).levelGrantPaidThrough,
      2,
      reason: 'the mark in memory is what stops the next resolution '
          'paying level 2 again',
    );
    final grant = DashboardNotifier.levelUpGoldGrants[2]!;
    expect(
      (await account())['gold'],
      grant,
      reason: 'level 2\'s gold was paid again on every later square',
    );
    expect((await account())['levelGrantPaidThrough'], 2);
    final levelUps =
        (await journey()).where((e) => e.type == MilestoneType.levelUp);
    expect(levelUps, hasLength(1));
  });

  test('a medal a square unlocks is logged with it', () async {
    final c = await launch(
      account: {
        'totalGreenSquares': 0,
        'unlockedAchievements': <String>[],
      },
    );

    await c
        .read(dashboardProvider.notifier)
        .applyGridSquareChange(
          xpDelta: 10,
          greenDelta: 1,
          dateKey: todayKey(),
        )
        .written;

    expect(c.read(dashboardProvider).unlockedAchievements, contains('green_1'));
    final unlocks = (await journey())
        .where((e) => e.type == MilestoneType.achievementUnlocked);
    expect(unlocks.map((e) => e.achievementId), contains('green_1'));
  });

  test('a square on yesterday writes yesterday\'s ledger, not today\'s',
      () async {
    // The signed-in half of grid_grace_day_cap_test: the spend lands on the
    // day's own document, as completeHabit's grace write does.
    DateTime preCutoff() {
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day, 2, 18);
    }

    final yesterdayKey = dayPlus(preCutoff().effectiveDay, -1).toDateKey();
    final c = await launch(
      clock: preCutoff,
      account: {
        'earnedDayKey': preCutoff().effectiveDay.toDateKey(),
        'earnedXpToday': 40,
      },
    );

    await c
        .read(dashboardProvider.notifier)
        .applyGridSquareChange(
          xpDelta: 5,
          greenDelta: 0,
          dateKey: yesterdayKey,
        )
        .written;

    expect((await account())['earnedXpToday'], 40);
    await settle();
    final day =
        (await userDoc().collection('daily').doc(yesterdayKey).get()).data();
    expect(day?['dayEarnedXp'], 5);
  });
}
