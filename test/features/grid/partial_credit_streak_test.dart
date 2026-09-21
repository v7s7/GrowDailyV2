// A جزئي mark, not just a completion, can be the tap that crosses the
// streak threshold — and until now, only a completion ever re-asked the
// question.
//
// willCompleteAllHabitsToday already credits an existing جزئي at 0.5 when a
// LATER completion finishes the day (mark one habit جزئي, then finish the
// rest, and the day correctly streaks — see
// streak_partial_credit_test.dart). What it never covered is the day that
// finishes the other way around: finish every other habit first, then mark
// the last one جزئي. That tap crosses the same threshold, but setSquare
// deliberately never calls completeHabit for a جزئي, so nothing ever
// re-checked it. Reported live (Aziz, 2026-09-21): "i am already above 80%
// with the 0.5 habit."
//
// earnStreakFromPartialCredit closes that gap. This exercises it directly
// against the notifiers, the same choice palette_correction_race_test.dart
// makes and for the same reason: completeHabit's full reward pipeline pops
// a celebration overlay that a widget test cannot cleanly pump past, and
// none of that is what this file is testing. willCrossStreakThresholdOnPartial
// itself (the predicate that decides WHEN to call this) needs a WidgetRef
// and is left to manual review — same as its sibling willCompleteAllSquaresOn,
// which has no direct test in this repo either; the arithmetic it shares
// with willCompleteAllHabitsToday is already pinned in
// streak_partial_credit_test.dart.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart'
    show habitListProvider, habitsStillLoadingProvider;

import '../../helpers/wait_until.dart';

void main() {
  late Directory tmp;
  late ProviderContainer container;

  // Four genuinely every-day habits (no weekday restriction), so this test
  // cannot go flaky depending on which day of the week it runs.
  const habitA = 'quran_daily_page';
  const habitB = 'quran_memorization';
  const habitC = 'morning_athkar';
  const habitD = 'evening_athkar';

  setUp(() async {
    // Without this, completeHabit's local-notification path reaches into
    // flutter_local_notifications, which has no platform behind it in a
    // test — see palette_correction_race_test.dart's identical setup.
    NotificationService.instance.celebrationsEnabled = false;
    tmp = await Directory.systemTemp.createTemp('partial_streak_');
    Hive.init(tmp.path);
    final settings = await Hive.openBox<dynamic>('box_settings');
    await Hive.openBox<dynamic>('box_daily_logs');
    await Hive.openBox<dynamic>('box_habits');
    await settings.put(
        'active_catalog_ids_v1', const [habitA, habitB, habitC, habitD]);
    container = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
    ]);
    await container.read(authStateProvider.future);
    container.read(weeklyGridProvider);
    container.read(dashboardProvider);
    container.read(habitsStillLoadingProvider);
    await waitUntil(
      () =>
          !container.read(weeklyGridProvider).isLoading &&
          !container.read(dashboardProvider).isLoading &&
          !container.read(habitsStillLoadingProvider),
      describe: 'the grid, dashboard and habit list to finish their '
          'initial load',
    );
  });

  tearDown(() async {
    container.dispose();
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  IslamicHabitTemplate habitTemplate(String id) =>
      container.read(habitListProvider).firstWhere((h) => h.id == id);

  /// The palette's own «مكتمل» pick, reproduced exactly: completeHabit's
  /// reward, then setSquareStateOnly's visual mirror — see
  /// grid_screen_cell_editor.dart's _handlePaletteTap.
  Future<void> completeViaPalette(String id, {required bool allDone}) async {
    final habit = habitTemplate(id);
    final today = DateTime.now().effectiveDay;
    await container.read(dashboardProvider.notifier).completeHabit(
          habitId: id,
          xpReward: habit.xpReward,
          goldReward: habit.goldReward,
          frequencyTarget: 1,
          allHabitsDoneAfter: allDone,
        );
    container
        .read(weeklyGridProvider.notifier)
        .setSquareStateOnly(id, today, SquareState.complete);
  }

  /// The palette's own «جزئي» pick's visual half — setSquare, which pays
  /// the flat rate and, unlike setSquareStateOnly, never touches the streak
  /// on its own (see its doc comment). The threshold check itself
  /// (willCrossStreakThresholdOnPartial) is left out here on purpose — see
  /// the file header — so callers pass whether this tap is the one that
  /// crosses it, exactly as they would have already worked out by hand.
  void markPartialViaPalette(String id) {
    final today = DateTime.now().effectiveDay;
    container
        .read(weeklyGridProvider.notifier)
        .setSquare(id, today, SquareState.partial);
  }

  test(
    '3 of 4 done, then a جزئي mark that crosses 80% earns the streak',
    () async {
      await completeViaPalette(habitA, allDone: false); // 1/4 = 25%
      await completeViaPalette(habitB, allDone: false); // 2/4 = 50%
      await completeViaPalette(habitC, allDone: false); // 3/4 = 75%
      expect(container.read(dashboardProvider).streakEarnedToday, isFalse,
          reason: '3 of 4 is 75%, below the threshold');
      expect(container.read(dashboardProvider).streak, 0);

      // The deciding tap: not a completion, a جزئي. 3 full + 1 half of 4
      // is 3.5 / 4 = 87.5%, which crosses kStreakDayCompletionThreshold —
      // exactly what willCrossStreakThresholdOnPartial would have answered
      // true for here, which is why the real palette calls this next.
      markPartialViaPalette(habitD);
      await container
          .read(dashboardProvider.notifier)
          .earnStreakFromPartialCredit();

      expect(container.read(dashboardProvider).streakEarnedToday, isTrue,
          reason: 'a جزئي mark should be able to finish the day exactly '
              'like a completion can, once real completions already carry '
              'most of it');
      expect(container.read(dashboardProvider).streak, 1);
    },
  );

  test(
    'once already earned by completions, a later جزئي does not re-fire it',
    () async {
      await completeViaPalette(habitA, allDone: false); // 1/4 = 25%
      await completeViaPalette(habitB, allDone: false); // 2/4 = 50%
      await completeViaPalette(habitC, allDone: false); // 3/4 = 75%
      // The day earns the ordinary way, with nothing جزئي anywhere yet.
      await completeViaPalette(habitD, allDone: true); // 4/4 = 100%
      expect(container.read(dashboardProvider).streakEarnedToday, isTrue);
      expect(container.read(dashboardProvider).streak, 1);

      // Correcting a completed square back to جزئي is a locked-square
      // correction in the real palette (it goes through uncompleteHabit,
      // never through setSquare), so it can never reach earnStreakFrom
      // PartialCredit at all in practice. What this pins is that method's
      // own guard directly: called again on an already-earned day, it must
      // be a no-op, or every جزئي mark on an already-perfect day would bump
      // the streak a second time.
      await container
          .read(dashboardProvider.notifier)
          .earnStreakFromPartialCredit();

      expect(container.read(dashboardProvider).streak, 1,
          reason: 'earnStreakFromPartialCredit must refuse once '
              'streakEarnedToday is already true');
    },
  );

  test(
    'جزئي marks alone can never cross the threshold, however many there are',
    () async {
      // Every habit جزئي, nothing ever completed: the highest a day with no
      // green or blue square anywhere can average is 0.5, and the
      // threshold is 0.8 — willCrossStreakThresholdOnPartial's own doc
      // comment leans on exactly this, so it never even calls
      // earnStreakFromPartialCredit for a day shaped like this one. This
      // test pins the arithmetic that guarantee rests on, from the
      // notifier's own state rather than the predicate.
      for (final id in [habitA, habitB, habitC, habitD]) {
        markPartialViaPalette(id);
      }

      expect(container.read(dashboardProvider).streakEarnedToday, isFalse,
          reason: 'nothing here ever called completeHabit or '
              'earnStreakFromPartialCredit, so nothing should have changed '
              'the streak at all');
      expect(container.read(dashboardProvider).streak, 0);
    },
  );
}
