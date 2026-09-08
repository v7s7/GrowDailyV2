// PrayerTimesService.calculateDays — the multi-day source the reminder
// window is armed from.
//
// The window exists so a phone that is not opened tomorrow still has
// tomorrow's reminder waiting, and it is only worth anything if each day in
// it carries its OWN prayer times: Fajr moves by about a minute every other
// day, so four copies of one frozen moment would be four reminders drifting
// away from the prayer they name.
//
// Two paths, and neither touches the network here. Bahrain is answered from
// the bundled official table and never makes a request at all; everywhere
// else goes through Aladhan's month calendar, which
// [PrayerTimesService.debugMonthResponder] stands in for.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/services/bahrain_prayer_table.dart';
import 'package:grow_daily_v2/core/services/prayer_times_service.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Manama, inside the Bahrain box PrayerTimesService.isInBahrain draws.
const _manamaLat = 26.2285;
const _manamaLng = 50.5860;

/// Cairo — outside every hand-verified box, resolved through the country
/// tier, so it takes the live month path.
const _cairoLat = 30.0444;
const _cairoLng = 31.2357;

String _key(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// A calendar body shaped exactly like Aladhan's, with a Fajr that moves a
/// minute every other day the way a real one does.
String _calendarBody(int year, int month, {int days = 30}) {
  String hhmm(int minutes) => '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';
  return jsonEncode({
    'code': 200,
    'data': [
      for (var day = 1; day <= days; day++)
        {
          'timings': {
            'Fajr': '${hhmm(4 * 60 + (day ~/ 2))} (EEST)',
            'Sunrise': hhmm(5 * 60 + 30),
            'Dhuhr': hhmm(12 * 60),
            'Asr': hhmm(15 * 60 + 30),
            'Maghrib': hhmm(18 * 60),
            'Isha': hhmm(19 * 60 + 30),
          },
          'date': {
            'gregorian': {
              'date': '${day.toString().padLeft(2, '0')}-'
                  '${month.toString().padLeft(2, '0')}-$year',
            },
          },
        },
    ],
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Bahrain'));
  });

  setUp(() {
    PrayerTimesService.resetMonthCache();
    PrayerTimesService.debugMonthResponder = null;
  });

  tearDown(() {
    PrayerTimesService.debugMonthResponder = null;
    PrayerTimesService.resetMonthCache();
  });

  group('Bahrain — the bundled official table, offline and free', () {
    setUpAll(BahrainPrayerTable.ensureLoaded);

    test('every day of the window carries its own official Fajr', () async {
      final from = DateTime(2026, 9, 8);
      final days = await PrayerTimesService.calculateDays(
        latitude: _manamaLat,
        longitude: _manamaLng,
        from: from,
        days: 5,
        madhab: PrayerMadhab.shafi,
        countryCode: 'BH',
      );

      expect(days, hasLength(5));
      for (var i = 0; i < days.length; i++) {
        final date = from.add(Duration(days: i));
        final official = BahrainPrayerTable.lookup(date);
        expect(official, isNotNull,
            reason: 'the bundled table covers ${_key(date)}');
        expect(days[i].fajr, official!.fajr,
            reason: 'day $i must be ${_key(date)}\'s own Fajr, not day 0\'s');
        expect(days[i].fajr.day, date.day,
            reason: 'and it must land on that calendar day');
      }
    });

    test('the window MOVES — this is the whole point of it', () async {
      // A month apart, so the drift is unmistakable rather than a rounding
      // argument. The reminder a person sets as "15 minutes before Fajr"
      // is the number under test: it has to be a different clock time in
      // October than it was in September.
      final september = await PrayerTimesService.calculateDays(
        latitude: _manamaLat,
        longitude: _manamaLng,
        from: DateTime(2026, 9, 8),
        days: 1,
        madhab: PrayerMadhab.shafi,
        countryCode: 'BH',
      );
      final october = await PrayerTimesService.calculateDays(
        latitude: _manamaLat,
        longitude: _manamaLng,
        from: DateTime(2026, 10, 8),
        days: 1,
        madhab: PrayerMadhab.shafi,
        countryCode: 'BH',
      );
      int minutes(tz.TZDateTime t) => t.hour * 60 + t.minute;
      final drift = minutes(october.single.fajr) - minutes(september.single.fajr);
      expect(drift, greaterThan(10),
          reason: 'Fajr in Bahrain gets later by about a quarter of an hour '
              'over these thirty days; a frozen reminder would be that far '
              'out by the end of the month');
    });

    test('never asks the network — the table answers every day', () async {
      var requests = 0;
      PrayerTimesService.debugMonthResponder = (_) async {
        requests++;
        return null;
      };
      await PrayerTimesService.calculateDays(
        latitude: _manamaLat,
        longitude: _manamaLng,
        from: DateTime(2026, 9, 8),
        days: 5,
        madhab: PrayerMadhab.shafi,
        countryCode: 'BH',
      );
      expect(requests, 0);
    });

    test('past the table it still answers, from the calculation', () async {
      // The bundled asset stops at 2027-06-05. A window that runs off the
      // end must not return short or throw — the calculated path takes over
      // silently, exactly as it does for every other country.
      final days = await PrayerTimesService.calculateDays(
        latitude: _manamaLat,
        longitude: _manamaLng,
        from: DateTime(2027, 6, 4),
        days: 5,
        madhab: PrayerMadhab.shafi,
        countryCode: 'BH',
      );
      expect(days, hasLength(5));
      for (var i = 0; i < days.length; i++) {
        expect(days[i].fajr.day, DateTime(2027, 6, 4 + i).day);
      }
    });
  });

  group('everywhere else — one month request, not one per day', () {
    test('a five-day window costs a SINGLE request', () async {
      final asked = <Uri>[];
      PrayerTimesService.debugMonthResponder = (uri) async {
        asked.add(uri);
        return _calendarBody(2026, 9);
      };
      final days = await PrayerTimesService.calculateDays(
        latitude: _cairoLat,
        longitude: _cairoLng,
        from: DateTime(2026, 9, 8),
        days: 5,
        madhab: PrayerMadhab.shafi,
        countryCode: 'EG',
      );
      expect(days, hasLength(5));
      expect(asked, hasLength(1),
          reason: 'a day at a time would have been five round trips, on '
              'every recompute, and a recompute runs on every resume');
      expect(asked.single.path, '/v1/calendar/2026/9');
      expect(asked.single.queryParameters['school'], '0');
      expect(asked.single.queryParameters['timezonestring'], 'Asia/Bahrain');
    });

    test('each day gets its own row, and the times move', () async {
      PrayerTimesService.debugMonthResponder =
          (_) async => _calendarBody(2026, 9);
      final days = await PrayerTimesService.calculateDays(
        latitude: _cairoLat,
        longitude: _cairoLng,
        from: DateTime(2026, 9, 8),
        days: 5,
        madhab: PrayerMadhab.shafi,
        countryCode: 'EG',
      );
      // The stub moves Fajr a minute every other day, so five days spans
      // three distinct minutes — and, critically, more than one.
      expect(days.map((d) => '${d.fajr.hour}:${d.fajr.minute}').toSet().length,
          greaterThan(1));
      expect(days.first.fajr.day, 8);
      expect(days.last.fajr.day, 12);
    });

    test('a window across a month boundary asks for both months', () async {
      final asked = <String>[];
      PrayerTimesService.debugMonthResponder = (uri) async {
        asked.add(uri.path);
        return _calendarBody(
          int.parse(uri.pathSegments[2]),
          int.parse(uri.pathSegments[3]),
        );
      };
      final days = await PrayerTimesService.calculateDays(
        latitude: _cairoLat,
        longitude: _cairoLng,
        from: DateTime(2026, 9, 29),
        days: 5,
        madhab: PrayerMadhab.shafi,
        countryCode: 'EG',
      );
      expect(days, hasLength(5));
      expect(asked.toSet(), {'/v1/calendar/2026/9', '/v1/calendar/2026/10'});
      expect(days.map((d) => d.fajr.month).toSet(), {9, 10});
    });

    test('the month is fetched once and reused across calls', () async {
      var requests = 0;
      PrayerTimesService.debugMonthResponder = (_) async {
        requests++;
        return _calendarBody(2026, 9);
      };
      // What a resume does: several recomputes in a row, each asking for
      // the same window.
      for (var i = 0; i < 4; i++) {
        await PrayerTimesService.calculateDays(
          latitude: _cairoLat,
          longitude: _cairoLng,
          from: DateTime(2026, 9, 8),
          days: 5,
          madhab: PrayerMadhab.shafi,
          countryCode: 'EG',
        );
      }
      expect(requests, 1);
    });

    test('concurrent callers share one request, not one each', () async {
      var requests = 0;
      PrayerTimesService.debugMonthResponder = (_) async {
        requests++;
        return _calendarBody(2026, 9);
      };
      await Future.wait([
        for (var i = 0; i < 4; i++)
          PrayerTimesService.calculateDays(
            latitude: _cairoLat,
            longitude: _cairoLng,
            from: DateTime(2026, 9, 8),
            days: 5,
            madhab: PrayerMadhab.shafi,
            countryCode: 'EG',
          ),
      ]);
      expect(requests, 1, reason: 'the cache holds the future, not the value');
    });

    test('no connection still returns a full window, calculated', () async {
      PrayerTimesService.debugMonthResponder = (_) async => null;
      final days = await PrayerTimesService.calculateDays(
        latitude: _cairoLat,
        longitude: _cairoLng,
        from: DateTime(2026, 9, 8),
        days: 5,
        madhab: PrayerMadhab.shafi,
        countryCode: 'EG',
      );
      expect(days, hasLength(5));
      for (var i = 0; i < days.length; i++) {
        final expected = PrayerTimesService.calculateOfflineCorrected(
          latitude: _cairoLat,
          longitude: _cairoLng,
          date: DateTime(2026, 9, 8 + i),
          madhab: PrayerMadhab.shafi,
          countryCode: 'EG',
        );
        expect(days[i].fajr, expected.fajr,
            reason: 'the offline calculation answers day $i, and it is still '
                "that day's own answer");
      }
    });

    test('a failure is not retried on every recompute', () async {
      var requests = 0;
      PrayerTimesService.debugMonthResponder = (_) async {
        requests++;
        return null;
      };
      for (var i = 0; i < 5; i++) {
        await PrayerTimesService.calculateDays(
          latitude: _cairoLat,
          longitude: _cairoLng,
          from: DateTime(2026, 9, 8),
          days: 5,
          madhab: PrayerMadhab.shafi,
          countryCode: 'EG',
        );
      }
      expect(requests, 1,
          reason: 'five recomputes with no connection must not mean five '
              'timeouts; the cooldown lets the next real open retry');
    });

    test('a malformed day costs that day only', () async {
      PrayerTimesService.debugMonthResponder = (_) async => jsonEncode({
            'data': [
              {
                'timings': {'Fajr': 'not a time'},
                'date': {
                  'gregorian': {'date': '08-09-2026'},
                },
              },
              {
                'timings': {
                  'Fajr': '04:12',
                  'Sunrise': '05:30',
                  'Dhuhr': '12:00',
                  'Asr': '15:30',
                  'Maghrib': '18:00',
                  'Isha': '19:30',
                },
                'date': {
                  'gregorian': {'date': '09-09-2026'},
                },
              },
            ],
          });
      final days = await PrayerTimesService.calculateDays(
        latitude: _cairoLat,
        longitude: _cairoLng,
        from: DateTime(2026, 9, 8),
        days: 2,
        madhab: PrayerMadhab.shafi,
        countryCode: 'EG',
      );
      expect(days, hasLength(2));
      expect(days[1].fajr.hour, 4);
      expect(days[1].fajr.minute, 12);
      final fallback = PrayerTimesService.calculateOfflineCorrected(
        latitude: _cairoLat,
        longitude: _cairoLng,
        date: DateTime(2026, 9, 8),
        madhab: PrayerMadhab.shafi,
        countryCode: 'EG',
      );
      expect(days[0].fajr, fallback.fajr);
    });
  });

  group('parseAladhanCalendar', () {
    test('reads each row by its own date, not by list position', () {
      // Deliberately out of order: the day is whatever the row says.
      final parsed = PrayerTimesService.parseAladhanCalendar(
        jsonEncode({
          'data': [
            {
              'timings': {
                'Fajr': '04:20',
                'Sunrise': '05:30',
                'Dhuhr': '12:00',
                'Asr': '15:30',
                'Maghrib': '18:00',
                'Isha': '19:30',
              },
              'date': {
                'gregorian': {'date': '17-09-2026'},
              },
            },
          ],
        }),
        2026,
        9,
      );
      expect(parsed.keys, ['2026-09-17']);
      expect(parsed['2026-09-17']!.fajr.hour, 4);
      expect(parsed['2026-09-17']!.fajr.minute, 20);
    });

    test('drops a response for some other month entirely', () {
      final parsed = PrayerTimesService.parseAladhanCalendar(
        _calendarBody(2026, 8),
        2026,
        9,
      );
      expect(parsed, isEmpty,
          reason: 'storing August under September would hand every later '
              'lookup the wrong days');
    });

    test('a body that is not a calendar at all parses to nothing', () {
      expect(PrayerTimesService.parseAladhanCalendar('{}', 2026, 9), isEmpty);
      expect(
        PrayerTimesService.parseAladhanCalendar(
            jsonEncode({'data': 'nope'}), 2026, 9),
        isEmpty,
      );
    });
  });

  group('aladhanCalendarUri', () {
    test('carries the same place, method, madhab and zone the day '
        'endpoint does', () {
      final uri = PrayerTimesService.aladhanCalendarUri(
        latitude: _cairoLat,
        longitude: _cairoLng,
        year: 2026,
        month: 9,
        method: PrayerCalcMethod.egyptian,
        madhab: PrayerMadhab.hanafi,
        fajrCorrectionMinutes: 9,
      );
      expect(uri.host, 'api.aladhan.com');
      expect(uri.path, '/v1/calendar/2026/9');
      expect(uri.queryParameters['school'], '1');
      expect(uri.queryParameters['tune'], '0,9,0,0,0,0,0,0,0');
      expect(uri.queryParameters['latitude'], '$_cairoLat');
      expect(uri.queryParameters['timezonestring'], 'Asia/Bahrain');
    });
  });
}
