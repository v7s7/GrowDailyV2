import 'dart:math' show max, min;

import '../../habits/catalog/islamic_habit_catalog.dart';

/// Which of this person's habits a room's plan entry most likely IS, when a
/// leader and a member named the same habit differently.
///
/// Aziz, 2026-09-24: a leader added «الضحى» and «الوتر» to a room's plan,
/// and the member already had «صلاة الضحى» and «صلاة الوتر», but the link
/// sheet offered nothing, because the old guess only forgave a typo or two
/// (five extra letters is far past that). Everything here runs on the phone
/// with fixed rules and a short list of names, so it costs nothing and
/// never sends a habit name anywhere.
///
/// A match is only ever a SUGGESTION: every caller pre-selects it in a
/// dropdown the person can change, or shows it in a "possible duplicate"
/// note (see suggestExistingMatch in rooms_notifier.dart). So the rules
/// lean towards "no guess" whenever two names could be different habits:
/// «صلاة الفجر» is never offered for «سنة الفجر», nor «أذكار المساء» for
/// «أذكار الصباح», nor «التدخين» for «ترك التدخين».
///
/// How sure a pair is, highest first:
///  100  the same name once spelling is evened out (see
///       [normalizeHabitText]): tashkeel, أ/إ/آ, ة/ه, ى/ي, spacing
///   95  the same catalog habit, found through the plan entry's name even
///       when this person renamed their copy (see [bestHabitMatch])
///   90  two names for the same habit from [_sameHabit], in either
///       language: «الوتر» and "Witr", «قيام الليل» and «صلاة التهجد»
///   80  the same words once filler is dropped: «الضحى» and «صلاة الضحى»
///   70  one name is the other with a few extra words that do not change
///       which habit it is: «الصدقة» and «الصدقة ولو بالقليل»
///   <60 a typo: «صلاة الضجى» and «صلاة الضحى»
///    0  no guess
const int kHabitMatchExact = 100;
const int kHabitMatchCatalog = 95;
const int kHabitMatchSameHabit = 90;
const int kHabitMatchSameWords = 80;
const int kHabitMatchExtraWords = 70;
const int kHabitMatchTypo = 60;

/// [text] with the spelling differences that do not change a word evened
/// out, so two people's spellings of one name compare equal.
///
///  * Latin letters lower case, and Arabic-Indic digits as Latin ones.
///  * Tashkeel, Quranic marks, the dagger alef and the tatweel removed.
///  * أ إ آ ٱ as ا, ة as ه, ى as ي, ؤ as و, ئ as ي.
///  * Anything that is not a letter or a digit is a space, and runs of
///    spaces are one.
String normalizeHabitText(String text) {
  var t = text.toLowerCase();
  t = t.replaceAllMapped(
    RegExp('[\u0660-\u0669]'),
    (m) => String.fromCharCode(m[0]!.codeUnitAt(0) - 0x0660 + 0x30),
  );
  t = t.replaceAllMapped(
    RegExp('[\u06F0-\u06F9]'),
    (m) => String.fromCharCode(m[0]!.codeUnitAt(0) - 0x06F0 + 0x30),
  );
  t = t.replaceAll(
    RegExp('[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED\u0640]'),
    '',
  );
  t = t
      .replaceAll(RegExp('[\u0623\u0625\u0622\u0671]'), '\u0627')
      .replaceAll('\u0629', '\u0647')
      .replaceAll('\u0649', '\u064A')
      .replaceAll('\u0624', '\u0648')
      .replaceAll('\u0626', '\u064A');
  t = t.replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ');
  return t.trim();
}

/// The article and the one-letter prepositions glued to it, longest first.
/// A bare و is never cut on its own: it is the first letter of «وتر».
const List<String> _gluedPrefixes = [
  'وال', 'بال', 'فال', 'كال', 'لل', 'ال', //
];

/// Words written more than one way that mean one thing, after
/// [normalizeHabitText] and the article is gone.
const Map<String, String> _sameWord = {
  'ذكر': 'اذكار',
  'صبح': 'صباح',
  'مسا': 'مساء',
  'صوم': 'صيام',
  'تلاوه': 'قراءه',
  'ورد': 'قراءه',
  'athkar': 'adhkar',
  'azkar': 'adhkar',
  'dhikr': 'adhkar',
  'zikr': 'adhkar',
  'zuhr': 'dhuhr',
  'duhr': 'dhuhr',
  'dhuha': 'duha',
  'doha': 'duha',
  'qiyam': 'tahajjud',
  'sadaqa': 'sadaqah',
  'charity': 'sadaqah',
  'quraan': 'quran',
  "qur'an": 'quran',
};

/// Words that say nothing about WHICH habit it is: "prayer", "two rak'ahs",
/// "surah", "reading", "daily", "habit". Dropped before names are compared,
/// so «صلاة الضحى» is «ضحي» and «ورد القرآن اليومي» is «قران».
const Set<String> _filler = {
  'صلاه', 'ركعه', 'ركعتين', 'ركعتي', 'ركعتا', 'ركعات', 'سوره', 'قراءه',
  'يومي', 'يوميه', 'يوميا', 'يوم', 'اداء', 'عاده', //
  'prayer', 'prayers', 'pray', 'salah', 'salat', 'salaat', 'surah', 'sura',
  'read', 'reading', 'daily', 'habit', 'rakah', 'rakat',
};

/// Small joining words, dropped like [_filler].
const Set<String> _joining = {
  'في', 'من', 'الي', 'علي', 'عن', 'مع', 'ولو', 'او', 'و', 'كل', 'بعض',
  'هذا', 'هذه', //
  'the', 'a', 'an', 'of', 'in', 'on', 'at', 'to', 'for', 'with', 'and', 'or',
  'my', 'every', 'each', 'per',
};

/// Words that DO say which habit it is, so a name that has one and a name
/// that does not are never the same habit: the sunnah and the obligatory
/// prayer, before and after, morning and evening, one prayer and another,
/// doing a thing and quitting it, reading the Quran and memorising it.
const Set<String> _changesMeaning = {
  'سنه', 'سنن', 'فرض', 'فريضه', 'نافله', 'قبل', 'بعد', 'قبليه', 'بعديه',
  'راتبه', 'رواتب', 'صباح', 'مساء', 'ليل', 'ليله', 'نهار', 'فجر', 'ظهر',
  'عصر', 'مغرب', 'عشاء', 'ضحي', 'وتر', 'تهجد', 'قيام', 'جمعه', 'اثنين',
  'خميس', 'سبت', 'احد', 'ثلاثاء', 'اربعاء', 'بيض', 'ترك', 'تقليل', 'بدون',
  'بلا', 'لا', 'عدم', 'اقل', 'حفظ', 'مراجعه', 'تفسير', 'اسبوع', 'اسبوعي',
  'شهر', 'شهري', //
  'sunnah', 'fard', 'before', 'after', 'morning', 'evening', 'night',
  'fajr', 'dhuhr', 'asr', 'maghrib', 'isha', 'duha', 'witr', 'tahajjud',
  'friday', 'monday', 'thursday', 'quit', 'stop', 'no', 'not', 'less',
  'reduce', 'without', 'memorize', 'memorise', 'memorization',
  'memorisation', 'review', 'tafsir', 'weekly', 'monthly',
};

/// Names that are one habit, in Arabic and English, each group keyed by
/// one id. Written the way people type them; they go through the same
/// steps as any name before they are compared (see [_sameHabitIndex]).
/// Kept short on purpose: a wrong entry here would link two different
/// habits for everyone.
const Map<String, List<String>> _sameHabit = {
  'fajr': ['صلاة الفجر', 'الفجر', 'Fajr', 'Fajr Prayer'],
  'dhuhr': ['صلاة الظهر', 'الظهر', 'Dhuhr', 'Zuhr', 'Dhuhr Prayer'],
  'asr': ['صلاة العصر', 'العصر', 'Asr', 'Asr Prayer'],
  'maghrib': ['صلاة المغرب', 'المغرب', 'Maghrib', 'Maghrib Prayer'],
  'isha': ['صلاة العشاء', 'العشاء', 'Isha', 'Isha Prayer'],
  // Not «ركعتا الفجر»: «ركعتا» is filler (see [_filler]), so it would read
  // as just «الفجر», the obligatory prayer. [sameHabitTableConflicts]
  // catches that kind of slip.
  'sunnah_fajr': [
    'سنة الفجر', 'راتبة الفجر', 'Fajr Sunnah', 'Sunnah of Fajr',
    'Sunnah Fajr', //
  ],
  'duha': ['صلاة الضحى', 'الضحى', 'Duha', 'Duha Prayer', 'Dhuha'],
  'witr': ['صلاة الوتر', 'الوتر', 'Witr', 'Witr Prayer'],
  'tahajjud': [
    'صلاة التهجد', 'التهجد', 'قيام الليل', 'صلاة الليل', 'Tahajjud',
    'Tahajjud Prayer', 'Qiyam', 'Qiyam al-Layl', 'Night Prayer', //
  ],
  'morning_adhkar': [
    'أذكار الصباح', 'Morning Adhkar', 'Morning Athkar', 'Morning Azkar',
    'Morning Dhikr', //
  ],
  'evening_adhkar': [
    'أذكار المساء', 'Evening Adhkar', 'Evening Athkar', 'Evening Azkar',
    'Evening Dhikr', //
  ],
  'quran_reading': [
    'قراءة القرآن', 'ورد القرآن', 'تلاوة القرآن', 'ورد القرآن اليومي',
    'Quran', 'Quran Reading', 'Read Quran', 'Quran Daily Page', //
  ],
  'quran_memorization': [
    'حفظ القرآن', 'Quran Memorization', 'Memorize Quran', //
  ],
  'mulk': ['سورة الملك', 'Surah Al-Mulk', 'Al-Mulk', 'Mulk'],
  'kahf': ['سورة الكهف', 'Surah Al-Kahf', 'Al-Kahf', 'Kahf'],
  'sadaqah': ['الصدقة', 'صدقة يومية', 'Sadaqah', 'Charity', 'Daily Sadaqah'],
  'monday_thursday_fast': [
    'صيام الاثنين والخميس', 'Monday & Thursday Fast',
    'Monday and Thursday Fasting', //
  ],
  'istighfar': ['الاستغفار', 'Istighfar'],
};

/// Which catalog habit (islamic_habit_catalog.dart) each [_sameHabit] group
/// is, so a plan entry named any of those ways finds this person's copy of
/// the catalog habit even after they renamed it.
const Map<String, String> _sameHabitCatalogId = {
  'fajr': 'prayer_fajr',
  'dhuhr': 'prayer_dhuhr',
  'asr': 'prayer_asr',
  'maghrib': 'prayer_maghrib',
  'isha': 'prayer_isha',
  'tahajjud': 'tahajjud',
  'morning_adhkar': 'morning_athkar',
  'evening_adhkar': 'evening_athkar',
  'quran_reading': 'quran_daily_page',
  'quran_memorization': 'quran_memorization',
  'sadaqah': 'daily_sadaqah',
  'monday_thursday_fast': 'sunnah_fasting',
};

/// One word with the article (and a preposition glued to it) cut off, then
/// written its usual way (see [_sameWord]).
String _word(String w) {
  for (final p in _gluedPrefixes) {
    if (w.startsWith(p) && w.length - p.length >= 2) {
      w = w.substring(p.length);
      break;
    }
  }
  return _sameWord[w] ?? w;
}

/// The words of an already normalized name that say which habit it is:
/// [_filler] and [_joining] words dropped. When that leaves nothing (a
/// plan entry called just «القراءة»), the name's own words are kept, so a
/// name is never compared as empty.
List<String> _coreWords(String normalized) {
  final words = [
    for (final w in normalized.split(' '))
      if (w.isNotEmpty) _word(w),
  ];
  final core = [
    for (final w in words)
      if (!_filler.contains(w) && !_joining.contains(w)) w,
  ];
  return core.isEmpty ? words : core;
}

/// [_sameHabit], looked up by a name's core words in their order. A key two
/// groups share is left out entirely rather than given to either: two
/// different habits that read alike are exactly what must never be guessed.
final Map<String, String> _sameHabitIndex = () {
  final index = <String, String>{};
  final shared = sameHabitTableConflicts().toSet();
  _sameHabit.forEach((id, names) {
    for (final name in names) {
      final key = _coreWords(normalizeHabitText(name)).join(' ');
      if (!shared.contains(key)) index[key] = id;
    }
  });
  return index;
}();

/// The keys two different [_sameHabit] groups both produce once filler is
/// dropped. Should always be empty; a test holds it to that, because the
/// clash only shows up as two habits quietly treated as one.
List<String> sameHabitTableConflicts() {
  final owner = <String, String>{};
  final clashes = <String>{};
  _sameHabit.forEach((id, names) {
    for (final name in names) {
      final key = _coreWords(normalizeHabitText(name)).join(' ');
      final before = owner[key];
      if (before != null && before != id) clashes.add(key);
      owner[key] = before ?? id;
    }
  });
  return clashes.toList();
}

String? _sameHabitIdOf(List<String> core) => _sameHabitIndex[core.join(' ')];

/// How many single-letter edits turn [a] into [b].
int habitNameEditDistance(String a, String b) {
  final la = a.length, lb = b.length;
  if (la == 0) return lb;
  if (lb == 0) return la;
  var prev = List<int>.generate(lb + 1, (j) => j);
  var curr = List<int>.filled(lb + 1, 0);
  for (var i = 1; i <= la; i++) {
    curr[0] = i;
    for (var j = 1; j <= lb; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      curr[j] = min(min(curr[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
    }
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[lb];
}

/// How sure it is that [a] and [b] name the same habit: one of the kHabit*
/// levels above, a typo score below [kHabitMatchTypo], or 0 for no guess.
int habitNameMatchScore(String a, String b) {
  final na = normalizeHabitText(a);
  final nb = normalizeHabitText(b);
  if (na.isEmpty || nb.isEmpty) return 0;
  if (na == nb) return kHabitMatchExact;

  final ca = _coreWords(na);
  final cb = _coreWords(nb);
  final ida = _sameHabitIdOf(ca);
  final idb = _sameHabitIdOf(cb);
  if (ida != null && ida == idb) return kHabitMatchSameHabit;
  // Two habits this file knows, and they are different ones («صلاة الفجر»
  // and «سنة الفجر»): no amount of shared words makes them one.
  if (ida != null && idb != null) return 0;

  final sa = ca.toSet();
  final sb = cb.toSet();
  if (sa.length == sb.length && sa.containsAll(sb)) {
    return kHabitMatchSameWords;
  }
  final small = sa.length <= sb.length ? sa : sb;
  final big = identical(small, sa) ? sb : sa;
  if (big.containsAll(small)) {
    final extra = big.difference(small);
    if (extra.length <= 3 &&
        !extra.any(_changesMeaning.contains) &&
        small.any((w) => w.length >= 3)) {
      return kHabitMatchExtraWords;
    }
    // Every word of one is in the other, so what is left is a word that
    // changes the habit: no typo rule can make them one.
    return 0;
  }

  // A typo, judged on the words that matter. A word that changes the habit
  // on one side only is never a typo («سنه» or «ترك» added or missing).
  final onlyOneSide = sa.difference(sb).union(sb.difference(sa));
  if (onlyOneSide.any(_changesMeaning.contains) &&
      !_bothHaveTypoOf(sa, sb)) {
    return 0;
  }
  // The words that matter, or the whole names when those are too short to
  // judge a typo on («ضحي» is three letters): the old rule's length floor.
  var ja = ca.join(' ');
  var jb = cb.join(' ');
  if (ja.length < 4 || jb.length < 4) {
    ja = na;
    jb = nb;
  }
  if (ja.length < 4 || jb.length < 4) return 0;
  final distance = habitNameEditDistance(ja, jb);
  final allowed = (min(ja.length, jb.length) * 0.25).ceil().clamp(1, 3);
  if (distance > allowed) return 0;
  return max(1, kHabitMatchTypo - distance);
}

/// Whether every word that differs between [a] and [b] is one letter away
/// from a word on the other side: a misspelt «الضجى» for «الضحى» still
/// reads as the same prayer, where «الظهر» for «العصر» does not.
bool _bothHaveTypoOf(Set<String> a, Set<String> b) {
  final onlyA = a.difference(b);
  final onlyB = b.difference(a);
  if (onlyA.length != onlyB.length) return false;
  for (final w in onlyA) {
    if (!onlyB.any((v) => w.length >= 3 && habitNameEditDistance(w, v) == 1)) {
      return false;
    }
  }
  return true;
}

/// The catalog habit [name] names (islamic_habit_catalog.dart), by its
/// English or Arabic catalog name or any [_sameHabit] name for it, or null.
String? catalogHabitIdFor(String name) {
  final normalized = normalizeHabitText(name);
  if (normalized.isEmpty) return null;
  for (final t in IslamicHabitCatalog.templates) {
    if (normalizeHabitText(t.name) == normalized) return t.id;
    final ar = t.nameAr;
    if (ar != null && normalizeHabitText(ar) == normalized) return t.id;
  }
  final same = _sameHabitIdOf(_coreWords(normalized));
  return same == null ? null : _sameHabitCatalogId[same];
}

/// The habit in [myHabits] a plan entry named [planName] most likely is,
/// or null when none is a safe guess. Compares against each habit's name
/// and its Arabic name; a catalog habit also matches by its id
/// ([catalogHabitIdFor]), so renaming a preset does not hide it. The
/// surest match wins, and between equally sure ones the habit that comes
/// first (the person's own order).
IslamicHabitTemplate? bestHabitMatch(
  String planName,
  List<IslamicHabitTemplate> myHabits,
) {
  final catalogId = catalogHabitIdFor(planName);
  IslamicHabitTemplate? best;
  var bestScore = 0;
  for (final h in myHabits) {
    final score = _scoreHabit(planName, h, catalogId);
    if (score > bestScore) {
      best = h;
      bestScore = score;
    }
  }
  return best;
}

/// How sure it is that [h] is the plan entry [planName]: its name, its
/// Arabic name, and (for a catalog habit) its id through [catalogId], the
/// entry's own [catalogHabitIdFor].
int _scoreHabit(String planName, IslamicHabitTemplate h, String? catalogId) {
  var score = habitNameMatchScore(planName, h.name);
  final ar = h.nameAr;
  if (ar != null && ar.trim().isNotEmpty) {
    score = max(score, habitNameMatchScore(planName, ar));
  }
  if (catalogId != null && h.id == catalogId) {
    score = max(score, kHabitMatchCatalog);
  }
  return score;
}

/// What one row of a room's plan should open on: [habitId] to pre-select,
/// or null for "add as new". When it is null because two or more of this
/// person's habits fit the entry EQUALLY well, [tornBetween] names them
/// (ids, in the person's own order), so the row can say so and list them
/// first rather than guess.
class PlanMatch {
  const PlanMatch(this.habitId, [this.tornBetween = const []]);

  final String? habitId;
  final List<String> tornBetween;

  bool get isTorn => tornBetween.isNotEmpty;
}

/// The whole plan's suggestions at once, one [PlanMatch] per entry of
/// [planNames] (null for an entry that is not asked about, such as a slot
/// the leader removed). [taken] are habits already filling some slot, which
/// no row may be offered.
///
/// Aziz, 2026-09-24: "maybe conflict, so the system needs to know which one
/// is the correct, and no mistakes". Two conflicts, two answers:
///
///  * Two rows want the same habit («الضحى» and «صلاة الضحى» in one plan,
///    one «صلاة الضحى» in the person's list): the surest pair in the whole
///    plan is settled first, so the habit goes to the row it matches best,
///    not to whichever row is listed first, and the other row moves on to
///    its next choice.
///  * One row fits two habits equally (a «صلاة الضحى» and a «الضحى ركعتين»,
///    both the Duha prayer): nothing is pre-selected. Picking either would
///    be a coin toss the person might not notice; the row asks instead.
///
/// A habit is never suggested for two rows.
List<PlanMatch> suggestPlanMatches(
  List<String?> planNames,
  List<IslamicHabitTemplate> myHabits, {
  Set<String> taken = const {},
}) {
  final habits = [
    for (final h in myHabits)
      if (!taken.contains(h.id)) h,
  ];
  final scores = [
    for (final name in planNames)
      if (name == null)
        List<int>.filled(habits.length, 0)
      else
        () {
          final catalogId = catalogHabitIdFor(name);
          return [for (final h in habits) _scoreHabit(name, h, catalogId)];
        }(),
  ];
  final result = List<PlanMatch>.filled(planNames.length, const PlanMatch(null));
  final settled = List<bool>.filled(planNames.length, false);
  // A habit given to a row, or held back for a row that is torn over it:
  // either way no other row is offered it. Holding a torn row's habits back
  // keeps a weaker row from quietly taking one of them.
  final off = <int>{};
  while (true) {
    var best = 0;
    for (var r = 0; r < scores.length; r++) {
      if (settled[r]) continue;
      for (var h = 0; h < habits.length; h++) {
        if (!off.contains(h) && scores[r][h] > best) best = scores[r][h];
      }
    }
    if (best == 0) break;
    List<int> atBest(int r) => [
          for (var h = 0; h < habits.length; h++)
            if (!off.contains(h) && scores[r][h] == best) h,
        ];
    // Among the rows this sure of something, one with a single clear habit
    // is settled before one torn between several (the torn row may be left
    // with one choice once the clear rows have taken theirs); between
    // equals, the earlier row, so the outcome depends on nothing but the
    // two lists.
    int? clearRow;
    int? tornRow;
    for (var r = 0; r < scores.length; r++) {
      if (settled[r]) continue;
      final options = atBest(r);
      if (options.length == 1) {
        clearRow = r;
        break;
      }
      if (options.length > 1) tornRow ??= r;
    }
    if (clearRow != null) {
      final h = atBest(clearRow).single;
      result[clearRow] = PlanMatch(habits[h].id);
      settled[clearRow] = true;
      off.add(h);
      continue;
    }
    final r = tornRow!;
    final options = atBest(r);
    result[r] = PlanMatch(null, [for (final h in options) habits[h].id]);
    settled[r] = true;
    off.addAll(options);
  }
  return result;
}
