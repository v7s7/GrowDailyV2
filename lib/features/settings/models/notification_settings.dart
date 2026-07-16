import 'package:flutter/material.dart' show TimeOfDay;

import '../../../core/services/prayer_times_service.dart';

/// A location for prayer-time calculation — resolved once (via on-device
/// GPS, see DeviceLocationService, or a typed city search via
/// [GeocodingService] as the fallback) and cached here from then on, so no
/// location permission or search is needed again. Every later reminder
/// computation sends just this lat/lng to a prayer-times API for an exact
/// result (see [PrayerTimesService.calculate]), falling back to an offline
/// calculation from the same coordinates when there's no connection. See
/// NotificationSettingsScreen's doc comment for how the two location-
/// resolution paths fit together.
///
/// A country code for the same coordinates is resolved separately, right
/// alongside this (see [NotificationSettings.resolvedCountryCode]) — kept
/// as its own nullable field rather than bundled into this class, since it
/// can legitimately still be null for a moment (or permanently, if that
/// one lookup fails) even once a location is already set and showing.
class NotificationLocation {
  final double lat;
  final double lng;
  final String label; // e.g. "Cairo, Al Qahirah, Egypt" — shown verbatim in Settings

  const NotificationLocation({
    required this.lat,
    required this.lng,
    required this.label,
  });

  Map<String, dynamic> toMap() => {'lat': lat, 'lng': lng, 'label': label};

  static NotificationLocation? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final lat = (raw['lat'] as num?)?.toDouble();
    final lng = (raw['lng'] as num?)?.toDouble();
    final label = raw['label'] as String?;
    if (lat == null || lng == null || label == null || label.isEmpty) {
      return null;
    }
    return NotificationLocation(lat: lat, lng: lng, label: label);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotificationLocation &&
          lat == other.lat &&
          lng == other.lng &&
          label == other.label;

  @override
  int get hashCode => Object.hash(lat, lng, label);
}

String _timeToMap(TimeOfDay t) => '${t.hour}:${t.minute}';

TimeOfDay _timeFromMap(Object? raw, TimeOfDay fallback) {
  if (raw is! String) return fallback;
  final parts = raw.split(':');
  if (parts.length != 2) return fallback;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return fallback;
  return TimeOfDay(hour: hour, minute: minute);
}

/// Every knob GrowDaily's notification system exposes, all in one
/// persisted blob (see NotificationSettingsNotifier) instead of scattered
/// individual providers — deliberately, since Settings > Notifications
/// shows and edits all of them together, and a user turning the master
/// switch off needs to reason about (and this needs to cancel) every
/// category at once.
///
/// Defaults are chosen to be genuinely helpful out of the box without
/// feeling like spam: reminders and streak protection on, but nothing
/// fires until a habit actually has a resolvable cue (a picked clock time,
/// or a prayer cue *and* a saved location) — same "never guess a wrong
/// time" philosophy the original NotificationService shipped with.
class NotificationSettings {
  /// Top-level kill switch — off means every notification this app sends
  /// (reminders, streak risk, celebrations, the plain daily reminder) stops,
  /// full stop. Everything below only matters when this is true.
  final bool masterEnabled;

  /// Per-habit reminders — the ones tied to a habit's own cue (prayer or
  /// clock time), with Mark Done/Snooze actions.
  final bool habitRemindersEnabled;

  /// The evening "you're about to lose your streak" nudge — see
  /// NotificationService.scheduleStreakRiskCheck. Only ever fires when a
  /// streak is actually at risk (streak > 0 and something's still
  /// unfinished today), never as a blind daily ping.
  final bool streakRiskEnabled;

  /// In-the-moment celebration pings: habit completed, level up,
  /// achievement unlocked. These fire immediately (not scheduled ahead),
  /// so "not spam" here means "off means off," not rate-limiting.
  final bool celebrationsEnabled;

  /// Whether the streak-risk nudge also mentions a pending count of
  /// DO-FIRST (urgent + important) Matrix tasks, when there are any. Adds a
  /// line to that one notification rather than a separate ping of its own
  /// — see NotificationService.scheduleStreakRiskCheck.
  final bool matrixNudgeEnabled;

  /// When two or more habit reminders land within the same few minutes,
  /// combine them into one notification ("3 habits ready: ...") instead of
  /// firing one each — see NotificationService's bundling pass.
  final bool bundleEnabled;

  final bool quietHoursEnabled;
  final TimeOfDay quietHoursStart;
  final TimeOfDay quietHoursEnd;

  /// Quiet hours suppress the generic daily reminder and the streak-risk
  /// nudge by default, but a prayer-linked habit reminder is exempt unless
  /// this is explicitly turned on — because the entire point of "remind me
  /// after Fajr" is to be reminded near Fajr, which for most of the world
  /// falls well inside a typical nighttime quiet window. Flip this on only
  /// if quiet hours should override that too.
  final bool quietHoursAppliesToPrayer;

  /// Minutes after the prayer itself a prayer-linked habit reminder fires
  /// — e.g. 10 means "10 minutes after Maghrib," giving a little breathing
  /// room after the prayer rather than firing at the exact adhan moment.
  final int prayerOffsetMinutes;

  /// Local clock time the streak-risk check runs at, if it's going to fire
  /// at all that day (see [streakRiskEnabled]'s doc comment).
  final TimeOfDay streakRiskTime;

  final NotificationLocation? location;

  /// ISO 3166-1 alpha-2 country code for [location], resolved once via
  /// CountryLookupService at the same moment [location] itself was set (GPS
  /// detect or manual city search — see NotificationSettingsScreen's
  /// `_LocationRow`) and cached here the same way, rather than looked up
  /// fresh on every prayer-time calculation. Feeds
  /// [PrayerTimesService.resolveRegion]'s global country-default tier; null
  /// if [location] was never set, or if the lookup failed — a failed
  /// lookup never blocks setting the location itself, [PrayerTimesService]
  /// just falls back to its plain global default until this resolves
  /// successfully (e.g. on the next GPS re-detect).
  final String? resolvedCountryCode;

  final PrayerMadhab madhab;

  const NotificationSettings({
    this.masterEnabled = true,
    this.habitRemindersEnabled = true,
    this.streakRiskEnabled = true,
    this.celebrationsEnabled = true,
    this.matrixNudgeEnabled = true,
    this.bundleEnabled = true,
    this.quietHoursEnabled = true,
    this.quietHoursStart = const TimeOfDay(hour: 22, minute: 0),
    this.quietHoursEnd = const TimeOfDay(hour: 7, minute: 0),
    this.quietHoursAppliesToPrayer = false,
    this.prayerOffsetMinutes = 10,
    this.streakRiskTime = const TimeOfDay(hour: 20, minute: 30),
    this.location,
    this.resolvedCountryCode,
    this.madhab = PrayerMadhab.shafi,
  });

  bool get hasLocation => location != null;

  NotificationSettings copyWith({
    bool? masterEnabled,
    bool? habitRemindersEnabled,
    bool? streakRiskEnabled,
    bool? celebrationsEnabled,
    bool? matrixNudgeEnabled,
    bool? bundleEnabled,
    bool? quietHoursEnabled,
    TimeOfDay? quietHoursStart,
    TimeOfDay? quietHoursEnd,
    bool? quietHoursAppliesToPrayer,
    int? prayerOffsetMinutes,
    TimeOfDay? streakRiskTime,
    // Nullable field: copyWith's usual `?? this.x` can't express "set it
    // back to null," so clearing location goes through [clearLocation]
    // instead — same reasoning HabitModel/MatrixTask's copyWiths use
    // elsewhere in this codebase for their own nullable fields.
    NotificationLocation? location,
    bool clearLocation = false,
    // Cleared alongside location by default (clearLocation also wipes
    // this — a country code resolved for a location that's just been
    // cleared is stale, not still meaningful) — pass a fresh value
    // explicitly (as _LocationRow does, in the same call that sets a new
    // location) to update it instead.
    String? resolvedCountryCode,
    PrayerMadhab? madhab,
  }) =>
      NotificationSettings(
        masterEnabled: masterEnabled ?? this.masterEnabled,
        habitRemindersEnabled:
            habitRemindersEnabled ?? this.habitRemindersEnabled,
        streakRiskEnabled: streakRiskEnabled ?? this.streakRiskEnabled,
        celebrationsEnabled: celebrationsEnabled ?? this.celebrationsEnabled,
        matrixNudgeEnabled: matrixNudgeEnabled ?? this.matrixNudgeEnabled,
        bundleEnabled: bundleEnabled ?? this.bundleEnabled,
        quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
        quietHoursStart: quietHoursStart ?? this.quietHoursStart,
        quietHoursEnd: quietHoursEnd ?? this.quietHoursEnd,
        quietHoursAppliesToPrayer:
            quietHoursAppliesToPrayer ?? this.quietHoursAppliesToPrayer,
        prayerOffsetMinutes: prayerOffsetMinutes ?? this.prayerOffsetMinutes,
        streakRiskTime: streakRiskTime ?? this.streakRiskTime,
        location: clearLocation ? null : (location ?? this.location),
        resolvedCountryCode: clearLocation
            ? null
            : (resolvedCountryCode ?? this.resolvedCountryCode),
        madhab: madhab ?? this.madhab,
      );

  Map<String, dynamic> toMap() => {
        'masterEnabled': masterEnabled,
        'habitRemindersEnabled': habitRemindersEnabled,
        'streakRiskEnabled': streakRiskEnabled,
        'celebrationsEnabled': celebrationsEnabled,
        'matrixNudgeEnabled': matrixNudgeEnabled,
        'bundleEnabled': bundleEnabled,
        'quietHoursEnabled': quietHoursEnabled,
        'quietHoursStart': _timeToMap(quietHoursStart),
        'quietHoursEnd': _timeToMap(quietHoursEnd),
        'quietHoursAppliesToPrayer': quietHoursAppliesToPrayer,
        'prayerOffsetMinutes': prayerOffsetMinutes,
        'streakRiskTime': _timeToMap(streakRiskTime),
        if (location != null) 'location': location!.toMap(),
        if (resolvedCountryCode != null)
          'resolvedCountryCode': resolvedCountryCode,
        'madhab': madhab.toJson(),
      };

  factory NotificationSettings.fromMap(Map<String, dynamic> map) {
    const defaults = NotificationSettings();
    return NotificationSettings(
      masterEnabled: map['masterEnabled'] as bool? ?? defaults.masterEnabled,
      habitRemindersEnabled: map['habitRemindersEnabled'] as bool? ??
          defaults.habitRemindersEnabled,
      streakRiskEnabled:
          map['streakRiskEnabled'] as bool? ?? defaults.streakRiskEnabled,
      celebrationsEnabled:
          map['celebrationsEnabled'] as bool? ?? defaults.celebrationsEnabled,
      matrixNudgeEnabled:
          map['matrixNudgeEnabled'] as bool? ?? defaults.matrixNudgeEnabled,
      bundleEnabled: map['bundleEnabled'] as bool? ?? defaults.bundleEnabled,
      quietHoursEnabled:
          map['quietHoursEnabled'] as bool? ?? defaults.quietHoursEnabled,
      quietHoursStart:
          _timeFromMap(map['quietHoursStart'], defaults.quietHoursStart),
      quietHoursEnd: _timeFromMap(map['quietHoursEnd'], defaults.quietHoursEnd),
      quietHoursAppliesToPrayer: map['quietHoursAppliesToPrayer'] as bool? ??
          defaults.quietHoursAppliesToPrayer,
      prayerOffsetMinutes: (map['prayerOffsetMinutes'] as num?)?.toInt() ??
          defaults.prayerOffsetMinutes,
      streakRiskTime: _timeFromMap(map['streakRiskTime'], defaults.streakRiskTime),
      location: NotificationLocation.fromMap(map['location']),
      resolvedCountryCode: map['resolvedCountryCode'] as String?,
      madhab: PrayerMadhab.fromJson(map['madhab'] as String?),
    );
  }
}
