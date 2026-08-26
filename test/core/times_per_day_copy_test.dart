// Arabic counts its nouns in three shapes, and the times-per-day copy has to
// use all three. A flat "n > 1 means plural" rule is an English habit, and it
// produced "2 مرات في اليوم" (which should be the dual, مرتين) and
// "12 مرات في اليوم" (which should be back to the singular, مرة).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';

void main() {
  final ar = S(const Locale('ar'));
  final en = S(const Locale('en'));

  group('the standalone phrase', () {
    test('two is the dual, not a numeral plus a plural', () {
      expect(ar.timesPerDayPhrase(2), 'مرتين في اليوم');
      expect(ar.timesPerDayPhrase(2), isNot(contains('2')),
          reason: 'in Arabic the number two is the noun\'s form, not a digit '
              'placed in front of it');
    });

    test('three through ten take the plural', () {
      expect(ar.timesPerDayPhrase(3), '3 مرات في اليوم');
      expect(ar.timesPerDayPhrase(10), '10 مرات في اليوم');
    });

    test('eleven and above go back to the singular', () {
      expect(ar.timesPerDayPhrase(11), '11 مرة في اليوم');
      expect(ar.timesPerDayPhrase(12), '12 مرة في اليوم');
      for (final n in [11, 12, 20, 99]) {
        expect(ar.timesPerDayPhrase(n), isNot(contains('مرات')),
            reason: '$n must not take the plural');
      }
    });

    test('one says it once', () {
      expect(ar.timesPerDayPhrase(1), 'مرة في اليوم');
      expect(en.timesPerDayPhrase(1), 'once a day');
    });

    test('English is unchanged', () {
      expect(en.timesPerDayPhrase(2), '2 times a day');
      expect(en.timesPerDayPhrase(12), '12 times a day');
    });
  });

  group('the bare unit beside the stepper numeral', () {
    test('eleven and above no longer read as a plural', () {
      expect(ar.timesPerDayLabel(12), 'مرة في اليوم');
      expect(ar.timesPerDayLabel(11), 'مرة في اليوم');
    });

    test('three through ten still do', () {
      expect(ar.timesPerDayLabel(4), 'مرات في اليوم');
    });

    test('one is singular', () {
      expect(ar.timesPerDayLabel(1), 'مرة في اليوم');
    });
  });

  group('the stepper buttons say what they do', () {
    test('each names its direction and the current value', () {
      // The old labels were the unit strings timesPerDayLabel(1) and (2), so a
      // screen reader announced "once a day, button" and "times a day, button"
      // with no direction and no current count.
      final dec = ar.timesPerDayDecrease(4);
      final inc = ar.timesPerDayIncrease(4);
      expect(dec, contains('إنقاص'));
      expect(inc, contains('زيادة'));
      expect(dec, contains('4 مرات في اليوم'));
      expect(inc, contains('4 مرات في اليوم'));
      expect(dec, isNot(equals(inc)),
          reason: 'the two buttons must not announce identically');
    });

    test('English reads as an action too', () {
      expect(en.timesPerDayDecrease(3), 'Decrease, currently 3 times a day');
      expect(en.timesPerDayIncrease(3), 'Increase, currently 3 times a day');
    });

    test('the announced value tracks the count', () {
      expect(ar.timesPerDayIncrease(2), contains('مرتين'));
      expect(ar.timesPerDayIncrease(12), contains('12 مرة'));
    });
  });
}
