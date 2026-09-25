import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../features/settings/models/notification_settings.dart';
import 'home_widget_service.dart';
import 'prayer_times_service.dart';

/// Keeps the prayer-countdown widget (ios/GrowDailyWidget/
/// PrayerCountdownWidget.swift) supplied with a week of upcoming prayer
/// instants.
///
/// The widget deliberately owns none of this: it has no location, no
/// calculation method and no madhab, and it never asks the network. It only
/// picks the next instant out of the list this pushes and counts to it. So
/// everything that makes a prayer time *correct* — Bahrain's own official
/// table, the Aladhan month calendar, the offline fallback, the region's
/// Fajr correction — stays in [PrayerTimesService] where the rest of the app
/// already reads it, and the widget can never disagree with a reminder.
///
/// ── Why a week, not the next prayer ──────────────────────────────────
/// A widget cannot fetch. Whatever is written here is all it has until the
/// app is next opened, so a single "next prayer" would go stale the moment
/// that adhan passed and leave the face blank for the rest of the day. A
/// week costs nothing to compute inside Bahrain (the bundled table is
/// offline and exact) and at most one or two memoized month requests
/// anywhere else, and it means a phone left alone over a weekend still
/// shows the right countdown.
class PrayerWidgetFeed {
  PrayerWidgetFeed._();

  /// How far ahead each push writes.
  @visibleForTesting
  static const days = 7;

  /// What the widget counts to, in the order the moments occur, as
  /// [PrayerDayTimes]' own field names.
  ///
  /// Sunrise is in the list but it is not one of the five: nobody calls an
  /// adhan for it, so the widget says «باقي على الشروق» and «مضى على
  /// الشروق» where a prayer says «الأذان» (PrayerSlot.hasAdhan on the Swift
  /// side), and it keeps its own minutes after it passes like the rest (see
  /// [elapsedMinutes]). It earns its place because without it the stretch
  /// from Fajr to Dhuhr is five hours with nothing to count to — Aziz asked
  /// for it on 2026-09-23, on the condition that the time be right, and the
  /// bundled Bahrain table was re-measured against the official feed for
  /// it: 521 of 521 days exact.
  static const _keys = [
    'fajr',
    'sunrise',
    'dhuhr',
    'asr',
    'maghrib',
    'isha',
  ];

  /// How many minutes each moment stays on the widget's face after it
  /// passes, counting up: «مضى على الأذان» after the five, «مضى على
  /// الشروق» after sunrise. Aziz's numbers (2026-09-25), which replaced a
  /// flat half hour for the five and none at all for sunrise.
  ///
  /// Must match `prayerElapsedMinutes` in ios/GrowDailyWidget/
  /// PrayerSchedule.swift. The widget applies the same rule against its own
  /// clock, and a shorter window here would delete the very moment the face
  /// is showing; the test reads the Swift table and holds the two equal.
  @visibleForTesting
  static const elapsedMinutes = {
    'fajr': 25,
    'sunrise': 15,
    'dhuhr': 25,
    'asr': 25,
    'maghrib': 15,
    'isha': 25,
  };

  /// [elapsedMinutes] for [key], or nothing for a key it does not name.
  /// Mirrors PrayerSlot.elapsedWindow in PrayerSchedule.swift.
  @visibleForTesting
  static Duration elapsedWindowFor(String key) =>
      Duration(minutes: elapsedMinutes[key] ?? 0);

  /// Guards against two pushes overlapping — resume, a settings change and
  /// the day turning can all land within the same moment, and the second
  /// one would otherwise recompute the identical week.
  static Future<void> _chain = Future.value();

  /// The (location, country, day) a push last covered. A repeat of
  /// the same inputs on the same day is skipped: the widget filters the
  /// list against its own clock, so nothing about it goes stale during a
  /// day, and every resume would otherwise redo the work.
  static String? _lastPushKey;

  /// Forgets [_lastPushKey], so the next [push] recomputes. For tests, and
  /// for anything that needs to force a rewrite.
  @visibleForTesting
  static void resetPushGuard() => _lastPushKey = null;

  /// Computes the next [days] days of prayers for [settings]' saved location
  /// and hands them to the widget. Never throws.
  ///
  /// With no saved location this pushes an EMPTY list rather than returning
  /// early: that is what clears the widget back to its "set your location"
  /// face when the location is removed in Settings.
  static Future<void> push(NotificationSettings settings, {DateTime? now}) {
    return _chain = _chain.then((_) => _push(settings, now ?? DateTime.now()));
  }

  static Future<void> _push(NotificationSettings settings, DateTime now) async {
    try {
      final loc = settings.location;
      final key = loc == null
          ? 'none'
          : '${loc.lat},${loc.lng},'
              '${settings.resolvedCountryCode},'
              '${now.year}-${now.month}-${now.day}';
      if (key == _lastPushKey) return;

      if (loc == null) {
        await HomeWidgetService.instance.updatePrayerWidgetData(const []);
        _lastPushKey = key;
        return;
      }

      final schedule = await PrayerTimesService.calculateDays(
        latitude: loc.lat,
        longitude: loc.lng,
        from: now,
        days: days,
        countryCode: settings.resolvedCountryCode,
      );
      final out = flatten(schedule, from: now);
      if (out.isEmpty) return; // Nothing computed; keep whatever it has.
      await HomeWidgetService.instance.updatePrayerWidgetData(out);
      _lastPushKey = key;
    } catch (e) {
      // A widget going a day stale is never worth an error on screen, and
      // the next resume tries again.
      debugPrint('[PrayerWidgetFeed] push skipped: $e');
    }
  }

  /// [days] worth of [PrayerDayTimes] as one ascending run of (key, moment)
  /// pairs, dropping everything already behind [from].
  ///
  /// Prayers already fully behind [from] are dropped HERE rather than left
  /// to the widget: they are the only part of the list that is dead on
  /// arrival, and trimming them keeps the payload to what the widget can
  /// actually show. The widget still re-filters against its own clock,
  /// since this list is read for days after it is written.
  ///
  /// "Fully behind" means older than that moment's own elapsed window, not
  /// merely past: the prayer whose adhan went twenty minutes ago is exactly
  /// the one the face is showing right now, and dropping it would cut «مضى
  /// على الأذان» short every time the app was opened during those minutes.
  /// Sunrise is kept the same way, for its own quarter hour.
  @visibleForTesting
  static List<({String key, DateTime at})> flatten(
    List<PrayerDayTimes> schedule, {
    required DateTime from,
  }) {
    final out = <({String key, DateTime at})>[];
    for (final day in schedule) {
      for (final key in _keys) {
        final floor = from.subtract(elapsedWindowFor(key));
        final at = _momentOf(day, key);
        if (at == null) continue;
        // A local DateTime, not the tz.TZDateTime as-is: only the instant
        // travels to the widget (as epoch milliseconds), and iOS renders it
        // in the device's own zone.
        final moment = DateTime.fromMillisecondsSinceEpoch(
          at.millisecondsSinceEpoch,
        );
        if (!moment.isAfter(floor)) continue;
        out.add((key: key, at: moment));
      }
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  /// [PrayerDayTimes.forKey] plus sunrise. forKey deliberately answers only
  /// the five HabitCue can anchor a reminder to, and widening it there
  /// would let a habit be scheduled against sunrise, which is a different
  /// feature; this keeps the extra key local to the widget's list.
  static tz.TZDateTime? _momentOf(PrayerDayTimes day, String key) =>
      key == 'sunrise' ? day.sunrise : day.forKey(key);
}
