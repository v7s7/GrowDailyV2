import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../features/settings/models/notification_settings.dart';
import 'prayer_times_service.dart';

/// One habit's reminder inputs, as read straight off its [HabitCue] by
/// main.dart — a *raw*, unresolved cue (at most one of [clockTime]/
/// [prayerKey] is set, never both) plus the dashboard context needed to
/// decide whether to fire at all. Turning this into an actual fire time —
/// including the prayer-time calculation itself — happens inside
/// [NotificationService.scheduleSmartReminders], alongside the settings
/// that affect it (location, calculation method, offset, quiet hours), so
/// main.dart's job stays "read the providers and hand over what they say"
/// rather than duplicating scheduling policy.
typedef HabitReminderInput = ({
  String id,
  String name,
  TimeOfDay? clockTime,
  String? prayerKey,
  int streak,
  bool isDoneToday,
  // Minutes to fire *before* the resolved clock/prayer moment — 0 fires
  // right at that moment (the original, still-default behavior). Ignored
  // when both clockTime and prayerKey are null, since there's no moment to
  // count back from.
  int reminderLeadMinutes,
});

typedef _ResolvedReminder = ({
  String id,
  String name,
  tz.TZDateTime fireTime,
  int streak,
});

/// One quit habit's evening check-in inputs, read off the providers by
/// main.dart the same way [HabitReminderInput] is. [isLimit] picks the
/// body wording (avoid-completely vs set-a-limit); [isResolvedToday] means
/// today's outcome is already known — affirmed on-track (completed) or
/// logged as a slip (red square) — so tonight's check-in for it should be
/// cancelled, not asked again.
typedef QuitCheckInInput = ({
  String id,
  String name,
  bool isLimit,
  bool isResolvedToday,
});

/// Real local-notification service backing daily/habit reminders,
/// prayer-linked reminders, streak-risk nudges, and in-the-moment
/// celebration pings (habit completed, level up, achievement unlocked).
/// Uses `flutter_local_notifications` — no remote push server is involved,
/// everything is scheduled/fired on-device, which is what keeps this
/// entirely free to run. Prayer-linked reminders resolve their fire time
/// through [PrayerTimesService], which reaches out to a live prayer-times
/// API for an exact result and falls back to an offline calculation when
/// there's no connection — see that class's doc comment.
///
/// ── Why "smart" scheduling means one-off, not recurring ─────────────
/// flutter_local_notifications can schedule a notification that recurs
/// forever at a fixed clock time (`matchDateTimeComponents:
/// DateTimeComponents.time`), which used to be how per-habit reminders
/// worked here — but a recurring schedule fires unconditionally, with no
/// way to skip just *today's* occurrence. That's a real problem for
/// "smart, not spammy": it means still nagging about a habit that's
/// already been marked done for the day. There's no backend here to push a
/// last-second cancel, so the only way to actually respect same-day
/// completion (or quiet hours, or a settings change) is to schedule only
/// the *next* single occurrence, then re-decide and reschedule every time
/// something relevant changes — a habit gets completed, the habit list
/// changes, settings change, or the app simply comes back to the
/// foreground (see main.dart's `_recomputeNotifications`, which is wired
/// to all of those). The trade-off: if the app genuinely never reopens for
/// more than a day, that one habit's reminders go quiet until it does —
/// judged an acceptable trade for a habit-tracking app (which assumes
/// fairly regular opens) against the alternative of reminding someone
/// about something they already finished.
///
/// One-time native setup still required after `flutter create .` generates
/// the ios/ and android/ folders on your Mac:
///   iOS    — none beyond what this service already requests at runtime.
///   Android — a small notification icon at
///             android/app/src/main/res/drawable/ic_notification.png
///             (falls back to @mipmap/ic_launcher if you skip this).
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();

  static const _dailyReminderId = 1001;
  static const _channelId = 'growdaily_general';
  static const _channelName = 'GrowDaily';
  static const _channelDesc = 'Habit reminders and progress celebrations';

  // ── Actionable notifications ─────────────────────────────────
  //
  // Both actions are registered with DarwinNotificationActionOption
  // .foreground / AndroidNotificationAction(showsUserInterface: true) on
  // purpose — that forces the tap through the normal, already-tested
  // main-isolate onDidReceiveNotificationResponse path (or a cold-launch
  // resolved via getNotificationAppLaunchDetails at startup), instead of
  // iOS/Android's separate background-isolate path. That background path
  // can act silently without opening the app, but it runs in a fresh
  // Flutter engine with none of the app's state, and replicating
  // completeHabit's XP/streak/gold logic there isn't something that can be
  // verified without a device to test on. This trades a brief app-open for
  // actions that are guaranteed to run through the real, working code.
  static const _habitCategoryId = 'habitReminderCategory';
  static const actionMarkDone = 'mark_done';
  static const actionSnooze = 'snooze_1h';

  // Quit-habit evening check-in — its own category because its two actions
  // mean something different from Mark Done/Snooze: "On Track" affirms the
  // day (same reward path as Mark Done), "Slipped" logs today as a
  // slip/over-limit day (red square, any same-day reward reversed) — see
  // main.dart's _handleNotificationAction. Same foreground-only routing
  // rationale as the habit category above.
  static const _quitCategoryId = 'quitCheckInCategory';
  static const actionStayedClean = 'quit_on_track';
  static const actionSlipped = 'quit_slipped';

  /// Body-tap payload for notifications whose natural landing place is the
  /// Today screen (daily reminder, streak-risk nudge) — deliberately a
  /// value that can never collide with a habit/task id, which are UUIDs or
  /// snake_case catalog ids, never colon-prefixed.
  static const openTodayPayload = 'open:today';

  bool _initialized = false;

  // A response that arrived before `onAction` was wired up — either a cold
  // app-launch resolved during init(), or (in principle) a very early tap
  // that raced main.dart's initState(). Flushed the moment onAction is set.
  NotificationResponse? _pendingResponse;
  void Function(String actionId, String? payload)? _onAction;

  /// Set once, from main.dart's app-level State, after the provider tree
  /// exists — so Mark Done/Snooze taps can call straight into the same
  /// completeHabit/snooze logic the UI itself uses. Assigning this replays
  /// any response that arrived first (e.g. the app was cold-launched by a
  /// notification action before this was set).
  set onAction(void Function(String actionId, String? payload)? callback) {
    _onAction = callback;
    final pending = _pendingResponse;
    if (callback != null && pending != null) {
      _pendingResponse = null;
      callback(pending.actionId ?? '', pending.payload);
    }
  }

  // Kept in sync by main.dart's reactive listener whenever
  // NotificationSettings changes (`masterEnabled && celebrationsEnabled`) —
  // NotificationService is a plain singleton with no ProviderRef of its
  // own, so it can't read Riverpod state itself; this mirrors how
  // [onAction] above is also assigned externally rather than looked up.
  bool _celebrationsEnabled = true;
  set celebrationsEnabled(bool value) => _celebrationsEnabled = value;

  void _dispatch(NotificationResponse response) {
    final callback = _onAction;
    if (callback == null) {
      _pendingResponse = response;
      return;
    }
    callback(response.actionId ?? '', response.payload);
  }

  Future<void> init() async {
    if (kIsWeb || _initialized) return;

    tz_data.initializeTimeZones();
    try {
      final currentTimeZone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(currentTimeZone));
    } catch (_) {
      // Fall back to UTC if the plugin can't resolve the device's IANA
      // timezone name; schedules still fire, just anchored to UTC until
      // that's resolved.
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    // Not const: DarwinNotificationAction.plain() below isn't a const
    // constructor (confirmed by `flutter analyze`, not assumed), so nothing
    // that contains it can be const either — built once at runtime instead
    // of compile time, which is functionally identical for a one-shot
    // init() call like this.
    final iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [
        DarwinNotificationCategory(
          _habitCategoryId,
          actions: [
            DarwinNotificationAction.plain(
              actionMarkDone,
              'Mark Done',
              options: {DarwinNotificationActionOption.foreground},
            ),
            DarwinNotificationAction.plain(
              actionSnooze,
              'Snooze 1h',
              options: {DarwinNotificationActionOption.foreground},
            ),
          ],
        ),
        // English-only labels, same as Mark Done/Snooze above — categories
        // register once at init, before the app's locale is knowable here.
        // Shared wording that works for both quit shapes: "On Track" covers
        // avoid-completely and set-a-limit alike, where "Stayed Clean"
        // would read oddly against a coffee limit.
        DarwinNotificationCategory(
          _quitCategoryId,
          actions: [
            DarwinNotificationAction.plain(
              actionStayedClean,
              'On Track',
              options: {DarwinNotificationActionOption.foreground},
            ),
            DarwinNotificationAction.plain(
              actionSlipped,
              'Slipped',
              options: {DarwinNotificationActionOption.foreground},
            ),
          ],
        ),
      ],
    );
    await _plugin.initialize(
      InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _dispatch,
    );

    // If a notification action cold-launched the app (it was fully
    // terminated when tapped), the tap never reaches
    // onDidReceiveNotificationResponse above — this recovers that case,
    // queuing it the same as any other response until onAction is wired up.
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final launchResponse = launchDetails?.notificationResponse;
    if (launchDetails?.didNotificationLaunchApp == true &&
        launchResponse != null) {
      _pendingResponse = launchResponse;
    }

    _initialized = true;
    debugPrint('[NotificationService] Ready');
  }

  /// Prompts the user for permission. Call this once, from a moment that
  /// makes sense in the flow (e.g. right after onboarding, or when the user
  /// first sets a reminder time) rather than at cold start.
  Future<bool> requestPermissions() async {
    if (kIsWeb) return false;
    final ios = await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    final android = await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    return (ios ?? true) && (android ?? true);
  }

  NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      );

  /// Same as [_details] but tagged with the habit-reminder category/actions
  /// so Mark Done + Snooze show up on the notification itself.
  NotificationDetails get _habitReminderDetails => const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          actions: [
            AndroidNotificationAction(actionMarkDone, 'Mark Done',
                showsUserInterface: true),
            AndroidNotificationAction(actionSnooze, 'Snooze 1h',
                showsUserInterface: true),
          ],
        ),
        iOS: DarwinNotificationDetails(categoryIdentifier: _habitCategoryId),
      );

  /// Same shape as [_habitReminderDetails], tagged with the quit check-in
  /// category instead so its On Track / Slipped actions show up — see
  /// [scheduleQuitCheckIns].
  NotificationDetails get _quitCheckInDetails => const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          actions: [
            AndroidNotificationAction(actionStayedClean, 'On Track',
                showsUserInterface: true),
            AndroidNotificationAction(actionSlipped, 'Slipped',
                showsUserInterface: true),
          ],
        ),
        iOS: DarwinNotificationDetails(categoryIdentifier: _quitCategoryId),
      );

  // ── Rotating copy ────────────────────────────────────────────
  //
  // Picked by a fixed day-based index rather than random — varies day to
  // day but won't visibly flicker between different lines if a reschedule
  // happens to fire more than once on the same day (habit list edited
  // twice, reminder time tweaked, etc). English/Arabic pools are kept the
  // same length so a given day picks the same *story* in either language.
  static const _dailyLines = [
    (
      'Time for your habits',
      "Don't break the streak — color today's square."
    ),
    (
      'Your habits are waiting',
      'A few minutes now, one more square colored today.'
    ),
    ('Keep the streak alive', "You've come this far — don't stop now."),
    ('Quick check-in', 'Which habit can you knock out right now?'),
    ('Still time today', 'Small steps count. Go color your grid.'),
  ];
  static const _dailyLinesAr = [
    ('حان وقت عاداتك', 'لا تكسر السلسلة — لوّن مربع اليوم.'),
    ('عاداتك تنتظرك', 'بضع دقائق الآن، ولوّنت مربعًا آخر اليوم.'),
    ('حافظ على السلسلة', 'وصلت إلى هنا — لا تتوقف الآن.'),
    ('تسجيل سريع', 'أي عادة يمكنك إنجازها الآن؟'),
    ('ما زال هناك وقت اليوم', 'خطوات صغيرة تُحتسب. اذهب ولوّن شبكتك.'),
  ];
  static const _habitLines = [
    "It's time — keep the streak going.",
    'A few minutes for this one today.',
    "Don't let today slip by.",
    'Ready when you are.',
  ];
  static const _habitLinesAr = [
    'حان الوقت — حافظ على استمرار السلسلة.',
    'بضع دقائق لهذه العادة اليوم.',
    'لا تدع اليوم يفوتك.',
    'جاهز عندما تكون مستعدًا.',
  ];

  int _dayIndex(int poolLength) {
    final day = DateTime.now();
    return (day.year * 400 + day.month * 31 + day.day) % poolLength;
  }

  /// Schedules (or reschedules) a repeating daily reminder at [hour]:[minute]
  /// local time. Safe to call every time the user changes the time — it
  /// replaces the previous schedule under the same notification id. This is
  /// the one deliberately-still-recurring schedule in this file (see the
  /// class doc comment) — it's not tied to any one habit's completion
  /// state, so there's nothing for it to over-fire about.
  Future<void> scheduleDailyReminder({
    int hour = 20,
    int minute = 0,
    bool isAr = false,
  }) async {
    if (kIsWeb) return;
    await init();
    final pool = isAr ? _dailyLinesAr : _dailyLines;
    final (title, body) = pool[_dayIndex(pool.length)];
    await _plugin.zonedSchedule(
      _dailyReminderId,
      title,
      body,
      _nextInstanceOf(hour, minute),
      _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      // Body-tap routing: land on Today, where the habits this reminder is
      // about actually live — see main.dart's _handleNotificationBodyTap.
      payload: openTodayPayload,
    );
    debugPrint(
        '[NotificationService] Daily reminder set — $hour:${minute.toString().padLeft(2, '0')}');
  }

  Future<void> cancelDailyReminder() async {
    if (kIsWeb) return;
    await _plugin.cancel(_dailyReminderId);
    debugPrint('[NotificationService] Daily reminder cancelled');
  }

  // Habit ids this instance currently owns a reminder (or a deliberate
  // no-reminder decision) for, so the next call can clean up exactly the
  // ones that no longer apply (habit deleted, cue changed to something
  // unresolvable) instead of leaving stale schedules behind. In-memory
  // only — re-derived fresh from the current habit list on every cold
  // start, since main.dart calls this with fireImmediately on the habit
  // list provider.
  final Set<String> _habitReminderHabitIds = {};

  int _habitReminderId(String habitId) =>
      5000 + habitId.hashCode.abs() % 1000;
  int _snoozeId(String habitId) => 6000 + habitId.hashCode.abs() % 1000;

  static const _bundleSlotBase = 7000;
  static const _maxBundleSlots = 6;
  static const _bundleWindow = Duration(minutes: 15);
  static const _streakRiskId = 8000;

  /// Schedules real, individually-cancellable reminders for habits with a
  /// resolvable cue — a fixed clock time, or a prayer cue once a location
  /// is saved in [settings] — replacing the previous
  /// `scheduleHabitReminders`. What "resolvable" excludes on purpose stays
  /// the same as before this rewrite: a routine-anchored preset that isn't
  /// one of the 5 prayers ('before sleep', 'morning', ...), freeform text,
  /// or no cue at all. Those still don't get a reminder — a wrong-time
  /// reminder is worse than none, and this app doesn't have real
  /// schedule/routine data for them yet.
  ///
  /// What's new here beyond prayer resolution:
  ///  - a habit already completed today is skipped entirely, not just
  ///    silently re-notified (see class doc comment on why that requires
  ///    one-off, not recurring, schedules);
  ///  - quiet hours suppress a reminder unless it's prayer-linked and
  ///    [NotificationSettings.quietHoursAppliesToPrayer] is off (the
  ///    default) — see that field's doc comment;
  ///  - 2+ habits landing within [_bundleWindow] of each other combine into
  ///    one notification instead of arriving back-to-back.
  ///
  /// Safe to call any time the habit list, dashboard completion state, or
  /// notification settings change — see main.dart's `_recomputeNotifications`.
  Future<void> scheduleSmartReminders(
    List<HabitReminderInput> habits,
    NotificationSettings settings, {
    required bool isAr,
  }) async {
    if (kIsWeb) return;
    await init();

    final nextHabitIds = habits.map((h) => h.id).toSet();

    if (!settings.masterEnabled || !settings.habitRemindersEnabled) {
      for (final id in _habitReminderHabitIds) {
        await _plugin.cancel(_habitReminderId(id));
        await _plugin.cancel(_snoozeId(id));
      }
      for (var i = 0; i < _maxBundleSlots; i++) {
        await _plugin.cancel(_bundleSlotBase + i);
      }
      _habitReminderHabitIds.clear();
      debugPrint('[NotificationService] Habit reminders off — cleared');
      return;
    }

    final resolved = <_ResolvedReminder>[];
    final now = tz.TZDateTime.now(tz.local);
    // Computed at most once each per call (not once per habit) — every
    // prayer-linked habit shares the same location/method/madhab, so
    // there's exactly one "today" and, only if needed, one "tomorrow" set
    // of prayer times for the whole batch.
    PrayerDayTimes? todayPrayers;
    PrayerDayTimes? tomorrowPrayers;

    for (final habit in habits) {
      if (habit.isDoneToday) {
        await _plugin.cancel(_habitReminderId(habit.id));
        continue;
      }

      tz.TZDateTime? fireTime;
      var isPrayerLinked = false;

      final lead = Duration(minutes: habit.reminderLeadMinutes);

      if (habit.clockTime != null) {
        fireTime = _nextInstanceOf(habit.clockTime!.hour, habit.clockTime!.minute)
            .subtract(lead);
        // A lead time can pull an already-imminent clock time into the
        // past (e.g. it's 8:58, the habit is set for 9:00, and the lead is
        // 15 min) — the wall-clock time repeats daily, so the fix is just
        // the same moment tomorrow, not a full recalculation.
        if (!fireTime.isAfter(now)) {
          fireTime = fireTime.add(const Duration(days: 1));
        }
      } else if (habit.prayerKey != null && settings.location != null) {
        isPrayerLinked = true;
        final loc = settings.location!;
        todayPrayers ??= await PrayerTimesService.calculate(
          latitude: loc.lat,
          longitude: loc.lng,
          date: now,
          madhab: settings.madhab,
          countryCode: settings.resolvedCountryCode,
        );
        // Named locals purely for readability (avoids repeating
        // `todayPrayers!.forKey` etc. below) — `??=` above already
        // promotes todayPrayers to non-null here, so no `!` is needed.
        final today = todayPrayers;
        // Written as an explicit null-check + reassignment rather than a
        // `?.add(...).subtract(...)` chain — Dart's "null-shorting" would
        // make that chain correct too (a `?.` shorts every plain `.` call
        // chained after it, not just the very next one), but that's a
        // sharp-edged-enough corner of the language to avoid leaning on
        // without a compiler on hand to double check it.
        var candidate = today.forKey(habit.prayerKey!);
        if (candidate != null) {
          candidate = candidate
              .add(Duration(minutes: settings.prayerOffsetMinutes))
              .subtract(lead);
        }
        if (candidate != null && !candidate.isAfter(now)) {
          tomorrowPrayers ??= await PrayerTimesService.calculate(
            latitude: loc.lat,
            longitude: loc.lng,
            date: now.add(const Duration(days: 1)),
            madhab: settings.madhab,
            countryCode: settings.resolvedCountryCode,
          );
          final tomorrow = tomorrowPrayers;
          candidate = tomorrow.forKey(habit.prayerKey!);
          if (candidate != null) {
            candidate = candidate
                .add(Duration(minutes: settings.prayerOffsetMinutes))
                .subtract(lead);
          }
        }
        fireTime = candidate;
      }

      if (fireTime == null) {
        await _plugin.cancel(_habitReminderId(habit.id));
        continue;
      }

      final exemptFromQuietHours =
          isPrayerLinked && !settings.quietHoursAppliesToPrayer;
      if (!exemptFromQuietHours &&
          settings.quietHoursEnabled &&
          isMinuteWithinQuietHours(
            fireTime.hour * 60 + fireTime.minute,
            settings.quietHoursStart,
            settings.quietHoursEnd,
          )) {
        await _plugin.cancel(_habitReminderId(habit.id));
        continue;
      }

      resolved.add((
        id: habit.id,
        name: habit.name,
        fireTime: fireTime,
        streak: habit.streak,
      ));
    }

    await _scheduleResolved(resolved, settings.bundleEnabled, isAr);

    for (final staleId in _habitReminderHabitIds.difference(nextHabitIds)) {
      await _plugin.cancel(_habitReminderId(staleId));
      await _plugin.cancel(_snoozeId(staleId));
    }
    _habitReminderHabitIds
      ..clear()
      ..addAll(nextHabitIds);
    debugPrint(
        '[NotificationService] ${resolved.length} habit reminder(s) resolved, '
        '${habits.length - resolved.length} skipped (done/unresolvable/quiet-hours)');
  }

  /// Groups [resolved] by fire time (within [_bundleWindow]) and schedules
  /// either one actionable per-habit notification (groups of 1, or any
  /// group at all when [bundleEnabled] is off) or one combined notification
  /// per group of 2+. Extracted from [scheduleSmartReminders] as its own
  /// step so the grouping logic itself — sort, walk, cut a new group past
  /// the window — reads as one clear pass instead of being interleaved with
  /// the resolution loop above it.
  Future<void> _scheduleResolved(
    List<_ResolvedReminder> resolved,
    bool bundleEnabled,
    bool isAr,
  ) async {
    final sorted = [...resolved]
      ..sort((a, b) => a.fireTime.compareTo(b.fireTime));
    final groups = <List<_ResolvedReminder>>[];
    for (final r in sorted) {
      final current = groups.isEmpty ? null : groups.last;
      if (bundleEnabled &&
          current != null &&
          r.fireTime.difference(current.first.fireTime) <= _bundleWindow) {
        current.add(r);
      } else {
        groups.add([r]);
      }
    }

    final usedBundleIds = <int>{};
    var slot = 0;
    for (final group in groups) {
      if (group.length == 1) {
        final r = group.first;
        await _plugin.zonedSchedule(
          _habitReminderId(r.id),
          r.name,
          r.streak > 0
              ? (isAr
                  ? 'لا تفقد سلسلتك المكوّنة من ${r.streak} يوم.'
                  : "Don't lose your ${r.streak}-day streak.")
              : (isAr
                  ? _habitLinesAr[_dayIndex(_habitLinesAr.length)]
                  : _habitLines[_dayIndex(_habitLines.length)]),
          r.fireTime,
          _habitReminderDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: r.id,
        );
        continue;
      }
      // 2+ habits due within the same short window: one combined ping
      // instead of several back-to-back. No Mark Done action here (there's
      // no single target habit for a tap to complete) — a plain tap just
      // opens the app, same as any notification with no registered action
      // id (see NotificationService._dispatch / main.dart's
      // _handleNotificationAction, which already no-ops safely on an empty
      // actionId).
      if (slot >= _maxBundleSlots) {
        // Extremely unlikely in practice — would need 7+ distinct bundles
        // in a single day. The remaining group(s) just don't get a
        // combined notification rather than risk an unbounded id range.
        for (final r in group) {
          await _plugin.cancel(_habitReminderId(r.id));
        }
        continue;
      }
      final bundleId = _bundleSlotBase + slot;
      usedBundleIds.add(bundleId);
      slot++;
      final names = group.map((e) => e.name).join(isAr ? '، ' : ', ');
      await _plugin.zonedSchedule(
        bundleId,
        isAr ? '${group.length} عادات جاهزة' : '${group.length} habits ready',
        names,
        group.first.fireTime,
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      for (final r in group) {
        await _plugin.cancel(_habitReminderId(r.id));
      }
    }
    // A bundle slot not used this round might still hold a stale
    // notification from a previous recompute (fewer bundles today than
    // last time) — clear anything unused so nothing orphaned lingers.
    for (var i = 0; i < _maxBundleSlots; i++) {
      final id = _bundleSlotBase + i;
      if (!usedBundleIds.contains(id)) await _plugin.cancel(id);
    }
  }

  /// The evening "you're about to lose your streak" nudge. Re-evaluated
  /// from scratch on every relevant state change instead of being a blind
  /// daily recurring notification — it only actually schedules anything
  /// when there's a real streak to protect *and* something is genuinely
  /// still unfinished today; finishing everything (or never having a
  /// streak yet) cancels it for the day rather than firing a hollow "check
  /// your progress" ping. [urgentMatrixCount] optionally adds a Matrix
  /// (Do First quadrant) pending-count line to the same notification —
  /// never a separate one, so enabling it can't add to how many
  /// notifications fire, only to what one of them says.
  Future<void> scheduleStreakRiskCheck({
    required NotificationSettings settings,
    required int streak,
    required int pendingHabitCount,
    required int urgentMatrixCount,
    required bool isAr,
  }) async {
    if (kIsWeb) return;
    await init();

    final shouldFire = settings.masterEnabled &&
        settings.streakRiskEnabled &&
        streak > 0 &&
        pendingHabitCount > 0;
    if (!shouldFire) {
      await _plugin.cancel(_streakRiskId);
      return;
    }

    final fireTime = _nextInstanceOf(
      settings.streakRiskTime.hour,
      settings.streakRiskTime.minute,
    );
    if (settings.quietHoursEnabled &&
        isMinuteWithinQuietHours(
          fireTime.hour * 60 + fireTime.minute,
          settings.quietHoursStart,
          settings.quietHoursEnd,
        )) {
      await _plugin.cancel(_streakRiskId);
      return;
    }

    final habitsPart = isAr
        ? (pendingHabitCount == 1
            ? 'عادة واحدة متبقية اليوم'
            : '$pendingHabitCount عادات متبقية اليوم')
        : (pendingHabitCount == 1
            ? '1 habit left today'
            : '$pendingHabitCount habits left today');
    final matrixPart = settings.matrixNudgeEnabled && urgentMatrixCount > 0
        ? (isAr
            ? ' · $urgentMatrixCount مهمة عاجلة بانتظارك'
            : ' · $urgentMatrixCount urgent task${urgentMatrixCount == 1 ? '' : 's'} waiting')
        : '';
    final body = isAr
        ? '$habitsPart — حافظ على سلسلة $streak يوم.$matrixPart'
        : '$habitsPart — keep your $streak-day streak alive.$matrixPart';

    await _plugin.zonedSchedule(
      _streakRiskId,
      isAr ? 'سلسلتك على المحك' : 'Your streak is on the line',
      body,
      fireTime,
      _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      // Body-tap routing: what's pending lives on Today — see main.dart's
      // _handleNotificationBodyTap.
      payload: openTodayPayload,
    );
  }

  // Quit check-ins get their own id range (and stale-tracking set, same
  // pattern as _habitReminderHabitIds) — a quit habit can hold BOTH a cue
  // reminder (_habitReminderId) and an evening check-in at once, so the two
  // must never share notification ids.
  static const _quitCheckInBase = 70000;
  final Set<String> _quitCheckInHabitIds = {};
  int _quitCheckInId(String habitId) =>
      _quitCheckInBase + habitId.hashCode.abs() % 1000;

  /// Schedules tonight's "how did today go?" check-in for each unresolved
  /// quit habit — the flip side of [scheduleSmartReminders]'s morning-of
  /// nudges. A quit habit's success is the *absence* of something, so
  /// instead of only nagging at a cue time, the day gets settled in the
  /// evening: On Track / Slipped action buttons resolve it straight from
  /// the lock screen (see main.dart's _handleNotificationAction).
  ///
  /// Title is always the general "Evening check-in" — never the habit's own
  /// name (that used to be the title, with the reflective "how did today
  /// go?" question as the body; a bare habit name sitting alone above a
  /// question about *the day* read like a mismatched, half-finished
  /// notification, especially with more than one quit habit stacking up
  /// several same-titled-differently notifications). The habit is still
  /// named — right inside the body now, so tapping still makes it obvious
  /// which one this is about, it just isn't doing double duty as the title.
  ///
  /// Fires at [NotificationSettings.streakRiskTime] — deliberately the
  /// same user-configurable "evening reflection" moment as
  /// [scheduleStreakRiskCheck] rather than a new setting of its own, so
  /// Settings keeps one evening time to reason about. Respects quiet hours
  /// and the master + habit-reminders toggles the same way habit reminders
  /// do. Re-evaluated by every _recomputeNotifications pass: a habit
  /// resolved during the day (affirmed or slipped) gets tonight's check-in
  /// cancelled rather than asked again.
  Future<void> scheduleQuitCheckIns(
    List<QuitCheckInInput> habits,
    NotificationSettings settings, {
    required bool isAr,
  }) async {
    if (kIsWeb) return;
    await init();

    final nextIds = habits.map((h) => h.id).toSet();

    Future<void> cancelAllTracked() async {
      for (final id in _quitCheckInHabitIds) {
        await _plugin.cancel(_quitCheckInId(id));
      }
      _quitCheckInHabitIds.clear();
    }

    if (!settings.masterEnabled || !settings.habitRemindersEnabled) {
      await cancelAllTracked();
      return;
    }

    final fireTime = _nextInstanceOf(
      settings.streakRiskTime.hour,
      settings.streakRiskTime.minute,
    );
    if (settings.quietHoursEnabled &&
        isMinuteWithinQuietHours(
          fireTime.hour * 60 + fireTime.minute,
          settings.quietHoursStart,
          settings.quietHoursEnd,
        )) {
      await cancelAllTracked();
      return;
    }

    for (final habit in habits) {
      if (habit.isResolvedToday) {
        await _plugin.cancel(_quitCheckInId(habit.id));
        continue;
      }
      await _plugin.zonedSchedule(
        _quitCheckInId(habit.id),
        isAr ? 'تسجيل المساء' : 'Evening check-in',
        // Arabic phrasing chosen by the user himself (Bahraini) — «جريب»
        // not «قريب», plain comma, no em-dash anywhere in user copy.
        habit.isLimit
            ? (isAr
                ? '${habit.name} · اليوم جريب يخلص، بقيت ضمن الحد؟'
                : "${habit.name} · Day's almost done. Still within your limit?")
            : (isAr
                ? '${habit.name} · اليوم جريب يخلص، شلون امورك؟'
                : "${habit.name} · Day's almost done. How's it going?"),
        fireTime,
        _quitCheckInDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: habit.id,
      );
    }

    // Same stale-schedule cleanup contract as scheduleSmartReminders: a
    // quit habit deleted (or switched back to a build goal) since the last
    // pass still has tonight's check-in sitting scheduled — cancel exactly
    // those, then adopt the new id set.
    for (final staleId in _quitCheckInHabitIds.difference(nextIds)) {
      await _plugin.cancel(_quitCheckInId(staleId));
    }
    _quitCheckInHabitIds
      ..clear()
      ..addAll(nextIds);
  }

  /// True when [minuteOfDay] (0–1439) falls inside the [start]–[end] quiet
  /// window, correctly handling a window that wraps past midnight (e.g.
  /// 22:00–07:00). A zero-width window (start == end) is treated as
  /// "never quiet" rather than "always quiet" — matches
  /// [NotificationSettings.quietHoursEnabled] being the actual on/off
  /// switch; a degenerate same-value range shouldn't silently blank out
  /// every reminder. Pure and side-effect-free on purpose — this is the
  /// one piece of the scheduling logic that's meaningfully unit-testable
  /// without a device (see test/notification_scheduling_test.dart).
  @visibleForTesting
  static bool isMinuteWithinQuietHours(
    int minuteOfDay,
    TimeOfDay start,
    TimeOfDay end,
  ) {
    final s = start.hour * 60 + start.minute;
    final e = end.hour * 60 + end.minute;
    if (s == e) return false;
    if (s < e) return minuteOfDay >= s && minuteOfDay < e;
    return minuteOfDay >= s || minuteOfDay < e;
  }

  /// Reschedules habit [habitId]'s reminder for an hour from now, as a
  /// one-off — uses a separate notification id from the regular per-habit
  /// reminder (see [_snoozeId]) so it doesn't clobber that schedule.
  Future<void> snoozeHabitReminder(
    String habitId,
    String habitName, {
    bool isAr = false,
  }) async {
    if (kIsWeb) return;
    await init();
    await _plugin.zonedSchedule(
      _snoozeId(habitId),
      habitName,
      isAr ? 'تأجيل — حان الوقت.' : "Snoozed — it's time.",
      tz.TZDateTime.now(tz.local).add(const Duration(hours: 1)),
      _habitReminderDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: habitId,
    );
    debugPrint('[NotificationService] Snoozed reminder for $habitId');
  }

  // 50,000 slots starting well past every other id range in this file
  // (highest fixed id used elsewhere is 9000) — Matrix tasks are plain
  // UUIDs, not small stable habit ids, and a user can accumulate far more
  // of them over time than habits, so this range is deliberately much
  // wider than _habitReminderId's 1000 slots. A hash collision between two
  // tasks' ids just means one's schedule silently overwrites the other's —
  // same accepted trade-off _habitReminderId already makes, just against a
  // much larger id space here.
  static const _taskReminderBase = 10000;
  static const _taskReminderRange = 50000;
  int _taskReminderId(String taskId) =>
      _taskReminderBase + taskId.hashCode.abs() % _taskReminderRange;

  /// Schedules a one-off local notification for a single Matrix task at an
  /// exact, user-picked moment — see MatrixTask.reminderAt's doc comment
  /// for why this takes a plain absolute [fireTime] rather than a
  /// recurring TimeOfDay/HabitCue-style cue: a task is a single thing to
  /// do, not a daily routine, so there's exactly one moment worth firing
  /// at, ever, and nothing here re-derives or repeats the way
  /// [scheduleSmartReminders] does.
  ///
  /// Deliberately does NOT check quiet hours the way habit/streak
  /// reminders do (see [scheduleSmartReminders]) — those are the app's own
  /// auto-generated nudges, but this fire time was explicitly hand-picked
  /// by the user for this exact task, down to the minute; silently moving
  /// or suppressing it would second-guess a decision they already made on
  /// purpose. Also doesn't request notification permission itself, unlike
  /// habit_plans.dart's ReminderTimeNotifier.set — that's the calling
  /// sheet's job (see AddTaskSheet._submit / TaskDetailSheet's reminder
  /// handler), since
  /// scheduling here has to succeed unconditionally for MatrixNotifier's
  /// fire-and-forget call style to stay consistent; if permission is
  /// actually denied, this silently schedules something the OS just won't
  /// display, exactly as flutter_local_notifications already behaves
  /// anywhere permission was never granted.
  ///
  /// Uses the plain notification styling ([_details], no actions) rather
  /// than [_habitReminderDetails] — there's no Mark Done/Snooze action that
  /// makes sense here (this isn't a habit), same reasoning as the bundled
  /// multi-habit notification in [_scheduleResolved].
  Future<void> scheduleTaskReminder({
    required String id,
    required String title,
    required DateTime fireTime,
    required bool isAr,
  }) async {
    if (kIsWeb) return;
    await init();
    await _plugin.zonedSchedule(
      _taskReminderId(id),
      title,
      isAr ? 'حان وقت هذه المهمة' : 'Time for this task',
      tz.TZDateTime.from(fireTime, tz.local),
      _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: id,
    );
  }

  /// Cancels [id]'s reminder, if one is scheduled — a no-op otherwise.
  /// Called from MatrixNotifier whenever a task's reminder is cleared or
  /// changed (the old schedule has to go before a new one can replace it),
  /// or the task itself is completed, deleted, or restored-without-a-
  /// still-future reminder — see MatrixNotifier._syncReminderSchedule for
  /// the exact rules.
  Future<void> cancelTaskReminder(String id) async {
    if (kIsWeb) return;
    await _plugin.cancel(_taskReminderId(id));
  }

  tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  Future<void> showHabitCompleted({
    required String habitName,
    required int xpEarned,
    required int goldEarned,
  }) async {
    if (kIsWeb || !_celebrationsEnabled) return;
    await init();
    await _plugin.show(
      2000 + habitName.hashCode.abs() % 1000,
      habitName,
      '+$xpEarned XP · +$goldEarned Gold',
      _details,
    );
  }

  Future<void> showLevelUp(int newLevel) async {
    if (kIsWeb || !_celebrationsEnabled) return;
    await init();
    await _plugin.show(
      3000,
      'Level up!',
      "You've reached level $newLevel.",
      _details,
    );
  }

  Future<void> showAchievementUnlocked(String achievementName) async {
    if (kIsWeb || !_celebrationsEnabled) return;
    await init();
    await _plugin.show(
      4000 + achievementName.hashCode.abs() % 1000,
      'Achievement unlocked',
      achievementName,
      _details,
    );
  }

  /// Fires immediately, bypassing [_celebrationsEnabled] on purpose — this
  /// is the Notification Settings screen's "Send a test notification"
  /// button, whose entire point is letting someone confirm permissions and
  /// appearance are working right now. Gating a diagnostic action behind
  /// the very settings it's meant to help verify would make it silently
  /// useless exactly when it's most likely to be tapped (right after
  /// turning categories off to investigate).
  Future<void> showTest({required bool isAr}) async {
    if (kIsWeb) return;
    await init();
    await _plugin.show(
      9000,
      isAr ? 'إشعار تجريبي' : 'Test notification',
      isAr
          ? 'هكذا تبدو إشعارات GrowDaily على جهازك.'
          : "This is what GrowDaily's notifications look like on your device.",
      _details,
    );
  }
}
