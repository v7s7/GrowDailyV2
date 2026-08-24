// Correcting a green square to red has to un-count the habit, not just
// recolour it.
//
// The palette in the cell editor calls uncompleteHabit and then
// setSquareStateOnly. Both land in the SAME stored daily map, and each one is
// a read, modify, write of the whole map: uncompleteHabit clears
// habitCompletions[id], setSquareStateOnly writes squareStates[id]. The call
// was not awaited, so the square write read the map before the uncomplete had
// written it back, saved its own change on top of a stale copy, and put the
// completion count back to 1.
//
// What that looked like on a device: correct a green square to red, the
// square goes red and stays red, and the habit still counts as done for XP,
// for the streak, and in every report that reads habitCompletions. The square
// said one thing and the numbers said another, with no way for a person to
// tell which one the app believed.
//
// This asserts BOTH halves of the daily map, because asserting only the
// square colour is exactly what let this through: the colour was always
// right.
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
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';

void main() {
  late Directory tmp;
  late ProviderContainer container;

  setUp(() async {
    // Without this the completion path reaches into
    // flutter_local_notifications, which has no platform behind it in a test
    // and throws a LateInitializationError from inside an unawaited future.
    NotificationService.instance.celebrationsEnabled = false;
    tmp = await Directory.systemTemp.createTemp('palette_race_');
    Hive.init(tmp.path);
    container = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
    ]);
    await container.read(authStateProvider.future);
    container.read(weeklyGridProvider);
    container.read(dashboardProvider);
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while ((container.read(weeklyGridProvider).isLoading ||
            container.read(dashboardProvider).isLoading) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  });

  tearDown(() async {
    container.dispose();
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  test('correcting a locked green square un-counts the completion', () async {
    final today = DateTime.now().effectiveDay;
    await container.read(dashboardProvider.notifier).completeHabit(
          habitId: 'h1',
          xpReward: 10,
          goldReward: 5,
          frequencyTarget: 1,
          allHabitsDoneAfter: true,
        );
    container
        .read(weeklyGridProvider.notifier)
        .markCompleteFromHabit('h1', today);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    var stored = await LocalStoreService.getDailyMap(today.toDateKey());
    // Reproduces grid_screen_cell_editor.dart:399 exactly: uncompleteHabit
    // is NOT awaited before the square write.
    container.read(dashboardProvider.notifier).uncompleteHabit(
          habitId: 'h1',
          xpReward: 10,
          goldReward: 5,
        );
    container
        .read(weeklyGridProvider.notifier)
        .setSquareStateOnly('h1', today, SquareState.failed);
    await Future<void>.delayed(const Duration(milliseconds: 400));

    stored = await LocalStoreService.getDailyMap(today.toDateKey());
    expect((stored['squareStates'] as Map)['h1'], 'failed',
        reason: 'the colour was never the broken half');
    expect((stored['habitCompletions'] as Map?)?['h1'], anyOf(isNull, 0),
        reason: 'a square corrected to red still counted as a completion, so '
            'XP, the streak and every report kept believing the habit was '
            'done');
  });
}
