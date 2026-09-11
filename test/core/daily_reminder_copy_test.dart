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

/// Words that turn a reminder into a verdict or a threat, and the spellings
/// the house style bars. Both languages.
const blame = [
  'لا تكسر',
  'على المحك',
  'لم يُلوَّن',
  'لا تتوقف',
  'تنتظرك',
  'لا تفقد',
  'ما سويت',
  'بانتظارك',
  'تنتظر',
  'خسارة',
  'يفوت',
  'تفوت',
  'فات',
  'لسا',
  'لسه',
  'لسّه',
  'لسّا',
  'لسة',
  'هذي',
  'باچر',
  '\u2014',
  "Don't break",
  'on the line',
  'No days colored',
  "Don't stop",
  'waiting for you',
  "Don't lose",
  'waiting',
  'slip',
  'A shame',
];

/// «لسا» and «هذي» are barred as words, and «لسا» is also the middle of
/// «السادسة» and «السابعة», as «لسة» is of «جلسة». Those spellings are
/// matched only as whole words, with no Arabic letter on either side; every
/// other entry is matched anywhere, so a stem like «تنتظر» still catches
/// «تنتظرك».
///
/// Every spelling of «لسا» the house style bars is listed, including the two
/// no line has ever used: «لسّا» with a shadda, which the plain entry cannot
/// catch because the shadda sits inside the word, and «لسة».
const _wholeWords = ['لسا', 'لسه', 'لسّه', 'لسّا', 'لسة', 'هذي'];

bool says(String line, String word) {
  if (!_wholeWords.contains(word)) return line.contains(word);
  return RegExp('(^|[^\u0600-\u06FF])$word([^\u0600-\u06FF]|\$)')
      .hasMatch(line);
}

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
      expect(warm.title, 'يومك مفتوح إلى الآن');
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
        (title: 'يومك مفتوح إلى الآن', body: 'مربع واحد يكفي للبداية.'),
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

  group('habitsStillNeededForStreak', () {
    test('is the 80% rule in whole numbers', () {
      expect(habitsStillNeededForStreak(done: 0, total: 1), 1);
      expect(habitsStillNeededForStreak(done: 0, total: 5), 4);
      expect(habitsStillNeededForStreak(done: 2, total: 5), 2);
      expect(habitsStillNeededForStreak(done: 3, total: 5), 1);
      expect(habitsStillNeededForStreak(done: 4, total: 5), 0);
      expect(habitsStillNeededForStreak(done: 4, total: 6), 1);
      expect(habitsStillNeededForStreak(done: 8, total: 10), 0);
      // Against the rule itself (kStreakDayCompletionThreshold: done / total
      // >= 0.8) at every board size a day realistically has: exactly the
      // fewest more habits that reach it.
      for (var total = 1; total <= 30; total++) {
        bool earns(int n) => n / total >= 0.8;
        for (var done = 0; done <= total; done++) {
          final needed = habitsStillNeededForStreak(done: done, total: total);
          if (earns(done)) {
            expect(needed, lessThanOrEqualTo(0), reason: '$done of $total');
          } else {
            expect(earns(done + needed), isTrue, reason: '$done of $total');
            expect(
              earns(done + needed - 1),
              isFalse,
              reason: '$done of $total',
            );
          }
        }
      }
    });
  });

  group('streakRiskCopy', () {
    test('what is done, praised, then exactly what the streak still needs', () {
      final c = streakRiskCopy(
        done: 2,
        total: 5,
        streak: 7,
        urgentTasks: 0,
        isAr: true,
      )!;
      expect(c.title, 'سلسلتك ماشية ٧ أيام');
      expect(c.body, '٢ من ٥ خلّصت 👏🏼 سوي عادتين بس، وتصير ٨ أيام.');
      final en = streakRiskCopy(
        done: 2,
        total: 5,
        streak: 7,
        urgentTasks: 0,
        isAr: false,
      )!;
      expect(en.title, 'Your 7-day streak is going');
      expect(en.body, '2 of 5 done 👏🏼 Just 2 more and it turns 8.');
      // Sized to the rule, not to everything still open, and counted the way
      // Arabic counts.
      expect(
        streakRiskCopy(done: 3, total: 5, streak: 7, urgentTasks: 0, isAr: true)!
            .body,
        '٣ من ٥ خلّصت 👏🏼 سوي عادة وحدة بس، وتصير ٨ أيام.',
      );
      expect(
        streakRiskCopy(
          done: 1,
          total: 6,
          streak: 12,
          urgentTasks: 0,
          isAr: true,
        )!
            .body,
        '١ من ٦ خلّصت 👏🏼 سوي ٤ عادات بس، وتصير ١٣ يوم.',
      );
      expect(
        streakRiskCopy(
          done: 1,
          total: 15,
          streak: 10,
          urgentTasks: 0,
          isAr: true,
        )!
            .body,
        '١ من ١٥ خلّصت 👏🏼 سوي ١١ عادة بس، وتصير ١١ يوم.',
      );
      // It no longer counts the streak forward the old way.
      expect(c.body, isNot(contains('يخليها')));
    });

    test('nothing done yet opens on بسم الله', () {
      expect(
        streakRiskCopy(done: 0, total: 5, streak: 7, urgentTasks: 0, isAr: true)!
            .body,
        'بسم الله، سوي ٤ عادات اليوم وتصير ٨ أيام.',
      );
      expect(
        streakRiskCopy(
          done: 0,
          total: 5,
          streak: 7,
          urgentTasks: 0,
          isAr: false,
        )!
            .body,
        'Bismillah. 4 habits today and it turns 8.',
      );
      expect(
        streakRiskCopy(done: 0, total: 2, streak: 3, urgentTasks: 0, isAr: true)!
            .body,
        'بسم الله، سوي عادتين اليوم وتصير ٤ أيام.',
      );
    });

    test('a streak of one is a beginning, and the title counts in spoken order',
        () {
      final one = streakRiskCopy(
        done: 0,
        total: 1,
        streak: 1,
        urgentTasks: 0,
        isAr: true,
      )!;
      expect(one.title, 'سلسلتك بدأت');
      expect(one.body, 'بسم الله، سوي عادة وحدة اليوم وتصير يومين.');
      expect(
        streakRiskCopy(
          done: 0,
          total: 1,
          streak: 1,
          urgentTasks: 0,
          isAr: false,
        )!
            .title,
        'Your streak has begun',
      );
      expect(
        streakRiskCopy(done: 0, total: 1, streak: 2, urgentTasks: 0, isAr: true)!
            .title,
        'سلسلتك ماشية يومين',
      );
      expect(
        streakRiskCopy(
          done: 0,
          total: 1,
          streak: 11,
          urgentTasks: 0,
          isAr: true,
        )!
            .title,
        'سلسلتك ماشية ١١ يوم',
      );
    });

    test('urgent tasks get a short sentence of their own', () {
      String withTasks(int n) => streakRiskCopy(
            done: 2,
            total: 5,
            streak: 7,
            urgentTasks: n,
            isAr: true,
          )!
              .body;
      expect(
        withTasks(1),
        '٢ من ٥ خلّصت 👏🏼 سوي عادتين بس، وتصير ٨ أيام. وعندك مهمة عاجلة وحدة.',
      );
      expect(withTasks(2), endsWith(' وعندك مهمتين عاجلتين.'));
      expect(withTasks(3), endsWith(' وعندك ٣ مهام عاجلة.'));
      expect(withTasks(11), endsWith(' وعندك ١١ مهمة عاجلة.'));
      expect(withTasks(0), isNot(contains('عاجلة')));
      for (final n in [1, 2, 3, 11]) {
        expect(withTasks(n), isNot(contains('·')));
        expect(withTasks(n), isNot(contains('بانتظارك')));
      }
      expect(
        streakRiskCopy(done: 0, total: 5, streak: 7, urgentTasks: 1, isAr: true)!
            .body,
        'بسم الله، سوي ٤ عادات اليوم وتصير ٨ أيام. وعندك مهمة عاجلة وحدة.',
      );
      expect(
        streakRiskCopy(
          done: 2,
          total: 5,
          streak: 7,
          urgentTasks: 1,
          isAr: false,
        )!
            .body,
        endsWith(' Plus 1 urgent task.'),
      );
      expect(
        streakRiskCopy(
          done: 2,
          total: 5,
          streak: 7,
          urgentTasks: 2,
          isAr: false,
        )!
            .body,
        endsWith(' Plus 2 urgent tasks.'),
      );
    });

    test('nothing to ask once the done habits already cover the streak', () {
      expect(
        streakRiskCopy(done: 4, total: 5, streak: 7, urgentTasks: 2, isAr: true),
        isNull,
      );
      expect(
        streakRiskCopy(done: 2, total: 5, streak: 0, urgentTasks: 0, isAr: true),
        isNull,
      );
    });
  });

  group('weeklyNoteCopy', () {
    test("names the week's best habit and praises its count", () {
      expect(
        weeklyNoteCopy(
          habitName: 'أذكار الصباح',
          greenDays: 5,
          isQuit: false,
          isAr: true,
        ),
        (
          title: 'أذكار الصباح',
          body: '٥ أيام خضرا هذا الأسبوع 👏🏼 والليلة تختم الأسبوع.',
        ),
      );
      expect(
        weeklyNoteCopy(
          habitName: 'ترك التدخين',
          greenDays: 5,
          isQuit: true,
          isAr: true,
        )!
            .body,
        '٥ أيام التزام هذا الأسبوع 👏🏼 والليلة تختم الأسبوع.',
      );
      expect(
        weeklyNoteCopy(
          habitName: 'Morning Adhkar',
          greenDays: 5,
          isQuit: false,
          isAr: false,
        ),
        (
          title: 'Morning Adhkar',
          body: 'Green 5 days this week 👏🏼 Tonight closes the week.',
        ),
      );
      expect(
        weeklyNoteCopy(
          habitName: 'Quit Smoking',
          greenDays: 6,
          isQuit: true,
          isAr: false,
        )!
            .body,
        'Kept 6 days this week 👏🏼 Tonight closes the week.',
      );
      expect(
        weeklyNoteCopy(habitName: 'x', greenDays: 3, isQuit: false, isAr: true)!
            .body,
        startsWith('٣ أيام خضرا'),
      );
      expect(
        weeklyNoteCopy(habitName: 'x', greenDays: 7, isQuit: false, isAr: true)!
            .body,
        startsWith('٧ أيام خضرا'),
      );
    });

    test('a week under three green days is not held up', () {
      for (final g in [0, 1, 2]) {
        expect(
          weeklyNoteCopy(habitName: 'x', greenDays: g, isQuit: false, isAr: true),
          isNull,
        );
      }
    });
  });

  group('weeklyRepeatCopy', () {
    test('stays true on any Friday: a new week, and the longest run reached',
        () {
      expect(
        weeklyRepeatCopy(longestStreak: 14, isAr: true),
        (
          title: 'أسبوع جديد باجر',
          body: 'سبق ووصلت ١٤ يوم ورا بعض 👏🏼 ومربع واحد يفتح الأسبوع.',
        ),
      );
      expect(
        weeklyRepeatCopy(longestStreak: 7, isAr: true).body,
        'سبق ووصلت ٧ أيام ورا بعض 👏🏼 ومربع واحد يفتح الأسبوع.',
      );
      expect(
        weeklyRepeatCopy(longestStreak: 3, isAr: true).body,
        'سبق ووصلت ٣ أيام ورا بعض 👏🏼 ومربع واحد يفتح الأسبوع.',
      );
      expect(
        weeklyRepeatCopy(longestStreak: 14, isAr: false),
        (
          title: 'A new week tomorrow',
          body: "You've reached 14 days in a row before 👏🏼 One square opens "
              'the week.',
        ),
      );
    });

    test('under three it only opens the week', () {
      for (final l in [0, 1, 2]) {
        expect(
          weeklyRepeatCopy(longestStreak: l, isAr: true).body,
          'مربع واحد يفتح الأسبوع.',
        );
        expect(
          weeklyRepeatCopy(longestStreak: l, isAr: false).body,
          'One square opens the week.',
        );
      }
    });

    test('claims nothing about the week it happens to fire in', () {
      for (final l in [0, 3, 40]) {
        for (final isAr in [true, false]) {
          final c = weeklyRepeatCopy(longestStreak: l, isAr: isAr);
          expect('${c.title} ${c.body}', isNot(contains('هذا الأسبوع')));
          expect('${c.title} ${c.body}', isNot(contains('this week')));
        }
      }
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
          }
          for (final urgent in [0, 1, 2, 11]) {
            final s = streakRiskCopy(
              done: done,
              total: 5,
              streak: streak,
              urgentTasks: urgent,
              isAr: isAr,
            );
            if (s != null) lines.addAll([s.title, s.body]);
          }
        }
      }
      for (final g in [3, 5, 7]) {
        for (final isQuit in [true, false]) {
          final w = weeklyNoteCopy(
            habitName: isAr ? 'أذكار الصباح' : 'Morning Adhkar',
            greenDays: g,
            isQuit: isQuit,
            isAr: isAr,
          )!;
          lines.addAll([w.title, w.body]);
        }
      }
      for (final longest in [0, 2, 3, 14]) {
        final r = weeklyRepeatCopy(longestStreak: longest, isAr: isAr);
        lines.addAll([r.title, r.body]);
      }
    }
    expect(lines, isNotEmpty);
    for (final l in lines) {
      for (final word in blame) {
        expect(says(l, word), isFalse, reason: '"$l" says "$word"');
      }
    }
  });

  test('no habit reminder line carries a word of blame either', () {
    // habitOnTimeLine, habitReminderBody and the bundle copy were never in
    // this sweep, which is how «تنتظر» and «خسارة» survived in them.
    final lines = <String>[];
    for (final isAr in [true, false]) {
      final prayer = isAr ? 'الفجر' : 'Fajr';
      for (var v = 0; v < 6; v++) {
        lines.add(lateReminderAsk(v, isAr));
        for (final streak in [0, 1, 2, 7, 11]) {
          for (final everyDay in [true, false]) {
            if (streak > 0) {
              lines.add(lateStreakPraise(streak, isAr, everyDay: everyDay));
            }
            for (final ago in [null, 1, 4]) {
              for (final anchor in [null, prayer]) {
                final onTime = habitOnTimeLine(
                  streak: streak,
                  completedCount: 0,
                  dailyTarget: 1,
                  lastDoneDaysAgo: ago,
                  timerSeconds: v.isEven ? null : 120,
                  variantIndex: v,
                  isAr: isAr,
                  everyDay: everyDay,
                  anchorLabel: anchor,
                );
                lines.add(onTime);
                for (final offset in [-45, -15, 1, 2, 15, 60]) {
                  lines.add(
                    habitReminderBody(
                      offsetMinutes: offset,
                      streak: streak,
                      anchorLabel: anchor,
                      isAr: isAr,
                      onTimeLine: onTime,
                      everyDay: everyDay,
                      variantIndex: v,
                    ),
                  );
                }
              }
            }
          }
        }
        for (var done = 1; done < 12; done++) {
          lines.add(
            habitOnTimeLine(
              streak: 3,
              completedCount: done,
              dailyTarget: 12,
              lastDoneDaysAgo: 0,
              timerSeconds: null,
              variantIndex: v,
              isAr: isAr,
            ),
          );
        }
        for (final weekDone in [0, 1, 3]) {
          lines.add(
            habitOnTimeLine(
              streak: 0,
              completedCount: 0,
              dailyTarget: 1,
              lastDoneDaysAgo: 2,
              timerSeconds: null,
              variantIndex: v,
              isAr: isAr,
              weekTarget: 3,
              weekDone: weekDone,
              owedToday: v.isOdd,
            ),
          );
        }
      }
      final at = DateTime(2026, 9, 12, 4, 17);
      for (final offsets in [
        [0, 0],
        [-15, -15],
        [15, 15],
        [-15, 0],
        [20, -60, 0],
      ]) {
        for (final anchor in [null, prayer]) {
          lines.add(
            habitBundleBody(
              members: [
                for (final o in offsets)
                  (
                    offsetMinutes: o,
                    anchorLabel: anchor,
                    fireTime: at,
                    streak: 4,
                    everyDay: true,
                    isQuota: false,
                  ),
              ],
              isAr: isAr,
            ),
          );
        }
        lines.add(
          habitBundleTitle(
            names: [for (final o in offsets) isAr ? 'عادة $o' : 'Habit $o'],
            isAr: isAr,
          ),
        );
      }
    }
    expect(lines, isNotEmpty);
    for (final l in lines) {
      for (final word in blame) {
        expect(says(l, word), isFalse, reason: '"$l" says "$word"');
      }
    }
  });

  test('the sweep sees a barred word, and not a word that contains one', () {
    // Both halves matter, and a matcher that saw nothing would pass every
    // line above: «لسا» is barred as a word and «السادسة» is not it, and the
    // same for «لسة» inside «جلسة».
    expect(says('لسا ما خلّص', 'لسا'), isTrue);
    expect(says('الساعة السادسة', 'لسا'), isFalse);
    expect(says('لسّه ما خلّص', 'لسّه'), isTrue);
    expect(says('لسّا ما خلّص', 'لسّا'), isTrue);
    expect(says('لسة ما خلّص', 'لسة'), isTrue);
    expect(says('جلسة الصباح', 'لسة'), isFalse);
    expect(says('هذي عادتك', 'هذي'), isTrue);
    expect(says('عاداتك تنتظرك', 'تنتظر'), isTrue,
        reason: 'a stem is matched anywhere');
    for (final word in _wholeWords) {
      expect(blame, contains(word),
          reason: 'a whole word swept but not barred sweeps for nothing');
    }
  });
}
