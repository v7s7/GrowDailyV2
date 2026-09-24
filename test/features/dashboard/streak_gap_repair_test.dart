// A day recorded late gives back what the streak-gap judgement charged it.
//
// resolveStreakGap runs once, at the app's next open, and what it does is
// final: it spends freezes, or it ends the streak. It judges from what the app
// knew at that moment, and someone who trained on Tuesday and only opened the
// app on Thursday is charged for Tuesday. The square painted for it afterwards
// used to arrive too late to matter, because a past square pays nothing on
// purpose and the freeze was already gone.
//
// These pin the two halves of the repair: the judgement now READS the squares
// of the days it is judging, and a judgement already made is redone against
// them when one of its days turns green. Nothing here pays: a late square
// still earns no XP, no gold and no new streak point, it only stops a day
// being charged as missed.
//
// Guest storage, like streak_marker_state_test.dart, so the real load and save
// paths run. Every date is anchored on firstOpenDayAt(now) rather than on
// today, for the reason grid_progression_test.dart gives: a day stays markable
// until kDayCutoffHour, so "three days ago" is a different number of settled
// days before and after 10:00.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/models/streak_gap_charge.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';

import '../../helpers/never_bonus_random.dart';
import '../../helpers/wait_until.dart';

/// A habit scheduled every day, so every day of a gap owes something.
IslamicHabitTemplate everyDayHabit() => IslamicHabitTemplate(
      id: 'daily-habit',
      name: 'daily',
      description: '',
      category: HabitCategory.custom,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 10,
      goldReward: 5,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  final containers = <ProviderContainer>[];
  final habits = [everyDayHabit()];

  /// The last day that is settled: everything this suite judges sits before
  /// the first day that is still open.
  DateTime settledDay(int back) =>
      firstOpenDayAt(DateTime.now()).subtract(Duration(days: back));

  /// A reader shaped like WeeklyGridNotifier.storedSquaresFor: the habit is
  /// green on [green], blank on every other day, and [unreadable] answers
  /// null the way a day that could not be read does.
  Future<Map<String, SquareState>?> Function(DateTime) squares({
    Set<DateTime> green = const {},
    Set<DateTime> unreadable = const {},
  }) {
    final greenKeys = {for (final d in green) d.toDateKey()};
    final unreadableKeys = {for (final d in unreadable) d.toDateKey()};
    return (day) async {
      final key = day.toDateKey();
      if (unreadableKeys.contains(key)) return null;
      return {
        if (greenKeys.contains(key)) 'daily-habit': SquareState.complete,
      };
    };
  }

  Future<ProviderContainer> launch() async {
    final container = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
      dashboardProvider.overrideWith(
        (ref) => DashboardNotifier(null, random: NeverBonusRandom()),
      ),
    ]);
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

  Future<void> seed(Map<String, Object?> values) =>
      LocalStoreService.putSettingsMap(
        LocalStoreService.guestDashboardKey,
        values,
      );

  setUp(() async {
    NotificationService.instance.celebrationsEnabled = false;
    tmp = await Directory.systemTemp.createTemp('streak_gap_repair_');
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

  group('the judgement reads the squares', () {
    test('a day already recorded green is not charged', () async {
      // Two settled days since the last point, one of them already green
      // (the steps catch-up writes exactly this, up to a week back). One day
      // is owed, so the single freeze covers it and the streak stands.
      await seed({
        'currentStreak': 5,
        'streakFreezes': 1,
        'lastActiveDate': settledDay(3).toIso8601String(),
      });
      final container = await launch();
      final notifier = container.read(dashboardProvider.notifier);
      await notifier.resolveStreakGap(
        habits,
        squaresOn: squares(green: {settledDay(2)}),
      );

      final dash = container.read(dashboardProvider);
      expect(dash.streak, 5, reason: 'one owed day, and a freeze for it');
      expect(dash.streakFreezes, 0);
      expect(dash.streakGapCharge?.owed, 1);
      expect(dash.streakGapCharge?.freezesSpent, 1);
    });

    test('with every day recorded, nothing is spent at all', () async {
      await seed({
        'currentStreak': 5,
        'streakFreezes': 1,
        'lastActiveDate': settledDay(3).toIso8601String(),
      });
      final container = await launch();
      await container.read(dashboardProvider.notifier).resolveStreakGap(
            habits,
            squaresOn: squares(green: {settledDay(2), settledDay(1)}),
          );

      final dash = container.read(dashboardProvider);
      expect(dash.streak, 5);
      expect(dash.streakFreezes, 1, reason: 'no day was missed');
      expect(dash.streakGapCharge, isNull, reason: 'nothing was charged');
    });

    test('a day that cannot be read is not evidence of anything', () async {
      // The honest reading of an unreadable day is the one the judgement
      // always made: blank. A storage hiccup must not forgive a real miss.
      await seed({
        'currentStreak': 5,
        'streakFreezes': 2,
        'lastActiveDate': settledDay(3).toIso8601String(),
      });
      final container = await launch();
      await container.read(dashboardProvider.notifier).resolveStreakGap(
            habits,
            squaresOn: squares(unreadable: {settledDay(2), settledDay(1)}),
          );

      final dash = container.read(dashboardProvider);
      expect(dash.streakFreezes, 0, reason: 'both days still owed');
      expect(dash.streak, 5);
    });
  });

  group('a judgement already made', () {
    /// A charge for the two settled days before last, as the freeze branch
    /// would have written it.
    Map<String, Object?> spentTwoFreezes() => StreakGapCharge(
          from: settledDay(3),
          through: settledDay(1),
          owed: 2,
          freezesSpent: 2,
          streakBefore: 0,
        ).toJson();

    test('gives a freeze back for the day recorded late', () async {
      await seed({
        'currentStreak': 5,
        'streakFreezes': 0,
        'streakGap': spentTwoFreezes(),
      });
      final container = await launch();
      final notifier = container.read(dashboardProvider.notifier);
      expect(container.read(dashboardProvider).streakGapCharge?.owed, 2,
          reason: 'the charge survived the load');

      await notifier.repairStreakGapForDay(
        day: settledDay(2),
        habits: habits,
        squaresOn: squares(green: {settledDay(2)}),
      );

      final dash = container.read(dashboardProvider);
      expect(dash.streakFreezes, 1, reason: 'one day back, one freeze back');
      expect(dash.streakGapCharge?.owed, 1);
      expect(dash.streakGapCharge?.freezesSpent, 1,
          reason: 'what is left to give back');
    });

    test('never gives back more than it took', () async {
      await seed({
        'currentStreak': 5,
        'streakFreezes': 0,
        'streakGap': spentTwoFreezes(),
      });
      final container = await launch();
      await container.read(dashboardProvider.notifier).repairStreakGapForDay(
            day: settledDay(2),
            habits: habits,
            squaresOn: squares(green: {settledDay(2), settledDay(1)}),
          );

      final dash = container.read(dashboardProvider);
      expect(dash.streakFreezes, 2, reason: 'exactly the two it spent');
      expect(dash.streakGapCharge?.freezesSpent, 0);
      expect(dash.streakGapCharge?.owed, 0);
    });

    test('pays nothing while it repairs', () async {
      await seed({
        'currentStreak': 5,
        'cumulativeXp': 400,
        'gold': 70,
        'streakFreezes': 0,
        'streakGap': spentTwoFreezes(),
      });
      final container = await launch();
      await container.read(dashboardProvider.notifier).repairStreakGapForDay(
            day: settledDay(2),
            habits: habits,
            squaresOn: squares(green: {settledDay(2)}),
          );

      final dash = container.read(dashboardProvider);
      expect(dash.cumulativeXp, 400);
      expect(dash.gold, 70);
      expect(dash.streak, 5, reason: 'no new point, the streak never broke');
    });

    test('a day outside the window changes nothing', () async {
      await seed({
        'currentStreak': 5,
        'streakFreezes': 0,
        'streakGap': spentTwoFreezes(),
      });
      final container = await launch();
      await container.read(dashboardProvider.notifier).repairStreakGapForDay(
            day: settledDay(9),
            habits: habits,
            squaresOn: squares(green: {settledDay(9)}),
          );

      final dash = container.read(dashboardProvider);
      expect(dash.streakFreezes, 0);
      expect(dash.streakGapCharge?.owed, 2);
    });

    test('a broken streak comes back once the window owes nothing', () async {
      // The break branch's receipt: nothing spent, five taken away.
      await seed({
        'currentStreak': 2,
        'previousStreak': 5,
        'streakFreezes': 0,
        'streakGap': StreakGapCharge(
          from: settledDay(3),
          through: settledDay(1),
          owed: 2,
          freezesSpent: 0,
          streakBefore: 5,
        ).toJson(),
      });
      final container = await launch();
      final notifier = container.read(dashboardProvider.notifier);

      // One of the two days recorded: still short, so nothing comes back yet.
      await notifier.repairStreakGapForDay(
        day: settledDay(2),
        habits: habits,
        squaresOn: squares(green: {settledDay(2)}),
      );
      expect(container.read(dashboardProvider).streak, 2,
          reason: 'one day is still missed, the break stands');
      expect(container.read(dashboardProvider).streakGapCharge?.owed, 1);

      // The second one: the window owes nothing, so the number the break
      // took away comes back, with the two days earned since on top.
      await notifier.repairStreakGapForDay(
        day: settledDay(1),
        habits: habits,
        squaresOn: squares(green: {settledDay(2), settledDay(1)}),
      );

      final dash = container.read(dashboardProvider);
      expect(dash.streak, 7, reason: '5 taken away, plus the 2 earned since');
      expect(dash.longestStreak, greaterThanOrEqualTo(7));
      expect(dash.previousStreak, 0,
          reason: 'there is nothing left for the comeback card to sell');
      expect(dash.streakGapCharge, isNull, reason: 'repaired, and only once');
    });

    test('survives a reload, so a repair is not a same-session privilege',
        () async {
      await seed({
        'currentStreak': 5,
        'streakFreezes': 0,
        'streakGap': spentTwoFreezes(),
      });
      final first = await launch();
      await first.read(dashboardProvider.notifier).repairStreakGapForDay(
            day: settledDay(2),
            habits: habits,
            squaresOn: squares(green: {settledDay(2)}),
          );
      first.dispose();

      final second = await launch();
      final dash = second.read(dashboardProvider);
      expect(dash.streakFreezes, 1, reason: 'the refund was written down');
      expect(dash.streakGapCharge?.owed, 1);
      expect(dash.streakGapCharge?.freezesSpent, 1);
    });
  });

  group('StreakGapCharge', () {
    final charge = StreakGapCharge(
      from: DateTime(2026, 9, 20),
      through: DateTime(2026, 9, 22),
      owed: 2,
      freezesSpent: 2,
      streakBefore: 0,
    );

    test('covers the days after from, through through', () {
      expect(charge.covers(DateTime(2026, 9, 20)), isFalse,
          reason: 'the last earning day is not part of the gap');
      expect(charge.covers(DateTime(2026, 9, 21)), isTrue);
      expect(charge.covers(DateTime(2026, 9, 22)), isTrue);
      expect(charge.covers(DateTime(2026, 9, 23)), isFalse);
      expect(charge.covers(DateTime(2026, 9, 21, 23, 40)), isTrue,
          reason: 'a day, not an instant');
      expect(charge.days, [DateTime(2026, 9, 21), DateTime(2026, 9, 22)]);
    });

    test('round-trips through storage', () {
      expect(StreakGapCharge.fromJson(charge.toJson())?.toJson(),
          charge.toJson());
    });

    test('reads nothing out of a damaged record', () {
      expect(StreakGapCharge.fromJson(null), isNull);
      expect(StreakGapCharge.fromJson('yesterday'), isNull);
      expect(StreakGapCharge.fromJson({'from': 'x', 'through': 'y'}), isNull);
      expect(
        StreakGapCharge.fromJson(
            {'from': '2026-09-22', 'through': '2026-09-20', 'owed': 1}),
        isNull,
        reason: 'a window that ends before it starts is not a window',
      );
      expect(
        StreakGapCharge.fromJson(
            {'from': '2026-09-20', 'through': '2026-09-22', 'owed': 0}),
        isNull,
        reason: 'a charge for nothing has nothing to give back',
      );
    });
  });
}
