// The daily reminder speaks from where the day stands, and never in blame.
//
// Aziz, 2026-09-07: "some daily reminder talks like you didn't do anything".
// The تذكير يومي was five fixed lines drawn by the date; a person who had
// coloured five of six squares heard «عاداتك تنتظرك» and «لا تكسر السلسلة»
// at eight o'clock, and a person who had finished everything heard the
// same. Tonight's line now comes from the day's own numbers, a finished day
// gets no ping at all, and every line the app can say about a day is swept
// here for the words that made the old ones read as an accusation.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/reminder_copy.dart';

/// Words that turn a reminder into a verdict or a threat. Both languages.
const blame = [
  'لا تكسر',
  'على المحك',
  'لم يُلوَّن',
  'لا تتوقف',
  'تنتظرك',
  'لا تفقد',
  'ما سويت',
  "Don't break",
  'on the line',
  'No days colored',
  "Don't stop",
  'waiting for you',
  "Don't lose",
];

void main() {
  group('dailyReminderLine', () {
    test('a finished day gets no reminder at all', () {
      expect(
        dailyReminderLine(
            done: 6, total: 6, streak: 12, variantIndex: 0, isAr: true),
        isNull,
      );
      expect(
        dailyReminderLine(
            done: 7, total: 6, streak: 0, variantIndex: 0, isAr: false),
        isNull,
        reason: 'over-complete (a bonus square) is still finished',
      );
    });

    test('a day with nothing due gets no reminder either', () {
      expect(
        dailyReminderLine(
            done: 0, total: 0, streak: 3, variantIndex: 0, isAr: true),
        isNull,
      );
    });

    test('part of the day done: the number first, then what is left', () {
      final line = dailyReminderLine(
          done: 5, total: 6, streak: 12, variantIndex: 0, isAr: true)!;
      expect(line.title, 'باقي شوي ويكتمل يومك');
      expect(line.body, '٥ من ٦ اليوم، وباقي عادة وحدة.');
      expect(
        dailyReminderLine(
                done: 3, total: 5, streak: 0, variantIndex: 0, isAr: true)!
            .body,
        '٣ من ٥ اليوم، وباقي عادتين.',
      );
      expect(
        dailyReminderLine(
                done: 1, total: 4, streak: 0, variantIndex: 1, isAr: true)!
            .body,
        '١ من ٤ اليوم وماشية عدل، وباقي ٣ عادات.',
      );
      expect(
        dailyReminderLine(
                done: 5, total: 6, streak: 0, variantIndex: 0, isAr: false)!
            .body,
        '5 of 6 done today. 1 habit to go.',
      );
    });

    test('nothing yet with a streak: the streak, pointed at tomorrow', () {
      final line = dailyReminderLine(
          done: 0, total: 3, streak: 12, variantIndex: 0, isAr: true)!;
      expect(line.title, 'يومك لسا مفتوح');
      expect(line.body, '١٢ يوم ورا بعض، واليوم يخليها ١٣.');
    });

    test('nothing yet and no streak: an open door, one square', () {
      final line = dailyReminderLine(
          done: 0, total: 3, streak: 0, variantIndex: 0, isAr: true)!;
      expect(line.title, 'يومك لسا مفتوح');
      expect(line.body, 'مربع واحد يكفي للبداية.');
      expect(
        dailyReminderLine(
                done: 0, total: 3, streak: 0, variantIndex: 1, isAr: true)!
            .body,
        'خطوة صغيرة اليوم تنحسب.',
      );
    });
  });

  group('dailyFallbackLine', () {
    test('one date always draws one line, and the pools are the same size',
        () {
      for (var i = 0; i < 12; i++) {
        expect(dailyFallbackLine(i, true), dailyFallbackLine(i, true));
        expect(dailyFallbackLine(i, true), dailyFallbackLine(i + 5, true),
            reason: 'five lines, so day i and day i+5 tell the same story');
        expect(dailyFallbackLine(i, false), dailyFallbackLine(i + 5, false));
      }
    });

    test('knows nothing about the day, so claims nothing about it', () {
      for (var i = 0; i < 5; i++) {
        for (final isAr in [true, false]) {
          final l = dailyFallbackLine(i, isAr);
          expect(l.body, isNot(contains('سلسلة')));
          expect(l.body, isNot(contains('streak')));
          expect(l.body, isNot(contains('فاضي')));
        }
      }
    });
  });

  group('streakRiskCopy', () {
    test('leads with what is done and points the streak at tomorrow', () {
      final c = streakRiskCopy(
          done: 3, total: 5, streak: 12, urgentTasks: 0, isAr: true);
      expect(c.title, 'سلسلتك ١٢ يوم ماشية');
      expect(c.body, '٣ من ٥ اليوم، وباقي عادتين. ١٢ يوم ورا بعض، واليوم يخليها ١٣.');
    });

    test('nothing done yet names only what is left', () {
      final c = streakRiskCopy(
          done: 0, total: 2, streak: 7, urgentTasks: 0, isAr: true);
      expect(c.title, 'سلسلتك ٧ أيام ماشية');
      expect(c.body, 'باقي عادتين اليوم. ٧ أيام ورا بعض، واليوم يخليها ٨.');
    });

    test('a streak of one is a beginning, not «سلسلتك يوم»', () {
      expect(
        streakRiskCopy(done: 0, total: 1, streak: 1, urgentTasks: 0, isAr: true)
            .title,
        'سلسلتك بدأت',
      );
      expect(
        streakRiskCopy(
                done: 0, total: 1, streak: 1, urgentTasks: 0, isAr: false)
            .title,
        'Your streak has begun',
      );
    });

    test('the Matrix line rides along only when there are urgent tasks', () {
      expect(
        streakRiskCopy(done: 1, total: 2, streak: 3, urgentTasks: 2, isAr: true)
            .body,
        endsWith(' · ٢ مهمة عاجلة بانتظارك'),
      );
      expect(
        streakRiskCopy(done: 1, total: 2, streak: 3, urgentTasks: 1, isAr: false)
            .body,
        endsWith(' · 1 urgent task waiting'),
      );
      expect(
        streakRiskCopy(done: 1, total: 2, streak: 3, urgentTasks: 0, isAr: false)
            .body,
        isNot(contains('urgent')),
      );
    });
  });

  group('weeklyDigestBody', () {
    test('a week with nothing coloured is quiet, not a verdict', () {
      expect(weeklyDigestBody(greenDays: 0, streak: 0, isAr: true),
          'أسبوع هادي، ويصير. مربع واحد يكفي لبداية جديدة.');
      expect(weeklyDigestBody(greenDays: 0, streak: 0, isAr: false),
          'A quiet week, it happens. One square is enough for a fresh start.');
    });

    test('counts the days impersonally and points the streak forward', () {
      expect(weeklyDigestBody(greenDays: 3, streak: 0, isAr: true),
          '٣ من ٧ أيام ملوّنة هذا الأسبوع.');
      expect(weeklyDigestBody(greenDays: 5, streak: 12, isAr: true),
          '٥ من ٧ أيام ملوّنة هذا الأسبوع، وسلسلة ١٢ يوم ماشية.');
      expect(weeklyDigestBody(greenDays: 2, streak: 1, isAr: true),
          '٢ من ٧ أيام ملوّنة هذا الأسبوع، والسلسلة بدأت.');
      expect(weeklyDigestBody(greenDays: 4, streak: 6, isAr: false),
          '4 of 7 days colored this week, and a 6-day streak going.');
    });
  });

  test('no line the app can say about a day carries a word of blame', () {
    final lines = <String>[];
    for (final isAr in [true, false]) {
      for (var i = 0; i < 5; i++) {
        final f = dailyFallbackLine(i, isAr);
        lines.addAll([f.title, f.body]);
      }
      for (final done in [0, 1, 4]) {
        for (final streak in [0, 1, 9]) {
          for (final v in [0, 1]) {
            final d = dailyReminderLine(
                done: done, total: 5, streak: streak, variantIndex: v, isAr: isAr);
            if (d != null) lines.addAll([d.title, d.body]);
          }
          if (streak > 0) {
            final s = streakRiskCopy(
                done: done, total: 5, streak: streak, urgentTasks: 1, isAr: isAr);
            lines.addAll([s.title, s.body]);
          }
        }
      }
      for (final g in [0, 3, 7]) {
        lines.add(weeklyDigestBody(greenDays: g, streak: 4, isAr: isAr));
      }
    }
    expect(lines, isNotEmpty);
    for (final l in lines) {
      for (final word in blame) {
        expect(l, isNot(contains(word)), reason: '"$l" says "$word"');
      }
    }
  });
}
