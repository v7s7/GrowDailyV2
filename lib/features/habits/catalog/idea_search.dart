import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/habit_model.dart';
import 'habit_ideas.dart';

/// The ideas page's search (Aziz, 2026-10-03: "make the search in habit
/// when user want to find ideas, smart, and useful, fuzzy search"). The old
/// one kept an idea only when its name or card line held the typed text as
/// it was typed, so «صلاه» missed «صلاة», «القران» missed «القرآن», "smokng"
/// found nothing and «سجائر» never reached «بدون تدخين». This one:
///
/// - reads Arabic the way people type it ([normalizeSearchText]): no harakat
///   or tatweel, «ا» for «أ إ آ», «ه» for «ة», «ي» for «ى», the Gulf «گ» as
///   «ق», «١٠» as 10; and «ال» or a joined «و ب ل ف ك» does not stop a match;
/// - takes the words in any order, each one whole, the start of a word (as
///   it is being typed) or another form of it (walking, walk);
/// - knows other words for the same thing ([_concepts]): «سجائر», «شيشة» and
///   "vape" find «بدون تدخين», «انستا» finds less scrolling, and an idea's
///   category answers to its name and a few more ([_categoryWords]);
/// - forgives a typo or two in a longer word, but only when nothing matches
///   without one, so «صيام» never also lists «قيام الليل»;
/// - drops the words that only say what the page already knows («ابي»,
///   «عادة», «بدون», «ترك», "habit", "quit") while other words remain;
/// - when no idea has every word, shows the ones with the most;
/// - puts the best first: a hit in the name before one in the card's line,
///   and those before one only in the text behind the idea, which is shown
///   only when nothing nearer matches.
///
/// Pure Dart and built once per list ([IdeaSearch.new]); a search over the
/// 86 built-in ideas takes well under a frame.
class IdeaSearch {
  IdeaSearch(List<ShownIdea> ideas)
      : _entries = [
          for (var k = 0; k < ideas.length; k++) _Entry(ideas[k], k),
        ];

  final List<_Entry> _entries;

  /// The ideas that answer [query], best first. Every idea, in its own
  /// order, when [query] holds no word at all (only marks or spaces).
  List<ShownIdea> search(String query) {
    final words = _queryWords(query);
    if (words.isEmpty) return [for (final e in _entries) e.shown];
    final forms = [for (final w in words) _queryForms(w)];
    final whole = normalizeSearchText(query);
    final hits = <_Hit>[
      for (final e in _entries)
        if (e.match(forms, whole) case final _Hit hit) hit,
    ];
    if (hits.isEmpty) return const [];
    // Every word when any idea has them all, else the most any idea has;
    // then only the surest kind of match among those.
    final most = hits.map((h) => h.matched).reduce(math.max);
    final kept = [
      for (final h in hits)
        if (h.matched == most) h,
    ];
    final tier = kept.map((h) => h.tier).reduce(math.min);
    kept.removeWhere((h) => h.tier != tier);
    kept.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      if (a.entry.shown.featured != b.entry.shown.featured) {
        return a.entry.shown.featured ? -1 : 1;
      }
      return a.entry.order.compareTo(b.entry.order);
    });
    return [for (final h in kept) h.entry.shown];
  }
}

/// [text] as the search compares it: lower case; harakat, tatweel and
/// Quranic marks gone; «أ إ آ ٱ» → «ا», «ة» → «ه», «ى ئ» → «ي», «ؤ» → «و»;
/// the Persian and Gulf letters people type for Arabic ones («گ» → «ق»,
/// «چ» → «ك», «ک» → «ك», «ی» → «ي», «ڤ» → «ف», «پ» → «ب»); Arabic-Indic
/// digits as 0-9; a letter typed three or more times in a row as one
/// («صلااااه»); and everything that is not a letter or a digit a space, so
/// "late-night" is two words and «ﷺ» none.
@visibleForTesting
String normalizeSearchText(String text) {
  final chars = <int>[];
  for (final rune in text.toLowerCase().runes) {
    var c = rune;
    if (_isMark(c)) continue;
    if (c == 0x27 || c == 0x2019 || c == 0x60) continue; // don't → dont
    c = _letterFor[c] ?? c;
    if (c >= 0x0660 && c <= 0x0669) c = 0x30 + c - 0x0660;
    if (c >= 0x06F0 && c <= 0x06F9) c = 0x30 + c - 0x06F0;
    chars.add(_isWordChar(c) ? c : 0x20);
  }
  final out = StringBuffer();
  for (var i = 0; i < chars.length;) {
    final c = chars[i];
    var j = i;
    while (j < chars.length && chars[j] == c) {
      j++;
    }
    // One space for any gap; a letter typed three or more times as one.
    final keep = c == 0x20 ? 1 : (j - i >= 3 && !_isDigit(c) ? 1 : j - i);
    for (var k = 0; k < keep; k++) {
      out.writeCharCode(c);
    }
    i = j;
  }
  return out.toString().trim();
}

/// The words of [text] after [normalizeSearchText].
List<String> _words(String text) => [
      for (final w in normalizeSearchText(text).split(' '))
        if (w.isNotEmpty) w,
    ];

bool _isMark(int c) =>
    (c >= 0x064B && c <= 0x065F) || // harakat, shadda, sukun
    c == 0x0670 || // superscript alef
    (c >= 0x06D6 && c <= 0x06ED) || // Quranic marks
    c == 0x0640 || // tatweel
    (c >= 0x0300 && c <= 0x036F) || // Latin combining accents
    c == 0x200C ||
    c == 0x200D ||
    c == 0x200E ||
    c == 0x200F;

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

bool _isWordChar(int c) =>
    _isDigit(c) ||
    (c >= 0x61 && c <= 0x7A) || // a-z (already lower case)
    (c >= 0xE0 && c <= 0xFF && c != 0xF7) || // é, ü ...
    (c >= 0x0621 && c <= 0x064A) || // Arabic letters
    (c >= 0x0671 && c <= 0x06D3); // Persian and Urdu letters

const Map<int, int> _letterFor = {
  0x0623: 0x0627, // أ → ا
  0x0625: 0x0627, // إ → ا
  0x0622: 0x0627, // آ → ا
  0x0671: 0x0627, // ٱ → ا
  0x0629: 0x0647, // ة → ه
  0x0649: 0x064A, // ى → ي
  0x0626: 0x064A, // ئ → ي
  0x0624: 0x0648, // ؤ → و
  0x06AF: 0x0642, // گ → ق (Gulf: «گهوة» for «قهوة»)
  0x0686: 0x0643, // چ → ك (Gulf: «چاي»)
  0x06A9: 0x0643, // ک → ك
  0x06CC: 0x064A, // ی → ي
  0x06A4: 0x0641, // ڤ → ف
  0x067E: 0x0628, // پ → ب
};

/// The joined article forms, longest first: «والصلاة» and «بالقرآن» are
/// found by «صلاة» and «قرآن».
const _articles = ['وال', 'بال', 'كال', 'فال', 'ال', 'لل'];

/// [w] without a leading article, or null when it has none (or too little
/// would be left).
String? _withoutArticle(String w) {
  for (final a in _articles) {
    if (w.startsWith(a) && w.length - a.length >= 2) {
      return w.substring(a.length);
    }
  }
  return null;
}

/// The forms an idea's word is indexed under: itself, without its article,
/// and without one joined «و ب ل ف ك» («لأهلك» under «اهلك»).
Iterable<String> _indexForms(String w) sync* {
  yield w;
  final bare = _withoutArticle(w);
  if (bare != null) yield bare;
  if (w.length >= 4 && 'وبلفك'.contains(w[0])) yield w.substring(1);
}

/// The forms a typed word is looked up by: itself and without its article.
/// Not without a single letter, which would turn «كتاب» into «تاب».
List<String> _queryForms(String w) {
  final bare = _withoutArticle(w);
  return bare == null ? [w] : [w, bare];
}

/// The typed words that count: [_stopWords] are dropped while any other
/// word is left (so «ابي اترك التدخين» searches «التدخين», but «تقليل» alone
/// still finds «تقليل الكافيين»).
List<String> _queryWords(String query) {
  final words = <String>[];
  for (final w in _words(query)) {
    if (!words.contains(w)) words.add(w);
  }
  final kept = [
    for (final w in words)
      if (!_stops.contains(w)) w,
  ];
  return kept.isEmpty ? words : kept;
}

final Set<String> _stops = {
  for (final w in _stopWords) ..._words(w),
};

/// Words that say nothing about which idea: the page is already about
/// habits, already on one side (build or quit), and every idea is daily or
/// near it.
const _stopWords = [
  // Arabic
  'في', 'من', 'على', 'الى', 'إلى', 'عن', 'مع', 'و', 'او', 'أو', 'ما', 'لا',
  'مو', 'اللي', 'الذي', 'التي', 'ان', 'أن', 'انا', 'أنا', 'اريد', 'أريد',
  'ابي', 'أبي', 'ابغى', 'أبغى', 'ابغي', 'ودي', 'بغيت', 'عادة', 'عادات',
  'عادتي', 'عاداتي', 'كل', 'يوم', 'يومي', 'يومية', 'يوميا', 'بدون', 'ترك',
  'اترك', 'أترك', 'قلل', 'اقلل', 'أقلل', 'تقليل', 'وقف', 'اوقف', 'أوقف',
  'توقف', 'ابطل', 'أبطل', 'بطل', 'اتخلص', 'أتخلص', 'تخلص', 'كيف', 'شي',
  'حق', 'اكثر', 'أكثر', 'اقل', 'أقل',
  // English
  'a', 'an', 'the', 'of', 'to', 'in', 'on', 'at', 'for', 'and', 'or', 'my',
  'me', 'i', 'im', 'want', 'wanna', 'need', 'habit', 'habits', 'daily',
  'day', 'every', 'each', 'no', 'not', 'dont', 'stop', 'quit', 'quitting',
  'less', 'reduce', 'without', 'more', 'how', 'get', 'some', 'better',
  'start',
];

/// Where in an idea a word was found, and what that is worth: a hit in the
/// name counts most; a typed start of a word or a match inside one only
/// where the field is short enough for it to mean something; typos only in
/// the name and the other words for it («سيام» met «السيارة» on a card
/// line and listed the podcast idea).
enum _Field {
  name(3.0, minQuery: 1, inside: true, typos: true),
  keyword(2.2, minQuery: 2, inside: false, typos: true),
  short(1.5, minQuery: 2, inside: false, typos: false),
  text(1.0, minQuery: 3, inside: false, typos: false);

  const _Field(
    this.weight, {
    required this.minQuery,
    required this.inside,
    required this.typos,
  });

  final double weight;

  /// The shortest typed word looked for here: one letter finds the names
  /// that start with it, never every idea with that letter in its text.
  final int minQuery;

  /// Whether a typed word inside a longer one counts («صدقة» in «والصدقة»).
  final bool inside;

  /// Whether a typo match is tried here.
  final bool typos;
}

/// One idea and its words, by field.
class _Entry {
  _Entry(this.shown, this.order) {
    final idea = shown.idea;
    final names = '${idea.nameAr} ${idea.nameEn}';
    _add(_Field.name, names);
    _add(_Field.short, '${idea.shortAr} ${idea.shortEn}');
    final text = [
      idea.benefitAr,
      idea.benefitEn,
      idea.sourceAr ?? '',
      idea.sourceEn ?? '',
      ...idea.waysAr,
      ...idea.waysEn,
    ];
    _add(_Field.text, text.join(' '));
    final nameWords = <String>{
      for (final w in _words(names)) ...[w, _withoutArticle(w) ?? w],
    };
    final nameText = ' ${normalizeSearchText(names)} ';
    final keywords = _byField[_Field.keyword]!;
    for (final c in _conceptIndex) {
      if (c.isIn(nameWords, nameText)) keywords.addAll(c.words);
    }
    keywords.addAll(_categoryIndex[idea.category] ?? const {});
    final ar = normalizeSearchText(idea.nameAr);
    _names = [
      ar,
      _withoutArticle(ar) ?? ar,
      normalizeSearchText(idea.nameEn),
    ];
  }

  final ShownIdea shown;
  final int order;
  final Map<_Field, Set<String>> _byField = {
    for (final f in _Field.values) f: <String>{},
  };
  late final List<String> _names;

  /// Every word of [text], stop words too: a search made only of them
  /// («تقليل», "less") still finds the names that start with one.
  void _add(_Field field, String text) {
    for (final w in _words(text)) {
      _byField[field]!.addAll(_indexForms(w));
    }
  }

  /// How this idea answers the typed words ([forms], one list of looked-up
  /// forms per word), or null when it answers none of them.
  _Hit? match(List<List<String>> forms, String whole) {
    var matched = 0;
    var tier = 0;
    var score = 0.0;
    for (final f in forms) {
      final best = _best(f);
      if (best == null) continue;
      matched++;
      score += best.score;
      tier = math.max(tier, best.tier);
    }
    if (matched == 0) return null;
    // Typing the name from its start: «صلاة الض» puts «صلاة الضحى» first.
    // Barely for one whole word, or "water" would put the plants before
    // drinking water.
    if (whole.isNotEmpty && _names.any((n) => n.startsWith(whole))) {
      score += whole.contains(' ') ? 1.5 : 0.3;
    }
    return _Hit(this, matched: matched, tier: tier, score: score);
  }

  /// The best place one typed word is found, by tier: 0 in the name, the
  /// other words for it or the card's line; 1 only in the text behind the
  /// idea; 2 only with a typo. The best field counts in full and every
  /// other field it is also in adds a little, so "water" ranks the idea
  /// it names AND means above the one it only names.
  ({double score, int tier})? _best(List<String> forms) {
    final byField = <_Field, double>{};
    for (final q in forms) {
      for (final field in _Field.values) {
        if (q.length < field.minQuery) continue;
        for (final w in _byField[field]!) {
          final m = _meet(q, w, field);
          if (m == 0) continue;
          final s = m * field.weight;
          if (s > (byField[field] ?? 0)) byField[field] = s;
        }
      }
    }
    final text = byField.remove(_Field.text) ?? 0;
    if (byField.isNotEmpty) {
      final near = byField.values.reduce(math.max);
      final rest = byField.values.fold(0.0, (a, b) => a + b) - near;
      return (score: near + 0.25 * rest + 0.1 * text, tier: 0);
    }
    if (text > 0) return (score: text, tier: 1);
    var typo = 0.0;
    for (final q in forms) {
      final allowed = _typosAllowed(q);
      if (allowed == 0) continue;
      for (final field in _Field.values) {
        if (!field.typos) continue;
        for (final w in _byField[field]!) {
          final d = _typoDistance(q, w, allowed);
          if (d == null) continue;
          final s = (0.5 - 0.1 * d) * field.weight;
          if (s > typo) typo = s;
        }
      }
    }
    return typo > 0 ? (score: typo, tier: 2) : null;
  }
}

/// How well typed word [q] meets an idea's word [w] in [field]: 1 for the
/// same word, 0.7 to 0.9 for its start (more as more of it is typed), 0.75
/// for another form of it, 0.6 inside a name word, and 0 when they do not
/// meet. Another form is [w] with up to three letters more ("walking" for
/// "walk", "prayers"; not "whatsapp" for "what"), or the two sharing a
/// start of five letters or more that is most of the shorter one
/// ("meditation" and "meditate", «استغفر» and «استغفار»; not "clean" and
/// "clear"). A number only meets itself or a word it starts with a letter
/// after: "10" finds "10pm", never "100".
double _meet(String q, String w, _Field field) {
  if (q == w) return 1;
  if (w.startsWith(q)) {
    if (_isAllDigits(q) && _isDigit(w.codeUnitAt(q.length))) return 0;
    return 0.7 + 0.2 * q.length / w.length;
  }
  if (w.length >= 4 && q.startsWith(w) && q.length - w.length <= 3) {
    return _isAllDigits(w) ? 0 : 0.75;
  }
  final shorter = math.min(q.length, w.length);
  final common = _commonStart(q, w);
  if (common >= 5 && common * 4 >= shorter * 3) return 0.75;
  if (field.inside && q.length >= 3 && w.contains(q)) return 0.6;
  return 0;
}

bool _isAllDigits(String s) => s.codeUnits.every(_isDigit);

int _commonStart(String a, String b) {
  final n = math.min(a.length, b.length);
  var k = 0;
  while (k < n && a.codeUnitAt(k) == b.codeUnitAt(k)) {
    k++;
  }
  return k;
}

/// Typos forgiven in a typed word: none under four letters (Arabic's
/// three-letter words sit one letter apart: «نوم», «يوم», «صوم»), one up to
/// seven, two from eight (two at seven made "smoking" "seeking"); none in a
/// number.
int _typosAllowed(String q) {
  if (q.codeUnits.any(_isDigit)) return 0;
  if (q.length >= 8) return 2;
  if (q.length >= 4) return 1;
  return 0;
}

/// The typos between [q] and [w], or between [q] and the start of [w] as
/// long as [q] (a word still being typed), when at most [max]; else null.
/// A four-letter word is never forgiven into a shorter one: «صدقة» is one
/// letter from «صدق», and charity is not honesty.
int? _typoDistance(String q, String w, int max) {
  if (q.length < 5 && w.length < q.length) return null;
  var d = _editDistance(q, w, max);
  if (w.length > q.length) {
    d = math.min(d, _editDistance(q, w.substring(0, q.length), max));
  }
  return d <= max ? d : null;
}

/// Edits from [a] to [b] (a letter added, dropped, changed, or two side by
/// side swapped), stopping early past [max] with max + 1.
int _editDistance(String a, String b, int max) {
  if ((a.length - b.length).abs() > max) return max + 1;
  if (a == b) return 0;
  final n = a.length;
  final m = b.length;
  var prev2 = List<int>.filled(m + 1, 0);
  var prev = List<int>.generate(m + 1, (j) => j);
  var cur = List<int>.filled(m + 1, 0);
  for (var i = 1; i <= n; i++) {
    cur[0] = i;
    var rowMin = cur[0];
    for (var j = 1; j <= m; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var v = math.min(
        math.min(prev[j] + 1, cur[j - 1] + 1),
        prev[j - 1] + cost,
      );
      if (i > 1 &&
          j > 1 &&
          a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
          a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
        v = math.min(v, prev2[j - 2] + 1);
      }
      cur[j] = v;
      if (v < rowMin) rowMin = v;
    }
    if (rowMin > max) return max + 1;
    final t = prev2;
    prev2 = prev;
    prev = cur;
    cur = t;
  }
  return prev[m];
}

class _Hit {
  _Hit(
    this.entry, {
    required this.matched,
    required this.tier,
    required this.score,
  });
  final _Entry entry;
  final int matched;
  final int tier;
  final double score;
}

/// One set of words for the same thing, ready to compare: an idea whose
/// name holds any of [_singles] or [_phrases] is found by every one of
/// [words].
class _Concept {
  _Concept(List<String> raw) {
    for (final entry in raw) {
      // «+» marks a word that finds the group's ideas but does not bring
      // the group to an idea that has it in its name.
      final onlyFinds = entry.startsWith('+');
      final ws = _words(onlyFinds ? entry.substring(1) : entry);
      if (ws.isEmpty) continue;
      if (onlyFinds) {
        // Nothing to bring the group by.
      } else if (ws.length == 1) {
        _singles.addAll(_indexForms(ws.single));
      } else {
        _phrases.add(' ${ws.join(' ')} ');
      }
      for (final w in ws) {
        if (!_stops.contains(w)) words.addAll(_indexForms(w));
      }
    }
  }

  final words = <String>{};
  final _singles = <String>{};
  final _phrases = <String>[];

  bool isIn(Set<String> nameWords, String nameText) =>
      nameWords.any(_singles.contains) || _phrases.any(nameText.contains);
}

final List<_Concept> _conceptIndex = [
  for (final c in _concepts) _Concept(c),
];

final Map<HabitCategory, Set<String>> _categoryIndex = {
  for (final c in HabitCategory.values)
    c: {
      for (final entry in [
        c.localizedName(true),
        c.localizedName(false),
        ...?_categoryWords[c],
      ])
        for (final w in _words(entry))
          if (!_stops.contains(w)) ..._indexForms(w),
    },
};

/// More words each category answers to, beside its own name in both
/// languages («الصحة», "Health").
const Map<HabitCategory, List<String>> _categoryWords = {
  HabitCategory.faith: [
    'دين', 'ديني', 'إسلام', 'عبادة', 'عبادات', 'روحاني', 'islam', 'islamic',
    'deen', 'religion', 'worship', 'ibadah', 'spiritual',
  ],
  HabitCategory.health: [
    'صحي', 'جسم', 'لياقة', 'healthy', 'body', 'fitness',
  ],
  HabitCategory.learning: [
    'تعلم', 'تعليم', 'علم', 'معرفة', 'ثقافة', 'learn', 'education',
    'knowledge',
  ],
  HabitCategory.focus: [
    'إنتاجية', 'عمل', 'شغل', 'productivity', 'productive', 'work',
  ],
  HabitCategory.sleep: ['نايم', 'asleep'],
  HabitCategory.money: ['فلوس', 'مالي', 'finance', 'financial'],
  HabitCategory.mind: [
    'نفسية', 'نفسي', 'راحة', 'mental', 'wellbeing', 'peace',
  ],
  HabitCategory.social: [
    'اجتماعي', 'ناس', 'relationships', 'people',
  ],
  HabitCategory.custom: ['بيت', 'روتين', 'home', 'routine', 'other'],
};

/// Other words for the same thing, Arabic (written and spoken, Gulf
/// included) and English together, so either finds the idea in either
/// language. A group reaches an idea through its NAME only (a word, or a
/// phrase of several, in either language): a card line or a hadith is too
/// wide a net. A word that also names something else either stays out or
/// is marked «+» (it finds the group's ideas, never brings the group):
/// "bed" and «سرير» (the made bed is not sleep), "water" (the plants),
/// «تمارين» and "exercise" (stretching and breathing are not the gym),
/// «مراجعة» (the budget is not studying), «ورد» (the Quran wird is not
/// flowers), «موعد» (bedtime is not a meeting), "compare" (prices are not
/// envy), "late" (late naps are not punctuality), "phone call" (a call is
/// not the phone ideas).
const List<List<String>> _concepts = [
  // Faith
  [
    'quran', 'koran', 'quraan', 'surah', 'surat', 'juz', 'recite',
    'recitation', 'mushaf', 'قرآن', 'مصحف', 'تلاوة', 'ختمة', 'سورة', 'جزء',
    'تجويد', 'حفظ',
  ],
  [
    'prayer', 'prayers', 'pray', 'salah', 'salat', 'namaz', 'mosque',
    'masjid', 'صلاة', 'صلوات', 'فرض', 'فروض', 'مسجد', 'جماعة',
  ],
  ['night prayer', 'tahajjud', 'qiyam', 'witr', 'قيام الليل', 'تهجد', 'وتر'],
  [
    'athkar', 'adhkar', 'azkar', 'dhikr', 'zikr', 'tasbih', 'remembrance',
    'أذكار', 'ذكر', 'تسبيح', 'سبحان', 'حصن المسلم',
  ],
  ['dua', 'duaa', 'supplication', 'دعاء', 'أدعية'],
  [
    'istighfar', 'forgiveness', 'repentance', 'astaghfirullah', 'استغفار',
    'استغفر', 'توبة',
  ],
  [
    'charity', 'sadaqah', 'sadaqa', 'donate', 'donation', 'zakat', 'giving',
    'صدقة', 'تبرع', 'إنفاق', 'زكاة',
  ],
  ['fast', 'fasting', 'sawm', 'siyam', 'صيام', 'صوم', 'صائم'],
  [
    'sunnah prayers', 'rawatib', 'nafl', 'nawafil', 'السنن', 'رواتب', 'نوافل',
    'سنة',
  ],
  [
    'blessings on the prophet', 'salawat', 'durood', 'darood', 'الصلاة على النبي',
    'صلوات', 'محمد',
  ],
  ['lying', 'lie', 'lies', 'honest', 'honesty', 'truth', 'كذب', 'صدق', 'صادق'],
  ['backbiting', 'gossip', 'غيبة', 'نميمة', 'حش'],
  [
    'cursing', 'curse', 'swear', 'swearing', 'insult', 'insults', 'لعن', 'سب',
    'شتم', 'ألفاظ',
  ],
  ['fajr', 'dawn', 'فجر', 'صبح'],
  // Health
  ['walk', 'walking', 'steps', 'stroll', 'مشي', 'امشي', 'تمشية', 'خطوات'],
  [
    'gym', '+exercise', 'workout', 'sport', 'sports', 'fitness', 'training',
    'رياضة', '+تمارين', '+تمرين', 'جيم', 'نادي', 'حديد',
  ],
  [
    'stretch', 'stretching', 'yoga', 'flexibility', 'إطالة', 'تمدد', 'يوغا',
    'مرونة',
  ],
  [
    'drink water', 'hydrate', 'hydration', 'شرب الماء', 'ماء', 'مويه', 'موية',
    'ترطيب',
  ],
  [
    'fruit', 'fruits', 'vegetables', 'vegetable', 'veggies', 'salad',
    'healthy food', 'diet', 'خضار', 'خضروات', 'فواكه', 'فاكهة', 'سلطة',
    'أكل صحي', 'دايت', 'رجيم',
  ],
  [
    'sugar', 'sweets', 'dessert', 'desserts', 'candy', 'chocolate', 'سكر',
    'حلويات', 'شوكولاتة', 'شوكلت',
  ],
  [
    'junk food', 'fast food', 'burger', 'pizza', 'fries', 'أكل سريع',
    'وجبات سريعة', 'برغر', 'بيتزا', 'مطاعم',
  ],
  [
    'caffeine', 'coffee', 'tea', 'espresso', 'energy drink', 'كافيين', 'قهوة',
    'شاي', 'چاي', 'نسكافيه', 'ريدبول',
  ],
  ['cafe', 'cafes', 'starbucks', 'كوفي', 'كافيه', 'مقهى', 'ستاربكس'],
  ['snack', 'snacks', 'snacking', 'سناك', 'وجبات خفيفة', 'وجبات ليلية'],
  [
    'smoking', 'smoke', 'cigarette', 'cigarettes', 'vape', 'vaping', 'shisha',
    'hookah', 'tobacco', 'nicotine', 'تدخين', 'دخان', 'سجائر', 'سيجارة',
    'زقارة', 'زقاير', 'شيشة', 'فيب', 'معسل', 'تبغ', 'نيكوتين',
  ],
  // Learning
  [
    'read', 'reading', 'book', 'books', 'pages', 'قراءة', 'اقرأ', 'كتاب',
    'كتب', 'صفحات', 'مطالعة',
  ],
  [
    'study', 'studying', 'revision', 'revise', 'review notes', 'exam',
    'exams', 'test', 'tests', 'school', 'university', 'college', 'homework',
    'دراسة', 'مذاكرة', 'ذاكر', 'أذاكر', 'اختبار', 'اختبارات', 'امتحان',
    'امتحانات', 'جامعة', 'مدرسة', 'واجب', 'واجبات',
  ],
  [
    'language', 'languages', 'english', 'french', 'vocabulary', 'duolingo',
    'لغة', 'لغات', 'إنجليزي', 'انقليزي', 'فرنسي', 'كلمات',
  ],
  [
    'podcast', 'podcasts', 'audiobook', 'audiobooks', 'listen', 'listening',
    'بودكاست', 'كتاب صوتي', 'صوتي', 'استماع',
  ],
  // Focus
  [
    'focus', 'concentrate', 'concentration', 'deep work', 'productivity',
    'productive', 'تركيز', 'إنتاجية', 'إنجاز', 'شغل', 'عمل مركز',
  ],
  ['distraction', 'distractions', 'distracted', 'تشتت', 'تشتيت', 'ملهيات'],
  [
    'plan', 'planning', 'to do', 'todo', 'priorities', 'schedule', 'تخطيط',
    'خطة', 'مهام', 'أولويات', 'جدول', 'قائمة',
  ],
  [
    'phone', 'mobile', 'cellphone', 'iphone', 'screen', 'screens',
    'screen time', 'تلفون', 'تليفون', 'جوال', 'موبايل', 'هاتف', 'شاشة',
    'شاشات', 'ايفون',
  ],
  [
    'social media', 'scrolling', 'scroll', 'instagram', 'insta', 'tiktok',
    'snapchat', 'snap', 'twitter', 'youtube', 'reels', 'facebook', 'سوشال',
    'سوشيال', 'سوشل', 'تواصل اجتماعي', 'تصفح', 'انستقرام', 'انستا', 'تيك توك',
    'تيكتوك', 'سناب', 'تويتر', 'يوتيوب', 'ريلز', 'فيسبوك',
  ],
  [
    'games', 'gaming', 'video games', 'playstation', 'ps5', 'xbox', 'fortnite',
    'ألعاب', 'لعب', 'بلايستيشن', 'بلي', 'سوني', 'قيمز',
  ],
  // Sleep
  [
    'sleep', 'bedtime', 'asleep', 'insomnia', 'نوم', 'أنام', '+سرير', '+فراش',
    'أرق',
  ],
  [
    'wake', 'wake up', 'waking', 'early', 'alarm', 'snooze', 'snoozing',
    'صحيان', 'استيقاظ', 'أصحى', 'بدري', 'مبكر', 'منبه',
  ],
  ['nap', 'naps', 'napping', 'قيلولة', 'غفوة'],
  // Money
  [
    'money', 'spending', 'spend', 'expenses', 'budget', 'finance',
    'finances', 'salary', 'save', 'saving', 'savings', 'فلوس', 'مال',
    'مصروف', 'مصاريف', 'مصروفات', 'ميزانية', 'راتب', 'ادخار', 'توفير',
    'وفر',
  ],
  [
    'shopping', 'shop', 'buy', 'buying', 'purchase', 'amazon', 'shein',
    'prices', 'price', 'discount', 'sale', 'تسوق', 'شراء', 'اشتري',
    'مشتريات', 'أونلاين', 'أمازون', 'شي ان', 'أسعار', 'خصم', 'عروض',
  ],
  [
    'delivery', 'takeout', 'takeaway', 'talabat', 'deliveroo', 'jahez',
    'توصيل', 'طلبات', 'دليفري', 'جاهز', 'كيتا',
  ],
  // Mind
  [
    'meditate', 'meditation', 'mindfulness', 'mindful', 'calm', 'relax',
    'relaxation', 'تأمل', 'هدوء', 'استرخاء', 'صفاء', 'راحة بال', '+stress',
    '+anxiety', '+قلق', '+توتر',
  ],
  [
    'gratitude', 'grateful', 'thankful', 'thanks', 'journal', 'journaling',
    'diary', 'شكر', 'امتنان', 'الحمد', 'يوميات', 'مذكرات',
  ],
  [
    'breathing', 'breath', 'breathe', 'تنفس', 'نفس عميق', '+stress',
    '+anxiety', '+قلق', '+توتر',
  ],
  [
    'overthinking', 'stress', 'anxiety', 'anxious', 'worry', 'worried',
    'تفكير زائد', 'قلق', 'توتر', 'ضغط',
  ],
  [
    'positive', 'affirmations', 'affirmation', 'motivation', 'self talk',
    'confidence', 'إيجابي', 'إيجابية', 'تحفيز', 'ثقة', 'عبارات',
  ],
  [
    'complain', 'complaining', 'complaints', 'negativity', 'تذمر', 'شكوى',
    'تشكي', 'سلبية',
  ],
  ['comparisons', 'comparison', 'envy', 'jealousy', 'مقارنات', 'حسد', 'غيرة'],
  ['news', 'headlines', 'أخبار', 'نشرة'],
  // Social
  [
    'family', 'parents', 'mom', 'mum', 'dad', 'mother', 'father',
    'relative', 'relatives', 'kin', 'عائلة', 'أهل', 'والدين', 'أمي', 'أبوي',
    'أقارب', 'صلة رحم', 'رحم', 'أسرة',
  ],
  [
    'friend', 'friends', 'friendship', 'buddy', 'صديق', 'أصدقاء', 'أصحاب',
    'ربع', 'خوي', 'رفيق',
  ],
  [
    'call', 'visit', 'contact', 'اتصال', 'مكالمة', 'اتصل', 'زيارة',
  ],
  [
    'dinner', 'lunch', 'meal', 'meals', 'table', 'عشاء', 'غداء', 'وجبة',
    'سفرة',
  ],
  [
    'argue', 'arguing', 'argument', 'debate', 'fight', 'comments', 'جدال',
    'نقاش', 'مناقشة', 'تعليقات', 'هوشة',
  ],
  [
    'group chats', 'whatsapp', 'chats', 'groups', 'قروبات', 'جروبات',
    'قروب', 'واتساب', 'واتس', 'رسائل', 'محادثات',
  ],
  ['interrupt', 'interrupting', 'مقاطعة', 'أقاطع', 'إنصات'],
  // Home and routine
  [
    'tidy', 'clean', 'cleaning', 'declutter', 'organize', 'chores', 'house',
    'ترتيب', 'تنظيف', 'تنظيم', 'بيت',
  ],
  [
    'plants', 'plant', 'garden', 'gardening', 'flowers', 'زرع', 'نباتات',
    'نبات', 'زراعة', 'حديقة',
  ],
  [
    'arriving late', 'punctual', 'punctuality', 'appointments', 'meetings',
    'مواعيد', 'دوام', 'اجتماع',
  ],
  [
    'procrastination', 'procrastinate', 'postpone', 'postponing', 'delay',
    'delaying', 'lazy', 'laziness', 'تسويف', 'تأجيل', 'كسل', 'تأخير',
  ],
  ['dishes', 'washing up', 'kitchen', 'صحون', 'مواعين', 'أطباق', 'مطبخ'],
];
