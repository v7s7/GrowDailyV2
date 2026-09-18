// A habit's own streak carries across a schedule change.
//
// Aziz, 2026-09-18: a habit on specific days, made daily. Its streak is
// counted on its own days (completeHabit's gap, see habit_schedule.dart), and
// the gap used to be measured with the schedule it has TODAY: the rest day
// between its last completion and the first one after the change read as a
// missed daily day, so the first tick after the change restarted a live
// streak at 1. completeHabit now asks each day the schedule it had then
// (runsOn), and every screen passes it.
//
// Guest path, real Hive, the same order of operations as grid_progression's
// streak group: seed the stored dashboard first, then build the container so
// it loads that state.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_cadence.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';

import '../../helpers/wait_until.dart';

void main() {
  late Directory tmp;

  final today = DateTime.now().effectiveDay;
  final yesterday = DateTime(today.year, today.month, today.day - 1);
  final twoDaysAgo = DateTime(today.year, today.month, today.day - 2);

  // Ran only on the weekday of two days ago until yesterday (so yesterday was
  // a rest day), and daily from today.
  final habit = IslamicHabitTemplate(
    id: 'h',
    name: 'Sadaqah',
    description: '',
    category: HabitCategory.custom,
    frequencyType: HabitFrequencyType.daily,
    frequencyTarget: 1,
    hasTimer: false,
    xpReward: 10,
    goldReward: 5,
    createdAt: DateTime(today.year, today.month, today.day - 60),
    pastCadences: [
      PastCadence(
        until: yesterday,
        cadence: HabitCadence(
          frequencyType: HabitFrequencyType.weekly,
          frequencyTarget: 1,
          scheduledWeekdays: [twoDaysAgo.weekday],
        ),
      ),
    ],
  );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('schedule_streak_test_');
    Hive.init(tmp.path);
    await LocalStoreService.putSettingsMap(
      LocalStoreService.guestDashboardKey,
      {
        'habitStreakCounts': {'h': 5},
        'habitLongestStreaks': {'h': 5},
        'habitTotalCompletions': {'h': 5},
        'habitLastCompletedDate': {'h': twoDaysAgo.toDateKey()},
      },
    );
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  Future<ProviderContainer> freshContainer() async {
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

  test('guard: yesterday was a rest day then and is a daily day now', () {
    expect(habit.runsOn(yesterday), isFalse);
    expect(habit.runsOn(today), isTrue);
    expect(habit.scheduledWeekdays, isEmpty, reason: 'daily now');
  });

  test('the first tick after the change continues the streak', () async {
    final container = await freshContainer();
    addTearDown(container.dispose);
    expect(container.read(dashboardProvider).habitStreakCounts['h'], 5);

    await container.read(dashboardProvider.notifier).completeHabit(
          habitId: 'h',
          xpReward: 10,
          goldReward: 5,
          frequencyTarget: 1,
          allHabitsDoneAfter: false,
          scheduledWeekdays: habit.scheduledWeekdays.toSet(),
          runsOn: habit.runsOn,
        );

    final dash = container.read(dashboardProvider);
    expect(dash.habitStreakCounts['h'], 6,
        reason: 'yesterday was a rest day when it happened');
    expect(dash.habitStreak('h', runsOn: habit.runsOn), 6);
  });

  test("measured by today's schedule alone it restarted, the old bug",
      () async {
    final container = await freshContainer();
    addTearDown(container.dispose);
    await container.read(dashboardProvider.notifier).completeHabit(
          habitId: 'h',
          xpReward: 10,
          goldReward: 5,
          frequencyTarget: 1,
          allHabitsDoneAfter: false,
          scheduledWeekdays: habit.scheduledWeekdays.toSet(),
        );
    expect(container.read(dashboardProvider).habitStreakCounts['h'], 1);
  });

  test('the live streak reads the old rest day as rest too', () async {
    final container = await freshContainer();
    addTearDown(container.dispose);
    final dash = container.read(dashboardProvider);
    expect(dash.habitStreak('h', runsOn: habit.runsOn), 5);
    expect(dash.habitStreak('h'), 0,
        reason: 'by the calendar alone yesterday was a missed daily day');
  });
}
