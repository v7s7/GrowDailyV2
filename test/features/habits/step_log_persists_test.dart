import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/features/habits/step_auto_complete.dart';
import 'package:hive/hive.dart';

/// The day's step count, on disk.
///
/// "It should count each day at its 24h, when the day finish it saves the
/// data, and start count to the next day, it should not go to 0, even if its
/// 3921 steps and the goal is 6000" (Aziz, 2026-09-10). Before this the
/// count lived only in a Riverpod map, which made HealthKit the sole record:
/// the catch-up reaches seven days, a revoked permission answers a
/// well-formed zero for all of them, and every launch paid to re-learn what
/// the app already knew.
///
/// This exercises the real box, not a fake, because the thing being claimed
/// is that the number survives the process.
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('step_log_test_');
    Hive.init(tmp.path);
    // The same three-box fixture the rest of the suite opens: opening a
    // subset races the temp dir teardown.
    await Hive.openBox<dynamic>('box_settings');
    await Hive.openBox<dynamic>('box_daily_logs');
    await Hive.openBox<dynamic>('box_habits');
  });

  tearDown(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  test('a part-done walk survives the box it was written to', () async {
    // Below half a 6,000 goal, so the ladder writes no square at all: this
    // number is the ONLY record that the day was walked.
    await LocalStoreService.putSettingsMap(
      LocalStoreService.stepsByDayKey,
      prunedStepsLog(
        const {'2026-09-09': 2400},
        DateTime(2026, 9, 10, 5, 30),
      ),
    );
    await Hive.close();

    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings');
    final back = stepsLogFrom(
      await LocalStoreService.getSettingsMap(LocalStoreService.stepsByDayKey),
    );
    expect(back, {'2026-09-09': 2400});
  });

  test('a zero from a refused read cannot talk the stored day down',
      () async {
    // The merge on the way back in is stepsMapWith's, the same never-downward
    // rule two live reads get. On iOS a refused read is indistinguishable
    // from a quiet morning and arrives as a well-formed zero.
    await LocalStoreService.putSettingsMap(
      LocalStoreService.stepsByDayKey,
      const {'2026-09-09': 9000},
    );
    final stored = stepsLogFrom(
      await LocalStoreService.getSettingsMap(LocalStoreService.stepsByDayKey),
    );
    var merged = <String, int>{};
    for (final e in stored.entries) {
      merged = stepsMapWith(merged, e.key, e.value);
    }
    expect(stepsMapWith(merged, '2026-09-09', 0), {'2026-09-09': 9000});
  });

  test('the log is pruned on the way out, not left to grow forever', () async {
    final now = DateTime(2026, 9, 10, 5, 30);
    await LocalStoreService.putSettingsMap(
      LocalStoreService.stepsByDayKey,
      prunedStepsLog(
        const {
          '2026-01-01': 5000, // far past the window
          '2026-09-09': 2400,
          '2026-09-30': 8000, // a future day, from a wrong clock
        },
        now,
      ),
    );
    final back = stepsLogFrom(
      await LocalStoreService.getSettingsMap(LocalStoreService.stepsByDayKey),
    );
    expect(back, {'2026-09-09': 2400});
  });

  test('an empty box reads back as nothing, not as a zero day', () async {
    final back = stepsLogFrom(
      await LocalStoreService.getSettingsMap(LocalStoreService.stepsByDayKey),
    );
    expect(back, isEmpty);
  });
}
