import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/habits/models/habit_cue.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';

/// Covers the same add/edit/archive path Grid's long-press habit sheet and
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
      expect(habits.first.goalType, GoalType.build);
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
        frequencyTarget: 2,
        scheduledWeekdays: const [DateTime.monday, DateTime.thursday],
      );

      final habits = container.read(customHabitsProvider);
      expect(habits, hasLength(1));
      final updated = habits.first;
      expect(updated.id, original.id);
      expect(updated.name, 'New name');
      expect(updated.cueAfter, '7:30 AM');
      expect(updated.category, HabitCategory.fitness);
      expect(updated.frequencyType, HabitFrequencyType.weekly);
      expect(updated.frequencyTarget, 2);
      expect(updated.scheduledWeekdays, [DateTime.monday, DateTime.thursday]);
      expect(updated.isScheduledFor(DateTime(2026, 7, 6)), isTrue); // Monday
      expect(updated.isScheduledFor(DateTime(2026, 7, 8)), isFalse); // Wednesday
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



    test('add can create a quit/reduce goal with stable metadata', () async {
      final notifier = container.read(customHabitsProvider.notifier);
      notifier.add(
        name: 'Reduce scrolling',
        category: HabitCategory.focus,
        cueAfter: HabitCue.preset('before_sleep').toStorageValue(),
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
        goalType: GoalType.quit,
        reductionType: ReductionType.limit,
        limitAmount: 30,
        limitUnit: LimitUnit.minutes,
      );

      final habit = container.read(customHabitsProvider).first;
      expect(habit.goalType, GoalType.quit);
      expect(habit.reductionType, ReductionType.limit);
      expect(habit.limitAmount, 30);
      expect(habit.limitUnit, LimitUnit.minutes);
      expect(habit.category.toJson(), 'focus');
      expect(habit.cueAfter, 'before_sleep');
    });

    test(
        'archive removes the habit from the active list but keeps it, '
        'dated, in the archived list', () async {
      final notifier = container.read(customHabitsProvider.notifier);
      notifier.add(
        name: 'Temp habit',
        category: HabitCategory.custom,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
      );
      final id = container.read(customHabitsProvider).first.id;

      notifier.archive(id);

      // Gone from the active list — same observable effect the old
      // hard-delete ("remove") had on every "what's active right now"
      // surface (Grid rows, the Add sheet, today's streak check).
      expect(container.read(customHabitsProvider), isEmpty);
      // Unlike the old remove(), the habit itself isn't gone — it's what
      // allHabitsEverProvider (custom_habits_notifier.dart) reads to keep
      // this habit's real name and schedule available to the Heatmap and
      // Insights for every day up to and including today. See
      // IslamicHabitTemplate.archivedAt.
      expect(notifier.archived, hasLength(1));
      expect(notifier.archived.first.id, id);
      expect(notifier.archived.first.name, 'Temp habit');
      expect(notifier.archived.first.archivedAt, isNotNull);
    });

    test('archiving an unknown id is a harmless no-op', () async {
      final notifier = container.read(customHabitsProvider.notifier);
      notifier.archive('does-not-exist');
      expect(container.read(customHabitsProvider), isEmpty);
      expect(notifier.archived, isEmpty);
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
