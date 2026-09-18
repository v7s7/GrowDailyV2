// Saving a new schedule records the old one, and the record survives the
// device store, a reload, a pause and a resume.
//
// The pure rule is pinned in habit_cadence_test.dart; this is the notifier
// layer the edit sheet drives (CustomHabitsNotifier.update), through the guest
// store so nothing needs Firestore. A habit born today would never record a
// change (its old schedule governed no finished day), so every habit here is
// seeded as sixty days old.
//
// Also pinned: allHabitsEverProvider, which feeds the progress map, Insights
// and the recap, lays a person's own preset override (schedule and history)
// over the catalog template, the same way habitListProvider already did.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/habit_plans.dart'
    show activeCatalogProvider;
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_cadence.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/catalog_overrides_notifier.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';

void main() {
  late Directory tmp;
  late ProviderContainer container;

  final today = DateTime.now().effectiveDay;
  final yesterday = DateTime(today.year, today.month, today.day - 1);
  final born = DateTime(today.year, today.month, today.day - 60);

  /// The most recent [weekday] strictly before yesterday, so it is a day the
  /// OLD schedule governed.
  DateTime lastBefore(int weekday) {
    var d = DateTime(yesterday.year, yesterday.month, yesterday.day - 1);
    while (d.weekday != weekday) {
      d = DateTime(d.year, d.month, d.day - 1);
    }
    return d;
  }

  /// The first [weekday] after today, a day the NEW schedule governs.
  DateTime nextAfter(int weekday) {
    var d = DateTime(today.year, today.month, today.day + 1);
    while (d.weekday != weekday) {
      d = DateTime(d.year, d.month, d.day + 1);
    }
    return d;
  }

  const seeded = IslamicHabitTemplate(
    id: 'sadaqah',
    name: 'Sadaqah',
    description: '',
    category: HabitCategory.custom,
    frequencyType: HabitFrequencyType.weekly,
    frequencyTarget: 2,
    scheduledWeekdays: [DateTime.monday, DateTime.thursday],
    hasTimer: false,
    xpReward: 10,
    goldReward: 5,
  );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('schedule_record_test_');
    Hive.init(tmp.path);
    // All three boxes, exactly as main() opens them at boot.
    await Hive.openBox<dynamic>('box_settings');
    await Hive.openBox<dynamic>('box_daily_logs');
    final habits = await Hive.openBox<dynamic>('box_habits');
    await habits.put(LocalStoreService.guestCustomHabitsKey, [
      {
        'id': seeded.id,
        ...seeded.withCreatedAt(born).toFirestore(),
      },
    ]);
    container = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
    ]);
    await container.read(authStateProvider.future);
    container.read(customHabitsProvider);
    container.read(activeCatalogProvider);
    container.read(catalogOverridesProvider);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });

  tearDown(() async {
    await container.read(activeCatalogProvider.notifier).settled;
    container.dispose();
    // Guest saves are fire-and-forget; let them settle before the boxes go.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  CustomHabitsNotifier notifier() =>
      container.read(customHabitsProvider.notifier);

  IslamicHabitTemplate current() =>
      container.read(customHabitsProvider).firstWhere((h) => h.id == 'sadaqah');

  void makeDaily() => notifier().update(
        id: 'sadaqah',
        name: 'Sadaqah',
        category: HabitCategory.custom,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
        scheduledWeekdays: const [],
      );

  test('the seed loaded as a sixty-day-old Monday-and-Thursday habit', () {
    expect(current().createdAt, born);
    expect(current().pastCadences, isEmpty);
  });

  test('making it daily keeps Monday and Thursday up to yesterday', () {
    makeDaily();
    final h = current();
    expect(h.frequencyType, HabitFrequencyType.daily);
    expect(h.pastCadences, hasLength(1));
    expect(h.pastCadences.single.until, yesterday);
    expect(
      h.pastCadences.single.cadence.scheduledWeekdays,
      [DateTime.monday, DateTime.thursday],
    );
    // An old Tuesday is still an off-day; the next one is a daily day.
    expect(h.isScheduledFor(lastBefore(DateTime.tuesday)), isFalse);
    expect(h.isScheduledFor(lastBefore(DateTime.monday)), isTrue);
    expect(h.isScheduledFor(nextAfter(DateTime.tuesday)), isTrue);
    expect(h.isScheduledFor(today), isTrue,
        reason: 'the new schedule starts on the day it is saved');
  });

  test('a save that only renames records nothing', () {
    notifier().update(
      id: 'sadaqah',
      name: 'Sadaqah, even a little',
      category: HabitCategory.custom,
      frequencyType: HabitFrequencyType.weekly,
      frequencyTarget: 2,
      scheduledWeekdays: const [DateTime.thursday, DateTime.monday],
    );
    expect(current().pastCadences, isEmpty);
  });

  test('the record is written to the device store and read back', () async {
    makeDaily();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final raw = LocalStoreService.asMapList(
      (await LocalStoreService.habitsBox())
          .get(LocalStoreService.guestCustomHabitsKey),
    );
    expect(raw.single['scheduleHistory'], [
      {
        'until': yesterday.toDateKey(),
        'frequencyType': 'weekly',
        'frequencyTarget': 2,
        'scheduledWeekdays': [DateTime.monday, DateTime.thursday],
      },
    ]);

    // A fresh launch reads the same record.
    final relaunched = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
    ]);
    addTearDown(relaunched.dispose);
    await relaunched.read(authStateProvider.future);
    relaunched.read(customHabitsProvider);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final back = relaunched
        .read(customHabitsProvider)
        .firstWhere((h) => h.id == 'sadaqah');
    expect(back.pastCadences.single.until, yesterday);
    expect(back.isScheduledFor(lastBefore(DateTime.tuesday)), isFalse);
  });

  test('pausing and resuming keeps the record', () {
    makeDaily();
    notifier().archive('sadaqah', everCompleted: true);
    final paused = notifier().archived.firstWhere((h) => h.id == 'sadaqah');
    expect(paused.pastCadences.single.until, yesterday);
    notifier().unarchive('sadaqah');
    expect(current().pastCadences.single.until, yesterday);
    expect(current().isScheduledFor(lastBefore(DateTime.tuesday)), isFalse);
  });

  test('the history surfaces see a preset the way the person set it', () async {
    const presetId = 'morning_athkar';
    container.read(activeCatalogProvider.notifier).toggle(presetId);
    final catalog = IslamicHabitCatalog.findById(presetId)!;
    expect(catalog.scheduledWeekdays, isEmpty,
        reason: 'guard: the catalog runs it every day');
    await container.read(catalogOverridesProvider.notifier).setOverride(
          presetId,
          CatalogHabitOverride(
            frequencyType: HabitFrequencyType.weekly,
            frequencyTarget: 2,
            scheduledWeekdays: const [DateTime.monday, DateTime.thursday],
            pastCadences: [
              PastCadence(
                until: yesterday,
                cadence: const HabitCadence(
                  frequencyType: HabitFrequencyType.daily,
                  frequencyTarget: 1,
                ),
              ),
            ],
          ),
        );
    final ever =
        container.read(allHabitsEverProvider).where((h) => h.id == presetId);
    expect(ever, isNotEmpty);
    for (final h in ever) {
      expect(h.scheduledWeekdays, [DateTime.monday, DateTime.thursday],
          reason: 'the progress map and Insights used the catalog schedule');
      expect(h.pastCadences.single.until, yesterday);
    }
  });
}
