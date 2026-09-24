// A Mark Done from a reminder, or the Home Screen widget's tick (it queues
// the same action), on a habit counted several times a day paints the square
// of the day it was tapped on from THAT day's count.
//
// The tap can belong to yesterday. One made with the app closed is queued
// with its day and drained the next time the app opens, which after midnight
// is while yesterday is still open (until kDayCutoffHour), and it is paid on
// yesterday in full (main.dart, _processPendingNotificationActions). The
// payment was always right; the picture was not. main.dart painted the square
// from `completions`, which is TODAY's count: yesterday's square stayed empty
// while its count moved (today not started), or went green at 2 of 4 (today
// finished). Rooms, the heatmap and the reports all read that square.
//
// The paint now goes through WeeklyGridNotifier.markCountFromHabit, which
// reads the day's own count: today's `completions`, or yesterday's
// DashboardState.graceCompletions, which completeHabit has just updated.
// These drive the real dashboard and grid through the two calls main.dart
// makes, in the order it makes them. The clock is injected as in
// grace_day_counts_test.dart: 02:18 on today's real date keeps yesterday
// open whatever hour the suite runs at.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/square_audit.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';

import '../../helpers/never_bonus_random.dart';
import '../../helpers/wait_until.dart';

void main() {
  late Directory tmp;
  late ProviderContainer c;

  const habitId = 'h';
  const target = 4;

  DateTime at(int hour, int minute) {
    final t = DateTime.now();
    return DateTime(t.year, t.month, t.day, hour, minute);
  }

  final today = DateTime.now().effectiveDay;
  final yesterday = DateTime(today.year, today.month, today.day - 1);

  setUp(() async {
    NotificationService.instance.celebrationsEnabled = false;
    tmp = await Directory.systemTemp.createTemp('notification_counted_');
    Hive.init(tmp.path);
    c = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
      dashboardProvider.overrideWith(
        (ref) => DashboardNotifier(
          null,
          random: NeverBonusRandom(),
          clock: () => at(2, 18),
        ),
      ),
    ]);
    await c.read(authStateProvider.future);
    c.read(dashboardProvider);
    await waitUntil(
      () => !c.read(dashboardProvider).isLoading,
      describe: 'the dashboard to finish its initial load',
    );
    await c.read(dashboardProvider.notifier).ready;
    c.read(weeklyGridProvider);
    await waitUntil(
      () => !c.read(weeklyGridProvider).isLoading,
      describe: 'the grid to finish its initial load',
    );
  });

  tearDown(() async {
    c.dispose();
    await LocalStoreService.settleDailyWrites();
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  /// One slot of [day] recorded and paid, the call every completion makes.
  Future<void> record(DateTime day, {int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await c.read(dashboardProvider.notifier).completeHabit(
            habitId: habitId,
            xpReward: 12,
            goldReward: 4,
            frequencyTarget: target,
            allHabitsDoneAfter: false,
            day: day,
          );
    }
  }

  /// What main.dart's Mark Done does for a habit counted [target] times a
  /// day: pay one slot of the day the tap belongs to, then paint that day's
  /// square from its count. Answers whether it painted (main.dart then tells
  /// the room).
  Future<bool> markDoneFromNotification(DateTime day) async {
    await record(day);
    return c.read(weeklyGridProvider.notifier).markCountFromHabit(
          habitId,
          day,
          perDay: target,
          source: kSquareSourceNotification,
        );
  }

  /// [day]'s square as the store holds it, once every queued write landed.
  Future<SquareState> stored(DateTime day) async {
    await LocalStoreService.settleDailyWrites();
    final squares =
        await c.read(weeklyGridProvider.notifier).storedSquaresFor(day);
    expect(squares, isNotNull, reason: 'the stored day could not be read');
    return squares![habitId] ?? SquareState.none;
  }

  test("a tap queued on yesterday paints yesterday from yesterday's count",
      () async {
    await record(yesterday, times: 2);
    expect(await stored(yesterday), SquareState.none,
        reason: 'precondition: two slots paid, the square never painted, '
            'which is what the old paint left after every such tap');

    final painted = await markDoneFromNotification(yesterday);

    expect(c.read(dashboardProvider).graceCompletions[habitId], 3,
        reason: 'precondition: the tap was paid on yesterday');
    expect(painted, isTrue);
    expect(await stored(yesterday), SquareState.partial,
        reason: "3 of 4: today's count is 0, and painting from it left "
            'the square empty while the day was part done');
  });

  test('the tap that finishes yesterday paints it green', () async {
    await record(yesterday, times: 3);

    await markDoneFromNotification(yesterday);

    expect(c.read(dashboardProvider).graceCompletions[habitId], target);
    expect(await stored(yesterday), SquareState.complete);
  });

  test('a finished today does not paint yesterday green', () async {
    await record(today, times: target);
    await record(yesterday);

    await markDoneFromNotification(yesterday);

    expect(c.read(dashboardProvider).completions[habitId], target,
        reason: 'precondition: today is finished');
    expect(c.read(dashboardProvider).graceCompletions[habitId], 2);
    expect(await stored(yesterday), SquareState.partial,
        reason: "2 of 4 is part done, whatever today's count says");
  });

  test("today's own tap still paints from today's count", () async {
    await record(today);

    final painted = await markDoneFromNotification(today);

    expect(c.read(dashboardProvider).completions[habitId], 2);
    expect(painted, isTrue);
    expect(await stored(today), SquareState.partial);
  });

  test('a day with no count held here paints nothing', () async {
    // Closed days never reach this path (the drain records them without
    // pay, see _recordClosedDayAction), but the rule has to hold on its own:
    // a count this state does not hold is not today's, and not zero either.
    await record(today, times: 2);
    final older = DateTime(today.year, today.month, today.day - 2);

    final painted = c.read(weeklyGridProvider.notifier).markCountFromHabit(
          habitId,
          older,
          perDay: target,
          source: kSquareSourceNotification,
        );

    expect(painted, isFalse);
    expect(await stored(older), SquareState.none);
  });
}
