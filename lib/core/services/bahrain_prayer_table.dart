import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:timezone/timezone.dart' as tz;

import 'prayer_times_service.dart';

/// Bahrain's official prayer timetable, published by the Kingdom's own
/// government apps platform and bundled verbatim as an asset.
///
/// ── Why a table and not a calculation ────────────────────────────────
///
/// [PrayerTimesService] already resolves Bahrain to Karachi/Shafi, and that
/// pairing was measured against every one of the 521 days this file covers:
/// it lands within one minute on essentially every prayer, and never more
/// than two. Of the seven conventions tested against the same data it was
/// the closest by a wide margin (Kuwait is 3 minutes out on Isha, Umm
/// al-Qura 14, Egyptian 9 on Fajr), so nothing about the method was wrong.
///
/// The residual is not a method disagreement at all — it is sub-minute.
/// Directional rounding explains most of it and not all (rounding Maghrib
/// up matches 88% of days rather than 100%), which puts the rest down to
/// whichever solar-position constants Bahrain's own software uses. No
/// choice of method or offset available here can close a gap that small,
/// and the systematic part of it ran the wrong way: Maghrib computed one
/// minute EARLY on 89% of days. A minute is nothing for a habit reminder
/// and not nothing for the moment a fast ends, so with the authority's own
/// figures published as open data, using them directly is simply more
/// correct than approximating them.
///
/// ── Scope ─────────────────────────────────────────────────────────────
///
/// Covers 2026-01-01 through 2027-06-05 — the full span the source
/// published — and Bahrain only. [lookup] returns null outside either, and
/// every caller falls straight back to the calculated path, which is the
/// same path every other country in the world already uses. So this is
/// purely an accuracy upgrade where it applies and invisible everywhere
/// else, including in Bahrain after the table runs out.
///
/// Regenerate by re-fetching `source` from the asset and rebuilding
/// assets/prayer/bahrain_official.json in the same shape; the test in
/// test/bahrain_prayer_table_test.dart re-checks the bundled file's own
/// internal consistency and its agreement with the calculated path.
class BahrainPrayerTable {
  BahrainPrayerTable._();

  static const assetPath = 'assets/prayer/bahrain_official.json';

  /// "YYYY-MM-DD" -> "HH:MM HH:MM ..." in [_order].
  static Map<String, String>? _days;
  static const _order = ['fajr', 'sunrise', 'dhuhr', 'asr', 'maghrib', 'isha'];
  static bool _attempted = false;

  static bool get isLoaded => _days != null;

  /// Loads the bundled table once. Safe to call repeatedly and from
  /// anywhere; a failure is remembered so a broken asset can't turn into a
  /// re-read on every prayer lookup for the rest of the session.
  ///
  /// Must be awaited before [lookup] can return anything, which is why
  /// main.dart preloads it at startup: [lookup] itself is synchronous, so
  /// the one caller that cannot await (AddHabitSheet's live cue preview)
  /// still gets the official times rather than silently falling back.
  static Future<void> ensureLoaded() async {
    if (_attempted) return;
    _attempted = true;
    try {
      final decoded =
          jsonDecode(await rootBundle.loadString(assetPath)) as Map;
      _days = (decoded['days'] as Map).cast<String, String>();
    } catch (_) {
      // Fall back to calculation. Never throws: a missing or malformed
      // asset must not be able to stop prayer reminders working.
      _days = null;
    }
  }

  /// The official times for [date], or null when this table doesn't apply
  /// — outside its date range, or before [ensureLoaded] has run.
  ///
  /// The stored strings are Bahrain wall-clock, so they're built in
  /// Asia/Bahrain and then converted to the device's own zone, exactly
  /// like [PrayerTimesService.calculateOffline] does. That matters for a
  /// traveller who has pinned their prayer location to Bahrain: they get
  /// the same instants, shown on their own clock, rather than Bahrain's
  /// digits pasted onto a different timezone.
  static PrayerDayTimes? lookup(DateTime date) {
    final days = _days;
    if (days == null) return null;
    final key = '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final row = days[key];
    if (row == null) return null;
    final parts = row.split(' ');
    if (parts.length != _order.length) return null;
    try {
      final bahrain = tz.getLocation('Asia/Bahrain');
      final at = <String, tz.TZDateTime>{};
      for (var i = 0; i < _order.length; i++) {
        final hm = parts[i].split(':');
        at[_order[i]] = tz.TZDateTime.from(
          tz.TZDateTime(
            bahrain,
            date.year,
            date.month,
            date.day,
            int.parse(hm[0]),
            int.parse(hm[1]),
          ),
          tz.local,
        );
      }
      return PrayerDayTimes(
        fajr: at['fajr']!,
        sunrise: at['sunrise']!,
        dhuhr: at['dhuhr']!,
        asr: at['asr']!,
        maghrib: at['maghrib']!,
        isha: at['isha']!,
      );
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _days = null;
    _attempted = false;
  }
}
