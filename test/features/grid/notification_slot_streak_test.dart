// A reminder's Mark Done (or the Home Screen widget's tick, which queues the
// same action) on yesterday, for a habit counted several times a day, earns
// yesterday's streak point only when the day really is at the line with that
// one tap in it.
//
// A tap made with the app closed is drained the next time the app opens and
// paid on the day it was made, yesterday when that is after midnight
// (main.dart, _processPendingNotificationActions). The streak question for a
// day other than today is answered from its squares, and main.dart asked it
// with the tapped habit's square judged GREEN whatever the count: yesterday
// with two habits, one done and one counted four times going from 1 to 2,
// was judged 2 of 2 and earned its point at 1.5 of 2 (75%, under the 80%
// line). The Grid's own counter tap already judged the square as the tap
// leaves it (_GridTableState._addOneToday): green only on the tap that
// finishes the count, جزئي before that. main.dart now asks
// WeeklyGridNotifier.slotCrossesStreakOn, with the day's count read before
// the tap (DashboardNotifier.readCountOn).
//
// These run main.dart's calls, in its order, against the real dashboard and
// grid. The clock is injected as in grace_day_counts_test.dart: 02:18 on
// today's real date keeps yesterday open whatever hour the suite runs at.
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
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';

import '../../helpers/never_bonus_random.dart';
import '../../helpers/wait_until.dart';

void main() {
  /// Inbox Zero, counted four times a day.
  final base = IslamicHabitCatalog.findById('inbox_zero')!;
  final counted = IslamicHabitTemplate.fromMap(
    base.id,
    {...base.toFirestore(), 'frequencyTarget': 4},
  );
  const target = 4;

  /// Three habits done once a day.
  final planning = IslamicHabitCatalog.findById('daily_planning')!;
  final noPhone = IslamicHabitCatalog.findById('no_phone_morning')!;
  final coldShower = IslamicHabitCatalog.findById('cold_shower')!;

  DateTime at(int hour, int minute) {
    final t = DateTime.now();
    return DateTime(t.year, t.month, t.day, hour, minute);
  }

  final today = DateTime.now().effectiveDay;
  final yesterday = DateTime(today.year, today.month, today.day - 1);

  late Directory tmp;
  final containers = <ProviderContainer>[];

  setUp(() async {
    NotificationService.instance.celebrationsEnabled = false;
    tmp = await Directory.systemTemp.createTemp('notification_slot_streak_');
    Hive.init(tmp.path);
  });

  tearDown(() async {
    for (final c in containers) {
      c.dispose();
    }
    containers.clear();
    await LocalStoreService.settleDailyWrites();
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  /// The app open on [habits], a guest whose numbers load from Hive, the
  /// clock at 02:18 unless [clock] says otherwise, with the dashboard and
  /// the grid both loaded.
  Future<ProviderContainer> launch(
    List<IslamicHabitTemplate> habits, {
    DateTime Function()? clock,
  }) async {
    final c = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
      habitListProvider.overrideWith((ref) => habits),
      dashboardProvider.overrideWith(
        (ref) => DashboardNotifier(
          null,
          random: NeverBonusRandom(),
          clock: clock ?? () => at(2, 18),
        ),
      ),
    ]);
    containers.add(c);
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
    return c;
  }

  /// [slots] of [habit] on [day] recorded and paid, and its square painted
  /// as that count leaves it: what the Grid's own taps leave behind. Never
  /// earns a streak point itself, so each test decides which call does.
  Future<void> record(
    ProviderContainer c,
    IslamicHabitTemplate habit,
    DateTime day,
    int slots,
  ) async {
    final perDay = habit.effectiveDailyTarget;
    for (var i = 0; i < slots; i++) {
      await c.read(dashboardProvider.notifier).completeHabit(
            habitId: habit.id,
            xpReward: habit.xpReward,
            goldReward: habit.goldReward,
            frequencyTarget: perDay,
            allHabitsDoneAfter: false,
            day: day,
          );
    }
    await c.read(weeklyGridProvider.notifier).setSquareStateOnlyAsync(
          habit.id,
          day,
          slots >= perDay ? SquareState.complete : SquareState.partial,
        );
  }

  /// main.dart's Mark Done for [habit] on [day], its calls in its order: the
  /// day's count read before the tap, the streak question asked with it, one
  /// slot paid, then the square painted.
  Future<void> markDoneFromNotification(
    ProviderContainer c,
    IslamicHabitTemplate habit,
    DateTime day,
  ) async {
    final dash = c.read(dashboardProvider.notifier);
    final grid = c.read(weeklyGridProvider.notifier);
    final perDay = habit.effectiveDailyTarget;
    final doneBefore = perDay > 1 ? await dash.readCountOn(habit.id, day) : 0;
    await dash.completeHabit(
      habitId: habit.id,
      xpReward: habit.xpReward,
      goldReward: habit.goldReward,
      frequencyTarget: perDay,
      allHabitsDoneAfter:
          grid.slotCrossesStreakOn(habit, day, doneBefore: doneBefore),
      day: day,
    );
    if (perDay > 1) {
      grid.markCountFromHabit(habit.id, day,
          perDay: perDay, source: kSquareSourceNotification);
    } else {
      grid.markCompleteFromHabit(habit.id, day,
          source: kSquareSourceNotification);
    }
  }

  /// Whether [day]'s stored document says its streak point was earned.
  Future<bool> earnedOn(DateTime day) async {
    await LocalStoreService.settleDailyWrites();
    final stored = await LocalStoreService.getDailyMap(day.toDateKey());
    return stored['streakEarnedToday'] == true;
  }

  test('a tap that leaves yesterday part done does not earn its point',
      () async {
    final c = await launch([counted, planning]);
    await record(c, planning, yesterday, 1);
    await record(c, counted, yesterday, 1);
    final streakBefore = c.read(dashboardProvider).streak;

    await markDoneFromNotification(c, counted, yesterday);

    expect(c.read(dashboardProvider).graceCompletions[counted.id], 2,
        reason: 'precondition: the tap was paid on yesterday');
    expect(await earnedOn(yesterday), isFalse,
        reason: 'one habit done and the other at 2 of 4 is 1.5 of 2, 75%: '
            'under the line. Judged green, the counted square made it 2 of 2');
    expect(c.read(dashboardProvider).streak, streakBefore);
  });

  test('the tap that finishes the count earns it', () async {
    final c = await launch([counted, planning]);
    await record(c, planning, yesterday, 1);
    await record(c, counted, yesterday, 3);
    final streakBefore = c.read(dashboardProvider).streak;

    await markDoneFromNotification(c, counted, yesterday);

    expect(c.read(dashboardProvider).graceCompletions[counted.id], target);
    expect(await earnedOn(yesterday), isTrue);
    expect(c.read(dashboardProvider).streak, greaterThan(streakBefore));
  });

  test('a part-done tap earns it when the day is over the line anyway',
      () async {
    // Three of four habits done and the counted one half done is 3.5 of 4,
    // 87.5%: the جزئي square carries the day, exactly as it does on the
    // Grid. The fix judges the square honestly, it does not hold back every
    // tap short of the count.
    final c = await launch([counted, planning, noPhone, coldShower]);
    for (final habit in [planning, noPhone, coldShower]) {
      await record(c, habit, yesterday, 1);
    }
    await record(c, counted, yesterday, 1);

    await markDoneFromNotification(c, counted, yesterday);

    expect(c.read(dashboardProvider).graceCompletions[counted.id], 2);
    expect(await earnedOn(yesterday), isTrue);
  });

  test('a habit done once a day is judged as before', () async {
    final c = await launch([planning, noPhone]);
    await record(c, noPhone, yesterday, 1);

    await markDoneFromNotification(c, planning, yesterday);

    expect(await earnedOn(yesterday), isTrue,
        reason: 'at a target of 1 every tap finishes the count, so its '
            'square is judged green as it always was');
  });

  test("readCountOn reads the day's own count before a tap", () async {
    final c = await launch([counted, planning]);
    await record(c, counted, yesterday, 2);
    await record(c, counted, today, 1);
    final dash = c.read(dashboardProvider.notifier);

    expect(await dash.readCountOn(counted.id, yesterday), 2);
    expect(await dash.readCountOn(counted.id, today), 1);
    expect(
      await dash.readCountOn(
        counted.id,
        DateTime(today.year, today.month, today.day - 2),
      ),
      0,
      reason: 'a closed day has no count to add one to',
    );

    final afterCutoff =
        await launch([counted, planning], clock: () => at(kDayCutoffHour, 0));
    expect(
      await afterCutoff
          .read(dashboardProvider.notifier)
          .readCountOn(counted.id, yesterday),
      0,
      reason: 'yesterday closed at the cutoff',
    );
  });
}
