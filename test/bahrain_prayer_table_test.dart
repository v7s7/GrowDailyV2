import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/services/bahrain_prayer_table.dart';
import 'package:grow_daily_v2/core/services/prayer_times_service.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Manama, inside PrayerTimesService's Bahrain box.
const _lat = 26.2285;
const _lng = 50.5860;

String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}';

/// Spot values copied verbatim out of the government source
/// (static.prd.govapps.bh .../PRAYER_TIMINGS.json), in the order
/// fajr, sunrise, dhuhr, asr, maghrib, isha.
///
/// Hardcoded rather than read back out of the bundled asset on purpose: a
/// test that only compares the asset to itself would pass just as happily
/// against a regenerated file that had silently lost a day, shifted by a
/// timezone, or been rebuilt from some other source.
const _official = <String, List<String>>{
  '2026-01-01': ['05:02', '06:24', '11:42', '14:38', '16:58', '18:19'],
  '2026-03-20': ['04:24', '05:41', '11:46', '15:12', '17:49', '19:05'],
  '2026-07-17': ['03:26', '04:55', '11:45', '15:11', '18:32', '19:59'],
  '2026-08-18': ['03:49', '05:11', '11:43', '15:12', '18:12', '19:32'],
  '2026-12-21': ['04:57', '06:20', '11:37', '14:31', '16:51', '18:12'],
  '2027-06-05': ['03:14', '04:44', '11:37', '15:02', '18:28', '19:56'],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    tzdata.initializeTimeZones();
    // The device is IN Bahrain for these tests, so wall clock and stored
    // digits coincide. The traveller case gets its own test below.
    tz.setLocalLocation(tz.getLocation('Asia/Bahrain'));
    BahrainPrayerTable.resetForTest();
    await BahrainPrayerTable.ensureLoaded();
  });

  test('the bundled asset is loadable and covers a continuous span', () async {
    final decoded =
        jsonDecode(await rootBundle.loadString(BahrainPrayerTable.assetPath))
            as Map;
    final days = (decoded['days'] as Map).cast<String, String>();
    final keys = days.keys.toList()..sort();
    expect(keys.first, '2026-01-01');
    expect(keys.last, '2027-06-05');

    // No gaps: a missing day would show up in production as a silent
    // fallback to the calculated path on exactly that date, which is
    // precisely the kind of one-day-a-year bug nothing else would catch.
    var cursor = DateTime.parse(keys.first);
    for (final key in keys) {
      expect(key, _hmDate(cursor), reason: 'gap or duplicate before $key');
      cursor = cursor.add(const Duration(days: 1));
    }
    expect(keys.length, 521);
    for (final row in days.values) {
      expect(row.split(' ').length, 6);
    }
  });

  test('Bahrain gets the official times to the minute', () {
    for (final entry in _official.entries) {
      final date = DateTime.parse(entry.key);
      final got = PrayerTimesService.calculateOfflineCorrected(
        latitude: _lat,
        longitude: _lng,
        date: date,
        madhab: PrayerMadhab.shafi,
        countryCode: 'BH',
      );
      expect(
        [
          _hm(got.fajr),
          _hm(got.sunrise),
          _hm(got.dhuhr),
          _hm(got.asr),
          _hm(got.maghrib),
          _hm(got.isha),
        ],
        entry.value,
        reason: 'official Bahrain times for ${entry.key}',
      );
    }
  });

  test('the calculated path alone would NOT match, which is the point', () {
    // Karachi/Shafi is the closest of every convention tested and still
    // lands a minute out. If this ever starts passing, the table has
    // stopped being consulted and the assertions above are only
    // re-measuring the calculation.
    var mismatches = 0;
    for (final entry in _official.entries) {
      final date = DateTime.parse(entry.key);
      final raw = PrayerTimesService.calculateOffline(
        latitude: _lat,
        longitude: _lng,
        date: date,
        method: PrayerCalcMethod.karachi,
        madhab: PrayerMadhab.shafi,
      );
      final got = [
        _hm(raw.fajr),
        _hm(raw.sunrise),
        _hm(raw.dhuhr),
        _hm(raw.asr),
        _hm(raw.maghrib),
        _hm(raw.isha),
      ];
      if (!_listEq(got, entry.value)) mismatches++;
    }
    expect(mismatches, greaterThan(0));
  });

  test('a Hanafi user keeps the official five and computes only Asr', () {
    final date = DateTime.parse('2026-08-18');
    final shafi = PrayerTimesService.calculateOfflineCorrected(
      latitude: _lat,
      longitude: _lng,
      date: date,
      madhab: PrayerMadhab.shafi,
      countryCode: 'BH',
    );
    final hanafi = PrayerTimesService.calculateOfflineCorrected(
      latitude: _lat,
      longitude: _lng,
      date: date,
      madhab: PrayerMadhab.hanafi,
      countryCode: 'BH',
    );
    // Bahrain publishes one Asr, computed the standard way. Handing it to
    // a Hanafi user would be an hour wrong, not a rounding error.
    expect(_hm(hanafi.fajr), _hm(shafi.fajr));
    expect(_hm(hanafi.dhuhr), _hm(shafi.dhuhr));
    expect(_hm(hanafi.maghrib), _hm(shafi.maghrib));
    expect(_hm(hanafi.isha), _hm(shafi.isha));
    expect(hanafi.asr.difference(shafi.asr).inMinutes, greaterThan(30));
  });

  test('outside Bahrain the table is never consulted', () {
    // Riyadh. Umm al-Qura sits ~14 minutes off Bahrain's Isha, so if the
    // Bahrain table ever leaked across the border it would be obvious.
    final riyadh = PrayerTimesService.calculateOfflineCorrected(
      latitude: 24.7136,
      longitude: 46.6753,
      date: DateTime.parse('2026-08-18'),
      madhab: PrayerMadhab.shafi,
      countryCode: 'SA',
    );
    expect(_hm(riyadh.isha), isNot(_official['2026-08-18']![5]));
    expect(PrayerTimesService.isInBahrain(24.7136, 46.6753), isFalse);
    expect(PrayerTimesService.isInBahrain(_lat, _lng), isTrue);
  });

  test('past the table the calculated path takes over silently', () {
    final beyond = PrayerTimesService.calculateOfflineCorrected(
      latitude: _lat,
      longitude: _lng,
      date: DateTime.parse('2027-06-06'),
      madhab: PrayerMadhab.shafi,
      countryCode: 'BH',
    );
    expect(BahrainPrayerTable.lookup(DateTime.parse('2027-06-06')), isNull);
    // Still a usable answer, and still within a minute or two of where the
    // table left off the day before.
    final last = BahrainPrayerTable.lookup(DateTime.parse('2027-06-05'))!;
    expect(beyond.maghrib.difference(last.maghrib).inHours, inInclusiveRange(23, 25));
  });

  test('a traveller pinned to Bahrain sees the same instant, own clock', () {
    tz.setLocalLocation(tz.getLocation('Europe/London'));
    addTearDown(() => tz.setLocalLocation(tz.getLocation('Asia/Bahrain')));
    final got = BahrainPrayerTable.lookup(DateTime.parse('2026-08-18'))!;
    // 18:12 Bahrain (UTC+3) is 16:12 London (BST, UTC+1) on that date.
    expect(_hm(got.maghrib), '16:12');
  });
}

String _hmDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

bool _listEq(List<String> a, List<String> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
