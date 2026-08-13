// Deleting a habit used to be one-way.
//
// archive() moved a custom habit into `archived` so the Heatmap and Insights
// kept its history — and nothing anywhere could move it back. No unarchive, no
// list of archived habits, no undo on the snackbar. A preset could at least be
// switched on again from Plans; a habit someone had built themselves — their
// own name, cue, frequency, colour and reminder — ended one tap from gone,
// while deleting a mere task had an Undo button.
//
// These cover the restore path itself. The invariant is the id: a restored
// habit has to be the SAME habit, because Grid squares, streaks, completion
// counts and room links are all keyed by it.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;

void main() {
  late Directory tmp;
  late ProviderContainer container;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('unarchive_test_');
    Hive.init(tmp.path);
    // All three, as main() opens them at boot. CustomHabitsNotifier's
    // constructor runs _migrateLegacyPrayerOffset, which reads the SETTINGS
    // box — opening only box_habits left that racing this temp directory's
    // deletion, which surfaced as an intermittent failure in whichever test
    // happened to be running.
    await Hive.openBox<dynamic>('box_settings');
    await Hive.openBox<dynamic>('box_daily_logs');
    await Hive.openBox<dynamic>('box_habits');
    container = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
    ]);
    await container.read(authStateProvider.future);
    container.read(customHabitsProvider);
    await Future<void>.delayed(const Duration(milliseconds: 60));
  });

  tearDown(() async {
    container.dispose();
    // Guest saves are fire-and-forget; let them settle before the boxes go.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  // A local function, not a getter — a getter can't be declared inside a
  // function body, and Dart silently reads it as a function declaration.
  CustomHabitsNotifier notifier() =>
      container.read(customHabitsProvider.notifier);

  String addHabit({String name = 'Push-ups'}) {
    final created = notifier().add(
      name: name,
      category: HabitCategory.fitness,
      frequencyType: HabitFrequencyType.weekly,
      frequencyTarget: 4,
      cueAfter: 'fajr',
    );
    return created.id;
  }

  test('a completed habit archives, then restores with the same id', () {
    final id = addHabit();
    notifier().archive(id, everCompleted: true);
    expect(container.read(customHabitsProvider).any((h) => h.id == id), isFalse,
        reason: 'archived habits leave the active list');
    expect(notifier().archived.any((h) => h.id == id), isTrue);

    notifier().unarchive(id);

    final back = container.read(customHabitsProvider).where((h) => h.id == id);
    expect(back, hasLength(1), reason: 'the habit is back on the list');
    // The invariant everything else depends on.
    expect(back.first.id, id);
    expect(notifier().archived.any((h) => h.id == id), isFalse,
        reason: 'and it is no longer in the archive');
  });

  test('restoring keeps everything the person had configured', () {
    final id = addHabit(name: 'Gym');
    notifier().archive(id, everCompleted: true);
    notifier().unarchive(id);

    final back =
        container.read(customHabitsProvider).firstWhere((h) => h.id == id);
    expect(back.name, 'Gym');
    expect(back.cueAfter, 'fajr');
    expect(back.frequencyType, HabitFrequencyType.weekly);
    expect(back.frequencyTarget, 4);
  });

  test('the archive date is cleared, the birth date is not', () {
    // createdAt is what stops a restored habit's pre-existing days reading
    // as misses (isScheduledFor); archivedAt still set would keep it looking
    // retired.
    final id = addHabit();
    final bornBefore = container
        .read(customHabitsProvider)
        .firstWhere((h) => h.id == id)
        .createdAt;
    notifier().archive(id, everCompleted: true);
    notifier().unarchive(id);

    final back =
        container.read(customHabitsProvider).firstWhere((h) => h.id == id);
    expect(back.archivedAt, isNull);
    expect(back.createdAt, bornBefore);
  });

  test('a habit that was never completed is hard-deleted, not archived', () {
    // Which is why the Undo button is only offered when something restorable
    // actually went — see GridScreen._deleteSelected.
    final id = addHabit();
    notifier().archive(id, everCompleted: false);
    expect(container.read(customHabitsProvider).any((h) => h.id == id), isFalse);
    expect(notifier().archived.any((h) => h.id == id), isFalse,
        reason: 'nothing was kept, so there is nothing to restore');
  });

  test('unarchiving something that is not archived is a safe no-op', () {
    // Undo can be tapped twice, and a hard-deleted habit reaches here too.
    final before = container.read(customHabitsProvider).length;
    notifier().unarchive('nope-not-a-real-id');
    expect(container.read(customHabitsProvider), hasLength(before));
  });

  test('restoring one habit leaves the others archived', () {
    final a = addHabit(name: 'A');
    final b = addHabit(name: 'B');
    notifier().archive(a, everCompleted: true);
    notifier().archive(b, everCompleted: true);

    notifier().unarchive(a);

    expect(container.read(customHabitsProvider).any((h) => h.id == a), isTrue);
    expect(container.read(customHabitsProvider).any((h) => h.id == b), isFalse);
    expect(notifier().archived.any((h) => h.id == b), isTrue);
  });
}
