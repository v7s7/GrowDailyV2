// Yesterday's square of a habit counted more than once a day, tapped while
// yesterday is still open (until kDayCutoffHour the next morning), counts
// exactly like today's: each tap adds one and the square shows it ("5 / 6"),
// the last one turns it green, and a tap on a green square asks, then clears
// it. Aziz, 2026-09-24: "if 5 times it will be 6 times, unless it's 6/6".
//
// It recorded one slot and painted nothing. The tap went to
// _completeSquareToday, which calls DashboardNotifier.completeHabit ONCE and
// branches on its answer, and that answer is isGridSyncable,
// `frequencyTarget == 1`: false for every call of a counted habit. So the tap
// read its own success as a refusal. One slot was recorded and paid,
// S.squareNotReadyYet came up ("One moment, still loading"), and it returned
// before painting the square or telling the room. Every further tap did the
// same to the next slot, and the square never turned green. The Undo on the
// square's clear went through the same function, and counted from today.
//
// Driven through the real GridScreen, because the bug was in the wiring:
// completeHabit itself was never wrong, and the count a square reads for
// yesterday (DashboardState.graceCompletions) is what makes the counter
// possible there at all.
//
// Two things make this runnable at any hour:
//  - The clock. Against the real one this path exists ten hours in
//    twenty-four. The dashboard takes an injectable clock, and the square's
//    tap asks dayClockSourceProvider whether its day is open; both are set to
//    02:18 on today's real date, the hour a night owl marks yesterday. Only
//    the hour moves, as in grace_window_completion_test.dart, so the board and
//    the guest store still agree about which day is today.
//  - The storage. A widget test runs in fake async, where a Hive disk write
//    never finishes on its own (see landing_first_run_test.dart), and the
//    square is painted only after completeHabit's guest write returns.
//    [runTap] lets real time pass in small steps between frames, so the
//    tap's chain runs to its end the way it does on a phone, and
//    [reanchorBoxes] keeps one test's writes from hanging the next.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';

import 'package:grow_daily_v2/core/constants/game_constants.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/providers/day_clock_provider.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/core/utils/xp_calculator.dart';
import 'package:grow_daily_v2/features/achievements/models/achievement_model.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';

import '../../helpers/landing_harness.dart';
import '../../helpers/never_bonus_random.dart';
import '../../helpers/wait_until.dart';

void main() {
  const en = S(Locale('en'));

  /// Inbox Zero, counted four times a day.
  final base = IslamicHabitCatalog.findById('inbox_zero')!;
  final counted = IslamicHabitTemplate.fromMap(
    base.id,
    {...base.toFirestore(), 'frequencyTarget': 4},
  );
  const target = 4;

  /// 02:18 on today's real date: yesterday is still open, today has begun.
  DateTime preCutoff() {
    final t = DateTime.now();
    return DateTime(t.year, t.month, t.day, 2, 18);
  }

  final today = DateTime.now().effectiveDay;
  final yesterday = DateTime(today.year, today.month, today.day - 1);

  late LandingHarness h;

  /// The board with one counted habit, the clock at [preCutoff], and the
  /// dashboard for [uid]: null is a guest, whose numbers load from Hive.
  Future<void> prepareBoard({String? uid}) async {
    h = LandingHarness();
    await h.prepare(extraOverrides: [
      habitListProvider.overrideWith((ref) => [counted]),
      dashboardProvider.overrideWith(
        (ref) => DashboardNotifier(
          uid,
          random: NeverBonusRandom(),
          clock: preCutoff,
        ),
      ),
      dayClockSourceProvider.overrideWithValue(preCutoff),
    ]);
    // Hive boxes outlive a test (see note_save_feedback_test), so each one
    // starts from an empty store.
    await (await LocalStoreService.dailyBox()).clear();
    await (await LocalStoreService.settingsBox()).clear();
    // Every achievement already held, so no medal's own XP lands in the
    // totals below, and no unlock sheet covers the board.
    await LocalStoreService.putSettingsMap(
      LocalStoreService.guestDashboardKey,
      {
        'currentStreak': 0,
        'previousStreak': 0,
        'cumulativeXp': 0,
        'currentLevelXp': 0,
        'level': 1,
        'gold': 0,
        'unlockedAchievements': [
          for (final a in AchievementCatalog.all) a.id,
        ],
      },
    );
    h.container.read(dashboardProvider);
    await waitUntil(
      () => !h.container.read(dashboardProvider).isLoading,
      describe: 'the dashboard to finish its initial load',
    );
    await h.container.read(dashboardProvider.notifier).ready;
    h.container.read(weeklyGridProvider);
    await waitUntil(
      () => !h.container.read(weeklyGridProvider).isLoading,
      describe: 'the grid to finish its initial load',
    );
    // On a Saturday, yesterday closed the previous week.
    if (!h.container
        .read(weeklyGridProvider)
        .days
        .any((d) => d.isSameDayAs(yesterday))) {
      h.container.read(weeklyGridProvider.notifier).previousWeek();
      await waitUntil(
        () => h.container
            .read(weeklyGridProvider)
            .days
            .any((d) => d.isSameDayAs(yesterday)),
        describe: 'the week holding yesterday',
      );
    }
  }

  tearDown(() => h.dispose());

  Finder yesterdaySquare() => find.bySemanticsLabel(RegExp(
      '^${RegExp.escape('${counted.name}, '
          '${DateFormat('EEEE d MMMM', 'en').format(yesterday)},')}'));

  SquareState square() =>
      h.container.read(weeklyGridProvider).squareFor(counted.id, yesterday);

  bool notReadyShown() =>
      find.text(en.squareNotReadyYet).evaluate().isNotEmpty;

  int xp() => h.container.read(dashboardProvider).cumulativeXp;

  /// Yesterday's count as the board holds it (see _dayCount).
  int graceCount() =>
      h.container.read(dashboardProvider).graceCompletions[counted.id] ?? 0;

  /// Yesterday's square, found by a label that also says [text]: the count
  /// is drawn inside the square, so the screen-reader label is where a test
  /// can read it.
  Finder yesterdayShows(String text) => find.bySemanticsLabel(RegExp(
      '^${RegExp.escape('${counted.name}, '
          '${DateFormat('EEEE d MMMM', 'en').format(yesterday)},')}'
      '.*${RegExp.escape(text)}'));

  /// One step of real time for the disk, then a frame for whatever was
  /// waiting on it in the test's own zone. The frame moves the test's clock
  /// too, so a snackbar can finish leaving and the next one arrive.
  Future<void> step(WidgetTester tester) async {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 16));
  }

  /// Steps until every queued day write has landed.
  ///
  /// Never `runAsync(settleDailyWrites)`: a write whose next step is queued
  /// in the test's zone can only move on a frame, and runAsync pumps none,
  /// so that waits forever.
  Future<void> settleWrites(WidgetTester tester) async {
    var landed = false;
    unawaited(LocalStoreService.settleDailyWrites().then((_) => landed = true));
    for (var i = 0; i < 2000 && !landed; i++) {
      await step(tester);
    }
    if (!landed) fail('the day writes never landed');
  }

  /// Leaves every box's write queue ending on a future made in real time.
  ///
  /// Hive runs a box's operations one after another, each waiting on the
  /// future of the last (ReadWriteSync), and a finished future hands its
  /// result on through the zone it was made in. Every write this test's taps
  /// made was made in its fake-async zone, which dies with the test, so the
  /// next test's first write on that box would wait forever: that is the hang
  /// this file had before this existed. clear() takes both of a box's queues,
  /// and started from runAsync, what it leaves behind belongs to real time.
  Future<void> reanchorBoxes(WidgetTester tester) async {
    var cleared = false;
    await tester.runAsync(() async {
      unawaited(Future.wait([
        for (final name in [
          GameConstants.boxDailyLogs,
          GameConstants.boxSettings,
          GameConstants.boxHabits,
        ])
          Hive.box<dynamic>(name).clear(),
      ]).then((_) => cleared = true));
    });
    for (var i = 0; i < 2000 && !cleared; i++) {
      await step(tester);
    }
    if (!cleared) fail('the boxes never cleared');
  }

  /// What yesterday's stored day says this habit has, once every queued
  /// write has landed.
  Future<int> storedCount(WidgetTester tester) async {
    await settleWrites(tester);
    final day = LocalStoreService.asStringMap(
      Hive.box<dynamic>(GameConstants.boxDailyLogs)
          .get(yesterday.toDateKey()),
    );
    final raw = (day['habitCompletions'] as Map?)?[counted.id];
    return raw is num ? raw.toInt() : 0;
  }

  /// Runs what a tap started until [settled] holds, then until every write
  /// it queued has landed, so what the test reads back from the store is
  /// what the tap left there. Fails loudly rather than asserting against a
  /// chain still in flight.
  Future<void> runTap(
    WidgetTester tester,
    bool Function() settled,
    String describe,
  ) async {
    for (var i = 0; i < 2000 && !settled(); i++) {
      await step(tester);
    }
    await settleWrites(tester);
    // The settings box has no queue to wait on; a few more steps let the
    // guest state written after the day land too.
    for (var i = 0; i < 20; i++) {
      await step(tester);
    }
    if (!settled()) fail('the tap never settled: $describe');
  }

  /// Pumps the board with yesterday's square in view, runs [body], and then,
  /// whatever [body] did, takes the board down and lets every write that
  /// started land before the test ends.
  ///
  /// The finally is not tidiness: the boxes have to be re-anchored (see
  /// [reanchorBoxes]) even when an expect in [body] fails, or the next test
  /// in this file hangs instead of running.
  Future<void> onBoard(
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    await tester.pumpWidget(h.app());
    await h.settle(tester);
    try {
      expect(yesterdaySquare(), findsOneWidget,
          reason: 'the square is found by its date; nothing below is tested '
              'without it');
      await tester.ensureVisible(yesterdaySquare());
      await h.settle(tester);
      await body();
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      // Snackbars and the row's stagger leave timers behind, and the binding
      // fails a test that ends with one pending. Fired first, so anything
      // they write is still stepped through below.
      await tester.pump(const Duration(seconds: 7));
      await tester.pump(const Duration(milliseconds: 1));
      for (var i = 0; i < 20; i++) {
        await step(tester);
      }
      await settleWrites(tester);
      await reanchorBoxes(tester);
    }
  }

  /// Records slots of yesterday straight through the dashboard, the way the
  /// square used to leave them: recorded and paid, the square untouched.
  Future<void> recordSlots(WidgetTester tester, int slots) async {
    for (var i = 0; i < slots; i++) {
      await tester.runAsync(
        () => h.container.read(dashboardProvider.notifier).completeHabit(
              habitId: counted.id,
              xpReward: counted.xpReward,
              goldReward: counted.goldReward,
              frequencyTarget: target,
              allHabitsDoneAfter: false,
              day: yesterday,
            ),
      );
    }
    expect(await storedCount(tester), slots, reason: 'precondition');
  }

  group('with the account loaded', () {
    setUp(prepareBoard);

    testWidgets('each tap adds one and shows it; the last one is green',
        (tester) async {
      await onBoard(tester, () async {
        expect(square(), SquareState.none, reason: 'precondition');
        expect(yesterdayShows(en.timesPerDayProgress(0, target)),
            findsOneWidget,
            reason: 'yesterday shows its count before the first tap');
        final xpBefore = xp();

        for (var n = 1; n <= target; n++) {
          final painted = n < target ? SquareState.partial : SquareState.complete;
          await tester.tap(yesterdaySquare());
          await runTap(
            tester,
            () => (graceCount() >= n && square() == painted) || notReadyShown(),
            'yesterday counting to $n, or the not-ready message',
          );

          expect(notReadyShown(), isFalse,
              reason: 'tap $n: the old single call answered false for every '
                  'counted habit, and that false read as "still loading"');
          expect(await storedCount(tester), n,
              reason: 'tap $n adds exactly one, not the whole day');
          expect(square(), painted,
              reason: 'part done until the last tap, green on it');
          expect(yesterdayShows(en.timesPerDayProgress(n, target)),
              findsOneWidget,
              reason: 'the square shows the count the tap left');
          expect(
            xp() - xpBefore,
            XpCalculator.rewardPaidSoFar(
              total: counted.xpReward,
              target: target,
              done: n,
            ),
            reason: 'each tap is paid its slice, and the day its price once',
          );
        }
        expect(h.container.read(dashboardProvider).completions[counted.id],
            isNull,
            reason: "yesterday's count never lands on today's board");
      });
    });

    testWidgets('a day already part done shows its count, and a tap adds one',
        (tester) async {
      // What the broken tap left behind on anyone who tapped twice: two of four
      // slots recorded and paid, the square still empty.
      await recordSlots(tester, 2);
      await onBoard(tester, () async {
        expect(yesterdayShows(en.timesPerDayProgress(2, target)),
            findsOneWidget,
            reason: 'what was recorded is what the square shows');
        final xpBefore = xp();

        await tester.tap(yesterdaySquare());
        await runTap(
          tester,
          () => (graceCount() >= 3 && square() == SquareState.partial) ||
              notReadyShown(),
          'yesterday counting to 3, or the not-ready message',
        );

        expect(notReadyShown(), isFalse);
        expect(await storedCount(tester), 3);
        expect(square(), SquareState.partial);
        expect(yesterdayShows(en.timesPerDayProgress(3, target)),
            findsOneWidget);
        expect(
          xp() - xpBefore,
          XpCalculator.rewardPaidSoFar(
                total: counted.xpReward,
                target: target,
                done: 3,
              ) -
              XpCalculator.rewardPaidSoFar(
                total: counted.xpReward,
                target: target,
                done: 2,
              ),
          reason: 'only the third slice: the two already paid are not paid '
              'again',
        );
      });
    });

    testWidgets('a count that moved since the board read it is painted as it '
        'landed', (tester) async {
      // Storage says 3 of 4 while the board still holds 2: a tap from another
      // device, or a write this board never saw.
      await recordSlots(tester, 2);
      await tester.runAsync(
        () => LocalStoreService.updateDailyMap(yesterday.toDateKey(), (d) {
          d['habitCompletions'] = {
            ...((d['habitCompletions'] as Map?) ?? const {}),
            counted.id: 3,
          };
        }),
      );
      await onBoard(tester, () async {
        expect(yesterdayShows(en.timesPerDayProgress(2, target)),
            findsOneWidget,
            reason: 'precondition: the board still holds 2');

        await tester.tap(yesterdaySquare());
        await runTap(
          tester,
          () => (graceCount() >= target && square() == SquareState.complete) ||
              notReadyShown(),
          'yesterday at 4 of 4, or the not-ready message',
        );

        expect(notReadyShown(), isFalse);
        expect(await storedCount(tester), target,
            reason: 'the tap counted from the stored 3');
        expect(square(), SquareState.complete,
            reason: 'painted from the 4 that landed, not the 3 the board '
                'expected');
      });
    });

    testWidgets('clearing a full day names its reward, and Undo puts it back',
        (tester) async {
      // Yesterday finished and green, set up without the square's own tap so
      // this reaches the clear and the Undo whichever way the tap behaves.
      await recordSlots(tester, target);
      await tester.runAsync(
        () => h.container
            .read(weeklyGridProvider.notifier)
            .setSquareStateOnlyAsync(
              counted.id,
              yesterday,
              SquareState.complete,
            ),
      );
      await onBoard(tester, () async {
        expect(square(), SquareState.complete, reason: 'precondition');
        final xpFull = xp();

        // A tap on the green square asks first.
        await tester.tap(yesterdaySquare());
        await h.settle(tester);
        expect(
          find.text(en.gridClearMarkBody(
              counted.name, counted.xpReward, counted.goldReward)),
          findsOneWidget,
          reason: "the dialog read today's count for yesterday's square and "
              'promised no refund, while the clear took the reward back',
        );
        await tester.tap(find.text(en.gridClearMarkConfirm));
        await runTap(
          tester,
          () => find.text(en.undo).evaluate().isNotEmpty,
          'the cleared-mark snackbar',
        );
        expect(square(), SquareState.none, reason: 'precondition');
        expect(await storedCount(tester), 0, reason: 'precondition');
        expect(xpFull - xp(), counted.xpReward,
            reason: 'precondition: the clear refunds the whole day');

        // The steps above pump frames without moving the clock far, so the
        // snackbar may still be sliding in; a tap then lands on the board.
        await h.settle(tester);
        await tester.tap(find.text(en.undo));
        await runTap(
          tester,
          () => (graceCount() >= target &&
                  square() == SquareState.complete) ||
              notReadyShown(),
          'yesterday back at 4 of 4, or the not-ready message',
        );

        expect(notReadyShown(), isFalse,
            reason: 'the Undo made the same one call the tap did, and read '
                'its false the same way');
        expect(square(), SquareState.complete);
        expect(await storedCount(tester), target,
            reason: 'every tap of the day comes back, counted from '
                "yesterday's own number, not today's");
        expect(xp(), xpFull,
            reason: 'put back exactly as it stood before the clear');
      });
    });
  });

  group('with the account not loaded', () {
    // A signed-in account whose load failed: Firebase is never initialised
    // under flutter test, so the load throws and sets loadFailed, the
    // production state reached the production way (see
    // load_failed_guard_test.dart). completeHabit turns every call away then.
    setUp(() => prepareBoard(uid: 'signed-in'));

    testWidgets('the tap says so and paints nothing', (tester) async {
      expect(h.container.read(dashboardProvider).loadFailed, isTrue,
          reason: 'the fixture itself: nothing below is tested without it');
      await onBoard(tester, () async {
        await tester.tap(yesterdaySquare());
        await runTap(
          tester,
          () => square() != SquareState.none || notReadyShown(),
          'yesterday painted, or the not-ready message',
        );

        expect(notReadyShown(), isTrue,
            reason: 'nothing was recorded, and the person has to be told');
        expect(square(), SquareState.none,
            reason: 'nothing was recorded or paid, so the square must not '
                'claim otherwise');
      });
    });
  });
}
