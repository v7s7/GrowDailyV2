// Every category the Add Habit sheet offers has related suggestions on both
// sides, and only related ones are ever shown.
//
// Aziz, 2026-09-08: "search every category and fix them all, make the
// suggestions related". Four categories had no quit side, one had no build
// side, and «مخصص» had nothing at all, so the sheet fell back to the first
// six suggestions of the type and a person who had just tapped «التعلّم»
// saw chips about prayer and sugar.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/habits/catalog/goal_suggestions.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';

/// The nine categories the sheet's grid offers (AddHabitSheet._broadCategories).
const offered = [
  HabitCategory.faith,
  HabitCategory.health,
  HabitCategory.learning,
  HabitCategory.focus,
  HabitCategory.sleep,
  HabitCategory.money,
  HabitCategory.mind,
  HabitCategory.social,
  HabitCategory.custom,
];

void main() {
  test('every offered category has four suggestions on each side', () {
    for (final cat in offered) {
      for (final type in GoalType.values) {
        expect(suggestionsFor(type, cat), hasLength(4),
            reason: '${cat.name} / ${type.name}');
      }
    }
  });

  test('no suggestion belongs to a category the sheet cannot show', () {
    for (final s in goalSuggestions) {
      expect(offered, contains(s.category), reason: '${s.en} is filed under '
          '${s.category.name}, which the grid never offers, so it could never '
          'be seen');
    }
  });

  test('a quit suggestion reads as something to stop, a build one to do', () {
    for (final s in goalSuggestions.where((s) => s.type == GoalType.quit)) {
      expect(
        s.ar.startsWith('بدون') || s.ar.startsWith('تقليل'),
        isTrue,
        reason: '"${s.ar}" is on the quit side',
      );
      expect(
        s.en.startsWith('No ') ||
            s.en.startsWith('Less ') ||
            s.en.startsWith('Reduce '),
        isTrue,
        reason: '"${s.en}" is on the quit side',
      );
    }
    for (final s in goalSuggestions.where((s) => s.type == GoalType.build)) {
      expect(s.ar.startsWith('بدون'), isFalse, reason: '"${s.ar}" is a build');
    }
  });

  test('names are unique within a side and follow the house rules', () {
    for (final type in GoalType.values) {
      final ar = goalSuggestions.where((s) => s.type == type).map((s) => s.ar);
      final en = goalSuggestions.where((s) => s.type == type).map((s) => s.en);
      expect(ar.toSet().length, ar.length, reason: 'duplicate Arabic name');
      expect(en.toSet().length, en.length, reason: 'duplicate English name');
    }
    for (final s in goalSuggestions) {
      expect(s.ar.trim(), isNotEmpty);
      expect(s.en.trim(), isNotEmpty);
      expect(s.ar, isNot(contains('لسا')));
      expect(s.ar, isNot(contains('—')));
      expect(s.en, isNot(contains('—')));
    }
  });
}
