// A reminder row in Add Habit says the whole reminder as one sentence.
//
// «قبل ١٥ دقيقة» under a lit «بعد» chip was the report: the row never said
// before WHAT, so the person had to reconcile two controls to know when they
// would be reminded. With a prayer the row now names it and the side,
// «قبل الفجر بـ15 دقيقة», counted by the same function the notification
// counts with, in Latin digits. These pin the approved wording (Aziz,
// 2026-09-11), the بـ and ب join, and that a clock-time row keeps the words
// it always had, in Latin digits like the time drawn beside it.
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/l10n/reminder_copy.dart'
    show countedOffsetPhrase;
import 'package:grow_daily_v2/core/utils/western_digits.dart';
import 'package:grow_daily_v2/features/habits/models/habit_cue.dart';
import 'package:grow_daily_v2/features/habits/widgets/habit_offset_sheet.dart';
import 'package:grow_daily_v2/features/matrix/widgets/custom_offset_sheet.dart'
    show formatOffsetVerbose;

void main() {
  const ar = S(Locale('ar'));
  const en = S(Locale('en'));
  const prayerKeys = ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'];
  String prayer(String key, bool isAr) =>
      HabitCue.preset(key).labelForLocale(isAr);

  group('Arabic, the approved strings', () {
    test('on time', () {
      expect(
        habitReminderSentence(0, ar, prayer: prayer('fajr', true)),
        'في وقت الفجر',
      );
    });

    test('before, a counted amount takes بـ before its digits', () {
      expect(
        habitReminderSentence(-15, ar, prayer: prayer('fajr', true)),
        'قبل الفجر بـ15 دقيقة',
      );
      expect(
        habitReminderSentence(-45, ar, prayer: prayer('fajr', true)),
        'قبل الفجر بـ45 دقيقة',
        reason: 'صلاة التهجد, stored at 45 before Fajr',
      );
    });

    test('before, a word takes ب joined straight on', () {
      expect(
        habitReminderSentence(-1, ar, prayer: prayer('fajr', true)),
        'قبل الفجر بدقيقة',
      );
      expect(
        habitReminderSentence(-120, ar, prayer: prayer('fajr', true)),
        'قبل الفجر بساعتين',
      );
    });

    test('after', () {
      expect(
        habitReminderSentence(15, ar, prayer: prayer('fajr', true)),
        'بعد الفجر بـ15 دقيقة',
      );
      expect(
        habitReminderSentence(60, ar, prayer: prayer('maghrib', true)),
        'بعد المغرب بساعة',
      );
    });
  });

  group('English', () {
    test('the same six', () {
      expect(
        habitReminderSentence(0, en, prayer: prayer('fajr', false)),
        'At Fajr time',
      );
      expect(
        habitReminderSentence(-15, en, prayer: prayer('fajr', false)),
        '15 minutes before Fajr',
      );
      expect(
        habitReminderSentence(-1, en, prayer: prayer('fajr', false)),
        '1 minute before Fajr',
      );
      expect(
        habitReminderSentence(-120, en, prayer: prayer('fajr', false)),
        '2 hours before Fajr',
      );
      expect(
        habitReminderSentence(15, en, prayer: prayer('fajr', false)),
        '15 minutes after Fajr',
      );
      expect(
        habitReminderSentence(60, en, prayer: prayer('maghrib', false)),
        '1 hour after Maghrib',
      );
    });
  });

  group('every shift a habit reminder can carry, 12 hours each way', () {
    // Whole words only: «بس» is inside «بساعة», and that one is fine.
    bool hasWord(String text, String word) =>
        RegExp('(^|[\\s،.])$word(\$|[\\s،.])').hasMatch(text);

    for (final isAr in [true, false]) {
      final s = isAr ? ar : en;
      test('with a prayer, ${isAr ? 'Arabic' : 'English'}', () {
        for (final key in prayerKeys) {
          final name = prayer(key, isAr);
          for (var offset = -720; offset <= 720; offset++) {
            final text = habitReminderSentence(offset, s, prayer: name);
            final why = '$key $offset: $text';

            // U+2014, written as an escape so this file carries none itself.
            expect(text.contains('\u2014'), isFalse, reason: why);
            expect(text, contains(name), reason: why);
            expect(
              RegExp('[٠-٩]').hasMatch(text),
              isFalse,
              reason: 'Latin digits on screen: $why',
            );
            if (isAr) {
              for (final banned in ['لسا', 'لسه', 'لسّه', 'فات', 'بس']) {
                expect(hasWord(text, banned), isFalse, reason: why);
              }
              expect(
                RegExp('ب[0-9]').hasMatch(text),
                isFalse,
                reason: 'never ب before a digit: $why',
              );
              expect(
                RegExp('بـ(?![0-9])').hasMatch(text),
                isFalse,
                reason: 'never بـ before a letter: $why',
              );
            }

            if (offset == 0) {
              expect(text, isAr ? 'في وقت $name' : 'At $name time');
              continue;
            }
            final amount =
                toWesternDigits(countedOffsetPhrase(offset.abs(), isAr));
            if (isAr) {
              expect(
                text,
                startsWith(offset < 0 ? 'قبل $name ب' : 'بعد $name ب'),
                reason: why,
              );
              expect(
                text,
                endsWith(amount),
                reason: 'counted the way the notification counts: $why',
              );
            } else {
              expect(
                text,
                '$amount ${offset < 0 ? 'before' : 'after'} $name',
                reason: why,
              );
            }
          }
        }
      });

      // The English run is a guard: formatOffsetVerbose never drew anything
      // but Latin digits in English, so it held before this change too. The
      // Arabic run is the one that pins the change.
      test(
          'without a prayer the row keeps its words, in Latin digits, '
          '${isAr ? 'Arabic' : 'English, a guard'}', () {
        for (var offset = -720; offset <= 720; offset++) {
          final text = habitReminderSentence(offset, s);
          expect(
            text,
            offset == 0
                ? s.leadAtTime
                : toWesternDigits(formatOffsetVerbose(offset, isAr, s)),
            reason: '$offset',
          );
          expect(
            RegExp('[٠-٩]').hasMatch(text),
            isFalse,
            reason: 'the time beside it is Latin: $offset $text',
          );
        }
      });
    }
  });
}
