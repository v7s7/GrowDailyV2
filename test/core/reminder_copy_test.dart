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
        'فات وقتها قبل ساعة',
      );
      expect(
        overdueTaskReminderTitle(minutesLate: 60, isAr: false),
        'This was due 1 hour ago',
      );
    });

    test('a catch-up days later still reads correctly', () {
      expect(
        overdueTaskReminderTitle(minutesLate: 2880, isAr: true),
        'فات وقتها قبل يومين',
      );
      expect(
        overdueTaskReminderTitle(minutesLate: 2880, isAr: false),
        'This was due 2 days ago',
      );
    });

    test('a catch-up fired within the same minute falls back gracefully', () {
      // Rather than "فات وقتها قبل ٠ دقيقة".
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
    }) =>
        habitReminderBody(
          offsetMinutes: offset,
          streak: streak,
          anchorLabel: anchor,
          isAr: isAr,
          onTimeLine: isAr ? 'حان الوقت.' : "It's time.",
        );

    test('on time is left exactly as it was', () {
      expect(body(offset: 0), 'حان الوقت.');
      expect(body(offset: 0, isAr: false), "It's time.");
    });

    test('a prayer-anchored habit names the prayer it is counting to', () {
      expect(body(offset: -45, anchor: 'المغرب'), 'باقي ٤٥ دقيقة على المغرب.');
      expect(
        body(offset: -45, anchor: 'Maghrib', isAr: false),
        '45 minutes until Maghrib.',
      );
      expect(body(offset: 20, anchor: 'الفجر'), 'فات الفجر قبل ٢٠ دقيقة.');
      expect(
        body(offset: 20, anchor: 'Fajr', isAr: false),
        'Fajr was 20 minutes ago.',
      );
    });

    test('a clock-time habit does not read its own clock back to itself', () {
      expect(body(offset: -15), 'باقي ١٥ دقيقة على وقتها.');
      expect(body(offset: -15, isAr: false), '15 minutes to go.');
      expect(body(offset: 30), 'فات وقتها قبل ٣٠ دقيقة.');
      expect(body(offset: 30, isAr: false), '30 minutes past due.');
    });

    test('the streak is still the reason to act, so it is kept', () {
      // The day count declines like every count in this module: «٧ أيام»
      // for 3-10, dual for two, singular from 11 up.
      expect(
        body(offset: -15, streak: 7),
        'باقي ١٥ دقيقة على وقتها. ٧ أيام ورا بعض، واليوم يخليها ٨.',
      );
      expect(
        body(offset: -15, streak: 2),
        'باقي ١٥ دقيقة على وقتها. يومين ورا بعض، واليوم يخليها ٣.',
      );
      expect(
        body(offset: -15, streak: 15),
        'باقي ١٥ دقيقة على وقتها. ١٥ يوم ورا بعض، واليوم يخليها ١٦.',
      );
      expect(
        body(offset: -15, streak: 7, isAr: false),
        '15 minutes to go. 7 days in a row. Today makes it 8.',
      );
      // And an on-time reminder with a streak is untouched: its caller
      // already passes the streak line in as onTimeLine.
      expect(body(offset: 0, streak: 7), 'حان الوقت.');
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
      // Defaults to what a DAILY habit has missed: every day since the last
      // one but today. The scheduled-habit tests below pass it explicitly.
      int? missedSinceLastDone,
      int? timerSeconds,
      int variantIndex = 0,
      bool isAr = true,
      bool everyDay = true,
      int? weekTarget,
      int? weekDone,
      bool owedToday = false,
    }) =>
        habitOnTimeLine(
          streak: streak,
          completedCount: completedCount,
          dailyTarget: dailyTarget,
          lastDoneDaysAgo: lastDoneDaysAgo,
          missedSinceLastDone: missedSinceLastDone ??
              (lastDoneDaysAgo == null ? 0 : (lastDoneDaysAgo - 1).clamp(0, 999)),
          timerSeconds: timerSeconds,
          variantIndex: variantIndex,
          isAr: isAr,
          everyDay: everyDay,
          weekTarget: weekTarget,
          weekDone: weekDone,
          owedToday: owedToday,
        );

    test('today\'s progress outranks everything else it could say', () {
      // The one fact the habit's own name in the title cannot show.
      expect(
        line(completedCount: 2, dailyTarget: 3),
        '٢ من ٣ اليوم، وباقي وحدة.',
      );
      expect(
        line(completedCount: 1, dailyTarget: 3),
        '١ من ٣ اليوم، وباقي ثنتين.',
      );
      expect(
        line(completedCount: 1, dailyTarget: 5),
        '١ من ٥ اليوم، وباقي ٤ مرات.',
      );
      expect(
        line(completedCount: 2, dailyTarget: 3, isAr: false),
        '2 of 3 today. One more to go.',
      );
      // Even with a streak running: partial progress is more specific.
      expect(
        line(completedCount: 2, dailyTarget: 3, streak: 9),
        startsWith('٢ من ٣'),
      );
    });

    test('a streak speaks for itself once nothing is logged today', () {
      expect(line(streak: 4), habitStreakLine(4, true));
      expect(line(streak: 4, isAr: false), habitStreakLine(4, false));
      // And it rotates with the state's own variant, so a long streak
      // isn't the same sentence every single day.
      expect(
        line(streak: 4, variantIndex: 1),
        habitStreakLine(4, true, variantIndex: 1),
      );
      expect(
        line(streak: 4, variantIndex: 1),
        isNot(line(streak: 4, variantIndex: 0)),
      );
      // A single-target habit with today already done never reaches here
      // (the scheduler stands its reminder down), so 0-of-1 is the state
      // that must NOT be reported as progress.
      expect(line(streak: 4, completedCount: 0, dailyTarget: 1),
          habitStreakLine(4, true));
    });

    test('a habit never once completed is asked for its first square', () {
      // The exact state the old pool handled worst: it drew a generic
      // «بضع دقائق لهذه العادة اليوم» for a habit created minutes ago.
      for (var i = 0; i < 6; i++) {
        final l = line(variantIndex: i);
        expect(l, isNot(contains('بضع دقائق لهذه العادة')));
        expect(l, isNot(contains('سلسلة')));
      }
      expect(
        line(variantIndex: 0),
        'أول مربع فيها اليوم، ومن هنا تبدأ العادة.',
      );
      expect(
        line(variantIndex: 0, isAr: false),
        'First square today. This is where it starts.',
      );
    });

    test('a lapsed habit gets the gap named and no blame attached', () {
      expect(
        line(lastDoneDaysAgo: 3, variantIndex: 0),
        'صار لها ٣ أيام. مربع واحد اليوم وترجع السلسلة.',
      );
      expect(
        line(lastDoneDaysAgo: 2, variantIndex: 1),
        'آخر مرة كانت قبل يومين، واليوم بداية جديدة لها.',
      );
      expect(
        line(lastDoneDaysAgo: 3, variantIndex: 0, isAr: false),
        "It's been 3 days. One square today and the streak is back.",
      );
      // Never-completed is a different state and must not borrow this one:
      // there is no gap to name.
      expect(line(variantIndex: 0), isNot(contains('صار لها')));
    });

    test('a timer habit states its real length instead of "a few minutes"', () {
      expect(
        line(timerSeconds: 120, variantIndex: 1),
        'وقتها دقيقتين بس. عادة جديدة تنتظر أول مربع لها.',
      );
      expect(
        line(timerSeconds: 600, variantIndex: 1, isAr: false),
        'It only takes 10 minutes. A new habit waiting on its first square.',
      );
      // Nothing true to say: no timer, under a minute, or not a whole
      // number of minutes.
      expect(line(variantIndex: 1), isNot(contains('وقتها')));
      expect(line(timerSeconds: 30, variantIndex: 1), isNot(contains('وقتها')));
      expect(line(timerSeconds: 90, variantIndex: 1), isNot(contains('وقتها')));
      // And a state that already carries its own numbers doesn't stack a
      // second one on top.
      expect(
        line(timerSeconds: 120, streak: 4),
        isNot(contains('وقتها دقيقتين')),
      );
    });

    test('says it is going well where there is something to say it about',
        () {
      // Praise belongs where the app can point at something: progress
      // logged today, or a streak that is running.
      expect(
        line(completedCount: 2, dailyTarget: 3, variantIndex: 1),
        '٢ من ٣ اليوم وماشية عدل، وباقي وحدة.',
      );
      expect(
        line(completedCount: 2, dailyTarget: 3, variantIndex: 1, isAr: false),
        '2 of 3 today and going well. One more to go.',
      );
      expect(habitStreakLine(9, true, variantIndex: 1), contains('ماشية عدل'));
      expect(
        habitStreakLine(9, false, variantIndex: 1),
        contains('going strong'),
      );
      // But never at someone who has already missed days: a lapsed habit
      // has nothing going well to congratulate, and saying so would read
      // as sarcasm.
      for (var i = 0; i < 6; i++) {
        final lapsed = line(lastDoneDaysAgo: 4, variantIndex: i);
        expect(lapsed, isNot(contains('ماشية عدل')));
        expect(lapsed, isNot(contains('going well')));
      }
    });

    test('says it would be a shame to skip where there is no praise to give',
        () {
      // The other half of what a reminder is for. Phrased about the day or
      // the square, never as «لا تفوّتها», which would have to pick a
      // gender for the person reading it.
      expect(line(variantIndex: 3), 'أول مربع فيها اليوم، وخسارة يفوت.');
      expect(line(variantIndex: 3, isAr: false),
          'First square today. A shame to let it slip.');
      expect(
        line(lastDoneDaysAgo: 1, variantIndex: 2),
        'وقتها الحين، وخسارة لو تفوت اليوم.',
      );
      expect(
        line(lastDoneDaysAgo: 1, variantIndex: 2, isAr: false),
        "It's time. Don't let today slip by.",
      );
      // A lapsed habit is told nothing is lost, not that it slipped.
      expect(
        line(lastDoneDaysAgo: 4, variantIndex: 2),
        'صار لها ٤ أيام، وما ضاع شي. مربع واحد يرجعها.',
      );
    });

    test('reported bug: a habit on its own schedule is never called lapsed',
        () {
      // A Wed/Sat habit done Wednesday, reminded Saturday. Three calendar
      // days, zero missed days. It used to draw «صار لها ٣ أيام، وما ضاع
      // شي. مربع واحد يرجعها», telling someone exactly on time that it was
      // fine to be late.
      for (var i = 0; i < 6; i++) {
        final l = line(
          lastDoneDaysAgo: 3,
          missedSinceLastDone: 0,
          everyDay: false,
          variantIndex: i,
        );
        expect(l, isNot(contains('صار لها')));
        expect(l, isNot(contains('آخر مرة')));
        expect(l, isNot(contains('ما ضاع')));
        final en = line(
          lastDoneDaysAgo: 3,
          missedSinceLastDone: 0,
          everyDay: false,
          variantIndex: i,
          isAr: false,
        );
        expect(en, isNot(contains("It's been")));
        expect(en, isNot(contains('Last done')));
      }
      // With nothing else to say it gets the plain on-time line.
      expect(
        line(lastDoneDaysAgo: 3, missedSinceLastDone: 0, everyDay: false),
        'وقتها الحين، ومربع اليوم على بعد دقايق.',
      );
    });

    test('a scheduled habit\'s streak counts times, not days', () {
      // Its streak is counted on the days it runs (see scheduledGap), so
      // «٤ أيام ورا بعض» would read as four consecutive calendar days and be
      // false for a Wed/Sat habit.
      expect(
        line(streak: 4, lastDoneDaysAgo: 3, missedSinceLastDone: 0,
            everyDay: false),
        '٤ مرات ورا بعض، واليوم يخليها ٥.',
      );
      expect(
        line(streak: 1, lastDoneDaysAgo: 3, missedSinceLastDone: 0,
            everyDay: false),
        'مرة وحدة في السلسلة، واليوم يخليها ثنتين.',
      );
      expect(
        line(streak: 2, lastDoneDaysAgo: 3, missedSinceLastDone: 0,
            everyDay: false),
        'ثنتين ورا بعض، واليوم يخليها ٣.',
      );
      expect(
        line(streak: 4, lastDoneDaysAgo: 3, missedSinceLastDone: 0,
            everyDay: false, isAr: false),
        '4 in a row. Today makes it 5.',
      );
      // The every-day wording is byte-identical to what shipped.
      expect(line(streak: 4), '٤ أيام ورا بعض، واليوم يخليها ٥.');
    });

    test('a real miss on a scheduled habit is still named', () {
      // Wed/Sat habit, done a Saturday, Wednesday skipped, reminded the next
      // Saturday. One missed day; the calendar gap is still how long it has
      // actually been.
      expect(
        line(lastDoneDaysAgo: 7, missedSinceLastDone: 1, everyDay: false),
        'صار لها ٧ أيام. مربع واحد اليوم وترجع السلسلة.',
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
      // Done Monday, reminded Wednesday, two of three still open: two days
      // is a fact and not a lapse.
      final spare = line(
        weekTarget: 3,
        weekDone: 0,
        lastDoneDaysAgo: 2,
        missedSinceLastDone: 0,
      );
      expect(spare, isNot(contains('صار لها')));
      expect(spare, 'وقتها الحين، ومربع اليوم على بعد دقايق.');
      // An unknown week claims nothing about the week either way.
      final unknown = line(
        weekTarget: 3,
        weekDone: null,
        lastDoneDaysAgo: 2,
        missedSinceLastDone: 0,
      );
      expect(unknown, isNot(contains('هذا الأسبوع')));
      expect(unknown, isNot(contains('صار لها')));
      // And it never draws the streak line: a calendar streak says nothing
      // true about a week.
      expect(
        line(weekTarget: 3, weekDone: 0, streak: 5),
        isNot(contains('ورا بعض')),
      );
      // A proven lapse (a whole empty week) is still named.
      expect(
        line(
          weekTarget: 3,
          weekDone: 0,
          lastDoneDaysAgo: 14,
          missedSinceLastDone: 3,
        ),
        'صار لها ١٤ يوم. مربع واحد اليوم وترجع السلسلة.',
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

    test('no line addresses the reader with a gendered verb', () {
      // The register this file documents: the old pool's «حافظ», «ابدأ»,
      // «لا تدع» were all masculine, and half the people reading them are
      // not. Every line below talks about the habit or the day instead.
      const gendered = ['حافظ', 'ابدأ', 'لا تدع', 'لوّن', 'لا تفقد', 'لا تكسر'];
      for (var i = 0; i < 12; i++) {
        for (final state in [
          line(variantIndex: i),
          line(variantIndex: i, streak: 5),
          line(variantIndex: i, lastDoneDaysAgo: 4),
          line(variantIndex: i, completedCount: 1, dailyTarget: 2),
          line(variantIndex: i, lastDoneDaysAgo: 1),
        ]) {
          for (final verb in gendered) {
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
    test('all on time keeps "ready", which is true of all of them', () {
      // Two takes the dual — «2 عادات» is the exact class of error
      // countedOffsetPhrase exists to avoid, and two is a bundle's most
      // common size.
      expect(
        habitBundleTitle(offsetMinutes: [0, 0], isAr: true),
        'عادتين جاهزتين',
      );
      expect(
        habitBundleTitle(offsetMinutes: [0, 0, 0], isAr: true),
        '٣ عادات جاهزة',
      );
      expect(
        habitBundleTitle(offsetMinutes: [0, 0, 0], isAr: false),
        '3 habits ready',
      );
    });

    test('all early by the same amount counts down for the group', () {
      expect(
        habitBundleTitle(offsetMinutes: [-15, -15], isAr: true),
        'باقي ١٥ دقيقة على عادتين',
      );
      expect(
        habitBundleTitle(offsetMinutes: [-60, -60], isAr: false),
        '1 hour until 2 habits',
      );
    });

    test('a mixed bundle says the one thing true of every member', () {
      // Bundling groups by the clock and knows nothing about offsets, so a
      // 9:00 habit reminded 15 minutes early and an 8:50 one reminded on
      // time genuinely share a notification.
      expect(
        habitBundleTitle(offsetMinutes: [-15, 0], isAr: true),
        'عادتين بانتظارك',
      );
      expect(
        habitBundleTitle(offsetMinutes: [-15, -30], isAr: true),
        'عادتين بانتظارك',
      );
      expect(
        habitBundleTitle(offsetMinutes: [10, 10], isAr: false),
        '2 habits waiting',
      );
    });

    test('"ready" is reserved for bundles that really are', () {
      for (final offsets in [
        [-15, -15],
        [-15, 0],
        [20, 20],
        [-60, 30],
      ]) {
        expect(
          habitBundleTitle(offsetMinutes: offsets, isAr: true),
          isNot(contains('جاهزة')),
          reason: '$offsets does not describe a bundle that is ready now',
        );
      }
    });
  });
}
