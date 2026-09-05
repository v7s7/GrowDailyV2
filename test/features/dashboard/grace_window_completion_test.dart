// Marking a day that is still open but is no longer today.
//
// The night owl's case, run against real storage. Until now the app handled
// it by shifting effectiveDay back ten hours, which made the WHOLE app call
// yesterday "today" until 10 AM — and the Grid, which drew its week and its
// gold ring from the real calendar, disagreed with the reward engine for
// those ten hours. The square labelled TODAY at 2 AM was tappable, turned
// green, and paid nothing. Rooms grade off that square, so a room credited
// the day while the person's own XP did not (room ELQVF8, 2026-09-05).
//
// The day rolls at midnight now, and yesterday stays PAYABLE until the cutoff
// instead. These tests pin the half that matters: that a day inside its
// window really pays, that a day outside it really cannot, and that paying
// one day never touches the other's board.
//
// Every assertion is a DELTA off the state after load, never an absolute —
// loading runs _reconcileAchievements, which can hand out XP of its own.
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

  /// 02:18 on today's real date — the hour Hoor marked her Witr, and inside
  /// the grace window whatever time this suite actually runs at.
  ///
  /// Today's DATE is deliberately the real one: the guest store's load path
  /// and _saveGuestDaily's default both key off the real clock, so moving the
  /// date as well would make the notifier and its storage disagree about
  /// which day is today. Only the hour needs to move, and the hour is the
  /// whole rule being tested.
  DateTime preCutoff() {
    final today = DateTime.now();
    return DateTime(today.year, today.month, today.day, 2, 18);
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
    tmp = await Directory.systemTemp.createTemp('grace_window_');
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

  Future<bool> mark(
    DashboardNotifier notifier, {
    required DateTime day,
    String habitId = 'h1',
  }) =>
      notifier.completeHabit(
        habitId: habitId,
        xpReward: 10,
        goldReward: 5,
        frequencyTarget: 1,
        allHabitsDoneAfter: false,
        category: 'quran',
        day: day,
      );

  Future<Map<String, int>> storedCompletions(DateTime day) async {
    await LocalStoreService.settleDailyWrites();
    final d = await LocalStoreService.getDailyMap(day.toDateKey());
    final raw = d['habitCompletions'];
    return {
      if (raw is Map)
        for (final e in raw.entries)
          if (e.value is num) '${e.key}': (e.value as num).toInt(),
    };
  }

  test('passing today explicitly behaves exactly like passing nothing',
      () async {
    // The parameter's default has to be a no-op for every caller that
    // existed before it did, so this is the equivalence the whole change
    // rests on.
    final container = await launch();
    final notifier = container.read(dashboardProvider.notifier);
    final today = DateTime.now().effectiveDay;
    final xpBefore = container.read(dashboardProvider).cumulativeXp;

    await mark(notifier, day: today);

    expect(container.read(dashboardProvider).completions['h1'], 1);
    // At LEAST the base reward: a first completion can also trip an
    // achievement or a per-habit milestone, whose XP rides along. Pinning the
    // exact number here would make this fail the day someone adds a medal.
    expect(container.read(dashboardProvider).cumulativeXp - xpBefore,
        greaterThanOrEqualTo(10));
    expect((await storedCompletions(today))['h1'], 1);
  });

  test('a day already closed can never be bought, at any hour', () async {
    // The anti-backdating rule. Two days back is outside its window whatever
    // the clock says, so this holds at every hour the suite might run.
    final container = await launch();
    final notifier = container.read(dashboardProvider.notifier);
    final twoDaysBack =
        DateTime.now().effectiveDay.subtract(const Duration(days: 2));
    expect(twoDaysBack.isOpenDay, isFalse, reason: 'precondition');
    final xpBefore = container.read(dashboardProvider).cumulativeXp;

    await mark(notifier, day: twoDaysBack);

    expect(container.read(dashboardProvider).cumulativeXp, xpBefore,
        reason: 'colouring in an old day must never pay');
    expect(await storedCompletions(twoDaysBack), isEmpty);
  });

  test('a day that has not started yet can never be bought', () async {
    // The other half, and the one that was actually broken: nothing may be
    // marked ahead of its own midnight.
    final container = await launch();
    final notifier = container.read(dashboardProvider.notifier);
    final tomorrow =
        DateTime.now().effectiveDay.add(const Duration(days: 1));
    expect(tomorrow.isOpenDay, isFalse, reason: 'precondition');
    final xpBefore = container.read(dashboardProvider).cumulativeXp;

    await mark(notifier, day: tomorrow);

    expect(container.read(dashboardProvider).cumulativeXp, xpBefore);
    expect(await storedCompletions(tomorrow), isEmpty);
  });

  test('yesterday pays in full while its window is open', () async {
    final container = await launch(clock: preCutoff);
    final notifier = container.read(dashboardProvider.notifier);
    final yesterday =
        DateTime.now().effectiveDay.subtract(const Duration(days: 1));
    final xpBefore = container.read(dashboardProvider).cumulativeXp;
    final goldBefore = container.read(dashboardProvider).gold;

    await mark(notifier, day: yesterday);

    expect(container.read(dashboardProvider).cumulativeXp - xpBefore,
        greaterThanOrEqualTo(10),
        reason: 'an open day earns in full');
    expect(container.read(dashboardProvider).gold - goldBefore,
        greaterThanOrEqualTo(5));
    expect((await storedCompletions(yesterday))['h1'], 1,
        reason: 'and the completion lands on ITS day, not on today');
  });

  test('yesterday earns nothing once its window has shut', () async {
    // 10:00 exactly, the first instant past the cutoff.
    final container = await launch(clock: () {
      final t = DateTime.now();
      return DateTime(t.year, t.month, t.day, kDayCutoffHour, 0);
    });
    final notifier = container.read(dashboardProvider.notifier);
    final yesterday =
        DateTime.now().effectiveDay.subtract(const Duration(days: 1));
    final xpBefore = container.read(dashboardProvider).cumulativeXp;

    await mark(notifier, day: yesterday);

    expect(container.read(dashboardProvider).cumulativeXp, xpBefore,
        reason: 'the grace is a deadline, not an open door');
    expect(await storedCompletions(yesterday), isEmpty);
  });

  test('marking yesterday never touches today\'s board', () async {
    // The isolation that lets the two coexist. `completions` is what Today's
    // checklist and the day percentage read; a mark on another day landing
    // there would tick the wrong day on screen.
    final container = await launch(clock: preCutoff);
    final notifier = container.read(dashboardProvider.notifier);
    final today = DateTime.now().effectiveDay;
    final yesterday = today.subtract(const Duration(days: 1));

    await mark(notifier, day: yesterday);

    expect(container.read(dashboardProvider).completions['h1'], isNull,
        reason: "today's board must be untouched by yesterday's mark");
    expect(await storedCompletions(today), isEmpty);
  });

  test('both days can be marked in one sitting, and both are recorded',
      () async {
    // Aziz's rule: from midnight to the cutoff two days are open and both
    // pay. Skipped outside the window, where there is only one open day and
    // so nothing to assert.
    final container = await launch(clock: preCutoff);
    final notifier = container.read(dashboardProvider.notifier);
    final today = DateTime.now().effectiveDay;
    final yesterday = today.subtract(const Duration(days: 1));

    final xpBefore = container.read(dashboardProvider).cumulativeXp;
    await mark(notifier, day: yesterday);
    await mark(notifier, day: today);

    expect(container.read(dashboardProvider).cumulativeXp - xpBefore,
        greaterThanOrEqualTo(20),
        reason: 'two real days, two full payments');
    expect((await storedCompletions(yesterday))['h1'], 1);
    expect((await storedCompletions(today))['h1'], 1);
    expect(container.read(dashboardProvider).completions['h1'], 1,
        reason: "and only today's landed on today's board");
  });

  test('an undo can reach back exactly as far as a completion can', () async {
    // Otherwise a mark made during the grace could not be taken back by the
    // person who made it.
    final container = await launch(clock: preCutoff);
    final notifier = container.read(dashboardProvider.notifier);
    final yesterday =
        DateTime.now().effectiveDay.subtract(const Duration(days: 1));

    await mark(notifier, day: yesterday);
    final xpAfterMark = container.read(dashboardProvider).cumulativeXp;

    await notifier.uncompleteHabit(
      habitId: 'h1',
      xpReward: 10,
      goldReward: 5,
      category: 'quran',
      day: yesterday,
    );

    expect(container.read(dashboardProvider).cumulativeXp, xpAfterMark - 10,
        reason: 'the refund is the same size as the debit');
    expect(await storedCompletions(yesterday), isEmpty);
  });

  test('the completion time is not invented for a day that is not today',
      () async {
    // completedAtMinutes is minutes since local midnight. Stamping the
    // current clock onto yesterday would claim the habit happened at a time
    // nobody knows; an absent stamp reads as "completed, time unrecorded",
    // which is the truth. The admin report relies on this distinction.
    final container = await launch(clock: preCutoff);
    final notifier = container.read(dashboardProvider.notifier);
    final yesterday =
        DateTime.now().effectiveDay.subtract(const Duration(days: 1));

    await mark(notifier, day: yesterday);
    await LocalStoreService.settleDailyWrites();
    final stored = await LocalStoreService.getDailyMap(yesterday.toDateKey());

    expect(stored['habitCompletions'], isNotNull);
    expect(stored['completedAtMinutes'], isNull,
        reason: 'no stamp is better than a wrong one');
  });
}
