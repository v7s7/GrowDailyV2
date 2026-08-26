// The line of the day above the board.
//
// Two properties matter and neither is visible by reading the list: the quote
// must be the SAME one all day (a random pick would re-roll on every rebuild,
// so the line would flicker as the board scrolls), and the Arabic and English
// readers must be shown the same quote on the same day.
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/l10n/daily_quotes.dart';

void main() {
  group('the set itself', () {
    test('every quote exists in both languages', () {
      for (var i = 0; i < kDailyQuotes.length; i++) {
        final q = kDailyQuotes[i];
        expect(q.ar.trim(), isNotEmpty, reason: 'quote $i has no Arabic');
        expect(q.en.trim(), isNotEmpty, reason: 'quote $i has no English');
      }
    });

    test('a source, when given, is given in both languages', () {
      // Half an attribution is worse than none: the Arabic reader would see a
      // hadith credited and the English reader would see it as an app slogan.
      for (var i = 0; i < kDailyQuotes.length; i++) {
        final q = kDailyQuotes[i];
        expect(q.sourceAr == null, q.sourceEn == null,
            reason: 'quote $i attributes in only one language');
      }
    });

    test('no em dash anywhere in the copy', () {
      // House rule: the em dash is never used in this app's copy.
      for (var i = 0; i < kDailyQuotes.length; i++) {
        final q = kDailyQuotes[i];
        for (final text in [q.ar, q.en, q.sourceAr ?? '', q.sourceEn ?? '']) {
          expect(text.contains('—'), isFalse,
              reason: 'quote $i uses an em dash');
        }
      }
    });

    test('no duplicates', () {
      final ar = kDailyQuotes.map((q) => q.ar).toSet();
      final en = kDailyQuotes.map((q) => q.en).toSet();
      expect(ar.length, kDailyQuotes.length, reason: 'a repeated Arabic line');
      expect(en.length, kDailyQuotes.length, reason: 'a repeated English line');
    });

    test('the set is long enough not to repeat within a month', () {
      expect(kDailyQuotes.length, greaterThanOrEqualTo(25));
    });
  });

  group('picking the day\'s quote', () {
    test('the same day always gives the same quote', () {
      final a = quoteForDay(DateTime(2026, 8, 26));
      final b = quoteForDay(DateTime(2026, 8, 26));
      expect(identical(a, b), isTrue,
          reason: 'the line must not change as the board rebuilds');
    });

    test('the time of day never changes the answer', () {
      // Callers pass an effectiveDay (a day start), but a stray raw now() must
      // not silently produce a different line later in the same day.
      final morning = quoteForDay(DateTime(2026, 8, 26, 6, 1));
      final night = quoteForDay(DateTime(2026, 8, 26, 23, 59));
      expect(identical(morning, night), isTrue);
    });

    test('consecutive days give different quotes', () {
      for (var i = 0; i < 40; i++) {
        final day = DateTime(2026, 8, 1).add(Duration(days: i));
        final next = day.add(const Duration(days: 1));
        expect(identical(quoteForDay(day), quoteForDay(next)), isFalse,
            reason: 'the same line twice in a row on ${day.toIso8601String()}');
      }
    });

    test('a full cycle shows every quote exactly once', () {
      final seen = <String>{};
      for (var i = 0; i < kDailyQuotes.length; i++) {
        seen.add(quoteForDay(DateTime(2026, 1, 1).add(Duration(days: i))).en);
      }
      expect(seen.length, kDailyQuotes.length,
          reason: 'the rotation must reach every quote before repeating');
    });

    test('dates before the rotation epoch still resolve', () {
      // Dart's % is non-negative for a positive divisor, so this wraps rather
      // than throwing a RangeError on an account with an old device clock.
      expect(() => quoteForDay(DateTime(2019, 5, 4)), returnsNormally);
      expect(() => quoteForDay(DateTime(1999, 12, 31)), returnsNormally);
    });

    test('the reader is handed their own language', () {
      final q = kDailyQuotes.first;
      expect(q.text(true), q.ar);
      expect(q.text(false), q.en);
    });
  });
}
