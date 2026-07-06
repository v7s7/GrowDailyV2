import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/matrix/models/matrix_task.dart';
import 'package:grow_daily_v2/features/matrix/notifiers/matrix_notifier.dart';
import 'package:hive/hive.dart';

/// A plain (non-widget) test file on purpose: MatrixNotifier's guest save is
/// a fire-and-forget Hive write, and starting one inside a testWidgets'
/// fake-async zone leaves it permanently pending — real IO never resolves
/// there. Plain `test()` runs in a genuine async zone, so the write settles
/// normally and this can assert on it directly.
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('matrix_persist_test_');
    Hive.init(tmp.path);
    // Open it here, before any notifier or the test's own polling touches
    // it — otherwise the notifier's first settingsBox() call and this
    // file's later Hive.openBox() call can race to open the same box name.
    await Hive.openBox<dynamic>('box_settings');
  });

  tearDown(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  test('a guest\'s goals survive the app restarting', () async {
    // First "session": add a goal, same as a quick-suggestion tap would.
    final first = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
      ],
    );
    await first.read(authStateProvider.future);
    first.read(matrixProvider.notifier).add('Reply to an email', MatrixQuadrant.doFirst);

    // The save is fire-and-forget — poll the actual box instead of guessing
    // a delay, so this isn't racy against however long that write takes.
    final box = Hive.box<dynamic>('box_settings');
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (box.get('guest_matrix_tasks') == null &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(box.get('guest_matrix_tasks'), isNotNull,
        reason: 'the guest save never reached disk');
    first.dispose();

    // Second "session": a fresh notifier, same Hive-backed disk — nothing
    // should have been lost.
    final second = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
      ],
    );
    await second.read(authStateProvider.future);
    // Providers are lazy — this read is what constructs MatrixNotifier and
    // kicks off its guest load, so it must happen before waiting for it.
    second.read(matrixProvider);
    final loadDeadline = DateTime.now().add(const Duration(seconds: 5));
    while (second.read(matrixProvider).tasks.isEmpty &&
        DateTime.now().isBefore(loadDeadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    final tasks = second.read(matrixProvider).tasks;
    expect(tasks, hasLength(1));
    expect(tasks.first.title, 'Reply to an email');
    expect(tasks.first.quadrant, MatrixQuadrant.doFirst);
    second.dispose();
  });
}
