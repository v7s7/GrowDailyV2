// Linking a catalog preset to the step count.
//
// The steps link was built for one habit in particular, and until now that
// habit was the one that could not use it: the card was hidden for every
// preset, because CatalogHabitOverride had no field to keep a link in.
//
// The safety property this file exists for is the first group. A catalog
// template is shipped to every account, so a live stepGoal on one would mean
// switching that preset on starts reading somebody's health data before
// anyone has been asked. The suggestion is a different field for exactly
// that reason, and nothing but the person's own override may set the link.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/habits/catalog/habit_plans.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/core/utils/step_habit_detector.dart';
import 'package:grow_daily_v2/features/habits/models/habit_cue.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/catalog_overrides_notifier.dart';

void main() {
  IslamicHabitTemplate byId(String id) =>
      IslamicHabitCatalog.templates.firstWhere((t) => t.id == id);

  group('no preset ever ships a live link', () {
    test('every catalog template has a null stepGoal', () {
      // Non-null IS the link (see IslamicHabitTemplate.stepGoal). One of
      // these set in the catalog would read health data for every account
      // that ever switched that preset on, unasked.
      for (final t in IslamicHabitCatalog.templates) {
        expect(t.stepGoal, isNull, reason: '${t.id} ships a live steps link');
      }
    });

    test('the walking preset suggests a goal without being linked', () {
      final walk = byId('daily_walk');
      expect(walk.suggestedStepGoal, 10000);
      expect(walk.stepGoal, isNull);
    });
  });

  group('the walking preset', () {
    test('is named in both languages and is a daily build habit', () {
      final walk = byId('daily_walk');
      expect(walk.nameAr, 'المشي اليومي');
      expect(walk.name, 'Walk daily');
      expect(walk.goalType, GoalType.build);
      expect(walk.frequencyType, HabitFrequencyType.daily);
      expect(walk.frequencyTarget, 1);
    });

    test('its name is what the detector reads as walking', () {
      // The card only appears for a name the detector recognises, so a
      // preset the feature was built for has to pass its own test.
      expect(looksLikeStepHabit(byId('daily_walk').nameAr!), isTrue);
      expect(looksLikeStepHabit(byId('daily_walk').name), isTrue);
    });

    test('its cue is one that actually produces a reminder', () {
      // 'morning' would have read correctly (الصباح) and notified nobody:
      // NotificationService only resolves the five prayers and explicit
      // clock times, and a routine anchor has no time this app can derive.
      // A walking habit cued الصبح has to be Fajr for the reminder to exist
      // at all, so this pins the difference rather than trusting the label.
      final cue = HabitCue.fromStoredValue(byId('daily_walk').cueAfter);
      expect(cue.isPrayer, isTrue);
      expect(cue.prayerKey, 'fajr');
    });

    test('it is the only preset the detector reads as walking', () {
      // The card is no longer hidden for presets, so a false positive would
      // now put a "link this to your steps?" offer on a habit that has
      // nothing to do with walking. The detector's stoplist exists for
      // exactly these neighbours ("waking" is one edit from "walking"), and
      // this is what keeps it honest as the catalog grows.
      final detected = [
        for (final t in IslamicHabitCatalog.templates)
          if (looksLikeStepHabit(t.name) ||
              looksLikeStepHabit(t.nameAr ?? '')) t.id,
      ];
      expect(detected, ['daily_walk']);
    });

    test('it is in a plan, and that plan can still resolve every habit', () {
      final plan = habitPlans.firstWhere((p) => p.id == 'discipline_30');
      expect(plan.catalogIds, contains('daily_walk'));
      // A plan naming an id the catalog does not have would silently drop
      // that habit rather than fail, so the count is the real check.
      expect(plan.habits.length, plan.catalogIds.length);
    });
  });

  group('the override carries the link', () {
    final walk = byId('daily_walk');

    test('applying one turns the preset into a linked habit', () {
      final linked =
          const CatalogHabitOverride(stepGoal: 8000).applyTo(walk);
      expect(linked.stepGoal, 8000);
      expect(linked.id, walk.id, reason: 'the id must survive, history hangs on it');
    });

    test('no override leaves the preset unlinked', () {
      expect(const CatalogHabitOverride(name: 'x').applyTo(walk).stepGoal,
          isNull);
    });

    test('the suggestion survives an override', () {
      // Otherwise reopening an edited preset offers the generic default
      // instead of the number the habit is actually about.
      final edited = const CatalogHabitOverride(name: 'مشي').applyTo(walk);
      expect(edited.suggestedStepGoal, 10000);
    });

    test('a link alone is not an empty override', () {
      // isEmpty deletes the record, which would silently unlink the habit.
      expect(const CatalogHabitOverride(stepGoal: 10000).isEmpty, isFalse);
      expect(const CatalogHabitOverride().isEmpty, isTrue);
    });

    test('it round-trips through storage', () {
      final back = CatalogHabitOverride.fromMap(
        const CatalogHabitOverride(stepGoal: 7500).toMap(),
      );
      expect(back.stepGoal, 7500);
    });

    test('an unlinked override writes no key at all', () {
      expect(const CatalogHabitOverride(name: 'x').toMap().containsKey('stepGoal'),
          isFalse);
    });
  });
}
