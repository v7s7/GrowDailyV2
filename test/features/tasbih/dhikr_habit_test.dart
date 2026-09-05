import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/tasbih/tasbih_screen.dart';

/// The tasbih's one bridge into the habit system is offer-only, so this
/// boundary is tuned like the step detector's: generous on spelling, strict
/// about words that merely contain a dhikr root. A false positive costs one
/// dismissible button; a false negative hides the offer entirely.
void main() {
  bool match(String name, {HabitCategory category = HabitCategory.custom}) =>
      looksLikeDhikrHabit(category: category, name: name);

  test('the catalog athkar category always matches, whatever the name', () {
    expect(match('صباح', category: HabitCategory.athkar), isTrue);
  });

  test('plain dhikr names match in both languages', () {
    expect(match('أذكار الصباح'), isTrue);
    expect(match('اذكار المساء'), isTrue);
    expect(match('تسبيح بعد الصلاة'), isTrue);
    expect(match('السبحة'), isTrue);
    expect(match('استغفار ١٠٠ مرة'), isTrue);
    expect(match('Morning athkar'), isTrue);
    expect(match('Daily dhikr'), isTrue);
    expect(match('Tasbeeh after fajr'), isTrue);
  });

  test('spelling variants fold: hamza, teh marbuta, diacritics', () {
    expect(match('أَذْكَار'), isTrue, reason: 'diacritics are stripped');
    expect(match('سبحه'), isTrue, reason: 'teh marbuta and heh unify');
    expect(match('إستغفار'), isTrue, reason: 'hamza variants unify');
  });

  test('words that merely contain the dhikr root do not match', () {
    // «تذكر» (remember) and «مذاكرة» (studying) are ordinary habit words;
    // the bare root «ذكر» is deliberately not in the word list.
    expect(match('تذكر النعم'), isFalse);
    expect(match('مذاكرة ساعة'), isFalse);
    expect(match('قراءة القرآن'), isFalse);
    expect(match('تمرين'), isFalse);
    expect(match('Morning walk'), isFalse);
  });

  test('a non-athkar category alone is not enough', () {
    expect(match('صلاة الوتر', category: HabitCategory.faith), isFalse);
  });
}
