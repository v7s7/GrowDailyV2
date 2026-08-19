/// A deliberately small filter for the free text one user can put in front
/// of another: room names and display names.
///
/// Scope, stated plainly: this is the "filtering objectionable material"
/// half of App Review guideline 1.2, and it is the weakest of the three
/// mechanisms that guideline asks for. It catches lazy abuse — someone
/// typing a slur into a room name — and it will not catch a determined
/// person. That is why reporting and blocking exist alongside it rather
/// than instead of it: a filter is the lock on the door, reporting is what
/// you do when someone climbs through the window.
///
/// Matching is deliberately conservative, because a false positive here
/// silently refuses a name a real person chose, in their own language,
/// with no way for them to tell what was wrong. Substring matching would
/// do exactly that (the classic "Scunthorpe" failure), so every entry is
/// matched on WORD boundaries against a normalised copy of the input.
///
/// Arabic normalisation matters as much as the word list. The same word is
/// commonly written with or without diacritics, with أ/إ/آ for ا, ة for ه,
/// and ى for ي — so the text is folded before matching and one entry
/// covers all of those spellings instead of needing five.
library;

/// Latin entries. Lowercased, matched whole-word.
const _latin = <String>{
  'fuck', 'fucking', 'fuk', 'shit', 'bitch', 'cunt', 'whore', 'slut',
  'nigger', 'nigga', 'faggot', 'rape', 'rapist', 'porn', 'pornhub',
  'sex', 'sexy', 'nude', 'nudes', 'dick', 'cock', 'pussy', 'asshole',
  'kys', 'kill yourself', 'nazi', 'hitler', 'isis', 'daesh',
};

/// Arabic entries, written in their folded form (see [foldArabic]).
///
/// Includes religious insult specifically because this app's rooms are
/// built around صلاة and أذكار: a slur aimed at someone's practice is the
/// realistic abuse case here, far more than generic profanity.
const _arabic = <String>{
  'كس', 'كسمك', 'طيز', 'زب', 'شرموط', 'شرموطه', 'قحبه', 'عاهره',
  'خول', 'لوطي', 'منيك', 'متناك', 'زانيه', 'زاني',
  'كافر', 'كفار', 'ملحد', 'مرتد', 'نجس',
  'يلعن', 'لعنه', 'حقير', 'وسخ', 'خنزير', 'كلب',
  'داعش', 'صهيوني',
};

/// Folds the Arabic spelling variants that would otherwise each need their
/// own entry: strips diacritics and tatweel, and unifies alef, teh marbuta
/// and alef maksura.
String foldArabic(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    // Harakat (fatha..sukun), superscript alef, and tatweel carry no
    // information for matching and are commonly typed inconsistently.
    if ((rune >= 0x064B && rune <= 0x0652) || rune == 0x0670 || rune == 0x0640) {
      continue;
    }
    final ch = String.fromCharCode(rune);
    buffer.write(switch (ch) {
      'أ' || 'إ' || 'آ' || 'ٱ' => 'ا',
      'ة' => 'ه',
      'ى' => 'ي',
      'ؤ' => 'و',
      'ئ' => 'ي',
      _ => ch,
    });
  }
  return buffer.toString();
}

/// Everything that is not a letter or digit becomes a space, so that
/// punctuation, emoji and zero-width characters can't be used to glue a
/// banned word to its neighbours and slip past a word-boundary match.
String _normalise(String input) {
  final folded = foldArabic(input.toLowerCase());
  final buffer = StringBuffer();
  for (final rune in folded.runes) {
    final isLatin = (rune >= 0x61 && rune <= 0x7A) || (rune >= 0x30 && rune <= 0x39);
    final isArabic = rune >= 0x0621 && rune <= 0x064A;
    buffer.write(isLatin || isArabic ? String.fromCharCode(rune) : ' ');
  }
  return buffer.toString();
}

/// Whether [input] contains something that should not be shown to other
/// people. Empty and whitespace-only input is NOT objectionable — that is
/// an emptiness problem for the caller's own validator, not this one's.
bool isObjectionable(String input) {
  if (input.trim().isEmpty) return false;
  final words = _normalise(input).split(' ').where((w) => w.isNotEmpty).toSet();
  if (words.any(_latin.contains) || words.any(_arabic.contains)) return true;
  // Multi-word Latin entries ("kill yourself") need the joined form too.
  final joined = words.join(' ');
  return _latin.where((e) => e.contains(' ')).any(joined.contains);
}
