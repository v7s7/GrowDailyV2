// autoCleanQuitDay says whether it marked anything, and main.dart re-grades
// the rooms only when it did.
//
// It used to re-grade every room on every launch that had an eligible quit
// habit, whether or not a square changed: about 150 Firestore reads for a
// member of three rooms, nearly always to find nothing new (measured
// 2026-09-22). Guest storage, so the real write path runs.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';

import '../../helpers/wait_until.dart';

void main() {
  late Directory tmp;
  late ProviderContainer container;
  final yesterday =
      DateTime.now().effectiveDay.subtract(const Duration(days: 1));

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('quit_auto_clean_marks_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings');
    await Hive.openBox<dynamic>('box_daily_logs');
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
    await LocalStoreService.settleDailyWrites();
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  Future<Map<String, dynamic>> storedSquares() async {
    await LocalStoreService.settleDailyWrites();
    final day = await LocalStoreService.getDailyMap(yesterday.toDateKey());
    return Map<String, dynamic>.from((day['squareStates'] as Map?) ?? {});
  }

  WeeklyGridNotifier grid() => container.read(weeklyGridProvider.notifier);

  test('an untouched day is marked, and says so', () async {
    expect(await grid().autoCleanQuitDay(['quitA'], yesterday), isTrue);
    expect((await storedSquares())['quitA'], SquareState.complete.toJson());
  });

  test('a day already marked has nothing new: no rooms to re-grade',
      () async {
    await grid().autoCleanQuitDay(['quitA'], yesterday);
    expect(await grid().autoCleanQuitDay(['quitA'], yesterday), isFalse);
  });

  test('a slip the person recorded is never overwritten, and marks nothing',
      () async {
    await grid().setSquareStateOnlyAsync('quitA', yesterday, SquareState.failed);
    expect(await grid().autoCleanQuitDay(['quitA'], yesterday), isFalse);
    expect((await storedSquares())['quitA'], SquareState.failed.toJson());
  });

  test('no eligible habit, nothing to do', () async {
    expect(await grid().autoCleanQuitDay(const [], yesterday), isFalse);
  });
}
