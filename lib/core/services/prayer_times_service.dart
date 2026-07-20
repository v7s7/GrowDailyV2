import 'dart:convert';

import 'package:adhan_dart/adhan_dart.dart' as adhan;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:timezone/timezone.dart' as tz;

/// Which astronomical convention to use for Fajr/Isha's sun-angle
/// thresholds (they're the two prayers without a direct physical marker
/// like sunrise/sunset, so different regional authorities standardized on
/// different angles). Names/values are a small, UI-friendly subset of
/// adhan_dart's `CalculationMethodParameters` — deliberately not every
/// method the package ships (e.g. `other`, a 0°/0° "build your own"
/// placeholder, isn't something to expose as a picker option).
///
/// Not a user-facing picker (see [PrayerTimesService.resolveRegion]) — kept
/// as a full 12-value enum anyway since [PrayerTimesService]'s per-region
/// table needs to name a specific method for each verified country, and
/// adding a country later shouldn't require adding a new enum value too.
///
/// Persisted to Hive/Firestore via [toJson] — the enum name is the stable
/// storage key, so reordering this list is safe but renaming a value is
/// not (mirrors HabitCategory's toJson/fromJson convention elsewhere in
/// this codebase).
enum PrayerCalcMethod {
  muslimWorldLeague,
  egyptian,
  karachi,
  ummAlQura,
  northAmerica,
  moonsightingCommittee,
  singapore,
  dubai,
  qatar,
  kuwait,
  turkiye,
  tehran,
  // Added for global coverage (see PrayerTimesService.resolveRegion) — each
  // is a specific country's own documented official authority per
  // adhan_dart's own preset descriptions, not a guess. Deliberately NOT
  // adding adhan_dart's `gulfRegion` (redundant — every GCC country already
  // has its own individually-verified entry) or `jafari` (Shia
  // Ithna-Ashari is a denominational choice, like [PrayerMadhab], not
  // something a location-based table should assign to an entire country's
  // population regardless of the person's own affiliation).
  algerian,
  france,
  indonesian,
  jordan,
  morocco,
  portugal,
  russia,
  tunisia;

  String toJson() => name;

  static PrayerCalcMethod fromJson(String? v) => values.firstWhere(
        (e) => e.name == v,
        orElse: () => muslimWorldLeague,
      );

  /// Short label + one-line description — shown read-only in Notification
  /// Settings next to the auto-resolved method for the user's location
  /// (see [PrayerTimesService.resolveRegion]), not a picker anymore. Kept
  /// here (not app_strings.dart) since the description text is
  /// factual/geographic, not UI copy that changes with product decisions —
  /// same reasoning as HabitCategory keeping its own icon/label mapping.
  String label(bool isAr) => isAr
      ? switch (this) {
          muslimWorldLeague => 'رابطة العالم الإسلامي',
          egyptian => 'الهيئة المصرية العامة للمساحة',
          karachi => 'جامعة العلوم الإسلامية، كراتشي',
          ummAlQura => 'جامعة أم القرى، مكة المكرمة',
          northAmerica => 'الجمعية الإسلامية لأمريكا الشمالية (ISNA)',
          moonsightingCommittee => 'لجنة رؤية الهلال العالمية',
          singapore => 'سنغافورة',
          dubai => 'دبي',
          qatar => 'قطر',
          kuwait => 'الكويت',
          turkiye => 'تركيا (ديانت)',
          tehran => 'جامعة طهران',
          algerian => 'وزارة الشؤون الدينية الجزائرية',
          france => 'اتحاد المنظمات الإسلامية في فرنسا',
          indonesian => 'وزارة الأديان الإندونيسية',
          jordan => 'وزارة الأوقاف الأردنية',
          morocco => 'وزارة الأوقاف المغربية',
          portugal => 'الجماعة الإسلامية بلشبونة',
          russia => 'الإدارة الروحية لمسلمي روسيا',
          tunisia => 'وزارة الشؤون الدينية التونسية',
        }
      : switch (this) {
          muslimWorldLeague => 'Muslim World League',
          egyptian => 'Egyptian General Authority of Survey',
          karachi => 'University of Islamic Sciences, Karachi',
          ummAlQura => 'Umm al-Qura University, Makkah',
          northAmerica => 'Islamic Society of North America (ISNA)',
          moonsightingCommittee => 'Moonsighting Committee Worldwide',
          singapore => 'Singapore',
          dubai => 'Dubai',
          qatar => 'Qatar',
          kuwait => 'Kuwait',
          turkiye => 'Turkey (Diyanet approximation)',
          tehran => 'University of Tehran',
          algerian => 'Algerian Ministry of Religious Affairs',
          france => 'Union of Islamic Organizations of France',
          indonesian => 'Kemenag (Indonesia)',
          jordan => 'Jordan Ministry of Awqaf',
          morocco => 'Moroccan Ministry of Habous & Islamic Affairs',
          portugal => 'Islamic Community of Lisbon',
          russia => 'Spiritual Administration of Muslims of Russia',
          tunisia => 'Tunisian Ministry of Religious Affairs',
        };

  adhan.CalculationParameters _parameters() => switch (this) {
        muslimWorldLeague =>
          adhan.CalculationMethodParameters.muslimWorldLeague(),
        egyptian => adhan.CalculationMethodParameters.egyptian(),
        karachi => adhan.CalculationMethodParameters.karachi(),
        ummAlQura => adhan.CalculationMethodParameters.ummAlQura(),
        northAmerica => adhan.CalculationMethodParameters.northAmerica(),
        moonsightingCommittee =>
          adhan.CalculationMethodParameters.moonsightingCommittee(),
        singapore => adhan.CalculationMethodParameters.singapore(),
        dubai => adhan.CalculationMethodParameters.dubai(),
        qatar => adhan.CalculationMethodParameters.qatar(),
        kuwait => adhan.CalculationMethodParameters.kuwait(),
        turkiye => adhan.CalculationMethodParameters.turkiye(),
        tehran => adhan.CalculationMethodParameters.tehran(),
        algerian => adhan.CalculationMethodParameters.algerian(),
        france => adhan.CalculationMethodParameters.france(),
        indonesian => adhan.CalculationMethodParameters.indonesian(),
        jordan => adhan.CalculationMethodParameters.jordan(),
        morocco => adhan.CalculationMethodParameters.morocco(),
        portugal => adhan.CalculationMethodParameters.portugal(),
        russia => adhan.CalculationMethodParameters.russia(),
        tunisia => adhan.CalculationMethodParameters.tunisia(),
      };

  /// The same convention's numeric id in the Aladhan API
  /// (https://api.aladhan.com/v1/methods) — both this enum and Aladhan wrap
  /// the same underlying Batoul Apps "Adhan" algorithm family, so each of
  /// these ids is the literal same method [_parameters] already computes
  /// locally, not a different/approximate one. Used by
  /// [PrayerTimesService]'s live fetch; the offline path never needs this.
  int get _aladhanMethodId => switch (this) {
        northAmerica => 2,
        muslimWorldLeague => 3,
        ummAlQura => 4,
        egyptian => 5,
        tehran => 7,
        kuwait => 9,
        qatar => 10,
        singapore => 11,
        turkiye => 13,
        moonsightingCommittee => 15,
        dubai => 16,
        karachi => 1,
        france => 12,
        russia => 14,
        tunisia => 18,
        algerian => 19,
        indonesian => 20,
        morocco => 21,
        portugal => 22,
        jordan => 23,
      };
}

/// Which school of thought's Asr convention to use — the one other
/// user-facing knob adhan_dart's calculation exposes (a later Asr time
/// under Hanafi than Shafi/Maliki/Hanbali, which all agree on the earlier
/// time). Defaults to [shafi] since that's the majority convention
/// worldwide; Hanafi users (common in South/Central Asia, Turkey) flip
/// this once in Notification Settings.
enum PrayerMadhab {
  shafi,
  hanafi;

  String toJson() => name;

  static PrayerMadhab fromJson(String? v) =>
      values.firstWhere((e) => e.name == v, orElse: () => shafi);

  String label(bool isAr) => isAr
      ? switch (this) {
          shafi => 'شافعي (الأصل)',
          hanafi => 'حنفي',
        }
      : switch (this) {
          shafi => 'Shafi / Maliki / Hanbali',
          hanafi => 'Hanafi',
        };

  adhan.Madhab get _value =>
      this == hanafi ? adhan.Madhab.hanafi : adhan.Madhab.shafi;
}

/// One day's five prayer times plus sunrise, already converted to
/// [tz.TZDateTime] in the device's local zone — every field is directly
/// usable as a `zonedSchedule` target, no further conversion needed at the
/// call site.
class PrayerDayTimes {
  final tz.TZDateTime fajr;
  final tz.TZDateTime sunrise;
  final tz.TZDateTime dhuhr;
  final tz.TZDateTime asr;
  final tz.TZDateTime maghrib;
  final tz.TZDateTime isha;

  const PrayerDayTimes({
    required this.fajr,
    required this.sunrise,
    required this.dhuhr,
    required this.asr,
    required this.maghrib,
    required this.isha,
  });

  /// Looks up a prayer by [HabitCue.prayerKey]'s canonical string
  /// ('fajr'/'dhuhr'/'asr'/'maghrib'/'isha') — the one place that maps
  /// between HabitCue's storage key and this class's typed fields, so nothing
  /// else in the app needs a string-keyed switch over prayer names.
  tz.TZDateTime? forKey(String key) => switch (key) {
        'fajr' => fajr,
        'dhuhr' => dhuhr,
        'asr' => asr,
        'maghrib' => maghrib,
        'isha' => isha,
        _ => null,
      };
}

/// One verified (or best-available) calculation recipe for a bounding box
/// of coordinates — see [PrayerTimesService.resolveRegion] and the class
/// doc comment's "not every country, exactly" section for what each entry
/// here is actually backed by.
typedef _PrayerRegion = ({
  String name,
  bool Function(double latitude, double longitude) contains,
  PrayerCalcMethod method,
  int fajrCorrectionMinutes,
});

/// Computes real prayer times from coordinates — the piece
/// NotificationService's original doc comment flagged as missing ("we
/// don't have real prayer-time/schedule data").
///
/// ── Live first, offline fallback ─────────────────────────────────────
/// [calculate] fetches from the Aladhan API (api.aladhan.com — free, no API
/// key) so results match the locally-published calendar exactly where
/// that's been verified, not just approximate it (see [resolveRegion]'s
/// doc comment for how, and for which places that's actually true today).
/// If that call fails for any reason — no connection, a timeout, a non-200
/// response, a response shape that doesn't parse — it falls back to
/// [calculateOffline], the original pure astronomical calculation via
/// adhan_dart, so a habit reminder never just silently fails to schedule
/// for lack of a network connection. Both paths are seeded with the exact
/// same method/correction from [resolveRegion], so the fallback lands on
/// the live result's numbers whenever the two calculations agree (which is
/// most of the year — the live call mainly matters for whatever margin a
/// local calendar authority applies on top of the raw calculation).
///
/// ── Three tiers, not one "every country, exactly" answer ─────────────
/// [resolveRegion] resolves a location in three steps, each a step down in
/// confidence:
///  1. [_regions] — 6 GCC countries, each individually checked against a
///     real published local timetable (Bahrain was user-verified exact
///     against Bahrain's own Ministry of Justice, Islamic Affairs & Waqf
///     calendar; the other 5 against dated third-party sources — see each
///     entry's own comment for specifics and confidence notes). Resolved
///     straight from coordinates, no dependency on country lookup at all.
///  2. [_countryDefaults] — roughly 20 more countries, each mapped to the
///     specific official/standard authority adhan_dart's own preset docs
///     name for that country (e.g. "Egyptian General Authority of
///     Survey," not a guess at "the closest regional method"). Real, but
///     not independently re-verified against a live local source the way
///     tier 1 was — needs a resolved country code (see
///     CountryLookupService) to apply at all.
///  3. [_globalDefaultMethod] (Muslim World League) — anywhere else, or if
///     country resolution never succeeded.
///
/// Neighboring countries are not treated as safe stand-ins for each other
/// at any tier: Aladhan's own docs note that even next-door authorities in
/// the same region typically differ by a few minutes from any single
/// shared method (https://aladhan.com/calculation-methods), and this
/// file's own Jordan/Saudi-Arabia bounding-box overlap (see the Saudi
/// Arabia entry in [_regions]) is a concrete example of exactly that risk
/// materializing and getting fixed rather than shipped. Adding a country
/// to tier 1's precision means repeating tier 1's actual process — find
/// that authority's real published times, compare against the
/// calculation, derive its own correction — not just widening an existing
/// box or reusing a neighbor's tier-2 entry.
///
/// Coordinates themselves come from on-device GPS (DeviceLocationService)
/// or GeocodingService's city search — see NotificationSettingsScreen's doc
/// comment. The country code tier 2 needs is a separate, independent
/// resolution (CountryLookupService) made once at the same time, not
/// derived from either of those.
class PrayerTimesService {
  const PrayerTimesService._();

  /// Used for anywhere [resolveRegion] can't place via [_regions] or
  /// [_countryDefaults] — not any particular country's own authority, just
  /// Muslim World League: the method explicitly designed to be broadly
  /// applicable worldwide, and the standard baseline default across
  /// prayer-time apps and libraries generally. This app originally
  /// defaulted to Karachi instead (a leftover from before per-region
  /// verification existed at all, when Karachi+tune happened to be the
  /// closest single match found for Bahrain) — switched to MWL once the
  /// default's job became "anywhere with no specific answer" rather than
  /// "the one method this app happens to use," since MWL is the one built
  /// for exactly that. Not independently verified for any particular
  /// place; see the class doc comment.
  static const _globalDefaultMethod = PrayerCalcMethod.muslimWorldLeague;

  /// Checked in order, first match wins — deliberately smallest/most
  /// specific countries first and Saudi Arabia (by far the largest
  /// bounding box, and the one every neighbor's box would otherwise
  /// overlap) last, so e.g. Bahrain's coordinates can never accidentally
  /// resolve to Saudi Arabia's box just because Bahrain's box sits inside
  /// Saudi Arabia's lat/lng envelope. Every box is a generous rectangle,
  /// not a precise border — a location right on a real border (the
  /// Bahrain/Saudi causeway, the UAE/Oman border) could go either way,
  /// which is an acceptable, low-stakes edge case; what this table
  /// actually guards against is one country's specific correction
  /// silently leaking into some entirely different, unrelated country.
  static final List<_PrayerRegion> _regions = [
    (
      name: 'Bahrain',
      // Manama + Muharraq + Sitra + Hawar — RE-verified against the
      // official Bahrain times the user supplied for 2026-07-17 (Fajr
      // 3:27, Sunrise 4:56, Dhuhr 11:44, Asr 3:11, Maghrib 6:32, Isha
      // 8:00): plain Karachi/Shafi matches ALL SIX values to the minute
      // with no correction (confirmed live against Aladhan method=1 for
      // Manama on that exact date). The earlier +9-minute Fajr correction
      // — from a 2026-07-16 comparison — made Fajr 9 minutes late against
      // this newer, fully self-consistent ground truth, so it's removed;
      // if a future official calendar disagrees again, re-verify a full
      // day's six values before touching this, not Fajr alone.
      contains: (lat, lng) =>
          lat >= 25.5 && lat <= 26.5 && lng >= 50.3 && lng <= 50.9,
      method: PrayerCalcMethod.karachi,
      fajrCorrectionMinutes: 0,
    ),
    (
      name: 'Qatar',
      // Qatar's Ministry of Awqaf and Islamic Affairs publishes Fajr at
      // 18°, Isha 90 minutes after Maghrib — exactly Aladhan/adhan_dart's
      // named "Qatar" method, independently confirmed against published
      // angle values (not just a plausible-sounding preset name). Cross-
      // checked to within 1-2 minutes of a dated third-party Doha
      // timetable for 2026-07-16; no additional correction applied.
      contains: (lat, lng) =>
          lat >= 24.4 && lat <= 26.2 && lng >= 50.7 && lng <= 51.7,
      method: PrayerCalcMethod.qatar,
      fajrCorrectionMinutes: 0,
    ),
    (
      name: 'Kuwait',
      // Kuwait's official Fajr/Isha angles (18°/17.5°, independently
      // confirmed, not just the preset name) match Aladhan/adhan_dart's
      // named "Kuwait" method exactly. No additional correction applied.
      contains: (lat, lng) =>
          lat >= 28.5 && lat <= 30.1 && lng >= 46.5 && lng <= 48.5,
      method: PrayerCalcMethod.kuwait,
      fajrCorrectionMinutes: 0,
    ),
    (
      name: 'United Arab Emirates',
      // Aladhan's "Dubai" method (18.2°/18.2°) was purpose-built by the
      // library's own maintainers to approximate the UAE's General
      // Authority of Islamic Affairs & Endowments (Awqaf)/Dubai IACAD
      // standard, and a UAE-specific prayer-time site independently
      // confirmed using this exact method to match "official Awqaf."
      // Lower confidence than Bahrain/Kuwait/Qatar: no independent
      // minute-level verification against a primary published source was
      // possible (awqaf.gov.ae is JS-rendered, couldn't be fetched
      // directly) — best-available, not confirmed exact.
      contains: (lat, lng) =>
          lat >= 22.5 && lat <= 26.5 && lng >= 51.5 && lng <= 56.5,
      method: PrayerCalcMethod.dubai,
      fajrCorrectionMinutes: 0,
    ),
    (
      name: 'Oman',
      // Oman's Ministry of Endowments and Religious Affairs (Awqaf) uses a
      // Fajr angle of 18.5° with Isha 90 minutes after Maghrib —
      // independently confirmed, matches Umm al-Qura exactly (not the
      // older, looser "Gulf Region"/19.5° grouping some historical sources
      // list Oman under, which was checked and ruled out — 5 minutes
      // earlier on fajr than this). No additional correction applied.
      contains: (lat, lng) =>
          lat >= 16.5 && lat <= 26.5 && lng >= 56.0 && lng <= 59.9,
      method: PrayerCalcMethod.ummAlQura,
      fajrCorrectionMinutes: 0,
    ),
    (
      name: 'Saudi Arabia',
      // Umm al-Qura *is* Saudi Arabia's own official method (published by
      // Saudi's own Umm al-Qura University) — cross-checked against a
      // dated, explicitly "Umm al-Qura, Makkah"-labeled Riyadh timetable
      // for 2026-07-16 and landed within 1-2 minutes on all 6 values, the
      // same margin explained by using a slightly different reference
      // point for "Riyadh" rather than any real calculation gap. No
      // additional correction applied. Checked last: this box is large
      // enough that every other GCC country's coordinates also technically
      // fall inside it, so it only ever applies once nothing more specific
      // has already matched.
      //
      // Northern edge deliberately capped at 29.5°, well short of Saudi's
      // real northern extent (~32°) — a looser cap up there started
      // overlapping Jordan (Amman is ~31.95°N) once Jordan became a real,
      // separately-covered country via _countryDefaults rather than just
      // unclaimed territory, and confidently mislabeling Amman as Saudi
      // Arabia is a real error, not a low-stakes edge case (unlike
      // ambiguity between two neighboring GCC states, which this box's
      // looseness was originally scoped to tolerate). The handful of
      // genuinely-Saudi places north of 29.5° (Sakakah, Arar) simply fall
      // through to _countryDefaults's 'SA' entry instead, which resolves
      // to the exact same method — the only actual cost is needing a
      // successful country-code lookup instead of an instant, offline box
      // match for that specific sliver of the country.
      contains: (lat, lng) =>
          lat >= 16.0 && lat <= 29.5 && lng >= 34.5 && lng <= 55.7,
      method: PrayerCalcMethod.ummAlQura,
      fajrCorrectionMinutes: 0,
    ),
  ];

  /// Second tier, for everywhere [_regions] above doesn't cover — keyed by
  /// ISO 3166-1 alpha-2 country code (see CountryLookupService, which is
  /// what actually turns coordinates into that code). Every entry here is
  /// a country whose own official/standard authority is explicitly named
  /// in adhan_dart's own preset documentation — e.g.
  /// `CalculationMethodParameters.egyptian()`'s doc literally says
  /// "Egyptian General Authority of Survey" — not a guess at "the closest
  /// regional method."
  ///
  /// A meaningfully lower confidence tier than [_regions], though: those
  /// six were each individually checked against a real published local
  /// timetable (see the class doc comment's per-country notes); these are
  /// "this is the specific documented convention for this country," not
  /// independently re-verified against a live local source the way
  /// Bahrain was. The 6 GCC codes are listed again here too, defensively —
  /// [_regions] is checked first and is the precise, corrected path, but
  /// if a coordinate ever falls just outside one of those generous
  /// rectangles (a real border/offshore-island edge case, same tradeoff
  /// [_regions] itself already accepts) this still lands on that
  /// country's own method instead of falling all the way through to the
  /// uncorrected global default.
  ///
  /// US/CA/GB → [PrayerCalcMethod.moonsightingCommittee], not the more
  /// obviously-named `northAmerica` (ISNA): adhan_dart's own docs
  /// recommend moonsightingCommittee over northAmerica for North America,
  /// and separately call moonsightingCommittee out as "Recommended for
  /// North America and the UK" directly.
  static const Map<String, PrayerCalcMethod> _countryDefaults = {
    'BH': PrayerCalcMethod.karachi,
    'SA': PrayerCalcMethod.ummAlQura,
    'AE': PrayerCalcMethod.dubai,
    'KW': PrayerCalcMethod.kuwait,
    'QA': PrayerCalcMethod.qatar,
    'OM': PrayerCalcMethod.ummAlQura,
    'EG': PrayerCalcMethod.egyptian,
    'DZ': PrayerCalcMethod.algerian,
    'FR': PrayerCalcMethod.france,
    'ID': PrayerCalcMethod.indonesian,
    'JO': PrayerCalcMethod.jordan,
    'PT': PrayerCalcMethod.portugal,
    'MA': PrayerCalcMethod.morocco,
    'RU': PrayerCalcMethod.russia,
    'TN': PrayerCalcMethod.tunisia,
    'TR': PrayerCalcMethod.turkiye,
    'IR': PrayerCalcMethod.tehran,
    'PK': PrayerCalcMethod.karachi,
    'SG': PrayerCalcMethod.singapore,
    'MY': PrayerCalcMethod.singapore,
    'US': PrayerCalcMethod.moonsightingCommittee,
    'CA': PrayerCalcMethod.moonsightingCommittee,
    'GB': PrayerCalcMethod.moonsightingCommittee,
  };

  /// Which [PrayerCalcMethod] applies at [latitude]/[longitude], plus how
  /// many minutes of manual fajr correction ride on top of it. Three
  /// tiers, checked in order:
  ///  1. The 6 hand-verified GCC bounding boxes in [_regions] — exact, no
  ///     dependency on [countryCode] at all.
  ///  2. [_countryDefaults], keyed by [countryCode] if one was resolved
  ///     (see CountryLookupService) — a specific, documented convention
  ///     for that country, not independently re-verified.
  ///  3. [_globalDefaultMethod] (Muslim World League) — anywhere else, or
  ///     if [countryCode] is null (never resolved, or the lookup failed).
  ///
  /// Deliberately synchronous — [countryCode] is a plain value the caller
  /// already has cached (`NotificationSettings.resolvedCountryCode`, set
  /// once when the location itself was set), not something this function
  /// goes and fetches itself. That keeps this cheap enough to call from
  /// both [calculate]'s hot path and NotificationSettingsScreen's
  /// read-only method row directly inside `build()`, with no loading
  /// state to manage. Public (not `@visibleForTesting`) for the same
  /// reason: both of those call sites need the exact same resolution,
  /// rather than keeping a second copy of this logic in sync.
  static ({PrayerCalcMethod method, int fajrCorrectionMinutes}) resolveRegion(
    double latitude,
    double longitude, {
    String? countryCode,
  }) {
    for (final region in _regions) {
      if (region.contains(latitude, longitude)) {
        return (
          method: region.method,
          fajrCorrectionMinutes: region.fajrCorrectionMinutes,
        );
      }
    }
    final byCountry =
        countryCode == null ? null : _countryDefaults[countryCode];
    if (byCountry != null) {
      return (method: byCountry, fajrCorrectionMinutes: 0);
    }
    return (method: _globalDefaultMethod, fajrCorrectionMinutes: 0);
  }

  /// [date]'s year/month/day (its time-of-day component, if any, is
  /// ignored) determine which calendar day's times are calculated — pass
  /// `DateTime.now()` for today, or `DateTime.now().add(Duration(days: 1))`
  /// to look ahead to tomorrow (needed when today's occurrence of a prayer
  /// has already passed and the next reminder has to land on the right day
  /// instead of just naively adding 24h to a time that shifts by a minute
  /// or two daily).
  ///
  /// [latitude]/[longitude] (plus [countryCode], if one was resolved when
  /// the location was set — see CountryLookupService) pick the method
  /// automatically via [resolveRegion] — there's no method/madhab-method
  /// parameter here anymore, only [madhab] (a genuine personal preference,
  /// unlike the calculation method itself — see NotificationSettingsScreen's
  /// doc comment for why the method picker was removed). [countryCode] is
  /// optional and can safely be left null — [resolveRegion] just falls
  /// back to its plain global default in that case, the same as it always
  /// did before country-level resolution existed.
  ///
  /// Tries the live Aladhan fetch first (~8s timeout), falls back to
  /// [calculateOffline] on any failure — see the class doc comment. Always
  /// completes with a result; never throws.
  static Future<PrayerDayTimes> calculate({
    required double latitude,
    required double longitude,
    required DateTime date,
    required PrayerMadhab madhab,
    String? countryCode,
  }) async {
    final region = resolveRegion(latitude, longitude, countryCode: countryCode);
    final online = await _fetchOnline(
      latitude: latitude,
      longitude: longitude,
      date: date,
      method: region.method,
      madhab: madhab,
      fajrCorrectionMinutes: region.fajrCorrectionMinutes,
    );
    if (online != null) return online;

    return calculateOfflineCorrected(
      latitude: latitude,
      longitude: longitude,
      date: date,
      madhab: madhab,
      countryCode: countryCode,
    );
  }

  /// [calculateOffline]'s result with [resolveRegion]'s fajr correction
  /// already applied — the exact offline path [calculate] itself falls
  /// back to on any network failure, factored out into its own method so a
  /// second, synchronous-only caller can get the same answer without
  /// duplicating the correction-application step. Currently that second
  /// caller is AddHabitSheet's reminder-time preview (the small "you'll be
  /// reminded at ..." line under a prayer-linked habit's lead-time picker)
  /// — a live network round trip on every keystroke of that picker would be
  /// wasteful for what's just an illustrative preview, so it always takes
  /// this offline path rather than [calculate]'s live-API-first one. That
  /// means the preview can differ from the moment the habit actually fires
  /// at by the same small margin [calculate]'s own doc comment describes
  /// between the live and offline answers (typically seconds, occasionally
  /// a minute or two for the handful of places a local calendar authority
  /// applies its own extra margin) — an acceptable trade for a preview,
  /// not for the real scheduled notification.
  static PrayerDayTimes calculateOfflineCorrected({
    required double latitude,
    required double longitude,
    required DateTime date,
    required PrayerMadhab madhab,
    String? countryCode,
  }) {
    final region = resolveRegion(latitude, longitude, countryCode: countryCode);
    final offline = calculateOffline(
      latitude: latitude,
      longitude: longitude,
      date: date,
      method: region.method,
      madhab: madhab,
    );
    if (region.fajrCorrectionMinutes == 0) return offline;
    return PrayerDayTimes(
      fajr: offline.fajr.add(Duration(minutes: region.fajrCorrectionMinutes)),
      sunrise: offline.sunrise,
      dhuhr: offline.dhuhr,
      asr: offline.asr,
      maghrib: offline.maghrib,
      isha: offline.isha,
    );
  }

  /// Pure, synchronous, fully offline — no network call, no API key, no
  /// server, no region lookup and no correction applied (that's
  /// [calculate]'s job, layered on top of this) — just [method]'s raw
  /// angle-based calculation for whatever coordinates/date/madhab are
  /// passed in. What tests call directly for deterministic, hermetic
  /// assertions about the underlying math (see
  /// test/prayer_times_service_test.dart), and the primitive [calculate]
  /// falls back to (with its own correction added afterward) on any
  /// network failure.
  static PrayerDayTimes calculateOffline({
    required double latitude,
    required double longitude,
    required DateTime date,
    required PrayerCalcMethod method,
    required PrayerMadhab madhab,
  }) {
    final coordinates = adhan.Coordinates(latitude, longitude);
    final params = method._parameters()..madhab = madhab._value;
    final prayerTimes = adhan.PrayerTimes(
      coordinates: coordinates,
      date: DateTime(date.year, date.month, date.day),
      calculationParameters: params,
      precision: true,
    );
    // adhan_dart returns UTC-flagged DateTimes (see its README) —
    // TZDateTime.from converts the same instant into tz.local's wall-clock
    // representation, which is what a zonedSchedule call needs and what a
    // notification body's "today at HH:mm" should show.
    return PrayerDayTimes(
      fajr: tz.TZDateTime.from(prayerTimes.fajr, tz.local),
      sunrise: tz.TZDateTime.from(prayerTimes.sunrise, tz.local),
      dhuhr: tz.TZDateTime.from(prayerTimes.dhuhr, tz.local),
      asr: tz.TZDateTime.from(prayerTimes.asr, tz.local),
      maghrib: tz.TZDateTime.from(prayerTimes.maghrib, tz.local),
      isha: tz.TZDateTime.from(prayerTimes.isha, tz.local),
    );
  }

  /// The live half of [calculate] — returns null (never throws) on any
  /// failure so the caller's offline fallback is a plain `??`-shaped check.
  static Future<PrayerDayTimes?> _fetchOnline({
    required double latitude,
    required double longitude,
    required DateTime date,
    required PrayerCalcMethod method,
    required PrayerMadhab madhab,
    required int fajrCorrectionMinutes,
  }) async {
    try {
      final response = await http
          .get(aladhanRequestUri(
            latitude: latitude,
            longitude: longitude,
            date: date,
            method: method,
            madhab: madhab,
            fajrCorrectionMinutes: fajrCorrectionMinutes,
          ))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final timings = decoded['data']?['timings'];
      if (timings is! Map) return null;

      final day = DateTime(date.year, date.month, date.day);
      final fajr = parseAladhanTime(timings['Fajr'] as String?, day);
      final sunrise = parseAladhanTime(timings['Sunrise'] as String?, day);
      final dhuhr = parseAladhanTime(timings['Dhuhr'] as String?, day);
      final asr = parseAladhanTime(timings['Asr'] as String?, day);
      final maghrib = parseAladhanTime(timings['Maghrib'] as String?, day);
      final isha = parseAladhanTime(timings['Isha'] as String?, day);
      if (fajr == null ||
          sunrise == null ||
          dhuhr == null ||
          asr == null ||
          maghrib == null ||
          isha == null) {
        return null;
      }
      return PrayerDayTimes(
        fajr: fajr,
        sunrise: sunrise,
        dhuhr: dhuhr,
        asr: asr,
        maghrib: maghrib,
        isha: isha,
      );
    } catch (_) {
      // No connection, DNS failure, malformed JSON, a timeout — any of
      // these just means "use the offline fallback," not a crash.
      return null;
    }
  }

  /// Builds the exact Aladhan `/v1/timings/{DD-MM-YYYY}` request for
  /// [date]/[latitude]/[longitude]/[method]/[madhab], with
  /// [fajrCorrectionMinutes] applied via Aladhan's `tune` parameter (fajr's
  /// slot only — every other prayer's slot is always 0, since that's all
  /// any of [_regions] has ever needed) — pulled out as its own
  /// `@visibleForTesting` function so the URL (method id, tune string, date
  /// format, school) can be asserted on directly without a live network
  /// call. `timezonestring` is passed explicitly as `tz.local`'s IANA name
  /// so Aladhan localizes its "HH:mm" strings into the exact zone
  /// [parseAladhanTime] then reads them back into, rather than relying on
  /// Aladhan's own coordinate-based timezone guess matching tz.local (it
  /// normally does, since the location was set from where the device
  /// actually is, but this removes the assumption entirely).
  @visibleForTesting
  static Uri aladhanRequestUri({
    required double latitude,
    required double longitude,
    required DateTime date,
    required PrayerCalcMethod method,
    required PrayerMadhab madhab,
    int fajrCorrectionMinutes = 0,
  }) {
    final dateStr = '${date.day.toString().padLeft(2, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.year}';
    return Uri.https('api.aladhan.com', '/v1/timings/$dateStr', {
      'latitude': '$latitude',
      'longitude': '$longitude',
      'method': '${method._aladhanMethodId}',
      'tune': '0,$fajrCorrectionMinutes,0,0,0,0,0,0,0',
      'school': madhab == PrayerMadhab.hanafi ? '1' : '0',
      'timezonestring': tz.local.name,
    });
  }

  /// Parses one Aladhan timing value ("03:36", or occasionally "03:36
  /// (+03)" — the trailing part is dropped rather than relied on) into a
  /// [tz.TZDateTime] on [day] in `tz.local`. Returns null on anything that
  /// doesn't parse as `HH:mm`, so [_fetchOnline] can treat a malformed
  /// response the same as a network failure. `@visibleForTesting` for the
  /// same reason as [aladhanRequestUri] — a pure function worth asserting
  /// on directly.
  @visibleForTesting
  static tz.TZDateTime? parseAladhanTime(String? raw, DateTime day) {
    if (raw == null || raw.isEmpty) return null;
    final clean = raw.split(' ').first;
    final parts = clean.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return tz.TZDateTime(tz.local, day.year, day.month, day.day, hour, minute);
  }
}
