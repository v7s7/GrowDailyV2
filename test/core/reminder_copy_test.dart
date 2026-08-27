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
      expect(
        body(offset: -15, streak: 7),
        'باقي ١٥ دقيقة على وقتها. لا تفقد سلسلتك المكوّنة من 7 يوم.',
      );
      expect(
        body(offset: -15, streak: 7, isAr: false),
        "15 minutes to go. Don't lose your 7-day streak.",
      );
      // And an on-time reminder with a streak is untouched: its caller
      // already passes the streak line in as onTimeLine.
      expect(body(offset: 0, streak: 7), 'حان الوقت.');
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
      expect(
        habitBundleTitle(offsetMinutes: [0, 0], isAr: true),
        '2 عادات جاهزة',
      );
      expect(
        habitBundleTitle(offsetMinutes: [0, 0, 0], isAr: false),
        '3 habits ready',
      );
    });

    test('all early by the same amount counts down for the group', () {
      expect(
        habitBundleTitle(offsetMinutes: [-15, -15], isAr: true),
        'باقي ١٥ دقيقة على 2 عادات',
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
        '2 عادات تنتظرك',
      );
      expect(
        habitBundleTitle(offsetMinutes: [-15, -30], isAr: true),
        '2 عادات تنتظرك',
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
