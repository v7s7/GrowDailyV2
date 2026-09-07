// The daily reminder speaks from where the day stands, and never in blame.
//
// Aziz, 2026-09-07: "some daily reminder talks like you didn't do anything".
// The تذكير يومي was five fixed lines drawn by the date; a person who had
// coloured five of six squares heard «عاداتك تنتظرك» and «لا تكسر السلسلة»
// at eight o'clock, and a person who had finished everything heard the
// same. Tonight's line now comes from the day's own numbers, a finished day
// gets no ping at all, and every line the app can say about a day is swept
// here for the words that made the old ones read as an accusation.
//
// The same evening Aziz chose the voice (warm and proud), asked for variety
// so the same night does not read the same every day, and asked for a light
// Islamic warmth where it falls naturally and never in every line. Those
// three choices are pinned below as well.
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

const warmth = ['ما شاء الله', 'بسم الله', 'الحمد لله', 'Ma sha Allah', 'Bismillah', 'Alhamdulillah'];

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

    test('part of the day done: praised first, then what is left, small', () {
      final line = dailyReminderLine(
          done: 5, total: 6, streak: 12, variantIndex: 0, isAr: true)!;
      expect(line.title, 'يومك ماشي عدل');
      expect(line.body, '٥ من ٦ خلّصت، والباقي عادة وحدة بس.');
      final warm = dailyReminderLine(
          done: 3, total: 5, streak: 0, variantIndex: 1, isAr: true)!;
      expect(warm.title, 'ما شاء الله، شوي ويكتمل يومك');
      expect(warm.body, '٣ من ٥ خلّصت. باقي عادتين واليوم يكتمل.');
      expect(
        dailyReminderLine(
                done: 1, total: 4, streak: 0, variantIndex: 2, isAr: true)!
            .body,
        '١ من ٤ خلّصت وماشية عدل، والباقي ٣ عادات بس.',
      );
      expect(
        dailyReminderLine(
                done: 5, total: 6, streak: 0, variantIndex: 0, isAr: false)!
            .body,
        '5 of 6 done, only 1 habit left.',
      );
    });

    test('«خلّصت» belongs to the habits, so the verb is never first', () {
      for (var v = 0; v < 3; v++) {
        final body = dailyReminderLine(
                done: 2, total: 7, streak: 0, variantIndex: v, isAr: true)!
            .body;
        expect(body, startsWith('٢ من ٧ خلّصت'),
            reason: 'verb first would read as second person');
      }
    });

    test('nothing yet with a streak: three voices, the forward line among them',
        () {
      final plain = dailyReminderLine(
          done: 0, total: 3, streak: 12, variantIndex: 0, isAr: true)!;
      expect(plain.title, 'وقت عاداتك');
      expect(plain.body, '١٢ يوم ورا بعض، واليوم يخليها ١٣.');
      final warm = dailyReminderLine(
          done: 0, total: 3, streak: 12, variantIndex: 1, isAr: true)!;
      expect(warm.title, 'يومك لسا مفتوح');
      expect(warm.body, 'ما شاء الله، ١٢ يوم ورا بعض، واليوم يخليها ١٣.');
      final simple = dailyReminderLine(
          done: 0, total: 3, streak: 12, variantIndex: 2, isAr: true)!;
      expect(simple.body, 'بسم الله، مربع واحد يفتح اليوم، والسلسلة تكمل.');
      expect(simple.body, isNot(contains('١٢')),
          reason: 'some nights it is simply time for your habits');
    });

    test('nothing yet and no streak: an open door, one square', () {
      expect(
        dailyReminderLine(
            done: 0, total: 3, streak: 0, variantIndex: 0, isAr: true),
        (title: 'يومك لسا مفتوح', body: 'مربع واحد يكفي للبداية.'),
      );
      expect(
        dailyReminderLine(
                done: 0, total: 3, streak: 0, variantIndex: 1, isAr: true)!
            .body,
        'بسم الله، خطوة صغيرة اليوم تنحسب.',
      );
    });

    test('three consecutive days never read the same', () {
      for (final isAr in [true, false]) {
        for (final (done, streak) in [(0, 0), (0, 9), (2, 0), (2, 9)]) {
          final bodies = {
            for (var v = 0; v < 3; v++)
              dailyReminderLine(
                      done: done,
                      total: 5,
                      streak: streak,
                      variantIndex: v,
                      isAr: isAr)!
                  .body,
          };
          expect(bodies, hasLength(3), reason: 'done $done streak $streak');
        }
      }
    });

    test('warmth is light: never in every voice of a state', () {
      for (final isAr in [true, false]) {
        for (final (done, streak) in [(0, 0), (0, 9), (2, 0)]) {
          final plain = [
            for (var v = 0; v < 3; v++)
              dailyReminderLine(
                  done: done,
                  total: 5,
                  streak: streak,
                  variantIndex: v,
                  isAr: isAr)!,
          ].where((l) => !warmth.any((w) => '${l.title} ${l.body}'.contains(w)));
          expect(plain, isNotEmpty, reason: 'done $done streak $streak');
        }
      }
    });
  });

  group('dailyFallbackLine', () {
    test('one weekday always draws one line, and the pools are the same size',
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
    test('leads with what is done, praised, and points the streak at tomorrow',
        () {
      final c = streakRiskCopy(
          done: 3, total: 5, streak: 12, urgentTasks: 0, isAr: true);
      expect(c.title, 'سلسلتك ١٢ يوم ماشية');
      expect(c.body,
          '٣ من ٥ خلّصت، والباقي عادتين بس. ١٢ يوم ورا بعض، واليوم يخليها ١٣.');
    });

    test('every other day it opens on ما شاء الله', () {
      final c = streakRiskCopy(
          done: 3, total: 5, streak: 12, urgentTasks: 0, isAr: true, variantIndex: 1);
      expect(c.body,
          'ما شاء الله، ١٢ يوم ورا بعض، واليوم يخليها ١٣. ٣ من ٥ خلّصت، والباقي عادتين بس.');
      expect(
        streakRiskCopy(
                done: 3, total: 5, streak: 12, urgentTasks: 0, isAr: true, variantIndex: 2)
            .body,
        isNot(startsWith('ما شاء الله')),
      );
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
      expect(weeklyDigestBody(greenDays: 2, streak: 1, isAr: true),
          '٢ من ٧ أيام ملوّنة هذا الأسبوع، والسلسلة بدأت.');
      expect(weeklyDigestBody(greenDays: 4, streak: 6, isAr: false),
          '4 of 7 days colored this week, and a 6-day streak going.');
    });

    test('five or more coloured days open on الحمد لله', () {
      expect(weeklyDigestBody(greenDays: 5, streak: 12, isAr: true),
          'الحمد لله، ٥ من ٧ أيام ملوّنة هذا الأسبوع، وسلسلة ١٢ يوم ماشية.');
      expect(weeklyDigestBody(greenDays: 7, streak: 0, isAr: true),
          'الحمد لله، ٧ من ٧ أيام ملوّنة هذا الأسبوع.');
      expect(weeklyDigestBody(greenDays: 6, streak: 6, isAr: false),
          'Alhamdulillah, 6 of 7 days colored this week, and a 6-day streak going.');
      expect(weeklyDigestBody(greenDays: 4, streak: 2, isAr: true),
          isNot(contains('الحمد لله')));
    });
  });

  test('no line the app can say about a day carries a word of blame', () {
    final lines = <String>[];
    for (final isAr in [true, false]) {
      for (var i = 0; i < 7; i++) {
        final f = dailyFallbackLine(i, isAr);
        lines.addAll([f.title, f.body]);
      }
      for (final done in [0, 1, 4]) {
        for (final streak in [0, 1, 9]) {
          for (var v = 0; v < 3; v++) {
            final d = dailyReminderLine(
                done: done, total: 5, streak: streak, variantIndex: v, isAr: isAr);
            if (d != null) lines.addAll([d.title, d.body]);
            if (streak > 0) {
              final s = streakRiskCopy(
                  done: done,
                  total: 5,
                  streak: streak,
                  urgentTasks: 1,
                  isAr: isAr,
                  variantIndex: v);
              lines.addAll([s.title, s.body]);
            }
          }
        }
      }
      for (final g in [0, 3, 5, 7]) {
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
