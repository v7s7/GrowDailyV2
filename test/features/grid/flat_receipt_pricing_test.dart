// A square the flat rate never paid must cost nothing to change.
//
// WeeklyGridNotifier.setSquare priced every change from the two COLOURS:
// jumping from yellow to empty was "5 minus 0", so it took five XP back.
// That is only right for a yellow square setSquare painted itself, which is
// the one path that pays the flat rate. Two other writers leave a جزئي on the
// board without paying anything for it:
//
//  - the steps link, at half the goal (step_auto_complete: "a mark, not a
//    reward: the day is paid only when the goal is reached");
//  - the palette's مكتمل to جزئي correction on a done square, which takes
//    the completion back through uncompleteHabit and paints the yellow with
//    setSquareStateOnly.
//
// Tapping either one empty, or picking فشل or تخطّي on it, docked five XP that
// had never been paid, and picking جزئي again wrote a receipt of five that had
// never been paid either, which the canonical take-over later refunded as a
// deduction. The receipt (WeeklyGridState.flatPaid) already knew the truth;
// the price is read from it now.
//
// A counted habit's mid-count yellow had the same hole and was closed by
// locking the palette (paletteLockedFor). A habit done once a day cannot be
// locked that way, since its yellow is never a completion and مكتمل on it has
// to complete the habit, so the price itself had to change.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/square_audit.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';
import 'package:hive/hive.dart';

import '../../helpers/never_bonus_random.dart';
import '../../helpers/wait_until.dart';

void main() {
  late Directory tmp;
  late ProviderContainer container;

  setUp(() async {
    NotificationService.instance.celebrationsEnabled = false;
    tmp = await Directory.systemTemp.createTemp('flat_receipt_');
    Hive.init(tmp.path);
    container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        dashboardProvider.overrideWith(
          (ref) => DashboardNotifier(null, random: NeverBonusRandom()),
        ),
      ],
    );
    await container.read(authStateProvider.future);
    container.read(weeklyGridProvider);
    container.read(dashboardProvider);
    // Both loads first: a square set before the week's first read lands is
    // replaced by that read, receipt and all.
    await waitUntil(
      () =>
          !container.read(weeklyGridProvider).isLoading &&
          !container.read(dashboardProvider).isLoading,
      describe: 'the grid and dashboard to finish their initial load',
    );
    await container.read(dashboardProvider.notifier).ready;
  });

  tearDown(() async {
    container.dispose();
    await LocalStoreService.settleDailyWrites();
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  DateTime today() => DateTime.now().effectiveDay;
  int xp() => container.read(dashboardProvider).cumulativeXp;
  int receipt(String habitId) =>
      container.read(weeklyGridProvider).flatPaidFor(habitId, today());
  WeeklyGridNotifier grid() => container.read(weeklyGridProvider.notifier);
  DashboardNotifier dash() => container.read(dashboardProvider.notifier);

  /// What step_auto_complete does at half the goal.
  Future<void> stepsHalfway(String habitId) => grid().setSquareStateOnlyAsync(
        habitId,
        today(),
        SquareState.partial,
        source: kSquareSourceSteps,
      );

  /// What the palette does when مكتمل on a done square is corrected to جزئي
  /// (grid_screen_cell_editor's locked branch): the completion goes back
  /// through uncompleteHabit, then the yellow is painted without a price.
  Future<void> completeThenDowngrade(String habitId) async {
    await dash().completeHabit(
      habitId: habitId,
      xpReward: 10,
      goldReward: 5,
      frequencyTarget: 1,
      allHabitsDoneAfter: false,
      category: 'custom',
    );
    grid().markCompleteFromHabit(habitId, today());
    await dash().uncompleteHabit(
      habitId: habitId,
      xpReward: 10,
      goldReward: 5,
      clearWholeDay: true,
      category: 'custom',
    );
    grid().setSquareStateOnly(
      habitId,
      today(),
      SquareState.partial,
      source: kSquareSourcePalette,
    );
  }

  group('a جزئي nothing paid for', () {
    // XP in the account first, or a wrong debit has nothing to take: a fresh
    // guest sits at zero, the floor swallows the five, and the test passes
    // for the wrong reason. The first completion also collects green_1's
    // one-time medal here, so it is not part of any figure measured below.
    setUp(() async {
      await dash().completeHabit(
        habitId: 'warm-up',
        xpReward: 1,
        goldReward: 0,
        frequencyTarget: 1,
        allHabitsDoneAfter: false,
        category: 'custom',
      );
      expect(xp(), greaterThan(5));
    });

    test('the steps link\'s half-goal square costs nothing to tap empty',
        () async {
      await stepsHalfway('walk');
      expect(receipt('walk'), 0, reason: 'the steps link pays nothing here');
      final before = xp();

      // The square's own tap: جزئي cycles to empty (SquareState.next).
      grid().cycleSquare('walk', today());

      expect(grid().state.squareFor('walk', today()), SquareState.none);
      expect(
        xp(),
        before,
        reason: 'five XP were taken back that the square was never paid',
      );
    });

    test('nor to mark فشل or تخطّي from the palette', () async {
      await stepsHalfway('walk');
      await stepsHalfway('run');
      final before = xp();

      grid().setSquare(
        'walk',
        today(),
        SquareState.failed,
        source: kSquareSourcePalette,
      );
      grid().setSquare(
        'run',
        today(),
        SquareState.skipped,
        source: kSquareSourcePalette,
      );

      expect(xp(), before);
      expect(receipt('walk'), 0);
      expect(receipt('run'), 0);
    });

    test('the palette\'s مكتمل to جزئي correction leaves nothing to take back',
        () async {
      final start = xp();

      await completeThenDowngrade('h');
      expect(
        xp(),
        start,
        reason: 'the completion was taken back whole, and the yellow it '
            'left was painted without a price',
      );

      grid().setSquare(
        'h',
        today(),
        SquareState.failed,
        source: kSquareSourcePalette,
      );
      expect(
        xp(),
        start,
        reason: 'the correction to فشل docked five XP nobody was paid',
      );
    });

    test('picking جزئي again pays nothing and leaves no receipt', () async {
      await stepsHalfway('walk');
      final before = xp();

      grid().setSquare(
        'walk',
        today(),
        SquareState.partial,
        source: kSquareSourcePalette,
      );

      expect(xp(), before, reason: 'the same colour again is not a new mark');
      expect(
        receipt('walk'),
        0,
        reason: 'a receipt of five for a square paid nothing is a debt the '
            'next take-over collects',
      );

      // The walk reaches its goal: the canonical completion, then the square
      // mirrored green, exactly as step_auto_complete runs it.
      await dash().completeHabit(
        habitId: 'walk',
        xpReward: 10,
        goldReward: 5,
        frequencyTarget: 1,
        allHabitsDoneAfter: false,
        category: 'custom',
      );
      final paidForWalk = xp();
      grid().markCompleteFromHabit('walk', today(), source: kSquareSourceSteps);

      expect(
        xp(),
        paidForWalk,
        reason: 'the take-over refunded a flat five it never paid',
      );
    });
  });

  group('a جزئي the flat rate did pay', () {
    // The other half of the rule, unchanged: a square setSquare coloured
    // was paid its flat rate and gives exactly that back.
    test('pays five on the way in and gives five back on the way out',
        () async {
      final before = xp();

      grid().setSquare(
        'h',
        today(),
        SquareState.partial,
        source: kSquareSourcePalette,
      );
      expect(xp(), before + 5);
      expect(receipt('h'), 5);

      grid().setSquare(
        'h',
        today(),
        SquareState.failed,
        source: kSquareSourcePalette,
      );
      expect(xp(), before);
      expect(receipt('h'), 0);
    });

    test('and picking it again leaves the receipt where it was', () async {
      grid().setSquare(
        'h',
        today(),
        SquareState.partial,
        source: kSquareSourcePalette,
      );
      final before = xp();

      grid().setSquare(
        'h',
        today(),
        SquareState.partial,
        source: kSquareSourcePalette,
      );

      expect(xp(), before);
      expect(receipt('h'), 5);
    });

    test('a جزئي the daily ceiling clamped gives back only what it paid',
        () async {
      // Two XP of room left today. Every flat square asks against the floor
      // ceiling (it passes no roster), which a bonus spends like anything
      // else repeatable.
      final room = dailyXpCapFor(0) -
          container.read(dashboardProvider).earnedXpOn(today().toDateKey());
      await dash().awardBonus(xp: room - 2, gold: 0);
      final before = xp();

      grid().setSquare(
        'h',
        today(),
        SquareState.partial,
        source: kSquareSourcePalette,
      );
      expect(xp(), before + 2, reason: 'the ceiling let two of the five in');
      expect(
        receipt('h'),
        2,
        reason: 'the receipt says what was paid, not what the colour costs',
      );

      grid().setSquare(
        'h',
        today(),
        SquareState.none,
        source: kSquareSourcePalette,
      );
      expect(
        xp(),
        before,
        reason: 'clearing it took back five for a square paid two',
      );
      expect(
        container.read(dashboardProvider).earnedXpOn(today().toDateKey()),
        dailyXpCapFor(0) - 2,
        reason: 'and freed three XP of room the square never used',
      );
    });
  });
}
