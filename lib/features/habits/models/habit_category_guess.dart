import '../../../core/utils/step_habit_detector.dart';
import '../../../core/utils/text_moderation.dart';
import 'habit_model.dart';

// Add Habit's guess at a typed habit's category, from the words of its name.
// Moved out of add_habit_sheet.dart (2026-10-03) so it can be tested on its
// own: what it picks is saved on the habit, and Doum's praise is chosen by
// that saved category (see sprout_praise.dart). A wrong guess here is a
// wrong line there: «قراءة القرآن» used to land on Learning, because
// «القرآن» never matched the keyword «قرآن», and Doum said «معلومة تضيف لك»
// after a Quran reading (Aziz, 2026-10-03: the words must fit the habit).

/// The words a habit name is matched on: split on spaces after common
/// punctuation is stripped, rather than the plain substring match this
/// replaced. Deliberately doesn't use regex `\b`/`\w`: those only
/// recognize a-z/0-9 as "word" characters by default, so they'd silently
/// fail to find word boundaries anywhere in Arabic text. Splitting on
/// whitespace instead works identically for both scripts, since both
/// separate words with spaces.
///
/// Arabic is folded first ([foldArabic]: «القرآن» and «القران», «صدقة» and
/// «صدقه» are one word), and a word that opens with the article also counts
/// without it: «القرآن», «والأذكار», «بالرياضة» and «للنوم» reach «قرآن»,
/// «أذكار», «رياضة» and «نوم». The word as typed stays in the set too.
Set<String> habitNameWords(String text) {
  final cleaned = foldArabic(text.toLowerCase())
      .replaceAll(RegExp(r'[.,!?؟،:;]'), ' ');
  final words = <String>{};
  for (final word in cleaned.split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;
    words.add(word);
    final bare = _withoutArticle(word);
    if (bare != null) words.add(bare);
  }
  return words;
}

/// [word] without a leading «ال» (or «وال», «بال», «فال», «كال», «لل»), or
/// null when it has none. At least two letters must be left, so «الم» or
/// «بالي» are not cut down to nothing.
String? _withoutArticle(String word) {
  for (final prefix in const ['وال', 'بال', 'فال', 'كال']) {
    if (word.startsWith(prefix) && word.length >= prefix.length + 2) {
      return word.substring(prefix.length);
    }
  }
  for (final prefix in const ['ال', 'لل']) {
    if (word.startsWith(prefix) && word.length >= prefix.length + 2) {
      return word.substring(prefix.length);
    }
  }
  return null;
}

/// The keywords each of Add Habit's chips is guessed from. Written as they
/// are spelt; they are folded the same way as the name before matching.
/// Fasting, sadaqah, istighfar, qiyam and witr were added 2026-10-03: before
/// then a typed «صيام» was saved with no category and heard «كفو عليك»
/// rather than a prayer for the fast.
const Map<HabitCategory, List<String>> _keywordsByCategory = {
  HabitCategory.faith: [
    'quran', 'قرآن', 'سورة', 'آية', 'ayah', 'surah',
    'athkar', 'أذكار', 'ذكر', 'dhikr',
    'pray', 'prayer', 'praying', 'صلاة', 'صلي', 'دعاء', 'dua',
    'صيام', 'صوم', 'صدقة', 'استغفار', 'تسبيح', 'قيام', 'تهجد', 'وتر',
    'ضحى', 'fasting', 'charity', 'sadaqah', 'istighfar', 'witr', 'tahajjud',
  ],
  HabitCategory.health: [
    'gym', 'رياضة', 'مشي', 'تمرين', 'تمارين', 'ماء', 'موية',
    'walk', 'walking', 'run', 'running', 'jog', 'jogging',
    'workout', 'workouts', 'water', 'exercise', 'stretch', 'stretching',
  ],
  HabitCategory.learning: [
    'study', 'studying', 'دراسة', 'قراءة', 'لغة',
    'read', 'reading', 'language', 'english', 'course', 'كورس',
    'كتاب', 'book',
  ],
  HabitCategory.focus: [
    'phone', 'scrolling', 'scroll', 'جوال', 'تصفح',
    'tiktok', 'gaming', 'game', 'games', 'youtube', 'يوتيوب',
  ],
  HabitCategory.sleep: [
    'sleep', 'sleeping', 'نوم', 'سهر', 'bed', 'bedtime', 'nap',
  ],
  HabitCategory.money: [
    'money', 'spending', 'spend', 'صرف', 'مصروف',
    'budget', 'save', 'saving', 'savings', 'مال', 'ميزانية',
  ],
  HabitCategory.mind: [
    'meditate', 'meditation', 'تأمل',
    'gratitude', 'امتنان', 'journal', 'journaling', 'يوميات',
    'breathing', 'تنفس', 'mindfulness', 'stress', 'توتر',
    'anxiety', 'قلق',
  ],
  HabitCategory.social: [
    'family', 'عائلة', 'friend', 'friends', 'أصدقاء',
    'call', 'اتصال', 'visit', 'زيارة', 'message', 'رسالة',
  ],
};

/// Guesses a starting category from what's typed so far, or null when no
/// word gives one away. Never meant to be perfect, just a reasonable
/// default the user can always override with a manual chip tap.
///
/// Matching is whole-word only (a plain substring check matched "run"
/// inside "runway" and "bed" inside "bedroom"), and every category is
/// scored by how many of its keywords actually appear instead of returning
/// on the first `if` that matches, so a title mentioning two domains picks
/// whichever is the stronger signal rather than whichever category happened
/// to be checked first. A tie goes to the category listed first.
HabitCategory? guessHabitCategory(String text) {
  final words = habitNameWords(text);
  if (words.isEmpty) return null;
  HabitCategory? best;
  var bestScore = 0;
  for (final entry in _keywordsByCategory.entries) {
    var score = entry.value
        .where((k) => words.contains(foldArabic(k.toLowerCase())))
        .length;
    // The walking detector answers the same question about this name,
    // only far better than a word list can: it folds Arabic, strips the
    // definite article and forgives typos, so "المشي", "امشي شوي",
    // "walkk" and "10k steps" reach Health the way the exact keyword
    // "walking" already did. Before this they all landed on Custom,
    // which is how a habit the app was about to offer a step link for
    // could still be filed as uncategorised.
    //
    // Counted as one more health keyword rather than forced, so a name
    // that is mostly about something else ("read while walking") is
    // still decided by the rest of the words.
    if (entry.key == HabitCategory.health && looksLikeStepHabit(text)) {
      score += 1;
    }
    if (score > bestScore) {
      best = entry.key;
      bestScore = score;
    }
  }
  // "تيك توك" (TikTok) is the one keyword that's two tokens, not one, so
  // the word-set match above never sees it as a single unit, so it is checked
  // separately, only as a fallback so a real single-keyword match
  // elsewhere still wins.
  if (best == null && text.toLowerCase().contains('تيك توك')) {
    best = HabitCategory.focus;
  }
  return best;
}
