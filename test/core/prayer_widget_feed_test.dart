// PrayerWidgetFeed.flatten — what the prayer-countdown widget is handed.
//
// The widget (ios/GrowDailyWidget/PrayerCountdownWidget.swift) does no
// calculation of its own: it picks the next instant out of this list and
// counts to it. So the two things this list has to get right are the ONLY
// two things that can make the face wrong — which prayers are in it, and
// where it starts.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/services/prayer_times_service.dart';
import 'package:grow_daily_v2/core/services/prayer_widget_feed.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// One day of prayers, every time an offset in minutes from that day's
/// midnight — close enough to a real Bahrain day to read at a glance.
PrayerDayTimes _day(tz.Location zone, DateTime date) {
  tz.TZDateTime at(int hour, int minute) =>
      tz.TZDateTime(zone, date.year, date.month, date.day, hour, minute);
  return PrayerDayTimes(
    fajr: at(4, 10),
    sunrise: at(5, 30),
    dhuhr: at(11, 30),
    asr: at(14, 50),
    maghrib: at(17, 30),
    isha: at(19, 0),
  );
}

void main() {
  late tz.Location zone;

  setUpAll(() {
    tz_data.initializeTimeZones();
    zone = tz.getLocation('Asia/Bahrain');
  });

  test('carries the five prayers and sunrise of every day, in order', () {
    final start = DateTime(2026, 9, 23);
    final schedule = [
      for (var i = 0; i < 3; i++)
        _day(zone, DateTime(start.year, start.month, start.day + i)),
    ];

    final out = PrayerWidgetFeed.flatten(schedule, from: start);

    expect(out.length, 18, reason: '3 days x (5 prayers + sunrise)');
    expect(
      out.take(6).map((e) => e.key),
      ['fajr', 'sunrise', 'dhuhr', 'asr', 'maghrib', 'isha'],
    );
    // Strictly ascending: the widget builds a timeline straight off this
    // order, and WidgetKit silently drops an entry that goes backwards.
    for (var i = 1; i < out.length; i++) {
      expect(out[i].at.isAfter(out[i - 1].at), isTrue);
    }
  });

  test('keeps the prayer whose adhan just passed, drops the one before it',
      () {
    final date = DateTime(2026, 9, 23);
    final schedule = [_day(zone, date)];

    // 11:50 — twenty minutes past Dhuhr (11:30), which is exactly the
    // prayer the face is showing right now, counting «مضى على الأذان» up.
    // Fajr (04:10) is long gone.
    final out = PrayerWidgetFeed.flatten(
      schedule,
      from: DateTime(2026, 9, 23, 11, 50),
    );

    expect(out.first.key, 'dhuhr');
    expect(out.map((e) => e.key), ['dhuhr', 'asr', 'maghrib', 'isha']);
  });

  test('sunrise stays a quarter hour after it passes, then leaves', () {
    final schedule = [_day(zone, DateTime(2026, 9, 23))];
    String firstAt(int hour, int minute) => PrayerWidgetFeed.flatten(
          schedule,
          from: DateTime(2026, 9, 23, hour, minute),
        ).first.key;

    // One minute before the fixture's 05:30 sunrise, it is next.
    expect(firstAt(5, 29), 'sunrise');
    // 05:44, fourteen minutes after: the face is counting «مضى على الشروق»
    // up. Until 2026-09-25 sunrise left the list the moment it passed, and
    // the face was already counting down to Dhuhr here.
    expect(firstAt(5, 44), 'sunrise');
    // 05:45, its fifteen minutes are over.
    expect(firstAt(5, 45), 'dhuhr');
  });

  test('a prayer stays 25 minutes after its adhan, Maghrib 15', () {
    final schedule = [_day(zone, DateTime(2026, 9, 23))];
    String firstAt(int hour, int minute) => PrayerWidgetFeed.flatten(
          schedule,
          from: DateTime(2026, 9, 23, hour, minute),
        ).first.key;

    // Fajr 04:10: still showing at 04:34, gone at 04:35, where the face
    // turns to «باقي على الشروق».
    expect(firstAt(4, 34), 'fajr');
    expect(firstAt(4, 35), 'sunrise');
    // Dhuhr 11:30, the same 25 minutes.
    expect(firstAt(11, 54), 'dhuhr');
    expect(firstAt(11, 55), 'asr');
    // Maghrib 17:30 keeps only 15.
    expect(firstAt(17, 44), 'maghrib');
    expect(firstAt(17, 45), 'isha');
  });

  test('the minutes match the widget\'s own table', () {
    // The widget applies the same windows against its own clock
    // (prayerElapsedMinutes in ios/GrowDailyWidget/PrayerSchedule.swift). A
    // shorter window here would delete the very moment the face is showing;
    // a longer one would leave a dead moment in the list for the widget to
    // skip. So the Swift table is read, not restated.
    final swift =
        File('ios/GrowDailyWidget/PrayerSchedule.swift').readAsStringSync();
    final table = RegExp(r'let prayerElapsedMinutes[^=]*=\s*\[([^\]]*)\]')
        .firstMatch(swift);
    expect(table, isNotNull, reason: 'prayerElapsedMinutes moved or renamed');
    final swiftMinutes = {
      for (final m in RegExp(r'"(\w+)":\s*(\d+)').allMatches(table!.group(1)!))
        m.group(1)!: int.parse(m.group(2)!),
    };

    expect(PrayerWidgetFeed.elapsedMinutes, swiftMinutes);
    // Aziz's numbers, 2026-09-25.
    expect(PrayerWidgetFeed.elapsedMinutes, {
      'fajr': 25,
      'sunrise': 15,
      'dhuhr': 25,
      'asr': 25,
      'maghrib': 15,
      'isha': 25,
    });
  });
}
