import 'dart:io';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/core/utils/xp_calculator.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';

import 'helpers/wait_until.dart';

class _NeverBonusRandom implements Random {
  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 1;

  @override
  int nextInt(int max) => 0;
}

/// A habit scheduled every day, alive for all of history — the plain case
/// the streak-decay rules were originally written against.
IslamicHabitTemplate _everyDayHabit() => IslamicHabitTemplate(
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
  // completeHabit/applyGridSquareChange fire real local-notification calls
  // (habit-completed/level-up/achievement-unlocked) as unawaited
  // fire-and-forget side effects. flutter_local_notifications' plugin init
  // has no platform implementation to talk to under `flutter test` (no
  // real device/simulator), which previously surfaced as a
  // LateInitializationError thrown from inside those unawaited Futures —
  // unrelated to anything this file actually asserts on, but noisy/flaky
  // enough to fail tests that never cared about notifications in the
  // first place. This is the same on/off switch a real Settings screen
  // would flip; here it just keeps this suite headless.
  NotificationService.instance.celebrationsEnabled = false;

  group('SquareState', () {
    test('tap cycle follows white → green → white', () {
      // One tap means done. Yellow used to sit in the middle of this cycle,
      // which made the app's most common action cost two taps and put a
      // claim nobody made ("partly done") in between. Yellow is still
      // reachable, deliberately, from the long-press palette.
      expect(SquareState.none.next, SquareState.complete);
      expect(SquareState.complete.next, SquareState.none);
      // Every non-empty state taps back to a clean slate, yellow included:
      // a tap can leave partial but can no longer arrive at it.
      expect(SquareState.partial.next, SquareState.none);
      expect(SquareState.failed.next, SquareState.none);
      expect(SquareState.bonus.next, SquareState.none);
      expect(SquareState.skipped.next, SquareState.none);
    });

    test('a tap can never land on partial', () {
      // The property, rather than the table above: whatever the cycle is
      // rearranged into later, no single tap may produce a half-done claim.
      for (final s in SquareState.values) {
        expect(s.next, isNot(SquareState.partial),
            reason: '$s taps into partial');
      }
    });

    test('fixed XP values match the spec', () {
      expect(SquareState.complete.xpValue, 10);
      expect(SquareState.partial.xpValue, 5);
      expect(SquareState.bonus.xpValue, 15);
      expect(SquareState.failed.xpValue, -3);
      expect(SquareState.none.xpValue, 0);
      expect(SquareState.skipped.xpValue, 0);
    });

    test('green means complete or bonus, nothing else', () {
      expect(
        SquareState.values.where((s) => s.isGreen),
        [SquareState.complete, SquareState.bonus],
      );
    });
  });

  group('XpCalculator.applyXpDelta', () {
    test('negative delta trims XP but never de-levels', () {
      final r = XpCalculator.applyXpDelta(
        currentLevel: 3,
        currentLevelXp: 2,
        cumulativeXp: 302,
        xpDelta: -10,
      );
      expect(r.newLevel, 3);
      expect(r.newCurrentLevelXp, 0);
      expect(r.newCumulativeXp, 292);
    });

    test('positive delta still multi-levels through applyXpGain', () {
      final r = XpCalculator.applyXpDelta(
        currentLevel: 1,
        currentLevelXp: 95,
        cumulativeXp: 95,
        xpDelta: 10,
      );
      expect(r.newLevel, 2);
      expect(r.newCurrentLevelXp, 5);
    });
  });

  group('startOfGridWeek', () {
    test('always returns the Saturday on or before the date', () {
      // 2026-07-05 is a Sunday → week starts Saturday 2026-07-04.
      expect(
        startOfGridWeek(DateTime(2026, 7, 5)),
        DateTime(2026, 7, 4),
      );
      // A Saturday is its own week start.
      expect(
        startOfGridWeek(DateTime(2026, 7, 4)),
        DateTime(2026, 7, 4),
      );
      // A Friday belongs to the previous Saturday's week.
      expect(
        startOfGridWeek(DateTime(2026, 7, 10)),
        DateTime(2026, 7, 4),
      );
    });
  });

  group('grid → dashboard progression pipeline (guest path)', () {
    late Directory tmp;
    late ProviderContainer container;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('grid_test_');
      Hive.init(tmp.path);
      container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
          dashboardProvider.overrideWith(
            (ref) => DashboardNotifier(null, random: _NeverBonusRandom()),
          ),
        ],
      );
      // Resolve auth first so dependent notifiers are created exactly once —
      // otherwise the stream's async emission rebuilds them mid-test and
      // mutations land on a notifier that's about to be discarded.
      await container.read(authStateProvider.future);
      // Wait until the guest notifiers actually finish loading — a fixed
      // delay races the first (cold) Hive open and the late load result
      // would clobber XP earned by the test's own mutations.
      container.read(weeklyGridProvider);
      await waitUntil(
        () =>
            !container.read(dashboardProvider).isLoading &&
            !container.read(weeklyGridProvider).isLoading,
        describe: 'the dashboard and grid to finish their initial load',
      );
      expect(container.read(dashboardProvider).isLoading, isFalse);
    });

    tearDown(() async {
      container.dispose();
      // Square writes are deliberately fire and forget (the square turns on
      // the same frame either way), and they now queue per day so they cannot
      // clobber each other. Deleting the store out from under a queued write
      // is a thing only a test does, so drain first.
      await LocalStoreService.settleDailyWrites();
      await Hive.deleteFromDisk();
      await tmp.delete(recursive: true);
    });

    test('a counted habit keeps every XP its taps paid, with nothing clawed back',
        () async {
      // The leak: tap 1 of a 4x habit paints its square جزئي through
      // markResultFromHabit, which does NOT pay the flat rate (the reward is
      // completeHabit's slice). The finishing tap then repainted it أخضر, and
      // the refund path inferred "a yellow square was paid 5 XP" from the
      // colour alone and took 5 back. Every counted day silently netted 5 XP
      // short, and each tap-to-full-then-clear lap lost another 5.
      final today = DateTime.now().effectiveDay;
      const target = 4;
      const xpReward = 10;
      final dash = container.read(dashboardProvider.notifier);
      final grid = container.read(weeklyGridProvider.notifier);

      // Taps 1..N-1: each pays its slice and paints جزئي.
      for (var i = 0; i < target - 1; i++) {
        await dash.completeHabit(
          habitId: 'counted',
          xpReward: xpReward,
          goldReward: 4,
          frequencyTarget: target,
          allHabitsDoneAfter: false,
          category: 'custom',
          habitName: 'counted',
        );
        grid.markResultFromHabit('counted', today, SquareState.partial);
      }
      // The finishing tap's reward, banked before the square is repainted.
      await dash.completeHabit(
        habitId: 'counted',
        xpReward: xpReward,
        goldReward: 4,
        frequencyTarget: target,
        allHabitsDoneAfter: false,
        category: 'custom',
        habitName: 'counted',
      );
      expect(container.read(dashboardProvider).completions['counted'], target);

      // Measured across the mirror write ALONE, so unlocked achievements and
      // streak milestones (which pay real XP on these same taps) cannot mask
      // or fake the result. Mirroring a square is a picture, not a payment: it
      // must move the XP total by exactly nothing.
      final beforeMirror = container.read(dashboardProvider).cumulativeXp;
      grid.markResultFromHabit('counted', today, SquareState.complete);
      expect(
        container.read(dashboardProvider).cumulativeXp,
        beforeMirror,
        reason: 'the finishing tap repaints جزئي to أخضر; refunding a flat rate '
            'that markResultFromHabit never paid cost every counted day 5 XP',
      );
    });

    test('a palette lap still nets exactly zero', () async {
      // The other half of the same rule, and the reason the refund exists at
      // all: setSquare DOES pay the flat rate, so a square it painted must
      // still give that back when the canonical path takes it over. none →
      // جزئي (+5 paid) → complete (canonical, refunds the 5) must leave the
      // flat-rate economy exactly where it started.
      final today = DateTime.now().effectiveDay;
      final grid = container.read(weeklyGridProvider.notifier);
      final before = container.read(dashboardProvider).cumulativeXp;

      grid.setSquare('painted', today, SquareState.partial);
      await LocalStoreService.settleDailyWrites();
      expect(container.read(dashboardProvider).cumulativeXp, before + 5,
          reason: 'the palette pays the flat rate for yellow');

      grid.markResultFromHabit('painted', today, SquareState.complete);
      await LocalStoreService.settleDailyWrites();
      expect(container.read(dashboardProvider).cumulativeXp, before,
          reason: 'and the canonical take-over gives back exactly that 5, so '
              'the lap cannot be farmed');
    });

    test(
        'the first green square awards +10 XP and the First Victory achievement',
        () async {
      // effectiveDay, not raw now: between midnight and the 10 AM flex cutoff
      // (DateTimeGameExt.effectiveDay) the calendar day is ahead of the
      // app's reward day, and a raw now() square would be graded as
      // tomorrow's (zero XP). Raw now() made this whole file fail when
      // the suite ran inside the flex window.
      final today = DateTime.now().effectiveDay;
      container
          .read(weeklyGridProvider.notifier)
          .setSquare('habit_a', today, SquareState.complete);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final dash = container.read(dashboardProvider);
      // +10 for the square, +25 from the First Victory unlock.
      expect(dash.cumulativeXp, 35);
      expect(dash.unlockedAchievements, contains('green_1'));
      expect(dash.gold, 10);
      expect(dash.totalGreenSquares, 1);
      // A raw Grid color change never earns the streak on its own anymore —
      // streak means 100% of *today's real habits* done (see
      // DashboardState.streakEarnedToday), which only DashboardNotifier.
      // completeHabit can determine (it's the only caller with the actual
      // habit list). This test never touches completeHabit, so streak stays
      // untouched at its initial 0.
      expect(dash.streak, 0);

      final key =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      expect(dash.dailyGreenCounts[key], 1);
    });

    test(
        'cycling a square back and forth cannot farm XP, and never touches streak',
        () async {
      // effectiveDay, not raw now: between midnight and the 10 AM flex cutoff
      // (DateTimeGameExt.effectiveDay) the calendar day is ahead of the
      // app's reward day, and a raw now() square would be graded as
      // tomorrow's (zero XP). Raw now() made this whole file fail when
      // the suite ran inside the flex window.
      final today = DateTime.now().effectiveDay;
      final grid = container.read(weeklyGridProvider.notifier);

      grid.setSquare('habit_a', today, SquareState.complete);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      grid.setSquare('habit_a', today, SquareState.none);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      grid.setSquare('habit_a', today, SquareState.complete);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final dash = container.read(dashboardProvider);
      // Net effect identical to coloring it green once (+10 square, +25
      // one-time First Victory) — the achievement never re-unlocks.
      expect(dash.cumulativeXp, 35);
      expect(dash.totalGreenSquares, 1);
      // Grid color changes alone never grant a streak point (see the test
      // above) — asserted again here as a regression guard against the
      // original bug report (a Grid/habit-list action was independently
      // bumping the streak, letting a single day rack up several points).
      expect(dash.streak, 0);
    });

    test(
        'a colour handed over to the canonical path gives its flat-rate XP back',
        () async {
      // The test above only ever stays on the flat-rate path, where
      // setSquare's own delta math already balances — which is exactly why
      // it kept passing while a real leak sat next to it. This one crosses
      // the seam: yellow is paid by setSquare, then the square is taken over
      // by the canonical completeHabit path, which mirrors the visual state
      // through setSquareStateOnly. That mirror used to leave yellow's 5 XP
      // banked with nothing on screen to show for it, so a full
      // none → partial → complete → none lap netted +5 every time and could
      // be repeated forever. Reproduced by hand on a simulator before this
      // was fixed: 90 XP in, 95 XP out, square empty and gold unchanged.
      // effectiveDay, not raw now: between midnight and the 10 AM flex cutoff
      // (DateTimeGameExt.effectiveDay) the calendar day is ahead of the
      // app's reward day, and a raw now() square would be graded as
      // tomorrow's (zero XP). Raw now() made this whole file fail when
      // the suite ran inside the flex window.
      final today = DateTime.now().effectiveDay;
      final grid = container.read(weeklyGridProvider.notifier);

      grid.setSquare('habit_a', today, SquareState.partial);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(dashboardProvider).cumulativeXp, 5,
          reason: 'yellow should be paid its flat rate on the way in');

      // Stands in for the real tap handler, which calls completeHabit and
      // then mirrors the square rather than going through setSquare.
      grid.markCompleteFromHabit('habit_a', today);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final dash = container.read(dashboardProvider);
      // completeHabit is never called here, so the only XP movement this
      // test can observe is the reversal itself: yellow's 5 back out.
      expect(dash.cumulativeXp, 0,
          reason: 'the 5 XP yellow was paid must come back when the '
              'canonical path takes the square over');
    });

    test('a red square costs 3 XP but the floor is zero', () async {
      // effectiveDay, not raw now: between midnight and the 10 AM flex cutoff
      // (DateTimeGameExt.effectiveDay) the calendar day is ahead of the
      // app's reward day, and a raw now() square would be graded as
      // tomorrow's (zero XP). Raw now() made this whole file fail when
      // the suite ran inside the flex window.
      final today = DateTime.now().effectiveDay;
      container
          .read(weeklyGridProvider.notifier)
          .setSquare('habit_a', today, SquareState.failed);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final dash = container.read(dashboardProvider);
      expect(dash.cumulativeXp, 0); // 0 - 3 floors at 0
      expect(dash.totalGreenSquares, 0);
      expect(dash.streak, 0); // red never earns a streak
    });

    test(
        'coloring a past day green persists visually but awards zero XP, gold, or achievement credit',
        () async {
      final pastDay =
          DateTime.now().effectiveDay.subtract(const Duration(days: 3));
      final grid = container.read(weeklyGridProvider.notifier);

      grid.setSquare('habit_a', pastDay, SquareState.complete);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Visual record still updates — Grid stays an honest "what did I do"
      // log even for a day logged after the fact.
      expect(
        container.read(weeklyGridProvider).squareFor('habit_a', pastDay),
        SquareState.complete,
      );

      // Nothing reaches the reward system: no free XP/gold/achievement
      // farming by backdating squares to a day that was never lived through.
      // The heatmap rollup does update, because it is a historical visual
      // record rather than progression.
      final dash = container.read(dashboardProvider);
      expect(dash.cumulativeXp, 0);
      expect(dash.gold, 0);
      expect(dash.totalGreenSquares, 0);
      expect(dash.unlockedAchievements, isNot(contains('green_1')));
      expect(dash.streak, 0);

      final key = pastDay.toDateKey();
      expect(dash.dailyGreenCounts[key], 1);
    });

    test('today completion ratio counts daily tasks, not old squares', () {
      // effectiveDay, not raw now: between midnight and the 10 AM flex cutoff
      // (DateTimeGameExt.effectiveDay) the calendar day is ahead of the
      // app's reward day, and a raw now() square would be graded as
      // tomorrow's (zero XP). Raw now() made this whole file fail when
      // the suite ran inside the flex window.
      final today = DateTime.now().effectiveDay;
      final state = WeeklyGridState(
        weekStart: startOfGridWeek(today),
        states: {
          today.subtract(const Duration(days: 1)).toDateKey(): {
            'habit_a': SquareState.complete,
            'habit_b': SquareState.complete,
            'habit_c': SquareState.complete,
            'habit_d': SquareState.complete,
          },
          today.toDateKey(): {
            'habit_a': SquareState.complete,
          },
        },
        notes: const {},
      );

      expect(
        state.todayCompletionRatio([
          'habit_a',
          'habit_b',
          'habit_c',
          'habit_d',
          'habit_e',
        ]),
        0.2,
      );
    });

    test('today completion ratio counts yellow partials as half work', () {
      // effectiveDay, not raw now: between midnight and the 10 AM flex cutoff
      // (DateTimeGameExt.effectiveDay) the calendar day is ahead of the
      // app's reward day, and a raw now() square would be graded as
      // tomorrow's (zero XP). Raw now() made this whole file fail when
      // the suite ran inside the flex window.
      final today = DateTime.now().effectiveDay;
      final state = WeeklyGridState(
        weekStart: startOfGridWeek(today),
        states: {
          today.toDateKey(): {
            'habit_a': SquareState.partial,
            'habit_b': SquareState.partial,
            'habit_c': SquareState.partial,
            'habit_d': SquareState.partial,
          },
        },
        notes: const {},
      );

      expect(
        state.todayCompletionRatio([
          'habit_a',
          'habit_b',
          'habit_c',
          'habit_d',
        ]),
        0.5,
      );
    });

    test('reward-eligible Grid summary points only count today', () async {
      // effectiveDay, not raw now: between midnight and the 10 AM flex cutoff
      // (DateTimeGameExt.effectiveDay) the calendar day is ahead of the
      // app's reward day, and a raw now() square would be graded as
      // tomorrow's (zero XP). Raw now() made this whole file fail when
      // the suite ran inside the flex window.
      final today = DateTime.now().effectiveDay;
      final grid = container.read(weeklyGridProvider.notifier);
      final state = container.read(weeklyGridProvider);
      final pastDay = state.days.lastWhere(
        (d) => d.startOfDay.isBefore(today.startOfDay),
        orElse: () => today.subtract(const Duration(days: 1)),
      );

      grid.setSquare('habit_a', pastDay, SquareState.complete);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        container.read(weeklyGridProvider).rewardEligiblePoints(['habit_a']),
        0,
      );

      grid.setSquare('habit_a', today, SquareState.partial);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // Between midnight and the 10 AM cutoff on a week-boundary night the
      // visible week has already rolled while the reward day (effective
      // today) still belongs to the PREVIOUS week — the summary getters
      // deliberately return 0 then (their `days.any(isSameDayAs(today))`
      // guard), because the visible board genuinely holds no reward-eligible
      // square. Assert whichever regime the wall clock has us in, so this
      // test is honest at 3 AM Saturday and at 3 PM Tuesday alike.
      final visibleDays = container.read(weeklyGridProvider).days;
      final todayVisible = visibleDays.any((d) => d.isSameDayAs(today));
      expect(
        container.read(weeklyGridProvider).rewardEligiblePoints(['habit_a']),
        todayVisible ? SquareState.partial.xpValue : 0,
      );
    });

    test('grid state cycles and persists square + note per habit per day',
        () async {
      // effectiveDay, not raw now: between midnight and the 10 AM flex cutoff
      // (DateTimeGameExt.effectiveDay) the calendar day is ahead of the
      // app's reward day, and a raw now() square would be graded as
      // tomorrow's (zero XP). Raw now() made this whole file fail when
      // the suite ran inside the flex window.
      final today = DateTime.now().effectiveDay;
      final grid = container.read(weeklyGridProvider.notifier);

      grid.cycleSquare('habit_a', today); // → complete, in ONE tap
      expect(
        container.read(weeklyGridProvider).squareFor('habit_a', today),
        SquareState.complete,
      );
      grid.cycleSquare('habit_a', today); // → back to empty
      expect(
        container.read(weeklyGridProvider).squareFor('habit_a', today),
        SquareState.none,
      );
      // And round again, so the cycle is a cycle and not a one-way door.
      grid.cycleSquare('habit_a', today);
      expect(
        container.read(weeklyGridProvider).squareFor('habit_a', today),
        SquareState.complete,
      );

      grid.setNote('habit_a', today, '  felt great  ');
      expect(
        container.read(weeklyGridProvider).noteFor('habit_a', today),
        'felt great',
      );
    });

    test(
        "Today's habit-list completion (DashboardNotifier.completeHabit) "
        'awards XP, gold, and a streak point when it is the only habit '
        'scheduled today', () async {
      final ok = await container.read(dashboardProvider.notifier).completeHabit(
            habitId: 'habit_today',
            xpReward: 20,
            goldReward: 8,
            frequencyTarget: 1,
            // habit_today is the only habit scheduled, so finishing it is
            // by definition 100% of today.
            allHabitsDoneAfter: true,
            category: 'custom',
            habitName: 'Test Habit',
          );

      final dash = container.read(dashboardProvider);
      expect(ok, isTrue); // single-tap habit → Grid should mirror it
      // Single-tap completions also count as a green square (same field
      // Grid itself writes), so this is also the very first one — it earns
      // +20 for the habit plus +25/+10 from the one-time "First Victory"
      // achievement, exactly like coloring the first Grid square does.
      expect(dash.cumulativeXp, 45);
      expect(dash.gold, 18);
      expect(dash.unlockedAchievements, contains('green_1'));
      expect(dash.streak, 1);
      expect(dash.streakEarnedToday, isTrue);
      expect(dash.completions['habit_today'], 1);
      expect(dash.categoryCompletions['custom'], 1);
    });

    test('completing the same habit twice today does not double-pay', () async {
      final notifier = container.read(dashboardProvider.notifier);
      await notifier.completeHabit(
        habitId: 'habit_once',
        xpReward: 20,
        goldReward: 8,
        frequencyTarget: 1,
        allHabitsDoneAfter: true,
        category: 'custom',
        habitName: 'Test Habit',
      );
      final afterFirst = container.read(dashboardProvider);
      final second = await notifier.completeHabit(
        habitId: 'habit_once',
        xpReward: 20,
        goldReward: 8,
        frequencyTarget: 1,
        allHabitsDoneAfter: true,
        category: 'custom',
        habitName: 'Test Habit',
      );

      expect(second, isFalse); // already-done guard, no new reward
      final dash = container.read(dashboardProvider);
      expect(dash.cumulativeXp, afterFirst.cumulativeXp);
      expect(dash.gold, afterFirst.gold);
    });

    test(
        'streak means 100%: the first of two habits does not bump the '
        "streak, only the second (last) one does — this is today's real "
        'behavior for the reported "3-day streak on day 1" bug (it used to '
        'bump on the very first completion, regardless of how many habits '
        'were still left)', () async {
      final notifier = container.read(dashboardProvider.notifier);
      await notifier.completeHabit(
        habitId: 'habit_1',
        xpReward: 10,
        goldReward: 5,
        frequencyTarget: 1,
        allHabitsDoneAfter: false, // habit_2 is still pending
        category: 'custom',
        habitName: 'Habit One',
      );
      final afterFirst = container.read(dashboardProvider);
      expect(afterFirst.streak, 0);
      expect(afterFirst.streakEarnedToday, isFalse);

      await notifier.completeHabit(
        habitId: 'habit_2',
        xpReward: 10,
        goldReward: 5,
        frequencyTarget: 1,
        allHabitsDoneAfter: true, // habit_1 already done — this is the last
        category: 'custom',
        habitName: 'Habit Two',
      );

      final dash = container.read(dashboardProvider);
      expect(dash.streak, 1);
      expect(dash.streakEarnedToday, isTrue);
      // Each completion still pays its own XP/gold, independent of streak.
      expect(dash.cumulativeXp, afterFirst.cumulativeXp + 10);
      expect(dash.gold, afterFirst.gold + 5);
    });

    test(
        'three habits completed the same day still produce exactly a '
        '1-day streak, never 3 (direct regression test for the reported '
        'bug)', () async {
      final notifier = container.read(dashboardProvider.notifier);
      final ids = ['h1', 'h2', 'h3'];
      for (var i = 0; i < ids.length; i++) {
        await notifier.completeHabit(
          habitId: ids[i],
          xpReward: 5,
          goldReward: 2,
          frequencyTarget: 1,
          allHabitsDoneAfter: i == ids.length - 1,
          category: 'custom',
          habitName: 'Habit ${i + 1}',
        );
      }
      expect(container.read(dashboardProvider).streak, 1);
    });

    test(
        'streak stays sticky at 1 even if a habit added after 100% is also '
        "completed — adding/finishing a new habit after today's streak "
        'point is earned must never re-trigger or double it', () async {
      final notifier = container.read(dashboardProvider.notifier);
      await notifier.completeHabit(
        habitId: 'h1',
        xpReward: 5,
        goldReward: 2,
        frequencyTarget: 1,
        allHabitsDoneAfter: true,
        category: 'custom',
        habitName: 'Habit One',
      );
      expect(container.read(dashboardProvider).streak, 1);

      // A brand-new habit added after 100% and then completed — the caller
      // may honestly (re)report allHabitsDoneAfter: true (it again is 100%
      // of the now-larger list), but streakEarnedToday's stickiness must
      // stop this from paying out a second streak point today.
      await notifier.completeHabit(
        habitId: 'h2',
        xpReward: 5,
        goldReward: 2,
        frequencyTarget: 1,
        allHabitsDoneAfter: true,
        category: 'custom',
        habitName: 'Habit Two (added after 100%)',
      );
      expect(container.read(dashboardProvider).streak, 1);
    });
  });

  group('streak decay respects kStreakDayCompletionThreshold (guest path)', () {
    // A separate group from the one above: those tests seed a fresh
    // container in setUp before any test body runs, which doesn't allow
    // seeding a fake "yesterday" into storage first. These tests need to
    // write guest state, *then* create the container so it loads that
    // seeded state — same real Hive-backed LocalStoreService, just a
    // different order of operations.
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('streak_decay_test_');
      Hive.init(tmp.path);
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await tmp.delete(recursive: true);
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
      expect(container.read(dashboardProvider).isLoading, isFalse);
      return container;
    }

    test(
        'a non-qualifying completion does not persist lastActiveDate — the '
        'actual bug (any activity kept a streak alive indefinitely, '
        "regardless of whether a day ever hit kStreakDayCompletionThreshold)",
        () async {
      final container = await freshContainer();
      addTearDown(container.dispose);
      final notifier = container.read(dashboardProvider.notifier);

      await notifier.completeHabit(
        habitId: 'a',
        xpReward: 5,
        goldReward: 2,
        frequencyTarget: 1,
        allHabitsDoneAfter: false, // today does not qualify
        category: 'custom',
        habitName: 'Habit A',
      );
      var saved = await LocalStoreService.getSettingsMap(
        LocalStoreService.guestDashboardKey,
      );
      expect(
        saved['lastActiveDate'],
        isNull,
        reason: 'a non-qualifying completion must not refresh lastActiveDate',
      );

      await notifier.completeHabit(
        habitId: 'b',
        xpReward: 5,
        goldReward: 2,
        frequencyTarget: 1,
        allHabitsDoneAfter: true, // today now qualifies
        category: 'custom',
        habitName: 'Habit B',
      );
      saved = await LocalStoreService.getSettingsMap(
        LocalStoreService.guestDashboardKey,
      );
      expect(
        saved['lastActiveDate'],
        isNotNull,
        reason: 'a genuinely qualifying day must persist lastActiveDate',
      );
    });

    test(
        'a 3-day-old lastActiveDate (2+ non-qualifying days) resets the '
        'streak, even though "some" activity may have happened in between',
        () async {
      final today = DateTime.now().effectiveDay;
      await LocalStoreService.putSettingsMap(
        LocalStoreService.guestDashboardKey,
        {
          'currentStreak': 5,
          'streakFreezes': 1,
          'lastActiveDate':
              today.subtract(const Duration(days: 3)).toIso8601String(),
        },
      );

      final container = await freshContainer();
      addTearDown(container.dispose);

      // The loader records the gap and leaves it unjudged: deciding whether
      // those days were MISSED or merely days with nothing scheduled needs
      // the habit list, which the loader does not have. See
      // DashboardState.pendingStreakGapFrom.
      expect(
        container.read(dashboardProvider).pendingStreakGapFrom,
        isNotNull,
        reason: 'the gap is spotted at load',
      );
      expect(container.read(dashboardProvider).streak, 5,
          reason: 'and nothing is destroyed before it is judged');

      // Judged against an every-day habit: all three days genuinely owed
      // something, so the streak is gone.
      await container
          .read(dashboardProvider.notifier)
          .resolveStreakGap([_everyDayHabit()]);

      final dash = container.read(dashboardProvider);
      expect(dash.streak, 0);
      expect(dash.previousStreak, 5);
      expect(dash.showComebackBonus, isTrue);
    });

    test(
        'the SAME 3-day gap costs nothing when every day in it was a rest '
        'day', () async {
      // The bug this whole deferral exists for. lastActiveDate cannot
      // advance across a day with nothing scheduled, so a Sat/Mon/Wed
      // trainee accumulated calendar gaps they had never actually missed.
      final today = DateTime.now().effectiveDay;
      await LocalStoreService.putSettingsMap(
        LocalStoreService.guestDashboardKey,
        {
          'currentStreak': 5,
          'streakFreezes': 1,
          'lastActiveDate':
              today.subtract(const Duration(days: 3)).toIso8601String(),
        },
      );

      final container = await freshContainer();
      addTearDown(container.dispose);

      // A habit scheduled only on the day the gap STARTED and today - so
      // every day strictly in between asked for nothing at all.
      final restOnly = IslamicHabitTemplate(
        id: 'daily-habit',
        name: 'daily',
        description: '',
        category: HabitCategory.custom,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
        hasTimer: false,
        xpReward: 10,
        goldReward: 5,
        scheduledWeekdays: [
          today.subtract(const Duration(days: 3)).weekday,
          today.weekday,
        ],
      );
      await container
          .read(dashboardProvider.notifier)
          .resolveStreakGap([restOnly]);

      final dash = container.read(dashboardProvider);
      expect(dash.streak, 5, reason: 'nothing was missed, so nothing is lost');
      expect(dash.streakFreezes, 1, reason: 'and no freeze is spent');
      expect(dash.pendingStreakGapFrom, isNull, reason: 'question settled');
    });

    test(
        'a 2-day-old lastActiveDate (exactly one non-qualifying day) auto-'
        'consumes a freeze instead of resetting', () async {
      final today = DateTime.now().effectiveDay;
      await LocalStoreService.putSettingsMap(
        LocalStoreService.guestDashboardKey,
        {
          'currentStreak': 5,
          'streakFreezes': 1,
          'lastActiveDate':
              today.subtract(const Duration(days: 2)).toIso8601String(),
        },
      );

      final container = await freshContainer();
      addTearDown(container.dispose);
      await container
          .read(dashboardProvider.notifier)
          .resolveStreakGap([_everyDayHabit()]);

      final dash = container.read(dashboardProvider);
      expect(dash.streak, 5);
      expect(dash.streakFreezes, 0);
      expect(dash.didUseStreakFreeze, isTrue);
      expect(dash.previousStreak, 0);
    });
  });

  group('willCompleteAllHabitsToday', () {
    test('only true once every scheduled habit is done', () {
      const todayHabits = [
        (id: 'a', frequencyTarget: 1),
        (id: 'b', frequencyTarget: 1),
      ];

      // Nothing done yet — completing 'a' still leaves 'b' pending.
      expect(
        willCompleteAllHabitsToday(
          state: DashboardState.initial(),
          todayHabits: todayHabits,
          habitId: 'a',
          frequencyTarget: 1,
        ),
        isFalse,
      );

      // 'a' already done — completing 'b' is the last piece.
      final aDone = DashboardState.initial().copyWith(completions: {'a': 1});
      expect(
        willCompleteAllHabitsToday(
          state: aDone,
          todayHabits: todayHabits,
          habitId: 'b',
          frequencyTarget: 1,
        ),
        isTrue,
      );
    });

    test('a multi-tap habit only counts done on its final tap', () {
      const todayHabits = [(id: 'weekly', frequencyTarget: 3)];
      final twoOfThree =
          DashboardState.initial().copyWith(completions: {'weekly': 2});

      expect(
        willCompleteAllHabitsToday(
          state: DashboardState.initial(),
          todayHabits: todayHabits,
          habitId: 'weekly',
          frequencyTarget: 3,
        ),
        isFalse, // 1st of 3 taps
      );
      expect(
        willCompleteAllHabitsToday(
          state: twoOfThree,
          todayHabits: todayHabits,
          habitId: 'weekly',
          frequencyTarget: 3,
        ),
        isTrue, // 3rd of 3 taps
      );
    });

    test('an empty habit list is never "100%"', () {
      expect(
        willCompleteAllHabitsToday(
          state: DashboardState.initial(),
          todayHabits: const <({String id, int frequencyTarget})>[],
          habitId: 'a',
          frequencyTarget: 1,
        ),
        isFalse,
      );
    });

    // kStreakDayCompletionThreshold (0.8) coverage — the tests above only
    // ever exercise 1- or 2-habit lists, where 80% and 100% happen to
    // demand the exact same thing (you can't partially clear 80% of a
    // single item). These use a 5-habit list specifically so the two
    // thresholds actually diverge.
    group('kStreakDayCompletionThreshold (80%) leniency', () {
      const fiveHabits = [
        (id: 'a', frequencyTarget: 1),
        (id: 'b', frequencyTarget: 1),
        (id: 'c', frequencyTarget: 1),
        (id: 'd', frequencyTarget: 1),
        (id: 'e', frequencyTarget: 1),
      ];

      test(
          '4 of 5 done (80% exactly) now qualifies — previously required '
          'all 5', () {
        final threeDone = DashboardState.initial()
            .copyWith(completions: {'a': 1, 'b': 1, 'c': 1});
        expect(
          willCompleteAllHabitsToday(
            state: threeDone,
            todayHabits: fiveHabits,
            habitId: 'd', // completing this makes it 4 of 5
            frequencyTarget: 1,
          ),
          isTrue,
        );
      });

      test('3 of 5 done (60%) still does not qualify', () {
        final twoDone =
            DashboardState.initial().copyWith(completions: {'a': 1, 'b': 1});
        expect(
          willCompleteAllHabitsToday(
            state: twoDone,
            todayHabits: fiveHabits,
            habitId: 'c', // completing this makes it 3 of 5
            frequencyTarget: 1,
          ),
          isFalse,
        );
      });

      test('completing the 5th (100%) still qualifies, same as before', () {
        final fourDone = DashboardState.initial()
            .copyWith(completions: {'a': 1, 'b': 1, 'c': 1, 'd': 1});
        expect(
          willCompleteAllHabitsToday(
            state: fourDone,
            todayHabits: fiveHabits,
            habitId: 'e',
            frequencyTarget: 1,
          ),
          isTrue,
        );
      });
    });
  });
}
