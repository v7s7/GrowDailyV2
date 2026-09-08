// Clearing a note has to DELETE its key, not blank it.
//
// It used to write '', so every day anyone ever cleared a note on kept a
// permanent {habitId: ""} entry in squareNotes. That was harmless while
// nothing asked the question, and stopped being harmless the moment two
// surfaces started asking it: the Grid square's corner mark and the day-level
// note index behind the heatmap's. Anything counting KEY PRESENCE rather than
// the value would read every one of those days as written on, forever, and
// send the user to a sheet with nothing in it.
//
// Deliberately a plain async test rather than testWidgets, and in its own
// file: this is about what actually reaches the store, real Hive writes
// inside a fake-async zone hang silently, and two Hive harnesses in one
// process fight over the same open boxes. Same shape as
// palette_correction_race_test.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/grid/notifiers/note_index_notifier.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';

import '../../helpers/wait_until.dart';

void main() {
  late Directory tmp;
  late ProviderContainer container;

  setUp(() async {
    // The completion path reaches into flutter_local_notifications, which has
    // no platform behind it in a test.
    NotificationService.instance.celebrationsEnabled = false;
    tmp = await Directory.systemTemp.createTemp('note_tombstone_');
    Hive.init(tmp.path);
    container = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
    ]);
    await container.read(authStateProvider.future);
    container.read(weeklyGridProvider);
    await waitUntil(
      () => !container.read(weeklyGridProvider).isLoading,
      describe: 'the grid to finish its initial load',
    );
  });

  tearDown(() async {
    container.dispose();
    // Settle before the directory goes: an unawaited day write would
    // otherwise land on a deleted box.
    await LocalStoreService.settleDailyWrites();
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  test('no tombstone survives a cleared note', () async {
    final today = DateTime.now().effectiveDay;
    final key = today.toDateKey();
    final grid = container.read(weeklyGridProvider.notifier);

    await grid.setNote('inbox_zero', today, 'something');
    await LocalStoreService.settleDailyWrites();
    var stored = await LocalStoreService.getDailyMap(key);
    expect((stored['squareNotes'] as Map?)?['inbox_zero'], 'something');
    // The guest index folds straight off the store, so this is literally the
    // fact the heatmap's corner mark reads.
    expect(noteMonthIndexFrom({key: stored})[monthKeyOf(key)], {today.day});

    await grid.setNote('inbox_zero', today, '');
    await LocalStoreService.settleDailyWrites();
    stored = await LocalStoreService.getDailyMap(key);
    expect((stored['squareNotes'] as Map?)?.containsKey('inbox_zero') ?? false,
        isFalse,
        reason: 'the habit id is still in squareNotes, so this day would keep '
            'reading as written on forever');
    expect(noteMonthIndexFrom({key: stored}), isEmpty);
  });

  test('a day keeps its mark while another habit still has a note', () async {
    // The reason dayStillHasWriting has to be exact rather than a guess:
    // clearing one of two notes must not unmark the day.
    final today = DateTime.now().effectiveDay;
    final key = today.toDateKey();
    final grid = container.read(weeklyGridProvider.notifier);

    await grid.setNote('inbox_zero', today, 'first');
    await grid.setNote('deep_work', today, 'second');
    await grid.setNote('inbox_zero', today, '');
    await LocalStoreService.settleDailyWrites();

    final stored = await LocalStoreService.getDailyMap(key);
    final row = (stored['squareNotes'] as Map?)?.cast<String, dynamic>();
    expect(row?.containsKey('inbox_zero') ?? false, isFalse);
    expect(row?['deep_work'], 'second');
    expect(noteMonthIndexFrom({key: stored})[monthKeyOf(key)], {today.day});
  });

  test('a whitespace-only note is not writing', () async {
    final today = DateTime.now().effectiveDay;
    final key = today.toDateKey();
    final grid = container.read(weeklyGridProvider.notifier);

    await grid.setNote('inbox_zero', today, '   \n  ');
    await LocalStoreService.settleDailyWrites();

    final stored = await LocalStoreService.getDailyMap(key);
    expect((stored['squareNotes'] as Map?)?.containsKey('inbox_zero') ?? false,
        isFalse,
        reason: 'setNote trims, so this stores nothing; a key here would mark '
            'the day and open an empty editor');
    expect(noteMonthIndexFrom({key: stored}), isEmpty);
  });
}
