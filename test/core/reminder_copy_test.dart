import 'package:flutter/material.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/l10n/reminder_copy.dart';
import 'package:grow_daily_v2/features/matrix/widgets/custom_offset_sheet.dart'
    show formatOffsetVerbose;

/// The bug these pin: a reminder set for an hour BEFORE something announced
/// «حان الوقت» when it fired, an hour early. Every string here is therefore
/// really one assertion in three parts — the copy counts down before the
/// moment, states it on the moment, and counts up after it — and the
/// sweeping tests at the bottom are the ones that would catch a fourth
/// wording being added later that forgets to.
void main() {
  const ar = S(Locale('ar'));

  group('signedOffsetMinutes', () {
    final anchor = DateTime(2026, 8, 27, 8, 25);

    test('negative before the anchor, positive after, zero on it', () {
      expect(signedOffsetMinutes(DateTime(2026, 8, 27, 7, 25), anchor), -60);
      expect(signedOffsetMinutes(DateTime(2026, 8, 27, 8, 45), anchor), 20);
      expect(signedOffsetMinutes(anchor, anchor), 0);
    });

    test('rounds instead of truncating towards zero', () {
      // Duration.inMinutes would call this -59, and the notification would
      // then advertise "59 minutes" for something set as a flat hour.
      final off = DateTime(2026, 8, 27, 7, 25).add(const Duration(seconds: 18));
      expect(signedOffsetMinutes(off, anchor), -60);
    });

    test('spans days, which a reminder stack legitimately can', () {
      expect(
        signedOffsetMinutes(DateTime(2026, 8, 25, 8, 25), anchor),
        -2880,
      );
    });
  });

  group('countedOffsetPhrase', () {
    test('English counts singular and plural', () {
      expect(countedOffsetPhrase(1, false), '1 minute');
      expect(countedOffsetPhrase(45, false), '45 minutes');
      expect(countedOffsetPhrase(60, false), '1 hour');
      expect(countedOffsetPhrase(120, false), '2 hours');
      expect(countedOffsetPhrase(1440, false), '1 day');
      // Not evenly divisible, so it stays in minutes rather than becoming
      // "1.5 hours" — see splitOffsetUnit.
      expect(countedOffsetPhrase(90, false), '90 minutes');
    });

    test('Arabic counts singular, dual, plural, then back to singular', () {
      expect(countedOffsetPhrase(1, true), 'دقيقة');
      expect(countedOffsetPhrase(2, true), 'دقيقتين');
      expect(countedOffsetPhrase(5, true), '٥ دقائق');
      expect(countedOffsetPhrase(45, true), '٤٥ دقيقة');
      expect(countedOffsetPhrase(60, true), 'ساعة');
      expect(countedOffsetPhrase(120, true), 'ساعتين');
      expect(countedOffsetPhrase(1440, true), 'يوم');
      expect(countedOffsetPhrase(2880, true), 'يومين');
    });

    test('agrees with the picker chip that set the offset', () {
      // The whole reason this lives in core: somebody taps «قبل ساعة» and
      // later reads a notification about it. Those two counting the same
      // offset differently reads as two different reminders.
      for (final minutes in [5, 10, 15, 30, 45, 60, 90, 120, 1440, 2880]) {
        expect(
          countedOffsetPhrase(minutes, true),
          formatOffsetVerbose(-minutes, true, ar, withDirection: false),
          reason: '$minutes minutes should count the same either way',
        );
      }
    });
  });

  group('taskReminderTitle', () {
    test('an hour early counts down instead of claiming the time has come',
        () {
      // The reported case, verbatim: an 8:25 appointment reminded at 7:25.
      expect(
        taskReminderTitle(offsetMinutes: -60, isAr: true),
        'باقي ساعة على مهمتك',
      );
      expect(
        taskReminderTitle(offsetMinutes: -60, isAr: false),
        '1 hour until your task',
      );
    });

    test('on the dot keeps the wording that was never wrong', () {
      expect(taskReminderTitle(offsetMinutes: 0, isAr: true), 'حان الوقت');
      expect(taskReminderTitle(offsetMinutes: 0, isAr: false), "It's time");
    });

    test('a follow-up set for after the moment counts up', () {
      expect(
        taskReminderTitle(offsetMinutes: 20, isAr: true),
        'صار لها ٢٠ دقيقة، وبعدها بانتظارك',
      );
      expect(
        taskReminderTitle(offsetMinutes: 20, isAr: false),
        "It's been 20 minutes. Still waiting.",
      );
    });

    test('never says the time has come unless it actually has', () {
      for (final offset in [-2880, -120, -60, -15, -1, 1, 15, 60, 120, 2880]) {
        expect(
          taskReminderTitle(offsetMinutes: offset, isAr: true),
          isNot('حان الوقت'),
          reason: 'offset $offset is not the moment itself',
        );
        expect(
          taskReminderTitle(offsetMinutes: offset, isAr: false),
          isNot("It's time"),
          reason: 'offset $offset is not the moment itself',
        );
      }
    });
  });

  group('overdueTaskReminderTitle', () {
    test('states how late it is, rather than that it is time', () {
      expect(
        overdueTaskReminderTitle(minutesLate: 60, isAr: true),
        'وقتها كان قبل ساعة',
      );
      expect(
        overdueTaskReminderTitle(minutesLate: 60, isAr: false),
        'This was due 1 hour ago',
      );
    });

    test('a catch-up days later still reads correctly', () {
      expect(
        overdueTaskReminderTitle(minutesLate: 2880, isAr: true),
        'وقتها كان قبل يومين',
      );
      expect(
        overdueTaskReminderTitle(minutesLate: 2880, isAr: false),
        'This was due 2 days ago',
      );
    });

    test('a catch-up fired within the same minute falls back gracefully', () {
      // Rather than "وقتها كان قبل ٠ دقيقة".
      expect(overdueTaskReminderTitle(minutesLate: 0, isAr: true), 'حان الوقت');
      expect(
        overdueTaskReminderTitle(minutesLate: -3, isAr: false),
        "It's time",
      );
    });
  });

  group('habitReminderBody', () {
    String body({
      required int offset,
      int streak = 0,
      String? anchor,
      bool isAr = true,
      int variant = 0,
      bool everyDay = true,
    }) =>
        habitReminderBody(
          offsetMinutes: offset,
          streak: streak,
          anchorLabel: anchor,
          isAr: isAr,
          onTimeLine: isAr ? 'حان الوقت.' : "It's time.",
          everyDay: everyDay,
          variantIndex: variant,
        );

    test('on time is left exactly as it was', () {
      expect(body(offset: 0), 'حان الوقت.');
      expect(body(offset: 0, isAr: false), "It's time.");
      // With a streak too: its caller already passes the praise in as
      // onTimeLine.
      expect(body(offset: 0, streak: 7), 'حان الوقت.');
    });

    test('a prayer-anchored habit names the adhan it is counting to', () {
      expect(
        body(offset: -45, anchor: 'المغرب'),
        'باقي ٤٥ دقيقة على أذان المغرب. خلّك جاهز.',
      );
      expect(
        body(offset: -45, anchor: 'Maghrib', isAr: false),
        '45 minutes until the Maghrib adhan. Get ready.',
      );
      expect(
        body(offset: 20, anchor: 'الفجر'),
        'اذن الفجر قبل ٢٠ دقيقة. سوي عادتك الحين.',
      );
      expect(
        body(offset: 20, anchor: 'Fajr', isAr: false),
        'Fajr was 20 minutes ago. Do it now.',
      );
    });

    test('every late variant asks for the habit, and none says فات', () {
      // «فات» is barred: it tells the reader they have already lost
      // something at the one moment they can still do it. Aziz, on his own
      // سنة الفجر reminder: "فات الفجر قبل ١٥ دقيقة" should have been
      // «اذن الفجر قبل ١٥ دقيقة، سوي عادتك الحين».
      //
      // Every minute value the offset picker can produce, not just one, since
      // the noun declines (singular, dual, 3-10 plural, 11+ singular) and the
      // sentence has to survive all four shapes. Every rotation too, since
      // the ask moves and the clock fact does not.
      const lateMinutes = [1, 2, 3, 10, 11, 15, 20, 30, 45, 59];
      for (final m in lateMinutes) {
        for (var v = 0; v < 8; v++) {
          final withPrayer = body(offset: m, anchor: 'الفجر', variant: v);
          final withClock = body(offset: m, variant: v);
          for (final line in [withPrayer, withClock]) {
            expect(line, isNot(contains('فات')), reason: '$m min, variant $v');
          }
          expect(withPrayer, startsWith('اذن الفجر قبل '));
          expect(withClock, startsWith('صار لها '));
        }
      }
      // The declensions of the clock fact, spot-checked end to end.
      expect(
        body(offset: 15, anchor: 'الفجر'),
        'اذن الفجر قبل ١٥ دقيقة. سوي عادتك الحين.',
      );
      expect(
        body(offset: 1, anchor: 'الفجر'),
        'اذن الفجر قبل دقيقة. سوي عادتك الحين.',
      );
      expect(
        body(offset: 2, anchor: 'المغرب'),
        'اذن المغرب قبل دقيقتين. سوي عادتك الحين.',
      );
      expect(
        body(offset: 5, anchor: 'العشاء'),
        'اذن العشاء قبل ٥ دقائق. سوي عادتك الحين.',
      );
      expect(
        body(offset: 60, anchor: 'الظهر'),
        'اذن الظهر قبل ساعة. سوي عادتك الحين.',
      );
    });

    test("the ask rotates through Aziz's three, and the old ones are gone", () {
      // Aziz: «هي عادية بس فيه احلى لا تخليها تتكرر بس هي». On 2026-09-11 he
      // kept the first ask and replaced the other three.
      expect(
        body(offset: 15, anchor: 'الفجر'),
        'اذن الفجر قبل ١٥ دقيقة. سوي عادتك الحين.',
      );
      expect(
        body(offset: 15, anchor: 'الفجر', variant: 1),
        'اذن الفجر قبل ١٥ دقيقة. تقدر تسويها الحين.',
      );
      expect(
        body(offset: 15, anchor: 'الفجر', variant: 2),
        'اذن الفجر قبل ١٥ دقيقة. يلا، سويها الحين.',
      );
      expect(lateReminderAsk(0, false), 'Do it now.');
      expect(lateReminderAsk(1, false), 'You can do it now.');
      expect(lateReminderAsk(2, false), 'Come on, do it now.');
      final seen = <String>{};
      for (var v = 0; v < 9; v++) {
        final line = body(offset: 15, anchor: 'الفجر', variant: v);
        seen.add(line);
        for (final old in ['مستعد تنجز', 'يا بطل', 'يا كفو', 'ولوّن']) {
          expect(line, isNot(contains(old)));
        }
      }
      expect(seen, hasLength(3));
      // The same habit on the same day always reads the same.
      expect(
        body(offset: 15, anchor: 'الفجر', variant: 5),
        body(offset: 15, anchor: 'الفجر', variant: 5),
      );
    });

    test('a late streak is praised, never counted forward at the reader', () {
      // Aziz: «ماحب انه سوي عادتك الحين وبعدها ٧ ايام ورا بعض، واليوم
      // يخليها ٨». Two asks in one breath, the second of them arithmetic.
      // A late ping already asks; the streak owes it praise.
      expect(
        body(offset: 15, anchor: 'الفجر', streak: 7),
        'اذن الفجر قبل ١٥ دقيقة. سوي عادتك الحين. ملتزم صارلك ٧ أيام 👏🏼',
      );
      for (var v = 0; v < 8; v++) {
        final line = body(offset: 15, anchor: 'الفجر', streak: 7, variant: v);
        expect(line, isNot(contains('ورا بعض')));
        expect(line, isNot(contains('يخليها')));
        expect(line, contains('ملتزم صارلك'));
      }
      // Declines like every count in this file.
      expect(lateStreakPraise(1, true), 'ملتزم صارلك يوم 👏🏼');
      expect(lateStreakPraise(2, true), 'ملتزم صارلك يومين 👏🏼');
      expect(lateStreakPraise(7, true), 'ملتزم صارلك ٧ أيام 👏🏼');
      expect(lateStreakPraise(15, true), 'ملتزم صارلك ١٥ يوم 👏🏼');
    });

    test('a habit on set weekdays is praised in times, not days', () {
      // Its streak counts the days it runs on, so «ملتزم صارلك ٤ أيام» would
      // read as four calendar days and be false for a Wed/Sat habit.
      expect(
        body(offset: 15, anchor: 'العصر', streak: 4, everyDay: false),
        'اذن العصر قبل ١٥ دقيقة. سوي عادتك الحين. ملتزم ٤ مرات ورا بعض 👏🏼',
      );
      expect(
        body(
          offset: 15,
          anchor: 'Asr',
          streak: 4,
          everyDay: false,
          isAr: false,
        ),
        "Asr was 15 minutes ago. Do it now. You've kept it up 4 times in a "
        'row 👏🏼',
      );
      expect(lateStreakPraise(1, true, everyDay: false), 'سويتها آخر مرة 👏🏼');
      expect(
        lateStreakPraise(2, true, everyDay: false),
        'ملتزم مرتين ورا بعض 👏🏼',
      );
      expect(
        lateStreakPraise(4, true, everyDay: false),
        'ملتزم ٤ مرات ورا بعض 👏🏼',
      );
      expect(
        lateStreakPraise(10, true, everyDay: false),
        'ملتزم ١٠ مرات ورا بعض 👏🏼',
      );
      expect(
        lateStreakPraise(11, true, everyDay: false),
        'ملتزم ١١ مرة ورا بعض 👏🏼',
      );
      for (final s in [1, 2, 3, 10, 11, 40]) {
        final praise = lateStreakPraise(s, true, everyDay: false);
        expect(praise, isNot(contains('صارلك')));
        expect(praise, isNot(contains('أيام')));
        expect(praise, isNot(contains('ثنتين')));
      }
      // The every-day tail is byte-identical to the loved reminder's.
      expect(lateStreakPraise(3, true), 'ملتزم صارلك ٣ أيام 👏🏼');
    });

    test('an early reminder asks to get ready and praises the streak', () {
      expect(
        body(offset: -15, anchor: 'المغرب', streak: 3),
        'باقي ١٥ دقيقة على أذان المغرب. خلّك جاهز. ملتزم صارلك ٣ أيام 👏🏼',
      );
      expect(
        body(offset: -15, anchor: 'Maghrib', streak: 3, isAr: false),
        "15 minutes until the Maghrib adhan. Get ready. You've kept it up 3 "
        'days 👏🏼',
      );
      expect(
        body(offset: -15, streak: 7),
        'باقي ١٥ دقيقة على وقتها. خلّك جاهز. ملتزم صارلك ٧ أيام 👏🏼',
      );
      expect(
        body(offset: -15, streak: 2),
        'باقي ١٥ دقيقة على وقتها. خلّك جاهز. ملتزم صارلك يومين 👏🏼',
      );
      expect(
        body(offset: -15, streak: 15),
        'باقي ١٥ دقيقة على وقتها. خلّك جاهز. ملتزم صارلك ١٥ يوم 👏🏼',
      );
      expect(
        body(offset: -15, streak: 7, isAr: false),
        "15 minutes to go. Get ready. You've kept it up 7 days 👏🏼",
      );
      expect(
        body(offset: -45, anchor: 'الفجر', streak: 4, everyDay: false),
        'باقي ٤٥ دقيقة على أذان الفجر. خلّك جاهز. ملتزم ٤ مرات ورا بعض 👏🏼',
      );
      // It no longer counts the streak forward.
      for (final streak in [1, 2, 7, 15]) {
        final line = body(offset: -15, streak: streak);
        expect(line, isNot(contains('يخليها')));
        expect(line, isNot(contains('ورا بعض،')));
      }
    });

    test('a clock-time habit does not read its own clock back to itself', () {
      expect(body(offset: -15), 'باقي ١٥ دقيقة على وقتها. خلّك جاهز.');
      expect(body(offset: -15, isAr: false), '15 minutes to go. Get ready.');
      expect(body(offset: 30), 'صار لها ٣٠ دقيقة. سوي عادتك الحين.');
      expect(
        body(offset: 30, isAr: false),
        "It's been 30 minutes. Do it now.",
      );
    });
  });

  group('habitStreakLine', () {
    test('points the count forward instead of at what is at risk', () {
      // The number is the same lever either way; this is the version that
      // isn't a threat. Nothing in it may read as blame or as a loss.
      expect(habitStreakLine(7, true), '٧ أيام ورا بعض، واليوم يخليها ٨.');
      expect(habitStreakLine(7, false), '7 days in a row. Today makes it 8.');
      for (final streak in [1, 2, 3, 10, 11, 100]) {
        expect(habitStreakLine(streak, true), isNot(contains('لا تفقد')));
        expect(habitStreakLine(streak, false), isNot(contains("Don't lose")));
      }
    });

    test('one day is spelled out, since it has nothing to sit behind', () {
      expect(
        habitStreakLine(1, true),
        'يوم واحد في السلسلة، واليوم يخليها يومين.',
      );
      expect(habitStreakLine(1, false), 'One day down. Today makes it two.');
      // And the dual is the dual, not «٢ أيام».
      expect(habitStreakLine(2, true), startsWith('يومين'));
    });
  });

  group('habitOnTimeLine', () {
    String line({
      int streak = 0,
      int completedCount = 0,
      int dailyTarget = 1,
      int? lastDoneDaysAgo,
      int? timerSeconds,
      int variantIndex = 0,
      bool isAr = true,
      bool everyDay = true,
      int? weekTarget,
      int? weekDone,
      bool owedToday = false,
      String? anchorLabel,
    }) =>
        habitOnTimeLine(
          streak: streak,
          completedCount: completedCount,
          dailyTarget: dailyTarget,
          lastDoneDaysAgo: lastDoneDaysAgo,
          timerSeconds: timerSeconds,
          variantIndex: variantIndex,
          isAr: isAr,
          everyDay: everyDay,
          weekTarget: weekTarget,
          weekDone: weekDone,
          owedToday: owedToday,
          anchorLabel: anchorLabel,
        );

    test('a clock habit with a streak: the moment, the ask, the praise', () {
      // Aziz's pick of 2026-09-11, in the voice of the reminder he loved.
      expect(
        line(streak: 3, lastDoneDaysAgo: 1),
        'وقتها الحين. سوي عادتك. ملتزم صارلك ٣ أيام 👏🏼',
      );
      expect(
        line(streak: 3, lastDoneDaysAgo: 1, isAr: false),
        "It's time. Do it now. You've kept it up 3 days 👏🏼",
      );
      expect(
        line(streak: 4, lastDoneDaysAgo: 3, everyDay: false),
        'وقتها الحين. سوي عادتك. ملتزم ٤ مرات ورا بعض 👏🏼',
      );
      expect(
        line(streak: 1, lastDoneDaysAgo: 3, everyDay: false),
        'وقتها الحين. سوي عادتك. سويتها آخر مرة 👏🏼',
      );
      expect(
        line(streak: 2, lastDoneDaysAgo: 3, everyDay: false),
        'وقتها الحين. سوي عادتك. ملتزم مرتين ورا بعض 👏🏼',
      );
      // One line, not a pool: the loved shape does not rotate.
      for (var i = 0; i < 6; i++) {
        expect(
          line(streak: 3, lastDoneDaysAgo: 1, variantIndex: i),
          line(streak: 3, lastDoneDaysAgo: 1),
        );
      }
    });

    test('a habit never once done is asked for its first square', () {
      for (var i = 0; i < 6; i++) {
        final l = line(variantIndex: i);
        expect(l, 'وقتها الحين. سوي عادتك. بسم الله، أول مربع لها.');
        expect(l, isNot(contains('بضع دقائق لهذه العادة')));
      }
      expect(
        line(isAr: false),
        "It's time. Do it now. Bismillah, its first square.",
      );
    });

    test('a habit done before with no streak: the moment and the ask, no gap',
        () {
      // The gap lines («صار لها ٣ أيام. مربع واحد اليوم وترجع السلسلة») went
      // with the loss lines: a gap states an absence.
      for (final ago in [1, 2, 3, 7, 14]) {
        for (var i = 0; i < 6; i++) {
          expect(
            line(lastDoneDaysAgo: ago, variantIndex: i),
            'وقتها الحين. سوي عادتك.',
          );
          expect(
            line(lastDoneDaysAgo: ago, variantIndex: i, isAr: false),
            "It's time. Do it now.",
          );
        }
      }
    });

    test('at the adhan the prayer is named', () {
      // It never was: the on-time line returned before reading the anchor.
      expect(
        line(streak: 3, lastDoneDaysAgo: 1, anchorLabel: 'الفجر'),
        'اذن الفجر. سوي عادتك الحين. ملتزم صارلك ٣ أيام 👏🏼',
      );
      expect(
        line(streak: 3, lastDoneDaysAgo: 1, anchorLabel: 'Fajr', isAr: false),
        "It's Fajr. Do it now. You've kept it up 3 days 👏🏼",
      );
      expect(
        line(
          streak: 5,
          lastDoneDaysAgo: 2,
          anchorLabel: 'العصر',
          everyDay: false,
        ),
        'اذن العصر. سوي عادتك الحين. ملتزم ٥ مرات ورا بعض 👏🏼',
      );
      // No streak: the moment and the ask alone. The first-square tail was
      // only picked for a clock time.
      expect(
        line(lastDoneDaysAgo: 4, anchorLabel: 'المغرب'),
        'اذن المغرب. سوي عادتك الحين.',
      );
      expect(line(anchorLabel: 'المغرب'), 'اذن المغرب. سوي عادتك الحين.');
      // And the body hands it straight through on the dot.
      final onTime =
          line(streak: 3, lastDoneDaysAgo: 1, anchorLabel: 'الفجر');
      expect(
        habitReminderBody(
          offsetMinutes: 0,
          streak: 3,
          anchorLabel: 'الفجر',
          isAr: true,
          onTimeLine: onTime,
        ),
        'اذن الفجر. سوي عادتك الحين. ملتزم صارلك ٣ أيام 👏🏼',
      );
    });

    test('several times a day: which round, and what is done', () {
      expect(
        line(completedCount: 1, dailyTarget: 3),
        'وقت المرة الثانية. سويها الحين. ١ من ٣ خلّصت 👏🏼',
      );
      expect(
        line(completedCount: 2, dailyTarget: 3),
        'وقت المرة الأخيرة. سويها الحين. ٢ من ٣ خلّصت 👏🏼',
      );
      expect(
        line(completedCount: 2, dailyTarget: 5),
        'وقت المرة الثالثة. سويها الحين. ٢ من ٥ خلّصت 👏🏼',
      );
      expect(
        line(completedCount: 9, dailyTarget: 12),
        'وقت المرة العاشرة. سويها الحين. ٩ من ١٢ خلّصت 👏🏼',
      );
      expect(
        line(completedCount: 10, dailyTarget: 12),
        'وقت المرة رقم ١١. سويها الحين. ١٠ من ١٢ خلّصت 👏🏼',
      );
      expect(
        line(completedCount: 11, dailyTarget: 12),
        'وقت المرة الأخيرة. سويها الحين. ١١ من ١٢ خلّصت 👏🏼',
      );
      expect(
        line(completedCount: 1, dailyTarget: 3, isAr: false),
        'Time for round two. Do it now. 1 of 3 done 👏🏼',
      );
      expect(
        line(completedCount: 2, dailyTarget: 3, isAr: false),
        'Time for the last one. Do it now. 2 of 3 done 👏🏼',
      );
      expect(
        line(completedCount: 10, dailyTarget: 12, isAr: false),
        'Time for round 11. Do it now. 10 of 12 done 👏🏼',
      );
      // Today's progress outranks the streak.
      expect(
        line(completedCount: 2, dailyTarget: 3, streak: 9),
        startsWith('وقت المرة الأخيرة.'),
      );
      // Never «المرة الأولى»: a round is only named once one is logged.
      for (var target = 2; target <= 12; target++) {
        for (var done = 1; done < target; done++) {
          expect(
            line(completedCount: done, dailyTarget: target),
            isNot(contains('الأولى')),
          );
        }
      }
      // With none logged it is the plain on-time line, and so is the
      // default, 0 of 1.
      expect(
        line(dailyTarget: 3, streak: 4, lastDoneDaysAgo: 1),
        'وقتها الحين. سوي عادتك. ملتزم صارلك ٤ أيام 👏🏼',
      );
      expect(
        line(streak: 4, lastDoneDaysAgo: 1),
        'وقتها الحين. سوي عادتك. ملتزم صارلك ٤ أيام 👏🏼',
      );
    });

    test('a timer habit never done states its real length', () {
      expect(
        line(timerSeconds: 120),
        'وقتها دقيقتين بس. سوي عادتك. بسم الله، أول مربع لها.',
      );
      expect(
        line(timerSeconds: 600, isAr: false),
        'It only takes 10 minutes. Do it now. Bismillah, its first square.',
      );
      // Done before with no streak it reads like any clock habit: Aziz saw the
      // length only in place of «وقتها الحين.» on the first-square line
      // (catalog A4, option 2).
      expect(
        line(timerSeconds: 120, lastDoneDaysAgo: 2),
        'وقتها الحين. سوي عادتك.',
      );
      expect(
        line(timerSeconds: 600, lastDoneDaysAgo: 2, isAr: false),
        "It's time. Do it now.",
      );
      // Nothing true to say: no timer, under a minute, or not whole minutes.
      expect(line(), startsWith('وقتها الحين.'));
      expect(line(timerSeconds: 30), startsWith('وقتها الحين.'));
      expect(line(timerSeconds: 90), startsWith('وقتها الحين.'));
      // The praise carries its own number; no second one stacked on top.
      expect(
        line(timerSeconds: 120, streak: 4, lastDoneDaysAgo: 1),
        isNot(contains('دقيقتين')),
      );
    });

    test('the loss and waiting words are gone from every state', () {
      const barred = [
        'خسارة',
        'تنتظر',
        'يفوت',
        'تفوت',
        'فات',
        'ضاع',
        'صار لها',
        'slip',
        'waiting',
        'A shame',
        "It's been",
      ];
      for (var i = 0; i < 12; i++) {
        for (final isAr in [true, false]) {
          for (final l in [
            line(variantIndex: i, isAr: isAr),
            line(variantIndex: i, isAr: isAr, streak: 5, lastDoneDaysAgo: 1),
            line(variantIndex: i, isAr: isAr, lastDoneDaysAgo: 4),
            line(variantIndex: i, isAr: isAr, lastDoneDaysAgo: 1),
            line(
              variantIndex: i,
              isAr: isAr,
              completedCount: 1,
              dailyTarget: 2,
            ),
            line(variantIndex: i, isAr: isAr, timerSeconds: 300),
            line(
              variantIndex: i,
              isAr: isAr,
              anchorLabel: isAr ? 'الفجر' : 'Fajr',
            ),
          ]) {
            for (final word in barred) {
              expect(l, isNot(contains(word)), reason: '"$l" says "$word"');
            }
          }
        }
      }
    });

    test('reported bug: a habit on its own schedule is never called lapsed',
        () {
      // A Wed/Sat habit done Wednesday, reminded Saturday. Three calendar
      // days, zero missed days. It used to draw «صار لها ٣ أيام، وما ضاع
      // شي. مربع واحد يرجعها».
      for (var i = 0; i < 6; i++) {
        final l = line(lastDoneDaysAgo: 3, everyDay: false, variantIndex: i);
        expect(l, isNot(contains('صار لها')));
        expect(l, isNot(contains('آخر مرة كانت')));
        expect(l, isNot(contains('ما ضاع')));
        final en = line(
          lastDoneDaysAgo: 3,
          everyDay: false,
          variantIndex: i,
          isAr: false,
        );
        expect(en, isNot(contains("It's been")));
        expect(en, isNot(contains('Last done')));
      }
      expect(
        line(lastDoneDaysAgo: 3, everyDay: false),
        'وقتها الحين. سوي عادتك.',
      );
    });

    test('a weekly quota is told where its week stands', () {
      expect(
        line(weekTarget: 3, weekDone: 1),
        '١ من ٣ هذا الأسبوع، وباقي ثنتين.',
      );
      expect(
        line(weekTarget: 3, weekDone: 1, variantIndex: 1),
        '١ من ٣ هذا الأسبوع وماشية عدل، وباقي ثنتين.',
      );
      expect(
        line(weekTarget: 4, weekDone: 1, isAr: false),
        '1 of 4 this week. 3 more to go.',
      );
      // The last-chance day says so, and skips the praise.
      expect(
        line(weekTarget: 3, weekDone: 1, owedToday: true, variantIndex: 1),
        '١ من ٣ هذا الأسبوع، وباقي ثنتين، واليوم مطلوب.',
      );
      expect(
        line(weekTarget: 3, weekDone: 2, owedToday: true, isAr: false),
        '2 of 3 this week. One more to go, and today is one of them.',
      );
      // Nothing yet and no slack left.
      expect(
        line(weekTarget: 3, weekDone: 0, owedToday: true),
        'باقي ٣ مرات هذا الأسبوع، واليوم مطلوب.',
      );
      expect(
        line(weekTarget: 3, weekDone: 0, owedToday: true, isAr: false),
        '3 more to go this week, and today is one of them.',
      );
      // Target met: the rest of the week owes nothing, and the line says so
      // rather than nagging.
      expect(
        line(weekTarget: 3, weekDone: 3),
        'هدف الأسبوع تم، ٣ من ٣، ومربع اليوم زيادة.',
      );
      expect(
        line(weekTarget: 3, weekDone: 4, isAr: false),
        'Week target met, 4 of 3. Today is a bonus square.',
      );
    });

    test('a weekly quota is never late by the calendar', () {
      // Done Monday, reminded Wednesday, two of three still open.
      final spare = line(weekTarget: 3, weekDone: 0, lastDoneDaysAgo: 2);
      expect(spare, isNot(contains('صار لها')));
      expect(spare, 'وقتها الحين. سوي عادتك.');
      // An unknown week (no weekDone) claims nothing about the week either
      // way.
      final unknown = line(weekTarget: 3, lastDoneDaysAgo: 2);
      expect(unknown, isNot(contains('هذا الأسبوع')));
      expect(unknown, isNot(contains('صار لها')));
      // And it is never praised: a calendar streak says nothing true about a
      // week.
      final withStreak =
          line(weekTarget: 3, weekDone: 0, streak: 5, lastDoneDaysAgo: 1);
      expect(withStreak, isNot(contains('ملتزم')));
      expect(withStreak, isNot(contains('ورا بعض')));
      // Even a whole empty week no longer names a gap.
      expect(
        line(weekTarget: 3, weekDone: 0, lastDoneDaysAgo: 14),
        'وقتها الحين. سوي عادتك.',
      );
    });

    test('the same habit on the same day always picks the same line', () {
      // Rescheduling mid-day (habit list edited, reminder time nudged) must
      // not visibly reword a notification that is already pending.
      for (var i = 0; i < 12; i++) {
        expect(line(variantIndex: i), line(variantIndex: i));
      }
      // Negative seeds are reachable: the caller mixes in a habit id's
      // hashCode, which is signed.
      expect(() => line(variantIndex: -7), returnsNormally);
      expect(line(variantIndex: -7), isNotEmpty);
    });

    test('no line uses the old formal imperatives', () {
      // The old pool's «حافظ», «ابدأ», «لا تدع» were MSA commands, and «لوّن»
      // rode two of the late asks. Aziz's picks keep one short spoken ask.
      const formal = ['حافظ', 'ابدأ', 'لا تدع', 'لوّن', 'لا تفقد', 'لا تكسر'];
      for (var i = 0; i < 12; i++) {
        for (final state in [
          line(variantIndex: i),
          line(variantIndex: i, streak: 5, lastDoneDaysAgo: 1),
          line(variantIndex: i, lastDoneDaysAgo: 4),
          line(variantIndex: i, completedCount: 1, dailyTarget: 2),
          line(variantIndex: i, lastDoneDaysAgo: 1),
          lateReminderAsk(i, true),
        ]) {
          for (final verb in formal) {
            expect(state, isNot(contains(verb)));
          }
        }
      }
    });
  });

  group('action buttons', () {
    test('speak the same language as the notification above them', () {
      // They were English on an Arabic device: the one part of the ping the
      // reader is meant to act on was the one part not in their language.
      expect(markDoneAction(true), 'تمت');
      expect(snoozeAction(true), 'تأجيل ساعة');
      expect(onTrackAction(true), 'التزام');
      expect(slippedAction(true), 'زلة');
      expect(markDoneAction(false), 'Mark Done');
      expect(snoozeAction(false), 'Snooze 1h');
      expect(onTrackAction(false), 'On Track');
      expect(slippedAction(false), 'Slipped');
    });

    test('are nominal, so no button has a gender to get wrong', () {
      // «سجّل» / «أجّل» would each have to pick one. A button label is also
      // truncated hard by both platforms, hence the length bound.
      for (final label in [
        markDoneAction(true),
        snoozeAction(true),
        onTrackAction(true),
        slippedAction(true),
      ]) {
        expect(label, isNot(startsWith('سجّل')));
        expect(label, isNot(startsWith('أجّل')));
        expect(label.length, lessThanOrEqualTo(12));
      }
    });

    test("a task alarm's Done names what the tap records", () {
      // It sits beside the system's Stop, where a bare «تم» did not say
      // whether it stopped the alarm or finished the task. Still inside the
      // length bound above, since a button label is truncated hard.
      expect(taskDoneAction(true), 'خلّصت المهمة');
      expect(taskDoneAction(false), 'I did the task');
      expect(taskDoneAction(true).length, lessThanOrEqualTo(12));
    });
  });

  group('snoozedReminderBody', () {
    test('states the hour it knows, not a moment it does not', () {
      expect(snoozedReminderBody(true), 'صار لها ساعة من التأجيل.');
      expect(snoozedReminderBody(false), 'An hour since you snoozed.');
      // The reminder being snoozed may itself have been an early or a late
      // one, so this path cannot honestly claim the moment has come.
      expect(snoozedReminderBody(true), isNot(contains('حان الوقت')));
      expect(snoozedReminderBody(false), isNot(contains("It's time")));
    });
  });

  group('habitBundleTitle', () {
    test('names the habits, joined the way Arabic joins them', () {
      expect(
        habitBundleTitle(names: ['سنة الفجر', 'أذكار الصباح'], isAr: true),
        'سنة الفجر وأذكار الصباح',
      );
      expect(
        habitBundleTitle(
          names: ['سنة الفجر', 'أذكار الصباح', 'الوتر'],
          isAr: true,
        ),
        'سنة الفجر، أذكار الصباح والوتر',
      );
      expect(
        habitBundleTitle(names: ['Fajr Sunnah', 'Morning Adhkar'], isAr: false),
        'Fajr Sunnah and Morning Adhkar',
      );
      expect(
        habitBundleTitle(names: ['Fajr Sunnah', 'Witr', 'Duha'], isAr: false),
        'Fajr Sunnah, Witr and Duha',
      );
    });

    test('counts instead when the names do not fit one line', () {
      expect(
        habitBundleTitle(
          names: ['سنة الفجر', 'أذكار الصباح', 'قراءة القرآن'],
          isAr: true,
        ),
        '٣ عادات',
      );
      expect(
        habitBundleTitle(
          names: ['قراءة سورة الكهف', 'أذكار المساء كاملة'],
          isAr: true,
        ),
        'عادتين',
      );
      expect(
        habitBundleTitle(
          names: [for (var i = 0; i < 11; i++) 'عادة $i'],
          isAr: true,
        ),
        '١١ عادة',
      );
      expect(
        habitBundleTitle(
          names: ['Morning Adhkar', 'Evening Adhkar', 'Quran'],
          isAr: false,
        ),
        '3 habits',
      );
      for (final names in [
        ['سنة الفجر', 'أذكار الصباح'],
        ['سنة الفجر', 'أذكار الصباح', 'قراءة القرآن'],
      ]) {
        expect(
          habitBundleTitle(names: names, isAr: true).length,
          lessThanOrEqualTo(kBundleTitleMaxChars),
        );
      }
    });

    test('never says the habits are waiting', () {
      for (final names in [
        ['سنة الفجر', 'أذكار الصباح'],
        ['قراءة سورة الكهف', 'أذكار المساء كاملة', 'الوتر'],
      ]) {
        final title = habitBundleTitle(names: names, isAr: true);
        for (final word in ['بانتظارك', 'تنتظرك', 'جاهز']) {
          expect(title, isNot(contains(word)));
        }
      }
      expect(
        habitBundleTitle(
          names: ['Morning Adhkar', 'Evening Adhkar', 'Quran'],
          isAr: false,
        ),
        isNot(contains('waiting')),
      );
    });
  });

  group('habitBundleBody', () {
    final fajr = DateTime(2026, 9, 12, 4, 17);
    final clock = DateTime(2026, 9, 12, 8, 45);
    BundleMember m({
      int offset = 0,
      String? anchor,
      DateTime? at,
      int streak = 0,
      bool everyDay = true,
      bool isQuota = false,
    }) =>
        (
          offsetMinutes: offset,
          anchorLabel: anchor,
          fireTime: at ?? fajr,
          streak: streak,
          everyDay: everyDay,
          isQuota: isQuota,
        );

    test('one prayer, the same shift after it: the loved shape, for all', () {
      final late = fajr.add(const Duration(minutes: 15));
      expect(
        habitBundleBody(
          members: [
            m(offset: 15, anchor: 'الفجر', at: late, streak: 3),
            m(offset: 15, anchor: 'الفجر', at: late, streak: 5),
          ],
          isAr: true,
        ),
        'اذن الفجر قبل ١٥ دقيقة. سوي عاداتك الحين. ملتزم صارلك ٣ أيام 👏🏼',
      );
      expect(
        habitBundleBody(
          members: [
            m(offset: 15, anchor: 'Fajr', at: late, streak: 3),
            m(offset: 15, anchor: 'Fajr', at: late, streak: 5),
          ],
          isAr: false,
        ),
        "Fajr was 15 minutes ago. Do them now. You've kept it up 3 days 👏🏼",
      );
    });

    test('the same shift before, at the same minute', () {
      final early = fajr.subtract(const Duration(minutes: 15));
      expect(
        habitBundleBody(
          members: [
            m(offset: -15, anchor: 'الفجر', at: early, streak: 3),
            m(offset: -15, anchor: 'الفجر', at: early, streak: 4),
          ],
          isAr: true,
        ),
        'باقي ١٥ دقيقة على أذان الفجر. خلّك جاهز. ملتزم صارلك ٣ أيام 👏🏼',
      );
      expect(
        habitBundleBody(
          members: [
            m(offset: -15, at: clock, streak: 2),
            m(offset: -15, at: clock, streak: 9),
          ],
          isAr: true,
        ),
        'باقي ١٥ دقيقة على وقتها. خلّك جاهز. ملتزم صارلك يومين 👏🏼',
      );
      expect(
        habitBundleBody(
          members: [m(offset: -15, at: clock), m(offset: -15, at: clock)],
          isAr: false,
        ),
        '15 minutes to go. Get ready.',
      );
    });

    test('on the dot: one adhan, or one clock minute', () {
      expect(
        habitBundleBody(
          members: [m(anchor: 'المغرب'), m(anchor: 'المغرب')],
          isAr: true,
        ),
        'اذن المغرب. سوي عاداتك الحين.',
      );
      expect(
        habitBundleBody(members: [m(at: clock), m(at: clock)], isAr: true),
        'وقتها الحين. سويها وحدة وحدة.',
      );
      expect(
        habitBundleBody(members: [m(at: clock), m(at: clock)], isAr: false),
        "It's time. One at a time.",
      );
    });

    test('a mixed bundle says only what is true of every member', () {
      expect(
        habitBundleBody(
          members: [
            m(offset: -15, at: clock, streak: 3),
            m(at: clock, streak: 3),
          ],
          isAr: true,
        ),
        'عادتين مع بعض. سويها وحدة وحدة. ملتزم صارلك ٣ أيام 👏🏼',
      );
      // The same shift at different minutes: 9:00 and 9:10, both 15 early.
      expect(
        habitBundleBody(
          members: [
            m(offset: -15, at: clock),
            m(offset: -15, at: clock.add(const Duration(minutes: 10))),
            m(offset: -15, at: clock),
          ],
          isAr: true,
        ),
        '٣ عادات مع بعض. سويها وحدة وحدة.',
      );
      expect(
        habitBundleBody(
          members: [m(offset: -15, at: clock), m(at: clock)],
          isAr: false,
        ),
        'Two habits together. One at a time.',
      );
    });

    test('the praise is said only when it is true of every member', () {
      String body(List<BundleMember> members) =>
          habitBundleBody(members: members, isAr: true);
      // The smallest streak among them.
      expect(
        body([m(at: clock, streak: 12), m(at: clock, streak: 4)]),
        endsWith('ملتزم صارلك ٤ أيام 👏🏼'),
      );
      // All on set weekdays: counted in times.
      expect(
        body([
          m(at: clock, streak: 2, everyDay: false),
          m(at: clock, streak: 6, everyDay: false),
        ]),
        endsWith('ملتزم مرتين ورا بعض 👏🏼'),
      );
      // A member with no streak, a quota member, or a mix of cadences.
      for (final members in [
        [m(at: clock, streak: 5), m(at: clock)],
        [m(at: clock, streak: 5), m(at: clock, streak: 5, isQuota: true)],
        [m(at: clock, streak: 5), m(at: clock, streak: 5, everyDay: false)],
        // Weekday habits whose smallest run is one: that praise, «سويتها آخر
        // مرة», is about a single habit and would follow the plural ask.
        [
          m(at: clock, streak: 1, everyDay: false),
          m(at: clock, streak: 4, everyDay: false),
        ],
      ]) {
        expect(body(members), isNot(contains('👏🏼')));
        expect(body(members), isNot(contains('ملتزم')));
      }
    });
  });
}
