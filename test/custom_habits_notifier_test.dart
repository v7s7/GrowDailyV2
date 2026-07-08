import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/habits/models/habit_cue.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';

/// Covers the same add/edit/remove path Grid's long-press habit sheet and
/// Today's habit menu both drive — this is the model layer under
/// `AddHabitSheet(existing: habit)`, so a bug here would break "edit a
/// habit" everywhere it's exposed, not just in one screen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CustomHabitsNotifier (guest path)', () {
    late Directory tmp;
    late ProviderContainer container;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('habits_test_');
      Hive.init(tmp.path);
      container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        ],
      );
      await container.read(authStateProvider.future);
      // No isLoading flag to poll here (unlike dashboard/grid) — the guest
      // load is a single fast Hive read on a fresh temp box, so a short
      // fixed wait is enough to let it finish before mutating, the same
      // race grid_progression_test.dart's poll loop guards against.
      container.read(customHabitsProvider);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });

    tearDown(() async {
      container.dispose();
      await Hive.deleteFromDisk();
      await tmp.delete(recursive: true);
    });

    test('add creates a habit with the given fields', () async {
      final notifier = container.read(customHabitsProvider.notifier);
      notifier.add(
        name: 'Read 10 pages',
        category: HabitCategory.quran,
        cueAfter: 'Fajr',
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
      );

      final habits = container.read(customHabitsProvider);
      expect(habits, hasLength(1));
      expect(habits.first.name, 'Read 10 pages');
      expect(habits.first.cueAfter, 'Fajr');
      expect(habits.first.category, HabitCategory.quran);
      expect(habits.first.frequencyType, HabitFrequencyType.daily);
      expect(habits.first.frequencyTarget, 1);
    });

    test('update changes title/time/category/frequency but keeps the same id',
        () async {
      final notifier = container.read(customHabitsProvider.notifier);
      notifier.add(
        name: 'Old name',
        category: HabitCategory.custom,
        cueAfter: 'Fajr',
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
      );
      final original = container.read(customHabitsProvider).first;

      notifier.update(
        id: original.id,
        name: 'New name',
        category: HabitCategory.fitness,
        cueAfter: '7:30 AM',
        frequencyType: HabitFrequencyType.weekly,
        frequencyTarget: 4,
      );

      final habits = container.read(customHabitsProvider);
      expect(habits, hasLength(1));
      final updated = habits.first;
      expect(updated.id, original.id);
      expect(updated.name, 'New name');
      expect(updated.cueAfter, '7:30 AM');
      expect(updated.category, HabitCategory.fitness);
      expect(updated.frequencyType, HabitFrequencyType.weekly);
      expect(updated.frequencyTarget, 4);
    });

    test('update to a bare custom time (not a named prayer cue) round-trips',
        () async {
      final notifier = container.read(customHabitsProvider.notifier);
      notifier.add(
        name: 'Evening walk',
        category: HabitCategory.fitness,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
      );
      final original = container.read(customHabitsProvider).first;

      notifier.update(
        id: original.id,
        name: original.name,
        category: original.category,
        cueAfter: '9:15 PM',
        frequencyType: original.frequencyType,
        frequencyTarget: original.frequencyTarget,
      );

      expect(container.read(customHabitsProvider).first.cueAfter, '9:15 PM');
    });

    test(
        'the notifier stores exactly the canonical value it is given — '
        'AddHabitSheet is responsible for canonicalizing before calling in, '
        'not this layer', () async {
      final notifier = container.read(customHabitsProvider.notifier);
      // This is what AddHabitSheet._submit() now passes for a preset cue
      // (HabitCue.preset('maghrib').toStorageValue()) — a bare canonical
      // key, never the localized label ("المغرب"/"Maghrib") the chip
      // showed on screen.
      notifier.add(
        name: 'Read Surat Al-Mulk',
        category: HabitCategory.quran,
        cueAfter: HabitCue.preset('maghrib').toStorageValue(),
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
      );

      final stored = container.read(customHabitsProvider).first.cueAfter;
      expect(stored, 'maghrib');
      expect(stored, isNot('المغرب'));
      expect(stored, isNot('Maghrib'));
    });

    test('remove deletes the habit and it no longer appears in the list',
        () async {
      final notifier = container.read(customHabitsProvider.notifier);
      notifier.add(
        name: 'Temp habit',
        category: HabitCategory.custom,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
      );
      final id = container.read(customHabitsProvider).first.id;

      notifier.remove(id);

      expect(container.read(customHabitsProvider), isEmpty);
    });

    test('editing one habit does not touch a second habit', () async {
      final notifier = container.read(customHabitsProvider.notifier);
      notifier.add(
        name: 'Habit A',
        category: HabitCategory.custom,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
      );
      notifier.add(
        name: 'Habit B',
        category: HabitCategory.custom,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
      );
      final ids = container.read(customHabitsProvider).map((h) => h.id).toList();

      notifier.update(
        id: ids[0],
        name: 'Habit A renamed',
        category: HabitCategory.custom,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
      );

      final habits = container.read(customHabitsProvider);
      expect(habits, hasLength(2));
      expect(habits.firstWhere((h) => h.id == ids[0]).name, 'Habit A renamed');
      expect(habits.firstWhere((h) => h.id == ids[1]).name, 'Habit B');
    });
  });
}
