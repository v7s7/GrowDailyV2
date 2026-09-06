/// Recognises when a habit name means "walking" so the app can offer to
/// link it to the phone's step count, even when the name is misspelled,
/// in Arabic, in English, or phrased sideways ("stpes", "امشي شوي",
/// "morning walkk", "10k a day").
///
/// Detection is offer-only by design: a match shows the "link to steps?"
/// card in the habit editor with its switch already on, and files the
/// habit under Health. It never links silently and it never asks the OS
/// anything by itself, so the switch can still be turned off in one tap
/// before anything is written. That asymmetry sets the tuning: a false
/// positive costs one visible switch and, if nobody turns it off, one
/// permission prompt the card announced in words before it appeared. A
/// false negative hides the feature from exactly the person it was built
/// for. So matching stays generous, but not reckless; the stoplists below
/// exist because "work" and "waking" are one edit away from "walk"/
/// "walking" and are common habit words in their own right.
///
/// Kept as pure functions over strings so the whole thing is unit-testable
/// without a widget tree, a store, or platform channels.
library;

import 'text_moderation.dart' show foldArabic;
import 'western_digits.dart';

/// English tokens that mean walking/steps on their own. Matched exactly
/// (whole token) after normalisation.
const _latinExact = <String>{
  'walk', 'walks', 'walking', 'walked', 'walkin',
  'step', 'steps', 'stepcount',
  'jog', 'jogs', 'jogging',
  'run', 'runs', 'running',
  'hike', 'hikes', 'hiking',
  'stroll', 'strolling',
  'treadmill', 'pedometer',
};

/// Longer English keywords also matched at Damerau-Levenshtein distance 1,
/// so one-letter typos and transpositions ("wakling", "stpes", "runing")
/// still hit. Only words of 5+ letters take part: at 4 letters, distance 1
/// reaches too many real words ("walk" is one edit from "work" and "talk").
const _latinFuzzy = <String>{
  'walking', 'steps', 'jogging', 'running', 'hiking', 'stroll', 'treadmill',
};

/// Latin prefixes: any token starting with one of these matches, catching
/// the doubled-letter and dropped-g family ("walkk", "walkking", "runnin",
/// "stepss") that sits more than one edit from any full keyword. Stems are
/// chosen so no plausible habit word collides ("run" is not here because
/// of "runes"/"rundown"; "runn" is).
const _latinPrefixes = <String>['walk', 'step', 'jog', 'runn', 'hike', 'stroll'];

/// Real words that sit within distance 1 of a fuzzy keyword and must never
/// count as a match. "waking" (as in waking up early) is one edit from
/// "walking"; "stops" one from "steps"; "runnin'" style endings are fine
/// but "ruining" is one edit from "running".
const _latinStoplist = <String>{
  'waking', 'woken', 'stops', 'ruining', 'working', 'talking', 'taking',
  'sleep', 'sleeps', 'string', 'strong',
};

/// Arabic tokens (in [foldArabic]-folded form) matched exactly. Covers the
/// spoken forms actually typed in a habit name: امش، امشي، نمشي، تمشيت...
/// Folding upstream already collapses خطوة/خطوه and تمشية/تمشيه.
const _arabicExact = <String>{
  'مشي', 'امشي', 'امش', 'يمشي', 'نمشي', 'تمشي', 'تمشيه', 'مشيه', 'مشيت',
  'جري', 'اجري', 'يجري', 'نجري', 'ركض', 'اركض', 'يركض', 'هروله',
  'خطوه', 'خطوات', 'مشوار',
};

/// Arabic prefixes: any token starting with one of these is a match.
/// خطو catches خطواتي/خطوتين, تمش catches تمشيت/تمشينا. Kept to stems that
/// do not open onto unrelated words (مش would match مشروع, so it is not
/// here; the full مشي forms live in [_arabicExact] instead).
const _arabicPrefixes = <String>['خطو', 'تمش'];

/// Units that disqualify the number before them from being a step goal:
/// "walk 5 km" and "امش 30 دقيقه" are distance and time goals, not steps.
const _notStepUnits = <String>{
  'km', 'kms', 'كم', 'كيلو', 'كيلومتر', 'ميل', 'mi', 'miles', 'mile',
  'min', 'mins', 'minute', 'minutes', 'دقيقه', 'دقايق', 'دقائق',
  'ساعه', 'ساعات', 'hour', 'hours', 'hr', 'hrs', 'sec', 'seconds',
};

/// Units that explicitly mark the number before them as steps.
const _stepUnits = <String>{
  'step', 'steps', 'خطوه', 'خطوات',
};

/// "5 thousand (steps)" in either language multiplies by 1000.
const _thousandWords = <String>{'k', 'الف', 'الاف', 'ألف', 'thousand'};

/// Lowercased, Arabic-folded, ASCII-digit tokens of [name], with
/// everything that is not a letter or digit acting as a separator. A
/// leading Arabic definite article is stripped from longer tokens so
/// "المشي" matches the same entry as "مشي".
List<String> _tokens(String name) {
  final folded = foldArabic(toWesternDigits(name.toLowerCase()));
  final buffer = StringBuffer();
  for (final rune in folded.runes) {
    final isLatin = (rune >= 0x61 && rune <= 0x7A) || (rune >= 0x30 && rune <= 0x39);
    final isArabic = rune >= 0x0621 && rune <= 0x064A;
    // Keep a 'k' glued to digits ("10k") by keeping letters and digits;
    // everything else separates.
    buffer.write(isLatin || isArabic ? String.fromCharCode(rune) : ' ');
  }
  return buffer
      .toString()
      .split(' ')
      .where((t) => t.isNotEmpty)
      .map((t) => t.length > 4 && t.startsWith('ال') ? t.substring(2) : t)
      .toList();
}

/// Damerau-Levenshtein distance capped at 2: exact edit counts above the
/// cap are all the same to the caller, so the loop bails out early via the
/// band check. Small inputs only (habit-name tokens), so O(n*m) is fine.
int _damerau(String a, String b) {
  if ((a.length - b.length).abs() > 2) return 3;
  final rows = List.generate(
    a.length + 1,
    (i) => List<int>.filled(b.length + 1, 0),
  );
  for (var i = 0; i <= a.length; i++) {
    rows[i][0] = i;
  }
  for (var j = 0; j <= b.length; j++) {
    rows[0][j] = j;
  }
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      var best = rows[i - 1][j] + 1;
      if (rows[i][j - 1] + 1 < best) best = rows[i][j - 1] + 1;
      if (rows[i - 1][j - 1] + cost < best) best = rows[i - 1][j - 1] + cost;
      if (i > 1 &&
          j > 1 &&
          a[i - 1] == b[j - 2] &&
          a[i - 2] == b[j - 1] &&
          rows[i - 2][j - 2] + 1 < best) {
        best = rows[i - 2][j - 2] + 1;
      }
      rows[i][j] = best;
    }
  }
  return rows[a.length][b.length];
}

/// Whether [name] reads as a walking/steps habit in either language.
bool looksLikeStepHabit(String name) {
  final tokens = _tokens(name);
  for (final token in tokens) {
    if (_latinExact.contains(token) || _arabicExact.contains(token)) {
      return true;
    }
    if (_arabicPrefixes.any(token.startsWith)) return true;
    if (!_latinStoplist.contains(token) &&
        _latinPrefixes.any(token.startsWith)) {
      return true;
    }
    // "10k" alone is not enough to call something a walking habit; the
    // number parser handles it once a walking word is present.
    if (token.length >= 5 && !_latinStoplist.contains(token)) {
      for (final keyword in _latinFuzzy) {
        if (_damerau(token, keyword) <= 1) return true;
      }
    }
  }
  return false;
}

/// The step goal stated in [name], or null when the name does not state
/// one (or states a non-step goal like minutes or kilometres). "٨٠٠٠",
/// "10k", "٥ الاف خطوه" and "walk 6000" all parse; "walk 30 min" and
/// "امش 5 كيلو" return null on purpose.
int? parseStepGoal(String name) {
  final tokens = _tokens(name);
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    // "10k" glued together.
    final glued = RegExp(r'^(\d+)k$').firstMatch(token);
    if (glued != null) {
      return _sane(int.parse(glued.group(1)!) * 1000);
    }
    // "الف خطوه" with no digit: exactly one thousand.
    if (_thousandWords.contains(token) &&
        i + 1 < tokens.length &&
        _stepUnits.contains(tokens[i + 1])) {
      return 1000;
    }
    if (!RegExp(r'^\d+$').hasMatch(token)) continue;
    final value = int.parse(token);
    final next = i + 1 < tokens.length ? tokens[i + 1] : null;
    if (next != null && _notStepUnits.contains(next)) continue;
    if (next != null && _thousandWords.contains(next)) {
      return _sane(value * 1000);
    }
    if (next != null && _stepUnits.contains(next)) return _sane(value);
    // A bare number needs to be step-sized to count: "walk 30" is far more
    // likely thirty minutes than thirty steps.
    if (value >= 1000) return _sane(value);
  }
  return null;
}

/// Goals outside any plausible daily step range are treated as unstated.
int? _sane(int value) => (value >= 100 && value <= 100000) ? value : null;
