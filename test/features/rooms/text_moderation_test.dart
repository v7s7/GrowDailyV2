// The filtering half of App Review guideline 1.2, applied to the two
// strings one user puts in front of another: room names and display names.
//
// The tests that matter most here are the NEGATIVE ones. A filter that
// over-matches silently refuses a name a real person chose, in their own
// language, with no explanation they can act on — and in an Arabic-first
// app most of the risk lives in Arabic orthography, where the same word is
// routinely typed five different ways.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/utils/text_moderation.dart';

void main() {
  group('catches what it should', () {
    test('plain profanity, either script', () {
      expect(isObjectionable('fuck this'), isTrue);
      expect(isObjectionable('غرفة كس'), isTrue);
    });

    test('case and surrounding punctuation do not hide it', () {
      expect(isObjectionable('FUCK'), isTrue);
      expect(isObjectionable('...shit!!!'), isTrue);
      expect(isObjectionable('**bitch**'), isTrue);
    });

    test('emoji and zero-width padding do not hide it', () {
      // Punctuation-as-glue is the obvious first bypass attempt: without
      // normalisation, "🔥fuck🔥" is one token that matches nothing.
      expect(isObjectionable('🔥fuck🔥'), isTrue);
      expect(isObjectionable('f​uck'), isFalse,
          reason: 'a zero-width INSIDE a word genuinely breaks it; '
              'documented as a known limit, not a silent claim');
    });

    test('a multi-word phrase is caught', () {
      expect(isObjectionable('kill yourself'), isTrue);
    });

    test('religious insult is caught, which is the realistic case here', () {
      // The rooms are built around صلاة and أذكار, so a slur aimed at
      // someone's practice is likelier than generic profanity.
      expect(isObjectionable('يا كافر'), isTrue);
      expect(isObjectionable('ملحد'), isTrue);
    });

    test('Arabic spelling variants all collapse to one entry', () {
      // Diacritics, tatweel, and alef/teh-marbuta/alef-maksura variants.
      expect(isObjectionable('كافِر'), isTrue);
      expect(isObjectionable('كــافر'), isTrue);
      expect(isObjectionable('قحبة'), isTrue, reason: 'ة folds to ه');
    });
  });

  group('does NOT catch ordinary names', () {
    test('the app own vocabulary is safe', () {
      for (final ok in [
        'أذكار الصباح',
        'صلاة الأوابين',
        'الإلتزام',
        'سورة الملك',
        'قيام الليل',
        'رمضان',
        'تحدي القرآن',
      ]) {
        expect(isObjectionable(ok), isFalse, reason: ok);
      }
    });

    test('English room names are safe', () {
      for (final ok in [
        'Morning Routine',
        'Team Alpha',
        'Class of 2026',
        'Gym buddies',
        'Sunrise Club',
      ]) {
        expect(isObjectionable(ok), isFalse, reason: ok);
      }
    });

    test('substring collisions do not fire — the Scunthorpe case', () {
      // Every one of these CONTAINS a banned string and must still pass.
      // This is the single most important test in the file: word-boundary
      // matching is what stops the filter refusing real names.
      for (final ok in [
        'Scunthorpe',
        'Essex runners',
        'analysis club',
        'Cockburn',
        'Dickens reading',
        'classic',
        'assessment',
      ]) {
        expect(isObjectionable(ok), isFalse, reason: ok);
      }
    });

    test('Arabic substring collisions do not fire', () {
      // كس is a banned entry and a substring of several ordinary words.
      for (final ok in ['كسب', 'مكسب', 'اكتساب', 'كسول']) {
        expect(isObjectionable(ok), isFalse, reason: ok);
      }
    });

    test('empty is not objectionable — that is the caller own validator', () {
      expect(isObjectionable(''), isFalse);
      expect(isObjectionable('   '), isFalse);
    });
  });

  group('foldArabic', () {
    test('unifies the variants it claims to', () {
      expect(foldArabic('أإآ'), 'ااا');
      expect(foldArabic('ة'), 'ه');
      expect(foldArabic('ى'), 'ي');
      expect(foldArabic('مُحَمَّد'), 'محمد');
      expect(foldArabic('كــتاب'), 'كتاب');
    });

    test('leaves Latin and digits alone', () {
      expect(foldArabic('Hello 123'), 'Hello 123');
    });
  });
}
