// Covers the layer that finally made preset habits editable.
//
// Catalog habits are const templates shared by every user, so there was no
// per-user document to rewrite and no edit path anywhere in the app: activate
// صلاة الضحى from a Plan and its reminder, frequency and weekdays were fixed
// forever. The only workaround was deleting it and rebuilding it as a custom
// habit, which loses that habit's Grid squares, streak, completion counts and
// every room link it had.
//
// The invariant every test here exists to protect is the id. An override is
// merged over the template, never a replacement for it, so the habit stays the
// same habit and its whole history stays attached.
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/catalog_overrides_notifier.dart';

IslamicHabitTemplate _preset() => const IslamicHabitTemplate(
      id: 'duha_prayer',
      name: 'Duha Prayer',
      description: 'Mid-morning prayer',
      nameAr: 'صلاة الضحى',
      descriptionAr: 'صلاة الضحى',
      cueAfter: 'fajr',
      category: HabitCategory.faith,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 10,
      goldReward: 5,
      reminderOffsetMinutes: 0,
    );

void main() {
  group('an override keeps the habit the same habit', () {
    test('the id never changes — this is what saves the history', () {
      // Grid squares, streaks, completion counts and room links are all keyed
      // by id. A rebuild-as-custom-habit workaround changed it; this cannot.
      const o = CatalogHabitOverride(
        name: 'Morning prayer',
        frequencyTarget: 4,
        frequencyType: HabitFrequencyType.weekly,
      );
      expect(o.applyTo(_preset()).id, 'duha_prayer');
    });

    test('anything not overridden still comes from the catalog', () {
      const o = CatalogHabitOverride(cueAfter: 'dhuhr');
      final merged = o.applyTo(_preset());
      expect(merged.cueAfter, 'dhuhr');
      expect(merged.name, 'Duha Prayer');
      expect(merged.category, HabitCategory.faith);
      expect(merged.frequencyTarget, 1);
      expect(merged.xpReward, 10);
    });

    test('reminder and frequency — the two things people asked for', () {
      const o = CatalogHabitOverride(
        cueAfter: 'maghrib',
        frequencyType: HabitFrequencyType.weekly,
        frequencyTarget: 4,
        scheduledWeekdays: [DateTime.monday, DateTime.wednesday],
        reminderOffsetMinutes: -15,
      );
      final merged = o.applyTo(_preset());
      expect(merged.cueAfter, 'maghrib');
      expect(merged.frequencyType, HabitFrequencyType.weekly);
      expect(merged.frequencyTarget, 4);
      expect(merged.scheduledWeekdays, [DateTime.monday, DateTime.wednesday]);
      expect(merged.reminderOffsetMinutes, -15);
    });

    test('an empty override changes nothing at all', () {
      const o = CatalogHabitOverride();
      final merged = o.applyTo(_preset());
      expect(o.isEmpty, isTrue);
      expect(merged.name, 'Duha Prayer');
      expect(merged.cueAfter, 'fajr');
      expect(merged.frequencyTarget, 1);
    });

    test('createdAt and archivedAt pass through untouched', () {
      // The birth date is what stops pre-activation days reading as misses
      // (isScheduledFor), and the archive date bounds a finished stint. An
      // override must never disturb either.
      final born = DateTime(2026, 5, 1);
      final died = DateTime(2026, 8, 1);
      final stamped = _preset().withDates(createdAt: born, archivedAt: died);
      const o = CatalogHabitOverride(frequencyTarget: 3);
      final merged = o.applyTo(stamped);
      expect(merged.createdAt, born);
      expect(merged.archivedAt, died);
    });
  });

  group('renaming', () {
    test('a renamed preset shows the new name in both languages', () {
      // The catalog ships an English and an Arabic name, but someone who
      // renamed it typed one string and meant it — showing the old preset
      // name back after a language switch would read as the rename not
      // having saved.
      const o = CatalogHabitOverride(name: 'My workout');
      final merged = o.applyTo(_preset());
      expect(merged.localName(false), 'My workout');
      expect(merged.localName(true), 'My workout');
    });

    test('leaving the name alone keeps both catalog names', () {
      const o = CatalogHabitOverride(frequencyTarget: 2);
      final merged = o.applyTo(_preset());
      expect(merged.localName(false), 'Duha Prayer');
      expect(merged.localName(true), 'صلاة الضحى');
    });
  });

  group('round-trips through storage', () {
    test('every field survives toMap/fromMap', () {
      const o = CatalogHabitOverride(
        name: 'Renamed',
        cueAfter: 'isha',
        frequencyType: HabitFrequencyType.weekly,
        frequencyTarget: 5,
        scheduledWeekdays: [DateTime.saturday, DateTime.sunday],
        reminderOffsetMinutes: -10,
        ignoreQuietHours: true,
        iconColorHex: '#FF8800',
      );
      final back = CatalogHabitOverride.fromMap(o.toMap());
      expect(back.name, 'Renamed');
      expect(back.cueAfter, 'isha');
      expect(back.frequencyType, HabitFrequencyType.weekly);
      expect(back.frequencyTarget, 5);
      expect(back.scheduledWeekdays, [DateTime.saturday, DateTime.sunday]);
      expect(back.reminderOffsetMinutes, -10);
      expect(back.ignoreQuietHours, isTrue);
      expect(back.iconColorHex, '#FF8800');
    });

    test('an untouched field is absent from storage, not stored as null', () {
      // Keeps the stored doc small, and lets a catalog template that later
      // gains a better default still supply it for anything never edited.
      const o = CatalogHabitOverride(frequencyTarget: 3);
      final map = o.toMap();
      expect(map.keys, ['frequencyTarget']);
      expect(map.containsKey('name'), isFalse);
    });

    test('an empty override stores nothing', () {
      expect(const CatalogHabitOverride().toMap(), isEmpty);
    });

    test('junk weekday values are dropped on read', () {
      // Defensive: a hand-edited or corrupted doc must not produce a habit
      // scheduled on "day 9".
      final back = CatalogHabitOverride.fromMap(const {
        'scheduledWeekdays': [1, 9, 0, 7, -2],
      });
      expect(back.scheduledWeekdays, [1, 7]);
    });

    test('a malformed map reads as no override rather than throwing', () {
      final back = CatalogHabitOverride.fromMap(const {
        'frequencyTarget': null,
        'ignoreQuietHours': null,
      });
      expect(back.isEmpty, isTrue);
    });
  });
}
