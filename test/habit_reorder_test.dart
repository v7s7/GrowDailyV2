import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/habits/notifiers/habit_order_notifier.dart';

/// The model layer under the Grid's new reorder sheet: a drag calls
/// HabitOrderNotifier.reorder with the displayed order and the id that
/// should come after the moved habit, and habitListProvider re-sorts by
/// the resulting ranks. Until the sheet shipped, reorder() had no caller
/// and so no test pinning any of this down.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HabitOrderNotifier (guest path)', () {
    late Directory tmp;
    late ProviderContainer container;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('habit_order_test_');
      Hive.init(tmp.path);
      // Same three-box fixture custom_habits_notifier_test.dart documents:
      // habitListProvider reaches settings, and opening a subset races the
      // temp dir teardown.
      await Hive.openBox<dynamic>('box_settings');
      await Hive.openBox<dynamic>('box_daily_logs');
      await Hive.openBox<dynamic>('box_habits');
      container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        ],
      );
      await container.read(authStateProvider.future);
      container.read(customHabitsProvider);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });

    tearDown(() async {
      container.dispose();
      await Hive.deleteFromDisk();
      await tmp.delete(recursive: true);
    });

    List<String> addThree() {
      final notifier = container.read(customHabitsProvider.notifier);
      for (final name in ['alpha', 'beta', 'gamma']) {
        notifier.add(
          name: name,
          category: HabitCategory.custom,
          frequencyType: HabitFrequencyType.daily,
          frequencyTarget: 1,
        );
      }
      return [
        for (final h in container.read(habitListProvider)) h.name,
      ].isEmpty
          ? <String>[]
          : [for (final h in container.read(habitListProvider)) h.id];
    }

    List<String> namesInOrder() =>
        [for (final h in container.read(habitListProvider)) h.name];

    test('moving the last habit to the front re-sorts the list', () async {
      final ids = addThree();
      expect(namesInOrder(), ['alpha', 'beta', 'gamma']);

      // Drag gamma above alpha: anchor is the habit that should follow it.
      container
          .read(habitOrderProvider.notifier)
          .reorder(ids[2], ids, beforeId: ids[0]);

      expect(namesInOrder(), ['gamma', 'alpha', 'beta']);
    });

    test('moving the first habit to the end (no anchor) appends', () async {
      final ids = addThree();

      container
          .read(habitOrderProvider.notifier)
          .reorder(ids[0], ids, beforeId: null);

      expect(namesInOrder(), ['beta', 'gamma', 'alpha']);
    });

    test('a middle drop lands between its new neighbours', () async {
      final ids = addThree();

      // gamma between alpha and beta.
      container
          .read(habitOrderProvider.notifier)
          .reorder(ids[2], ids, beforeId: ids[1]);

      expect(namesInOrder(), ['alpha', 'gamma', 'beta']);
    });

    test('order survives a reload from the guest store', () async {
      final ids = addThree();
      container
          .read(habitOrderProvider.notifier)
          .reorder(ids[2], ids, beforeId: ids[0]);
      // The rank write is awaited inside _persist's box.put; give the
      // fire-and-forget a beat, then rebuild the provider from disk.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      container.invalidate(habitOrderProvider);
      container.read(habitOrderProvider);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(namesInOrder(), ['gamma', 'alpha', 'beta']);
    });
  });
}
