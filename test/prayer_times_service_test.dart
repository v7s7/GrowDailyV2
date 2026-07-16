import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:grow_daily_v2/core/services/prayer_times_service.dart';

void main() {
  // PrayerTimesService converts adhan_dart's UTC results into tz.local, and
  // (for the live path) passes tz.local's IANA name straight through as the
  // `timezonestring` request param — needs timezone data initialized and a
  // local zone set, same as NotificationService.init() does at app startup
  // (see its doc comment).
  setUpAll(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Riyadh'));
  });

  group('PrayerTimesService.calculateOffline', () {
    // These exercise the pure, synchronous, offline calculation directly —
    // no network involved, so they're deterministic and hermetic. This is
    // also exactly what PrayerTimesService.calculate falls back to whenever
    // the live Aladhan fetch fails, so these results double as "what a
    // user sees with no connection."
    test('Mecca, a fixed date — the 5 prayers land in ascending order', () {
      final result = PrayerTimesService.calculateOffline(
        latitude: 21.3891,
        longitude: 39.8579,
        date: DateTime(2026, 3, 15),
        method: PrayerCalcMethod.ummAlQura,
        madhab: PrayerMadhab.shafi,
      );

      expect(result.fajr.isBefore(result.sunrise), isTrue);
      expect(result.sunrise.isBefore(result.dhuhr), isTrue);
      expect(result.dhuhr.isBefore(result.asr), isTrue);
      expect(result.asr.isBefore(result.maghrib), isTrue);
      expect(result.maghrib.isBefore(result.isha), isTrue);

      // Sanity ranges for this latitude/date, not exact minute-for-minute
      // values (those legitimately shift with the calculation method
      // chosen) — this guards against a gross unit/timezone mistake (e.g.
      // an accidental UTC-vs-local mixup), not religious-accuracy down to
      // the minute.
      expect(result.fajr.hour, inInclusiveRange(3, 6));
      expect(result.dhuhr.hour, inInclusiveRange(11, 13));
      expect(result.maghrib.hour, inInclusiveRange(17, 19));
    });

    test('Hanafi Asr is never earlier than Shafi Asr, same day/location', () {
      const latitude = 24.7136;
      const longitude = 46.6753;
      final date = DateTime(2026, 6, 1);
      final shafi = PrayerTimesService.calculateOffline(
        latitude: latitude,
        longitude: longitude,
        date: date,
        method: PrayerCalcMethod.ummAlQura,
        madhab: PrayerMadhab.shafi,
      );
      final hanafi = PrayerTimesService.calculateOffline(
        latitude: latitude,
        longitude: longitude,
        date: date,
        method: PrayerCalcMethod.ummAlQura,
        madhab: PrayerMadhab.hanafi,
      );
      expect(
        hanafi.asr.isAfter(shafi.asr) || hanafi.asr.isAtSameMomentAs(shafi.asr),
        isTrue,
        reason: "Hanafi's later-shadow-length convention should never "
            'resolve to an earlier Asr than Shafi for the same day.',
      );
    });

    test(
        'Karachi/Shafi raw output for Manama, Bahrain — before the region '
        "correction PrayerTimesService.calculate layers on top", () {
      // calculateOffline itself is now fully region-unaware — it applies no
      // correction at all, for anywhere (see the resolveRegion group below
      // for where the +9 minute Bahrain fajr margin actually lives now).
      // This locks down the *raw* adhan_dart number these coordinates
      // produce: verified against Bahrain's official Ministry of Justice,
      // Islamic Affairs & Waqf published times for Manama on this exact
      // date, sunrise/asr/maghrib/isha are exact matches and fajr is
      // exactly 9 minutes earlier than the official 03:36 (i.e. this is the
      // same 9-minute gap [resolveRegion] returns for these coordinates).
      // dhuhr is 1 minute later here than the official 11:44 regardless — a
      // known cross-library rounding difference between adhan_dart's
      // solar-noon calculation and Aladhan's (whose *live* result, unlike
      // this offline one, does land on 11:44 exactly — see the
      // aladhanRequestUri group below and PrayerTimesService.calculate's
      // class doc comment for why this offline path is the fallback, not
      // the primary result).
      final result = PrayerTimesService.calculateOffline(
        latitude: 26.2285,
        longitude: 50.5860,
        date: DateTime(2026, 7, 16),
        method: PrayerCalcMethod.karachi,
        madhab: PrayerMadhab.shafi,
      );

      String hhmm(tz.TZDateTime d) =>
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

      expect(hhmm(result.fajr), '03:27');
      expect(hhmm(result.sunrise), '04:55');
      expect(hhmm(result.dhuhr), '11:45');
      expect(hhmm(result.asr), '15:11');
      expect(hhmm(result.maghrib), '18:32');
      expect(hhmm(result.isha), '20:00');
    });

    test('forKey resolves every HabitCue prayer key, and rejects an unknown one',
        () {
      final result = PrayerTimesService.calculateOffline(
        latitude: 30.0444,
        longitude: 31.2357,
        date: DateTime(2026, 1, 10),
        method: PrayerCalcMethod.egyptian,
        madhab: PrayerMadhab.shafi,
      );
      expect(result.forKey('fajr'), result.fajr);
      expect(result.forKey('dhuhr'), result.dhuhr);
      expect(result.forKey('asr'), result.asr);
      expect(result.forKey('maghrib'), result.maghrib);
      expect(result.forKey('isha'), result.isha);
      expect(result.forKey('before_sleep'), isNull);
      expect(result.forKey('sunrise'), isNull);
    });

    test(
        'karachi method raw output for the real city of Karachi, Pakistan '
        '— a second real location/method pair, distinct from the Bahrain '
        'test above', () {
      final result = PrayerTimesService.calculateOffline(
        latitude: 24.8607,
        longitude: 67.0011,
        date: DateTime(2026, 7, 16),
        method: PrayerCalcMethod.karachi,
        madhab: PrayerMadhab.shafi,
      );

      String hhmm(tz.TZDateTime d) =>
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

      // Raw adhan_dart output for these coordinates/date, shown in this
      // test file's fixed tz.local (Asia/Riyadh, UTC+3 — not Asia/
      // Karachi's own UTC+5, since calculateOffline always converts into
      // tz.local's wall clock regardless of where the coordinates are).
      // calculateOffline itself has no region awareness at all now (see
      // the resolveRegion group below for the actual "Bahrain's margin
      // doesn't leak to the rest of the world, including real Karachi"
      // regression coverage) — this is just a plain numeric sanity lock.
      expect(hhmm(result.fajr), '02:25');
    });

    // Smoke tests for the adhan_dart 1.2.0 -> 2.0.1 upgrade (see pubspec.yaml's
    // adhan_dart comment) — not a claim these two countries' methods are
    // independently verified (see resolveRegion's class doc comment for
    // that distinction), just confirming the new named presets this
    // upgrade unlocked actually produce a sane, ordered result at runtime
    // and not just at compile time.
    test('calculateOffline works with the newly-added algerian method', () {
      final result = PrayerTimesService.calculateOffline(
        latitude: 36.7538,
        longitude: 3.0588,
        date: DateTime(2026, 7, 16),
        method: PrayerCalcMethod.algerian,
        madhab: PrayerMadhab.shafi,
      );
      expect(result.fajr.isBefore(result.sunrise), isTrue);
      expect(result.sunrise.isBefore(result.dhuhr), isTrue);
      expect(result.maghrib.isBefore(result.isha), isTrue);
    });

    test('calculateOffline works with the newly-added russia method', () {
      final result = PrayerTimesService.calculateOffline(
        latitude: 55.7558,
        longitude: 37.6173,
        date: DateTime(2026, 7, 16),
        method: PrayerCalcMethod.russia,
        madhab: PrayerMadhab.shafi,
      );
      expect(result.fajr.isBefore(result.sunrise), isTrue);
      expect(result.sunrise.isBefore(result.dhuhr), isTrue);
      expect(result.maghrib.isBefore(result.isha), isTrue);
    });
  });

  group('PrayerTimesService.resolveRegion', () {
    // One assertion per verified GCC country (see PrayerTimesService's
    // class doc comment and the _regions table for what "verified" means
    // for each), plus the regression coverage for the exact bug this table
    // exists to prevent: a region's specific correction — or a
    // neighboring/larger region's box — silently applying to coordinates
    // it was never actually checked against.

    test('Bahrain (Manama) resolves to Karachi/Shafi + a 9 minute fajr correction', () {
      final region = PrayerTimesService.resolveRegion(26.2285, 50.5860);
      expect(region.method, PrayerCalcMethod.karachi);
      expect(region.fajrCorrectionMinutes, 9);
    });

    test('Qatar (Doha) resolves to the Qatar method, no correction', () {
      final region = PrayerTimesService.resolveRegion(25.2854, 51.5310);
      expect(region.method, PrayerCalcMethod.qatar);
      expect(region.fajrCorrectionMinutes, 0);
    });

    test('Kuwait (Kuwait City) resolves to the Kuwait method, no correction', () {
      final region = PrayerTimesService.resolveRegion(29.3759, 47.9774);
      expect(region.method, PrayerCalcMethod.kuwait);
      expect(region.fajrCorrectionMinutes, 0);
    });

    test('UAE (Dubai) resolves to the Dubai method, no correction', () {
      final region = PrayerTimesService.resolveRegion(25.2048, 55.2708);
      expect(region.method, PrayerCalcMethod.dubai);
      expect(region.fajrCorrectionMinutes, 0);
    });

    test('Oman (Muscat) resolves to Umm al-Qura, no correction', () {
      final region = PrayerTimesService.resolveRegion(23.5859, 58.4059);
      expect(region.method, PrayerCalcMethod.ummAlQura);
      expect(region.fajrCorrectionMinutes, 0);
    });

    test('Saudi Arabia (Riyadh) resolves to Umm al-Qura, no correction', () {
      final region = PrayerTimesService.resolveRegion(24.7136, 46.6753);
      expect(region.method, PrayerCalcMethod.ummAlQura);
      expect(region.fajrCorrectionMinutes, 0);
    });

    test(
        'a location outside every verified region, with no countryCode '
        'supplied, falls back to the plain global default (Muslim World '
        'League) — resolveRegion never does its own hidden geocoding, it '
        'only trusts what it is given', () {
      final region = PrayerTimesService.resolveRegion(51.5074, -0.1278);
      expect(region.method, PrayerCalcMethod.muslimWorldLeague);
      expect(region.fajrCorrectionMinutes, 0);
    });

    test(
        'a resolved countryCode with no _countryDefaults entry (Kenya) '
        'also falls back to the plain global default', () {
      final region = PrayerTimesService.resolveRegion(-1.2864, 36.8172,
          countryCode: 'KE');
      expect(region.method, PrayerCalcMethod.muslimWorldLeague);
      expect(region.fajrCorrectionMinutes, 0);
    });

    // Regression coverage: Bahrain's +9 minute margin is specific to
    // Bahrain, not to the Karachi *method* — a Karachi-method user who
    // isn't physically in Bahrain must never inherit it.
    test(
        'the real city of Karachi, Pakistan (which the method is named '
        "after) does not inherit Bahrain's correction", () {
      final region = PrayerTimesService.resolveRegion(24.8607, 67.0011);
      expect(region.method, PrayerCalcMethod.karachi);
      expect(region.fajrCorrectionMinutes, 0);
    });

    test(
        'Dammam, Saudi Arabia — just across the causeway from Bahrain — '
        "resolves to Saudi's own recipe, not Bahrain's", () {
      final region = PrayerTimesService.resolveRegion(26.4207, 50.0888);
      expect(region.method, PrayerCalcMethod.ummAlQura);
      expect(region.fajrCorrectionMinutes, 0);
    });

    test(
        "Saudi Arabia's bounding box geographically contains every other "
        'GCC box, so it must be checked last — this fails if a smaller '
        "country's entry ever gets reordered after it", () {
      expect(PrayerTimesService.resolveRegion(26.2285, 50.5860).method,
          PrayerCalcMethod.karachi); // Bahrain
      expect(PrayerTimesService.resolveRegion(25.2854, 51.5310).method,
          PrayerCalcMethod.qatar); // Qatar
      expect(PrayerTimesService.resolveRegion(29.3759, 47.9774).method,
          PrayerCalcMethod.kuwait); // Kuwait
      expect(PrayerTimesService.resolveRegion(25.2048, 55.2708).method,
          PrayerCalcMethod.dubai); // UAE
    });

    test(
        'the GCC bounding boxes take priority over countryCode even when '
        'one is supplied — Bahrain coordinates resolve to the verified '
        'Bahrain entry regardless of what countryCode comes with them '
        '(e.g. a hypothetical geocoding glitch)', () {
      final region = PrayerTimesService.resolveRegion(26.2285, 50.5860,
          countryCode: 'SA');
      expect(region.method, PrayerCalcMethod.karachi);
      expect(region.fajrCorrectionMinutes, 9);
    });

    // ── Global country-code tier ──────────────────────────────────────
    // Every entry in PrayerTimesService._countryDefaults, one test each,
    // using each country's real capital/largest-city coordinates — see
    // that map's doc comment for what "documented convention" means here
    // (adhan_dart's own preset docs explicitly naming that authority),
    // a meaningfully lower confidence tier than the 6 GCC boxes above.

    test('EG (Cairo) resolves to the Egyptian method', () {
      final region = PrayerTimesService.resolveRegion(30.0444, 31.2357,
          countryCode: 'EG');
      expect(region.method, PrayerCalcMethod.egyptian);
      expect(region.fajrCorrectionMinutes, 0);
    });

    test(
        'DZ (Algiers) resolves to the Algerian method', () {
      final region = PrayerTimesService.resolveRegion(36.7538, 3.0588,
          countryCode: 'DZ');
      expect(region.method, PrayerCalcMethod.algerian);
    });

    test('FR (Paris) resolves to the France method', () {
      final region = PrayerTimesService.resolveRegion(48.8566, 2.3522,
          countryCode: 'FR');
      expect(region.method, PrayerCalcMethod.france);
    });

    test('ID (Jakarta) resolves to the Indonesian (Kemenag) method', () {
      final region = PrayerTimesService.resolveRegion(-6.2088, 106.8456,
          countryCode: 'ID');
      expect(region.method, PrayerCalcMethod.indonesian);
    });

    test(
        "JO (Amman) resolves to the Jordan method, not Saudi Arabia's box "
        '(regression guard — Amman sits inside what used to be Saudi '
        "Arabia's looser bounding box before it was tightened; see "
        "_regions' Saudi Arabia entry)", () {
      final region = PrayerTimesService.resolveRegion(31.9454, 35.9284,
          countryCode: 'JO');
      expect(region.method, PrayerCalcMethod.jordan);
    });

    test('PT (Lisbon) resolves to the Portugal method', () {
      final region = PrayerTimesService.resolveRegion(38.7223, -9.1393,
          countryCode: 'PT');
      expect(region.method, PrayerCalcMethod.portugal);
    });

    test('MA (Rabat) resolves to the Morocco method', () {
      final region = PrayerTimesService.resolveRegion(34.0209, -6.8416,
          countryCode: 'MA');
      expect(region.method, PrayerCalcMethod.morocco);
    });

    test('RU (Moscow) resolves to the Russia method', () {
      final region = PrayerTimesService.resolveRegion(55.7558, 37.6173,
          countryCode: 'RU');
      expect(region.method, PrayerCalcMethod.russia);
    });

    test('TN (Tunis) resolves to the Tunisia method', () {
      final region = PrayerTimesService.resolveRegion(36.8065, 10.1815,
          countryCode: 'TN');
      expect(region.method, PrayerCalcMethod.tunisia);
    });

    test('TR (Istanbul) resolves to the Turkiye method', () {
      final region = PrayerTimesService.resolveRegion(41.0082, 28.9784,
          countryCode: 'TR');
      expect(region.method, PrayerCalcMethod.turkiye);
    });

    test('IR (Tehran) resolves to the Tehran method', () {
      final region = PrayerTimesService.resolveRegion(35.6892, 51.3890,
          countryCode: 'IR');
      expect(region.method, PrayerCalcMethod.tehran);
    });

    test(
        'PK (Karachi) resolves to the Karachi method with no fajr '
        "correction — that correction is Bahrain's specifically, not the "
        "method's own (see the earlier regression test at these same "
        'coordinates)', () {
      final region = PrayerTimesService.resolveRegion(24.8607, 67.0011,
          countryCode: 'PK');
      expect(region.method, PrayerCalcMethod.karachi);
      expect(region.fajrCorrectionMinutes, 0);
    });

    test('SG (Singapore) resolves to the Singapore method', () {
      final region = PrayerTimesService.resolveRegion(1.3521, 103.8198,
          countryCode: 'SG');
      expect(region.method, PrayerCalcMethod.singapore);
    });

    test(
        "MY (Kuala Lumpur) resolves to the Singapore method too — "
        "adhan_dart's own preset doc names Singapore, Malaysia, and "
        'Indonesia together', () {
      final region = PrayerTimesService.resolveRegion(3.1390, 101.6869,
          countryCode: 'MY');
      expect(region.method, PrayerCalcMethod.singapore);
    });

    test(
        'US (New York) resolves to moonsightingCommittee, not '
        "northAmerica — adhan_dart's own docs recommend it over ISNA for "
        'North America', () {
      final region = PrayerTimesService.resolveRegion(40.7128, -74.0060,
          countryCode: 'US');
      expect(region.method, PrayerCalcMethod.moonsightingCommittee);
    });

    test('CA (Toronto) resolves to moonsightingCommittee too', () {
      final region = PrayerTimesService.resolveRegion(43.6532, -79.3832,
          countryCode: 'CA');
      expect(region.method, PrayerCalcMethod.moonsightingCommittee);
    });

    test(
        'GB (London) resolves to moonsightingCommittee via the country '
        "tier — adhan_dart's moonsightingCommittee doc calls this out "
        'directly: "Recommended for North America and the UK"', () {
      final region = PrayerTimesService.resolveRegion(51.5074, -0.1278,
          countryCode: 'GB');
      expect(region.method, PrayerCalcMethod.moonsightingCommittee);
      expect(region.fajrCorrectionMinutes, 0);
    });
  });

  group('PrayerTimesService.calculateOfflineCorrected', () {
    // The exact offline path PrayerTimesService.calculate itself falls back
    // to on a network failure (see that method's doc comment), and what
    // AddHabitSheet's reminder-time preview calls directly for a
    // synchronous, no-network "roughly what time you'll be reminded"
    // estimate (see that widget's _reminderAnchorTime). These lock down
    // that resolveRegion's correction is actually layered on top of
    // calculateOffline's raw numbers, not just computed and discarded.

    test(
        "applies Bahrain's verified +9 minute fajr correction on top of "
        'the raw offline calculation', () {
      final corrected = PrayerTimesService.calculateOfflineCorrected(
        latitude: 26.2285,
        longitude: 50.5860,
        date: DateTime(2026, 7, 16),
        madhab: PrayerMadhab.shafi,
      );
      String hhmm(tz.TZDateTime d) =>
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
      // Raw offline fajr for these exact coordinates/date is 03:27 (see the
      // calculateOffline group above) — +9 minutes lands on the official
      // 03:36, matching the live-Aladhan-verified value from the
      // aladhanRequestUri group below.
      expect(hhmm(corrected.fajr), '03:36');
      // Every other prayer is untouched by the correction.
      expect(hhmm(corrected.sunrise), '04:55');
      expect(hhmm(corrected.dhuhr), '11:45');
      expect(hhmm(corrected.asr), '15:11');
      expect(hhmm(corrected.maghrib), '18:32');
      expect(hhmm(corrected.isha), '20:00');
    });

    test(
        'a location with zero fajr correction (Qatar) returns exactly what '
        'calculateOffline itself would, with the method resolved '
        'automatically via resolveRegion instead of passed in directly',
        () {
      const latitude = 25.2854;
      const longitude = 51.5310;
      final date = DateTime(2026, 6, 1);
      final corrected = PrayerTimesService.calculateOfflineCorrected(
        latitude: latitude,
        longitude: longitude,
        date: date,
        madhab: PrayerMadhab.shafi,
      );
      final rawDirect = PrayerTimesService.calculateOffline(
        latitude: latitude,
        longitude: longitude,
        date: date,
        method: PrayerCalcMethod.qatar,
        madhab: PrayerMadhab.shafi,
      );
      expect(corrected.fajr, rawDirect.fajr);
      expect(corrected.dhuhr, rawDirect.dhuhr);
      expect(corrected.isha, rawDirect.isha);
    });

    test(
        'resolves through the country-code tier too, not just the 6 GCC '
        'bounding boxes — Jordan (Amman) via countryCode', () {
      const latitude = 31.9454;
      const longitude = 35.9284;
      final date = DateTime(2026, 7, 16);
      final corrected = PrayerTimesService.calculateOfflineCorrected(
        latitude: latitude,
        longitude: longitude,
        date: date,
        madhab: PrayerMadhab.shafi,
        countryCode: 'JO',
      );
      final rawDirect = PrayerTimesService.calculateOffline(
        latitude: latitude,
        longitude: longitude,
        date: date,
        method: PrayerCalcMethod.jordan,
        madhab: PrayerMadhab.shafi,
      );
      expect(corrected.fajr, rawDirect.fajr);
      expect(corrected.maghrib, rawDirect.maghrib);
    });
  });

  group('PrayerTimesService.aladhanRequestUri', () {
    // Pure URL-building, asserted on directly rather than via a live call —
    // this is the one place a wrong method id or malformed tune string
    // would silently produce wrong prayer times again (the exact failure
    // this whole feature exists to avoid), so it's worth locking down.
    // fajrCorrectionMinutes is just formatted straight into the tune
    // string here — [PrayerTimesService.resolveRegion] (see that group
    // above) is what decides the actual number for a given location; this
    // group only checks the formatting is correct once a number is given.
    test(
        "Karachi/Shafi + Bahrain's verified +9 min correction builds the "
        'exact request', () {
      // Verified end-to-end against a real https://api.aladhan.com
      // response for this exact date/location/tune, which returned fajr
      // 03:36, sunrise 04:55, dhuhr 11:44, asr 15:11, maghrib 18:32, isha
      // 20:00 — an exact match on all 6 of the official Bahrain times, with
      // zero remaining gap (unlike the raw offline calculation above,
      // which needs this same +9 to match fajr and is still 1 minute off
      // on dhuhr regardless).
      final uri = PrayerTimesService.aladhanRequestUri(
        latitude: 26.2285,
        longitude: 50.5860,
        date: DateTime(2026, 7, 16),
        method: PrayerCalcMethod.karachi,
        madhab: PrayerMadhab.shafi,
        fajrCorrectionMinutes: 9,
      );

      expect(uri.host, 'api.aladhan.com');
      expect(uri.path, '/v1/timings/16-07-2026');
      expect(uri.queryParameters['latitude'], '26.2285');
      expect(uri.queryParameters['longitude'], '50.586');
      // Method 1 = University of Islamic Sciences, Karachi — verified
      // directly against https://api.aladhan.com/v1/methods.
      expect(uri.queryParameters['method'], '1');
      expect(uri.queryParameters['tune'], '0,9,0,0,0,0,0,0,0');
      expect(uri.queryParameters['school'], '0');
      expect(uri.queryParameters['timezonestring'], 'Asia/Riyadh');
    });

    test('fajrCorrectionMinutes defaults to zero when the caller omits it',
        () {
      final uri = PrayerTimesService.aladhanRequestUri(
        latitude: 24.7136,
        longitude: 46.6753,
        date: DateTime(2026, 6, 1),
        method: PrayerCalcMethod.ummAlQura,
        madhab: PrayerMadhab.shafi,
      );
      expect(uri.queryParameters['tune'], '0,0,0,0,0,0,0,0,0');
    });

    test('Hanafi maps to school=1', () {
      final uri = PrayerTimesService.aladhanRequestUri(
        latitude: 24.7136,
        longitude: 46.6753,
        date: DateTime(2026, 6, 1),
        method: PrayerCalcMethod.ummAlQura,
        madhab: PrayerMadhab.hanafi,
      );
      expect(uri.queryParameters['school'], '1');
    });

    test(
        'every PrayerCalcMethod maps to a distinct Aladhan method id, all '
        'in the 0-99 range Aladhan documents', () {
      final ids = <int>{};
      for (final method in PrayerCalcMethod.values) {
        final uri = PrayerTimesService.aladhanRequestUri(
          latitude: 0,
          longitude: 0,
          date: DateTime(2026, 1, 1),
          method: method,
          madhab: PrayerMadhab.shafi,
        );
        final id = int.parse(uri.queryParameters['method']!);
        expect(id, inInclusiveRange(0, 99));
        expect(ids.contains(id), isFalse,
            reason: '$method reused an id another method already claimed');
        ids.add(id);
      }
      expect(ids.length, PrayerCalcMethod.values.length);
    });

    test('a single-digit day/month is zero-padded in the date path segment',
        () {
      final uri = PrayerTimesService.aladhanRequestUri(
        latitude: 1,
        longitude: 1,
        date: DateTime(2026, 1, 5),
        method: PrayerCalcMethod.karachi,
        madhab: PrayerMadhab.shafi,
      );
      expect(uri.path, '/v1/timings/05-01-2026');
    });
  });

  group('PrayerTimesService.parseAladhanTime', () {
    final day = DateTime(2026, 7, 16);

    test('parses a plain HH:mm string', () {
      final result = PrayerTimesService.parseAladhanTime('03:36', day);
      expect(result, isNotNull);
      expect(result!.year, 2026);
      expect(result.month, 7);
      expect(result.day, 16);
      expect(result.hour, 3);
      expect(result.minute, 36);
    });

    test('drops a trailing suffix after the time (e.g. a timezone offset)',
        () {
      final result = PrayerTimesService.parseAladhanTime('18:32 (+03)', day);
      expect(result, isNotNull);
      expect(result!.hour, 18);
      expect(result.minute, 32);
    });

    test('returns null for null, empty, or malformed input', () {
      expect(PrayerTimesService.parseAladhanTime(null, day), isNull);
      expect(PrayerTimesService.parseAladhanTime('', day), isNull);
      expect(PrayerTimesService.parseAladhanTime('not-a-time', day), isNull);
      expect(PrayerTimesService.parseAladhanTime('25:99', day), isNull);
      expect(PrayerTimesService.parseAladhanTime('3', day), isNull);
    });
  });
}
