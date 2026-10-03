// A task added while the Tasks list is still loading must not cost the list.
//
// The loader used to drop what it read once anything had been done first. For
// an account that left the page holding only the new task until the next
// launch. For a guest it was worse: the add's own save then wrote that short
// list over the saved one, and every earlier task was gone from the phone.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/matrix/models/matrix_task.dart';
import 'package:grow_daily_v2/features/matrix/notifiers/matrix_notifier.dart';

import '../../helpers/wait_until.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MatrixTask task(String title, int minutesAgo) {
    final t = MatrixTask.create(title, MatrixQuadrant.doFirst);
    return MatrixTask.fromMap({
      ...t.toMap(),
      'createdAt': DateTime.now()
          .subtract(Duration(minutes: minutesAgo))
          .toIso8601String(),
    });
  }

  group('mergeLoadedTasks', () {
    test('keeps every loaded task and adds the ones made before it landed',
        () {
      final a = task('a', 30), b = task('b', 20), fresh = task('new', 0);
      final merged = mergeLoadedTasks(
        loaded: [b, a],
        local: [fresh],
        removed: const {},
      );
      expect(merged.map((t) => t.title), ['a', 'b', 'new'],
          reason: 'all of them, in created order');
    });

    test('a task the read already held is not doubled, and the copy made '
        'here wins', () {
      final fresh = task('new', 0);
      final renamedHere = MatrixTask.fromMap({...fresh.toMap(), 'title': 'x'});
      final merged = mergeLoadedTasks(
        loaded: [fresh],
        local: [renamedHere],
        removed: const {},
      );
      expect(merged, hasLength(1));
      expect(merged.single.title, 'x');
    });

    test('a task deleted before the load landed stays deleted', () {
      final a = task('a', 30), b = task('b', 20);
      final merged = mergeLoadedTasks(
        loaded: [a, b],
        local: const [],
        removed: {a.id},
      );
      expect(merged.map((t) => t.title), ['b']);
    });
  });

  group('a guest adding before the saved list is read', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('matrix_load_merge_');
      Hive.init(tmp.path);
      await LocalStoreService.settingsBox();
    });
    tearDown(() async {
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    test('keeps every saved task, on screen and on the phone', () async {
      final box = await LocalStoreService.settingsBox();
      await box.put(LocalStoreService.guestMatrixTasksKey, [
        task('old 1', 60).toMap(),
        task('old 2', 50).toMap(),
      ]);

      final c = ProviderContainer(overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
      ]);
      addTearDown(c.dispose);
      await c.read(authStateProvider.future);

      // Created and added to in the same tick, before its read can land.
      final n = c.read(matrixProvider.notifier);
      n.add('new', MatrixQuadrant.doFirst);

      await waitUntil(
        () => c.read(matrixProvider).tasks.length == 3,
        describe: 'the saved tasks joining the one just added',
        timeout: const Duration(seconds: 5),
      );
      expect(c.read(matrixProvider).tasks.map((t) => t.title),
          ['old 1', 'old 2', 'new']);

      await waitUntil(
        () =>
            LocalStoreService.asMapList(
              box.get(LocalStoreService.guestMatrixTasksKey),
            ).length ==
            3,
        describe: 'the merged list written back to the phone',
        timeout: const Duration(seconds: 5),
      );
    });
  });
}
