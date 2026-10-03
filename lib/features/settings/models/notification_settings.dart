import 'package:flutter/material.dart' show TimeOfDay;

import '../../../core/services/prayer_times_service.dart';

/// The five prayers an adhan alarm can be set for, in the day's order
/// ([NotificationSettings.prayerAlarms]). Sunrise is not one: no adhan is
/// called for it.
const List<String> kPrayerAlarmKeys = [
  'fajr',
  'dhuhr',
  'asr',
  'maghrib',
  'isha',
];

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

  /// Where this place came from, which decides whether the app may move it:
  ///  - true: the phone's own location. Kept current on its own, so a
  ///    person who travels gets the new city's prayers the next time the
  ///    app is opened (see autoLocatePrayerPlace).
  ///  - false: a city the person picked by hand. Never moved for them; a
  ///    tap on the location row is how they go back to automatic.
  ///  - null: saved before 2026-09-25, when nobody recorded which. Treated
  ///    as the phone's own when location access is granted, since granting
  ///    it was the only way a location got saved without a search.
  final bool? auto;

  /// A picked city's own time zone (IANA, e.g. "Europe/London"), from the
  /// city search. Null for the phone's own location, which is where the
  /// phone's clock already is, and for anything saved before 2026-10-01.
  /// Every prayer time stays on the phone's clock; this is only read to say
  /// so when the city's clock is a different one (PrayerTodayCard).
  final String? zone;

  const NotificationLocation({
    required this.lat,
    required this.lng,
    required this.label,
    this.auto,
    this.zone,
  });

  Map<String, dynamic> toMap() => {
        'lat': lat,
        'lng': lng,
        'label': label,
        if (auto != null) 'auto': auto,
        // Written even when null: the account copy is saved with a merge,
        // which leaves alone every key a write does not name, so a city's
        // zone would otherwise outlive it under the next place.
        'zone': zone,
      };

  static NotificationLocation? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final lat = (raw['lat'] as num?)?.toDouble();
    final lng = (raw['lng'] as num?)?.toDouble();
    final label = raw['label'] as String?;
    if (lat == null || lng == null || label == null || label.isEmpty) {
      return null;
    }
    final auto = raw['auto'];
    final zone = raw['zone'];
    return NotificationLocation(
      lat: lat,
      lng: lng,
      label: label,
      auto: auto is bool ? auto : null,
      zone: zone is String && zone.isNotEmpty ? zone : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotificationLocation &&
          lat == other.lat &&
          lng == other.lng &&
          label == other.label &&
          auto == other.auto &&
          zone == other.zone;

  @override
  int get hashCode => Object.hash(lat, lng, label, auto, zone);
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
  /// (habit reminders, the evening note, celebrations) stops,
  /// full stop. Everything below only matters when this is true.
  final bool masterEnabled;

  /// Per-habit reminders — the ones tied to a habit's own cue (prayer or
  /// clock time), with Mark Done/Snooze actions.
  final bool habitRemindersEnabled;

  /// Whether the ONE evening notification carries the streak ask — «سوي
  /// عادتين بس، وتصير ٨ أيام.» — see NotificationService
  /// .scheduleEveningNote. Only ever said when a streak is actually at risk
  /// (streak > 0 and enough build habits still unfinished today to close
  /// the gap), never as a blind daily ping.
  ///
  /// It was its own notification until 2026-09-16, on its own clock
  /// ([streakRiskTime]), and it counted the same board the daily reminder
  /// had counted half an hour earlier. Off now means the evening note falls
  /// through to the plain board line, not that the evening goes quiet. The
  /// note itself goes out only at a daily reminder time the person picked
  /// (2026-09-24), so without one this switch has nothing to add to.
  final bool streakRiskEnabled;

  /// Kept for stored-settings compatibility; no longer shown in Settings.
  /// The celebration pings it gated (habit completed, level up, achievement
  /// unlocked) were removed on 2026-09-08: each already has its in-app
  /// moment, and a system banner about your own tap was noise. The last
  /// ping left on it, a room's new shared habit shown locally when the Rooms
  /// screen noticed one, was removed on 2026-09-24: the server's
  /// notifyRoomHabitAdded push already says it, so members heard it twice.
  final bool celebrationsEnabled;

  /// Whether the evening note also mentions a pending count of DO-FIRST
  /// (urgent + important) Matrix tasks, when there are any. Adds a sentence
  /// to that one notification rather than a ping of its own — see
  /// NotificationService.scheduleEveningNote.
  final bool matrixNudgeEnabled;

  /// When two or more habit reminders land within the same few minutes,
  /// combine them into one notification ("3 habits ready: ...") instead of
  /// firing one each — see NotificationService's bundling pass.
  final bool bundleEnabled;

  /// The Saturday-morning note on the week that has just sealed, see
  /// NotificationService.scheduleWeeklyDigest. Off until the person turns it
  /// on: here in Settings, or with «إيه» under the week's recap card on
  /// Profile (Aziz, 2026-09-24, the evening note's rule: nothing is sent
  /// that the person did not choose).
  ///
  /// Its own key, 'weeklyNoteOn'. The switch it replaces, stored as
  /// 'weeklyDigestEnabled', was on for everyone from the start and written
  /// into every saved copy of these settings, so a stored true there says
  /// nothing about a choice and is not read. toMap still writes that key,
  /// from this value, for builds that only know the old one.
  final bool weeklyNoteOn;

  /// Server-sent push when a teammate in one of your rooms finishes their
  /// habit(s) for the day (see functions/index.js's notifyRoomFinish
  /// Callable function, invoked directly by RoomsController) — the one
  /// notification category this app sends from a server rather than
  /// scheduling locally, since it depends on someone else's action. Muting
  /// one specific room
  /// (RoomParticipant.notificationsMuted, via the room's app-bar bell) is
  /// the finer-grained control; this is the master switch for the whole
  /// category, same relationship [celebrationsEnabled] has to individual
  /// in-app celebration moments.
  final bool roomActivityEnabled;

  // roomNudgesEnabled, the opt-in playful «باقي أنت 👀» room push, was
  // removed on 2026-09-24 (Aziz): nobody had it on, and it was the one push
  // still wording the reader as the one behind. A stored value is ignored.

  /// Whether the person's own reminders go quiet between [quietHoursStart]
  /// and [quietHoursEnd]. Off until they turn it on (Aziz, 2026-09-28).
  ///
  /// It was on for everyone from the start, 22:00 to 07:00, and it silenced
  /// times people had picked themselves: a habit reminder at 23:00, and the
  /// evening note at «10:00 PM», one of the three ready times the daily
  /// reminder pop-up offers, which then never came at all. Every reminder
  /// the app sends now is at a time somebody chose, so a window nobody chose
  /// only ever took something away.
  ///
  /// Its own key, 'quietHoursOn'. The old key, 'quietHoursEnabled', was
  /// written true into every saved copy, so on its own it says nothing about
  /// a choice. A copy saved before this key existed reads as on only when
  /// the person had visibly changed quiet hours: a start or end other than
  /// 22:00 and 07:00, or [quietHoursAppliesToPrayer] turned on. See
  /// [quietHoursChosenBefore].
  ///
  /// Only the person's own reminders follow this switch. A room push or a
  /// message from the admin, someone else's timing, waits out the night
  /// whether it is on or not (functions/push_policy.js), so toMap keeps
  /// writing the old key as true for the server and for builds that only
  /// know that key.
  final bool quietHoursEnabled;
  final TimeOfDay quietHoursStart;
  final TimeOfDay quietHoursEnd;

  /// Quiet hours, once on, suppress the evening note, but a prayer-linked
  /// habit reminder is exempt unless
  /// this is explicitly turned on — because the entire point of "remind me
  /// after Fajr" is to be reminded near Fajr, which for most of the world
  /// falls well inside a typical nighttime quiet window. Flip this on only
  /// if quiet hours should override that too.
  final bool quietHoursAppliesToPrayer;

  // NOTE: the old global `prayerOffsetMinutes` ("minutes after the prayer"
  // applied to every prayer-linked habit at once) was removed. It was
  // *added* to a reminder's fire time while each habit's own value was
  // *subtracted* from it, so the two silently fought: "15 min before Fajr"
  // with the default +10 actually fired 5 minutes before, and Add Habit's
  // preview showed a time that never matched reality. Each habit's signed
  // IslamicHabitTemplate.reminderOffsetMinutes is now the single source of
  // truth. CustomHabitsNotifier._migrateLegacyPrayerOffset folds any saved
  // value into existing prayer habits once, so nobody's reminders moved.

  /// Kept for stored-settings compatibility; nothing reads it any more. It
  /// was the streak note's own clock, then the evening note's fallback when
  /// no daily reminder time was picked. Aziz, 2026-09-24: with no time
  /// picked nothing is sent, and the app asks instead, so the fallback and
  /// its Settings row are gone.
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

  /// The prayers whose adhan rings as an alarm, out of [kPrayerAlarmKeys]
  /// (Settings › موقع الصلاة, «منبّه الأذان»). Empty by default: nothing
  /// rings unless the person turned it on (Aziz, 2026-10-03). Its own
  /// choice, apart from the notification switches above: an alarm someone
  /// set is not a notification, the same way iOS keeps the two apart. It
  /// rings at the adhan of [location], so with no place saved it rings
  /// nothing.
  final Set<String> prayerAlarms;

  // There is no Asr madhab here any more: Asr is always the standard time
  // (see PrayerTimesService._asrMadhab). A 'madhab' key saved by an older
  // build is left in storage and simply not read.

  const NotificationSettings({
    this.masterEnabled = true,
    this.habitRemindersEnabled = true,
    this.streakRiskEnabled = true,
    this.celebrationsEnabled = true,
    this.matrixNudgeEnabled = true,
    this.bundleEnabled = true,
    this.weeklyNoteOn = false,
    this.roomActivityEnabled = true,
    this.quietHoursEnabled = false,
    this.quietHoursStart = const TimeOfDay(hour: 22, minute: 0),
    this.quietHoursEnd = const TimeOfDay(hour: 7, minute: 0),
    this.quietHoursAppliesToPrayer = false,
    this.streakRiskTime = const TimeOfDay(hour: 20, minute: 30),
    this.location,
    this.resolvedCountryCode,
    this.prayerAlarms = const {},
  });

  bool get hasLocation => location != null;

  NotificationSettings copyWith({
    bool? masterEnabled,
    bool? habitRemindersEnabled,
    bool? streakRiskEnabled,
    bool? celebrationsEnabled,
    bool? matrixNudgeEnabled,
    bool? bundleEnabled,
    bool? weeklyNoteOn,
    bool? roomActivityEnabled,
    bool? quietHoursEnabled,
    TimeOfDay? quietHoursStart,
    TimeOfDay? quietHoursEnd,
    bool? quietHoursAppliesToPrayer,
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
    Set<String>? prayerAlarms,
  }) =>
      NotificationSettings(
        masterEnabled: masterEnabled ?? this.masterEnabled,
        habitRemindersEnabled:
            habitRemindersEnabled ?? this.habitRemindersEnabled,
        streakRiskEnabled: streakRiskEnabled ?? this.streakRiskEnabled,
        celebrationsEnabled: celebrationsEnabled ?? this.celebrationsEnabled,
        matrixNudgeEnabled: matrixNudgeEnabled ?? this.matrixNudgeEnabled,
        bundleEnabled: bundleEnabled ?? this.bundleEnabled,
        weeklyNoteOn: weeklyNoteOn ?? this.weeklyNoteOn,
        roomActivityEnabled: roomActivityEnabled ?? this.roomActivityEnabled,
        quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
        quietHoursStart: quietHoursStart ?? this.quietHoursStart,
        quietHoursEnd: quietHoursEnd ?? this.quietHoursEnd,
        quietHoursAppliesToPrayer:
            quietHoursAppliesToPrayer ?? this.quietHoursAppliesToPrayer,
        streakRiskTime: streakRiskTime ?? this.streakRiskTime,
        location: clearLocation ? null : (location ?? this.location),
        resolvedCountryCode: clearLocation
            ? null
            : (resolvedCountryCode ?? this.resolvedCountryCode),
        prayerAlarms: prayerAlarms ?? this.prayerAlarms,
      );

  Map<String, dynamic> toMap() => {
        'masterEnabled': masterEnabled,
        'habitRemindersEnabled': habitRemindersEnabled,
        'streakRiskEnabled': streakRiskEnabled,
        'celebrationsEnabled': celebrationsEnabled,
        'matrixNudgeEnabled': matrixNudgeEnabled,
        'bundleEnabled': bundleEnabled,
        'weeklyNoteOn': weeklyNoteOn,
        // The old key, for builds that read only it: see [weeklyNoteOn].
        'weeklyDigestEnabled': weeklyNoteOn,
        'roomActivityEnabled': roomActivityEnabled,
        'quietHoursOn': quietHoursEnabled,
        // Always true: what the server reads, and what builds before
        // 'quietHoursOn' read as the switch. A push from someone else waits
        // out the night either way; see [quietHoursEnabled].
        'quietHoursEnabled': true,
        'quietHoursStart': _timeToMap(quietHoursStart),
        'quietHoursEnd': _timeToMap(quietHoursEnd),
        'quietHoursAppliesToPrayer': quietHoursAppliesToPrayer,
        'streakRiskTime': _timeToMap(streakRiskTime),
        if (location != null) 'location': location!.toMap(),
        if (resolvedCountryCode != null)
          'resolvedCountryCode': resolvedCountryCode,
        // Always written, empty too, in the day's order. The account copy is
        // saved with SetOptions(merge: true), and a list left out would keep
        // the last one on the server: the alarms switched off here would
        // come back on a new phone.
        'prayerAlarms': [
          for (final key in kPrayerAlarmKeys)
            if (prayerAlarms.contains(key)) key,
        ],
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
      // Never 'weeklyDigestEnabled': see [weeklyNoteOn].
      weeklyNoteOn: map['weeklyNoteOn'] as bool? ?? defaults.weeklyNoteOn,
      roomActivityEnabled:
          map['roomActivityEnabled'] as bool? ?? defaults.roomActivityEnabled,
      // Never 'quietHoursEnabled' on its own: see [quietHoursEnabled].
      quietHoursEnabled: switch (map['quietHoursOn']) {
        final bool on => on,
        _ => quietHoursChosenBefore(map),
      },
      quietHoursStart:
          _timeFromMap(map['quietHoursStart'], defaults.quietHoursStart),
      quietHoursEnd: _timeFromMap(map['quietHoursEnd'], defaults.quietHoursEnd),
      quietHoursAppliesToPrayer: map['quietHoursAppliesToPrayer'] as bool? ??
          defaults.quietHoursAppliesToPrayer,
      // `prayerOffsetMinutes` is deliberately not read here anymore — see
      // the note above the streakRiskTime field. Any saved value is left
      // sitting untouched in storage (this class neither reads nor writes
      // it) until CustomHabitsNotifier._migrateLegacyPrayerOffset folds it
      // into the habits themselves and drops the key.
      streakRiskTime: _timeFromMap(map['streakRiskTime'], defaults.streakRiskTime),
      location: NotificationLocation.fromMap(map['location']),
      resolvedCountryCode: map['resolvedCountryCode'] as String?,
      // Only the five prayers: anything else in a saved copy (a key from a
      // later build, a stray value) is not something this build can ring.
      prayerAlarms: switch (map['prayerAlarms']) {
        final List<dynamic> keys => {
            for (final key in keys)
              if (kPrayerAlarmKeys.contains(key)) key as String,
          },
        _ => const {},
      },
    );
  }

  /// Whether a copy saved before 'quietHoursOn' existed shows the person
  /// choosing quiet hours, in which case they stay on.
  ///
  /// Quiet hours were on by default and 'quietHoursEnabled' went into every
  /// saved copy, so that key cannot tell a choice from the default. What
  /// only a person could have done is move the start or the end away from
  /// 22:00 and 07:00, or turn on «تطبيقها على تذكيرات الصلاة أيضًا». Either
  /// one, with the switch still on, keeps it on. Everything else, the
  /// untouched default included, reads as off (Aziz, 2026-09-28: off unless
  /// they changed it), and a switch somebody had turned off stays off.
  static bool quietHoursChosenBefore(Map<String, dynamic> map) {
    // Read the way the old fromMap read it: a missing key was the old
    // default, on.
    final wasOn = switch (map['quietHoursEnabled']) {
      final bool on => on,
      _ => true,
    };
    if (!wasOn) return false;
    const defaults = NotificationSettings();
    final start =
        _timeFromMap(map['quietHoursStart'], defaults.quietHoursStart);
    final end = _timeFromMap(map['quietHoursEnd'], defaults.quietHoursEnd);
    return start != defaults.quietHoursStart ||
        end != defaults.quietHoursEnd ||
        map['quietHoursAppliesToPrayer'] == true;
  }
}
