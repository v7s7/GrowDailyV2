// Pure-logic tests for IslamicHabitTemplate.fromMap's category-recovery fix
// (islamic_habit_catalog.dart). HabitCategory.toJson() collapses
// quran/athkar/fasting/sadaqah -> faith and fitness -> health before every
// Firestore write, so a preset habit's stored 'category' field alone can
// never distinguish 'faith' from the collapsed form of 'quran'. fromMap
// recovers the true fine-grained category from IslamicHabitCatalog.findById
// (id) when the id matches a real catalog entry, since that const template's
// category never touched Firestore and so was never collapsed. This is the
// single highest-leverage bugfix in this codebase's Milestones/Statistics
// work: without it, categoryCompletions['quran'] never incremented past a
// user's first session, and the Quran Devotion achievement family could
// never unlock for anyone.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';

void main() {
  group('IslamicHabitTemplate.fromMap — category recovery', () {
    test(
        'recovers the fine-grained catalog category even when the stored '
        'field already shows the collapsed broad category', () {
      // 'faith' simulates exactly what HabitCategory.toJson() would have
      // written for a quran-category preset before this fix — the bug this
      // guards against.
      final result = IslamicHabitTemplate.fromMap(
        'quran_daily_page',
        {'category': 'faith'},
      );
      expect(result.category, HabitCategory.quran);
    });

    test('recovers correctly for a second catalog id in the same family',
        () {
      final result = IslamicHabitTemplate.fromMap(
        'quran_memorization',
        {'category': 'faith'},
      );
      expect(result.category, HabitCategory.quran);
    });

    test('still recovers the catalog category when the field is missing '
        'entirely', () {
      final result = IslamicHabitTemplate.fromMap('quran_daily_page', const {});
      expect(result.category, HabitCategory.quran);
    });

    test(
        'falls back to the stored field for an id with no catalog match '
        '(a user-created custom habit)', () {
      final result = IslamicHabitTemplate.fromMap(
        'some-user-generated-uuid',
        {'category': 'health'},
      );
      expect(result.category, HabitCategory.health);
    });

    test('a custom habit with no stored category at all defaults to custom',
        () {
      final result =
          IslamicHabitTemplate.fromMap('some-user-generated-uuid', const {});
      expect(result.category, HabitCategory.custom);
    });
  });
}
