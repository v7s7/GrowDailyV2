// PrayerWidgetFeed.flatten — what the prayer-countdown widget is handed.
//
// The widget (ios/GrowDailyWidget/PrayerCountdownWidget.swift) does no
// calculation of its own: it picks the next instant out of this list and
// counts to it. So the two things this list has to get right are the ONLY
// two things that can make the face wrong — which prayers are in it, and
// where it starts.
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

  test('sunrise leaves the list the moment it passes', () {
    final schedule = [_day(zone, DateTime(2026, 9, 23))];

    // One minute before the fixture's 05:30 sunrise.
    final before = PrayerWidgetFeed.flatten(
      schedule,
      from: DateTime(2026, 9, 23, 5, 29),
    );
    expect(before.first.key, 'sunrise', reason: 'a minute before, it is next');

    // 05:31 — one minute after. No adhan was called, so there is nothing to
    // say «مضى على الأذان» about and the face moves straight to Dhuhr, where
    // a prayer at the same moment would have stayed for half an hour.
    final after = PrayerWidgetFeed.flatten(
      schedule,
      from: DateTime(2026, 9, 23, 5, 31),
    );
    expect(after.first.key, 'dhuhr');
    expect(PrayerWidgetFeed.elapsedWindowFor('sunrise'), Duration.zero);
    expect(PrayerWidgetFeed.elapsedWindowFor('fajr'),
        PrayerWidgetFeed.elapsedWindow);
  });

  test('drops a prayer once its elapsed window has closed', () {
    final schedule = [_day(zone, DateTime(2026, 9, 23))];

    // 12:01 — thirty-one minutes past Dhuhr. The half hour is over and the
    // face has already moved on to Asr.
    final out = PrayerWidgetFeed.flatten(
      schedule,
      from: DateTime(2026, 9, 23, 12, 1),
    );

    expect(out.first.key, 'asr');
  });

  test('the elapsed window matches the widget\'s own', () {
    // ios/GrowDailyWidget/PrayerCountdownWidget.swift's
    // prayerElapsedWindow. A shorter window here would delete the very
    // prayer the widget is showing; a longer one would leave a dead prayer
    // in the list for the widget to skip.
    expect(PrayerWidgetFeed.elapsedWindow, const Duration(minutes: 30));
  });
}
