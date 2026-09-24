// Yesterday's counts, held for its square while yesterday is still open.
//
// Aziz, 2026-09-24: a tap on yesterday's square of a habit done several times
// a day adds one, like today's ("if 5 times it will be 6 times, unless it's
// 6/6"). A square can only count if it knows its number, and `completions` is
// today's and nothing else, so the dashboard keeps yesterday's beside it:
// DashboardState.graceCompletions, named by graceDayKey. These pin what fills
// it, what moves it, and what must never touch it.
//
// The clock is injected, as in grace_window_completion_test.dart: 02:18 on
// today's real date keeps yesterday open whatever hour the suite runs at, and
// 10:00 is the first instant it has closed.
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

  DateTime at(int hour, int minute) {
    final t = DateTime.now();
    return DateTime(t.year, t.month, t.day, hour, minute);
  }

  final today = DateTime.now().effectiveDay;
  final yesterday = DateTime(today.year, today.month, today.day - 1);

  Future<ProviderContainer> launch(DateTime Function() clock) async {
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

  /// Yesterday as the store holds it before the app opens.
  Future<void> storeYesterday(Map<String, int> counts) =>
      LocalStoreService.updateDailyMap(yesterday.toDateKey(), (d) {
        d['habitCompletions'] = counts;
      });

  Future<bool> mark(
    ProviderContainer c, {
    required DateTime day,
    String habitId = 'h',
    int target = 4,
  }) =>
      c.read(dashboardProvider.notifier).completeHabit(
            habitId: habitId,
            xpReward: 12,
            goldReward: 4,
            frequencyTarget: target,
            allHabitsDoneAfter: false,
            day: day,
          );

  setUp(() async {
    NotificationService.instance.celebrationsEnabled = false;
    tmp = await Directory.systemTemp.createTemp('grace_day_counts_');
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

  test('a load before the cutoff reads yesterday into its own slot', () async {
    await storeYesterday({'h': 2, 'other': 1});
    final c = await launch(() => at(2, 18));
    final s = c.read(dashboardProvider);

    expect(s.graceDayKey, yesterday.toDateKey());
    expect(s.graceCompletions, {'h': 2, 'other': 1});
    expect(s.completions, isEmpty,
        reason: "yesterday's counts never land on today's board");
  });

  test('a load once yesterday has closed reads nothing for it', () async {
    await storeYesterday({'h': 2});
    final c = await launch(() => at(kDayCutoffHour, 0));
    final s = c.read(dashboardProvider);

    expect(s.graceDayKey, isNull,
        reason: 'a closed day has no square that counts');
    expect(s.graceCompletions, isEmpty);
  });

  test('a tap on yesterday moves its count, and never today\'s', () async {
    await storeYesterday({'h': 2});
    final c = await launch(() => at(2, 18));

    await mark(c, day: yesterday);

    final s = c.read(dashboardProvider);
    expect(s.graceCompletions['h'], 3);
    expect(s.graceDayKey, yesterday.toDateKey());
    expect(s.completions['h'], isNull);
  });

  test('a tap on today leaves yesterday\'s count alone', () async {
    await storeYesterday({'h': 2});
    final c = await launch(() => at(2, 18));

    await mark(c, day: today);

    final s = c.read(dashboardProvider);
    expect(s.completions['h'], 1);
    expect(s.graceCompletions['h'], 2);
  });

  test('a refused tap leaves yesterday\'s count exactly as it was', () async {
    // Already full: completeHabit turns the fifth tap away, and the count the
    // square reads is how the Grid learns it was turned away.
    await storeYesterday({'h': 4});
    final c = await launch(() => at(2, 18));
    final before = c.read(dashboardProvider).graceCompletions;

    await mark(c, day: yesterday);

    expect(
      identical(c.read(dashboardProvider).graceCompletions, before),
      isTrue,
      reason: 'nothing landed, so nothing may look as if it did',
    );
    expect(c.read(dashboardProvider).graceCompletions['h'], 4);
  });

  test('clearing yesterday takes its count away', () async {
    await storeYesterday({'h': 2});
    final c = await launch(() => at(2, 18));
    await mark(c, day: yesterday);
    await mark(c, day: yesterday);
    expect(c.read(dashboardProvider).graceCompletions['h'], 4,
        reason: 'precondition');

    await c.read(dashboardProvider.notifier).uncompleteHabit(
          habitId: 'h',
          xpReward: 12,
          goldReward: 4,
          frequencyTarget: 4,
          clearWholeDay: true,
          day: yesterday,
        );

    expect(c.read(dashboardProvider).graceCompletions.containsKey('h'),
        isFalse);
  });

  test('readGraceDay reads yesterday on demand, and nothing else', () async {
    final c = await launch(() => at(kDayCutoffHour, 0));
    final notifier = c.read(dashboardProvider.notifier);
    await storeYesterday({'h': 3});

    await notifier.readGraceDay(yesterday);
    expect(c.read(dashboardProvider).graceDayKey, isNull,
        reason: 'yesterday closed at the cutoff: there is nothing to count');

    await notifier.readGraceDay(today);
    expect(c.read(dashboardProvider).graceDayKey, isNull,
        reason: "today's counts have their own map");

    final open = await launch(() => at(2, 18));
    await open.read(dashboardProvider.notifier).readGraceDay(yesterday);
    expect(open.read(dashboardProvider).graceCompletions['h'], 3);
  });
}
