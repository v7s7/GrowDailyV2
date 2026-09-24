// The palette's مكتمل (or إنجاز إضافي) on a counted habit's square part way
// through its day, 2 of 4, finishes the day: the two slots still owed are
// recorded and paid, and only then does the square take the picked colour.
//
// It only recoloured. paletteLockedFor treats a mid-count square as a paid
// completion (per-tap progress was paid), and _handlePaletteTap's first
// branch read every locked square picked green or blue as "already paid,
// change the colour and nothing else". That is true of a finished day and
// false of 2 of 4: the stored square said مكتمل, which rooms, the heatmap and
// the reports all read, while the count stayed at 2 and the last two slices
// were never recorded or paid.
//
// Today and yesterday (still open until kDayCutoffHour) both, since the
// palette locks both. Same harness as grace_day_counted_square_test.dart,
// which explains it: the dashboard clock and dayClockSourceProvider at 02:18
// on today's real date, real time stepped between frames so the guest writes
// land, and the boxes re-anchored at the end of every test so the next one
// does not hang.
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

  /// Left undone throughout, so finishing the counted habit never finishes
  /// the whole day: no perfect-day overlay over the board, no streak point.
  final other = IslamicHabitCatalog.findById('daily_planning')!;

  /// 02:18 on today's real date: yesterday is still open, today has begun.
  DateTime preCutoff() {
    final t = DateTime.now();
    return DateTime(t.year, t.month, t.day, 2, 18);
  }

  final today = DateTime.now().effectiveDay;
  final yesterday = DateTime(today.year, today.month, today.day - 1);

  late LandingHarness h;

  /// The board with the two habits, the clock at [preCutoff], a guest
  /// dashboard loaded from Hive, and the week holding [day] on screen.
  Future<void> prepareBoard(DateTime day) async {
    h = LandingHarness();
    await h.prepare(extraOverrides: [
      habitListProvider.overrideWith((ref) => [counted, other]),
      dashboardProvider.overrideWith(
        (ref) => DashboardNotifier(
          null,
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
        .any((d) => d.isSameDayAs(day))) {
      h.container.read(weeklyGridProvider.notifier).previousWeek();
      await waitUntil(
        () => h.container
            .read(weeklyGridProvider)
            .days
            .any((d) => d.isSameDayAs(day)),
        describe: 'the week holding the day under test',
      );
    }
  }

  tearDown(() => h.dispose());

  Finder squareOn(DateTime day) => find.bySemanticsLabel(RegExp(
      '^${RegExp.escape('${counted.name}, '
          '${DateFormat('EEEE d MMMM', 'en').format(day)},')}'));

  /// A palette swatch, found by its label inside the sheet only: the board
  /// behind it has words of its own.
  Finder swatch(SquareState state) => find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(state.label),
      );

  SquareState square(DateTime day) =>
      h.container.read(weeklyGridProvider).squareFor(counted.id, day);

  /// [day]'s count as the dashboard holds it: today's map, or yesterday's
  /// while it is open (DashboardState.graceCompletions).
  int count(DateTime day) {
    final dash = h.container.read(dashboardProvider);
    return (day.isToday
            ? dash.completions[counted.id]
            : dash.graceCompletions[counted.id]) ??
        0;
  }

  bool notReadyShown() =>
      find.text(en.squareNotReadyYet).evaluate().isNotEmpty;

  int xp() => h.container.read(dashboardProvider).cumulativeXp;
  int gold() => h.container.read(dashboardProvider).gold;

  /// One step of real time for the disk, then a frame for whatever was
  /// waiting on it in the test's own zone.
  Future<void> step(WidgetTester tester) async {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 16));
  }

  /// Steps until every queued day write has landed. Never
  /// `runAsync(settleDailyWrites)`: see grace_day_counted_square_test.dart.
  Future<void> settleWrites(WidgetTester tester) async {
    var landed = false;
    unawaited(LocalStoreService.settleDailyWrites().then((_) => landed = true));
    for (var i = 0; i < 2000 && !landed; i++) {
      await step(tester);
    }
    if (!landed) fail('the day writes never landed');
  }

  /// Leaves every box's write queue ending on a future made in real time, so
  /// the next test's first write does not wait forever on this test's dead
  /// zone. See grace_day_counted_square_test.dart's reanchorBoxes.
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

  /// What [day]'s stored document says this habit has, once every queued
  /// write has landed.
  Future<int> storedCount(WidgetTester tester, DateTime day) async {
    await settleWrites(tester);
    final stored = LocalStoreService.asStringMap(
      Hive.box<dynamic>(GameConstants.boxDailyLogs).get(day.toDateKey()),
    );
    final raw = (stored['habitCompletions'] as Map?)?[counted.id];
    return raw is num ? raw.toInt() : 0;
  }

  /// Runs what the pick started until [settled] holds (or a generous number
  /// of steps pass), then until every write it queued has landed. Does not
  /// fail on its own: the expects after it say what the pick left behind,
  /// which is a better message than "it never settled".
  Future<void> runPick(WidgetTester tester, bool Function() settled) async {
    for (var i = 0; i < 1500 && !settled(); i++) {
      await step(tester);
    }
    await settleWrites(tester);
    for (var i = 0; i < 20; i++) {
      await step(tester);
    }
  }

  /// Pumps the board, opens the long-press editor on [day]'s square, runs
  /// [body], and then, whatever [body] did, takes the board down and lets
  /// every write that started land before the test ends. The finally is what
  /// keeps a failing expect from hanging the next test.
  Future<void> inEditor(
    WidgetTester tester,
    DateTime day,
    Future<void> Function() body,
  ) async {
    await tester.pumpWidget(h.app());
    await h.settle(tester);
    try {
      expect(squareOn(day), findsOneWidget,
          reason: 'the square is found by its date; nothing below is tested '
              'without it');
      await tester.ensureVisible(squareOn(day));
      await h.settle(tester);
      await tester.longPress(squareOn(day));
      await h.settle(tester);
      expect(find.text(en.gridSave), findsOneWidget,
          reason: 'the long-press editor did not open, so nothing after this '
              'is testing anything');
      await body();
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 7));
      await tester.pump(const Duration(milliseconds: 1));
      for (var i = 0; i < 20; i++) {
        await step(tester);
      }
      await settleWrites(tester);
      await reanchorBoxes(tester);
    }
  }

  /// [slots] of [day] recorded and paid through the dashboard, and the
  /// square painted [painted], the way the square's own taps leave a counted
  /// day part done (see _GridTableState._addOneToday).
  Future<void> seedDay(
    WidgetTester tester,
    DateTime day,
    int slots, {
    required SquareState painted,
  }) async {
    for (var i = 0; i < slots; i++) {
      await tester.runAsync(
        () => h.container.read(dashboardProvider.notifier).completeHabit(
              habitId: counted.id,
              xpReward: counted.xpReward,
              goldReward: counted.goldReward,
              frequencyTarget: target,
              allHabitsDoneAfter: false,
              day: day,
            ),
      );
    }
    await tester.runAsync(
      () => h.container
          .read(weeklyGridProvider.notifier)
          .setSquareStateOnlyAsync(counted.id, day, painted),
    );
    expect(await storedCount(tester, day), slots, reason: 'precondition');
    expect(count(day), slots, reason: 'precondition');
    expect(square(day), painted, reason: 'precondition');
  }

  int paidFor(int done) => XpCalculator.rewardPaidSoFar(
        total: counted.xpReward,
        target: target,
        done: done,
      );
  int goldFor(int done) => XpCalculator.rewardPaidSoFar(
        total: counted.goldReward,
        target: target,
        done: done,
      );

  /// The whole check for one pick on a day part done: the slots still owed
  /// are recorded and paid, and the square wears [picked].
  Future<void> expectPickFinishesDay(
    WidgetTester tester,
    DateTime day,
    SquareState picked,
  ) async {
    await seedDay(tester, day, 2, painted: SquareState.partial);
    await inEditor(tester, day, () async {
      expect(find.text(en.gridSquarePartlyDoneFromToday), findsOneWidget,
          reason: 'precondition: the palette treats 2 of 4 as a paid, '
              'locked square');
      final xpBefore = xp();
      final goldBefore = gold();

      await tester.tap(swatch(picked));
      await runPick(
        tester,
        () => (count(day) >= target && square(day) == picked) ||
            notReadyShown(),
      );

      expect(notReadyShown(), isFalse);
      expect(await storedCount(tester, day), target,
          reason: 'the two slots still owed are recorded: the square says '
              'the day is done, so the count has to agree');
      expect(count(day), target);
      expect(square(day), picked);
      expect(xp() - xpBefore, paidFor(target) - paidFor(2),
          reason: 'the last two slices are paid, and only those');
      expect(gold() - goldBefore, goldFor(target) - goldFor(2));
    });
  }

  group('today', () {
    setUp(() => prepareBoard(today));

    testWidgets('مكتمل on 2 of 4 finishes the day', (tester) async {
      await expectPickFinishesDay(tester, today, SquareState.complete);
    });

    testWidgets('إنجاز إضافي on 2 of 4 finishes the day and paints it blue',
        (tester) async {
      await expectPickFinishesDay(tester, today, SquareState.bonus);
    });

    testWidgets('مكتمل on a green square the count never finished finishes it',
        (tester) async {
      // What the old recolour left behind on anyone who hit it: the stored
      // square green, the count still 2. Picking مكتمل again has to repair
      // the count, not repaint a colour that is already there.
      await seedDay(tester, today, 2, painted: SquareState.complete);
      await inEditor(tester, today, () async {
        final xpBefore = xp();

        await tester.tap(swatch(SquareState.complete));
        await runPick(
          tester,
          () => count(today) >= target || notReadyShown(),
        );

        expect(notReadyShown(), isFalse);
        expect(await storedCount(tester, today), target);
        expect(square(today), SquareState.complete);
        expect(xp() - xpBefore, paidFor(target) - paidFor(2));
      });
    });

    testWidgets('إنجاز إضافي on a finished day only recolours',
        (tester) async {
      // The rule the first branch exists for, which must survive: a day
      // already paid in full is never paid again.
      await seedDay(tester, today, target, painted: SquareState.complete);
      await inEditor(tester, today, () async {
        final xpBefore = xp();
        final goldBefore = gold();

        await tester.tap(swatch(SquareState.bonus));
        await runPick(tester, () => square(today) == SquareState.bonus);

        expect(square(today), SquareState.bonus);
        expect(await storedCount(tester, today), target);
        expect(xp(), xpBefore, reason: 'blue on a paid day is a colour');
        expect(gold(), goldBefore);
      });
    });
  });

  group('yesterday, before the cutoff', () {
    setUp(() => prepareBoard(yesterday));

    testWidgets('مكتمل on 2 of 4 finishes the day', (tester) async {
      await expectPickFinishesDay(tester, yesterday, SquareState.complete);
    });

    testWidgets('إنجاز إضافي on 2 of 4 finishes the day and paints it blue',
        (tester) async {
      await expectPickFinishesDay(tester, yesterday, SquareState.bonus);
    });

    testWidgets('مكتمل on a finished day only recolours', (tester) async {
      // 4 of 4 with a جزئي square: what the notification path left on
      // yesterday when it painted from today's count. The count is already
      // full, so the pick repairs the colour and pays nothing.
      await seedDay(tester, yesterday, target, painted: SquareState.partial);
      await inEditor(tester, yesterday, () async {
        final xpBefore = xp();

        await tester.tap(swatch(SquareState.complete));
        await runPick(
          tester,
          () => square(yesterday) == SquareState.complete || notReadyShown(),
        );

        expect(notReadyShown(), isFalse);
        expect(square(yesterday), SquareState.complete);
        expect(await storedCount(tester, yesterday), target);
        expect(xp(), xpBefore);
      });
    });
  });
}
