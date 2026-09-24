// DashboardState.lastStreakDay, the streak's marker held in state, has to
// move exactly when the stored lastActiveDay does, a grace day included.
//
// It is what tells a screen that YESTERDAY was finished after midnight, where
// streakEarnedToday cannot (it only ever speaks for today). The streak banner
// reads it from midnight on; see streak_warning_day_test.dart for why.
//
// Guest storage, like grace_window_completion_test.dart, and for the same
// reason: the real write path runs, and only the hour is moved.
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

import '../../helpers/never_bonus_random.dart';
import '../../helpers/wait_until.dart';

void main() {
  late Directory tmp;
  final containers = <ProviderContainer>[];

  /// 00:06 on today's real date: the minute Aziz finished Monday, inside the
  /// grace window whenever this suite runs. Only the hour moves, for the
  /// reason grace_window_completion_test.dart gives.
  DateTime justAfterMidnight() {
    final today = DateTime.now();
    return DateTime(today.year, today.month, today.day, 0, 6);
  }

  Future<ProviderContainer> launch({DateTime Function()? clock}) async {
    final container = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
      dashboardProvider.overrideWith(
        (ref) => DashboardNotifier(
          null,
          random: NeverBonusRandom(),
          clock: clock,
        ),
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

  setUp(() async {
    NotificationService.instance.celebrationsEnabled = false;
    tmp = await Directory.systemTemp.createTemp('streak_marker_');
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

  Future<void> mark(
    DashboardNotifier notifier, {
    required DateTime day,
    required bool finishesDay,
    String habitId = 'h1',
  }) =>
      notifier.completeHabit(
        habitId: habitId,
        xpReward: 10,
        goldReward: 5,
        frequencyTarget: 1,
        allHabitsDoneAfter: finishesDay,
        category: 'quran',
        day: day,
      );

  test('finishing yesterday after midnight moves the marker to yesterday',
      () async {
    final container = await launch(clock: justAfterMidnight);
    final notifier = container.read(dashboardProvider.notifier);
    final today = DateTime.now().effectiveDay;
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    expect(container.read(dashboardProvider).lastStreakDay, isNull,
        reason: 'a fresh account has never earned a point');

    await mark(notifier, day: yesterday, finishesDay: true);

    final state = container.read(dashboardProvider);
    expect(state.lastStreakDay, yesterday);
    expect(state.streakMarkerReached(yesterday), isTrue);
    expect(state.streakEarnedToday, isFalse,
        reason: "yesterday's point is not today's");
  });

  test('a mark that does not finish the day leaves the marker alone',
      () async {
    final container = await launch(clock: justAfterMidnight);
    final notifier = container.read(dashboardProvider.notifier);
    final today = DateTime.now().effectiveDay;
    final yesterday = DateTime(today.year, today.month, today.day - 1);

    await mark(notifier, day: yesterday, finishesDay: false);

    expect(container.read(dashboardProvider).lastStreakDay, isNull);
  });

  test("finishing today moves it to today", () async {
    final container = await launch();
    final notifier = container.read(dashboardProvider.notifier);
    final today = DateTime.now().effectiveDay;

    await mark(notifier, day: today, finishesDay: true);

    final state = container.read(dashboardProvider);
    expect(state.lastStreakDay, today);
    expect(state.streakEarnedToday, isTrue);
  });

  test('the marker survives a reload, read back from storage', () async {
    final first = await launch(clock: justAfterMidnight);
    final today = DateTime.now().effectiveDay;
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    await mark(first.read(dashboardProvider.notifier),
        day: yesterday, finishesDay: true);
    await LocalStoreService.settleDailyWrites();

    // A second launch is what a resume or a cold start does: the loader
    // rebuilds the state from the stored lastActiveDate alone.
    final second = await launch(clock: justAfterMidnight);
    expect(second.read(dashboardProvider).lastStreakDay, yesterday);
  });
}
