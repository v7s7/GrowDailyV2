// Add Habit's guess at a typed habit's category (habit_category_guess.dart).
// What it picks is saved on the habit, and Doum's praise is chosen by it, so
// a wrong guess is a wrong line: «قراءة القرآن» used to be filed under
// Learning and hear «معلومة تضيف لك» (Aziz, 2026-10-03: the words must fit
// the habit).
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/habits/models/habit_category_guess.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';

void main() {
  void expectGuess(Map<String, HabitCategory?> cases) {
    cases.forEach((name, category) {
      expect(guessHabitCategory(name), category, reason: name);
    });
  }

  test('a word with «ال» in front counts as the word itself', () {
    expectGuess({
      'قراءة القرآن': HabitCategory.faith,
      'ورد القرآن': HabitCategory.faith,
      'الأذكار': HabitCategory.faith,
      'والأذكار': HabitCategory.faith,
      'الرياضة': HabitCategory.health,
      'الالتزام بالرياضة': HabitCategory.health,
      'شرب الماء': HabitCategory.health,
      'النوم بدري': HabitCategory.sleep,
      'وقت للنوم': HabitCategory.sleep,
    });
  });

  test('spelling as people type it: no hamza, ه for ة', () {
    expectGuess({
      'قراءة القران': HabitCategory.faith,
      'اذكار المساء': HabitCategory.faith,
      'صدقه': HabitCategory.faith,
      'رياضه': HabitCategory.health,
    });
  });

  test('fasting, sadaqah, istighfar, qiyam and witr are worship', () {
    expectGuess({
      'صيام': HabitCategory.faith,
      'صيام الاثنين والخميس': HabitCategory.faith,
      'صوم': HabitCategory.faith,
      'صدقة يومية': HabitCategory.faith,
      'الاستغفار': HabitCategory.faith,
      'تسبيح': HabitCategory.faith,
      'قيام الليل': HabitCategory.faith,
      'الوتر': HabitCategory.faith,
      'صلاة الضحى': HabitCategory.faith,
      'fasting': HabitCategory.faith,
      'Read Quran': HabitCategory.faith,
    });
  });

  test('a name nothing gives away has no guess, so it stays Custom', () {
    expectGuess({
      'تنعيم اللحية': null,
      'no fast food': null,
      'الم': null,
      '': null,
      '.': null,
    });
  });

  test('what it already got right still holds', () {
    expectGuess({
      'walking': HabitCategory.health,
      'المشي': HabitCategory.health,
      'runway': null,
      'bedroom': null,
      'تيك توك': HabitCategory.focus,
      'قراءة كتاب': HabitCategory.learning,
      'اتصال بالعائلة': HabitCategory.social,
      'مصروف': HabitCategory.money,
      'يوميات امتنان': HabitCategory.mind,
    });
  });

  test('the words keep what was typed and add the bare form', () {
    final words = habitNameWords('القرآن، والأذكار');
    expect(words, containsAll(['القران', 'قران', 'والاذكار', 'اذكار']));
    expect(
      habitNameWords('الم'),
      {'الم'},
      reason: 'two letters must be left after the article',
    );
  });
}
