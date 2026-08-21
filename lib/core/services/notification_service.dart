import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../features/settings/models/notification_settings.dart';
import 'local_store_service.dart';
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
  // Signed minutes from the resolved clock/prayer moment to the fire time:
  // negative = before, 0 = exactly on time, positive = after. Ignored when
  // both clockTime and prayerKey are null, since there's no moment to
  // offset from. Mirrors IslamicHabitTemplate.reminderOffsetMinutes — see
  // that field's doc comment for the migration off the old always-before
  // `reminderLeadMinutes`.
  int reminderOffsetMinutes,
  // Lets this habit's reminder through quiet hours (the per-habit "Allow
  // anyway" escape hatch). Mirrors IslamicHabitTemplate.ignoreQuietHours.
  bool ignoreQuietHours,
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
  static const _channelName = 'Grow Daily';
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

  /// Whether the app is currently running in Arabic — kept in sync by the
  /// same main.dart listener that maintains [celebrationsEnabled] above,
  /// and for the same reason (this is a plain singleton with no
  /// ProviderRef and no BuildContext, so it can't read the locale itself).
  ///
  /// The celebration notifications below used to be hardcoded English —
  /// "Level up!", "Achievement unlocked", "+120 XP · +30 Gold" — which
  /// meant an Arabic user earned "شهر من الإتقان" in the app and then got
  /// a push notification about "Month of Mastery". Every *scheduled*
  /// notification in this file was already localized (they take an `isAr`
  /// argument from a widget that has a BuildContext); these three fire
  /// from DashboardNotifier, which has neither, hence the flag.
  ///
  /// Callers that need to localize their *own* argument — picking
  /// `AchievementModel.localName` for [showAchievementUnlocked], say —
  /// read this too, rather than each carrying a separate copy of the
  /// locale down to the call site.
  bool isArabic = false;

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

  /// Hive key for "has this device already told us the OS-level
  /// notification permission is granted" - see [requestPermissions]'s doc
  /// comment for why this exists.
  static const _kPermissionGrantedKey = 'notification_permission_granted_v1';

  /// Prompts the user for permission. Call this once, from a moment that
  /// makes sense in the flow (e.g. right after onboarding, or when the user
  /// first sets a reminder time) rather than at cold start.
  ///
  /// In practice this is called from four different places (AddHabitSheet,
  /// AddTaskSheet, TaskDetailSheet, habit_plans.dart's daily-reminder setup)
  /// - every one of them a genuinely reasonable moment to ask, and every one
  /// of them independent of the others, so nothing before this fix stopped
  /// the *second* one of these that ran from re-invoking the native
  /// permission call all over again. iOS/Android themselves never show a
  /// second system dialog once someone's actually answered the first one -
  /// a repeat request when the OS already has a real answer just returns
  /// that answer straight back with no UI - so this was never a case of
  /// anyone actually being asked to decide twice. It was still a real,
  /// pointless platform-channel round trip on every single save though, and
  /// worth actually shortcutting rather than leaving as "harmless but
  /// wasteful". Once a call here has genuinely confirmed "granted", every
  /// later call - this session or a future one - skips the native call
  /// entirely and returns true immediately.
  ///
  /// Deliberately NOT cached on a denial: unlike a granted answer (which
  /// essentially never reverts on its own), someone can always flip
  /// notifications back on for this app from their device Settings after
  /// having said no here - caching "denied" forever would keep silently
  /// re-declining on their behalf even after they've since turned it on
  /// themselves. Re-asking after a denial is exactly as safe as before this
  /// change (still just an instant no-UI echo of their last real answer,
  /// unless Settings changed it), so there's nothing to lose by leaving
  /// that path exactly as it was.
  Future<bool> requestPermissions() async {
    if (kIsWeb) return false;
    // The cached 'granted' flag is a fast path, NOT the truth.
    //
    // It used to short-circuit and return true forever, so a permission the
    // person revoked in iOS Settings stayed masked: every later call claimed
    // success, nothing was ever actually scheduled, and the "notifications
    // are off" warning this method exists to trigger never appeared. Asking
    // the OS is cheap and, once answered, never re-prompts — so the cache
    // buys nothing worth a permanently wrong answer. Kept only as the
    // fallback for platforms that return null below.
    final cached =
        await LocalStoreService.getSettingsMap(_kPermissionGrantedKey);
    final ios = await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    final android = await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    // Null means "this platform doesn't answer" (e.g. Android below 13),
    // not "denied" — so a null side is simply not evidence either way and
    // the other platform's answer decides. If neither answers, fall back to
    // the last real answer we recorded rather than assuming success.
    final answered = ios ?? android;
    final granted = answered ?? (cached['granted'] == true);
    // Written on every call, not only on success — that one-sided write is
    // what let a revoked permission stay cached as granted forever.
    await LocalStoreService.putSettingsMap(
        _kPermissionGrantedKey, {'granted': granted});
    return granted;
  }

  /// Whether the OS will actually DISPLAY this app's notifications right
  /// now — the system-Settings-level answer, not the app's own toggles.
  ///
  /// This is the question the app could not answer during a real incident:
  /// with iOS notifications switched off in system Settings, every toggle in
  /// Notification Settings read "on", every schedule call "succeeded", the
  /// test button "sent" — and iOS silently dropped all of it. Nothing
  /// anywhere told the person their reminders were going nowhere.
  /// NotificationSettingsScreen's permission banner renders off this.
  ///
  /// Returns null when the platform can't say (web, or an OS without the
  /// query) — callers should treat null as "assume fine, say nothing".
  Future<bool?> checkSystemPermission() async {
    if (kIsWeb) return null;
    await init();
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final options = await ios.checkPermissions();
      return options?.isEnabled;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) return android.areNotificationsEnabled();
    return null;
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
    ('Time for your habits', "Don't break the streak. Color today's square."),
    (
      'Your habits are waiting',
      'A few minutes now, one more square colored today.'
    ),
    ('Keep the streak alive', "You've come this far. Don't stop now."),
    ('Quick check-in', 'Which habit can you knock out right now?'),
    ('Still time today', 'Small steps count. Go color your grid.'),
  ];
  static const _dailyLinesAr = [
    ('حان وقت عاداتك', 'لا تكسر السلسلة. لوّن مربع اليوم.'),
    ('عاداتك تنتظرك', 'بضع دقائق الآن، ولوّنت مربعًا آخر اليوم.'),
    ('حافظ على السلسلة', 'وصلت إلى هنا. لا تتوقف الآن.'),
    ('تسجيل سريع', 'أي عادة يمكنك إنجازها الآن؟'),
    ('ما زال هناك وقت اليوم', 'خطوات صغيرة تُحتسب. اذهب ولوّن شبكتك.'),
  ];
  static const _habitLines = [
    "It's time. Keep the streak going.",
    'A few minutes for this one today.',
    "Don't let today slip by.",
    'Ready when you are.',
  ];
  static const _habitLinesAr = [
    'حان الوقت. حافظ على استمرار السلسلة.',
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

  int _habitReminderId(String habitId) => 5000 + habitId.hashCode.abs() % 1000;
  int _snoozeId(String habitId) => 6000 + habitId.hashCode.abs() % 1000;

  static const _bundleSlotBase = 7000;
  static const _maxBundleSlots = 6;
  static const _bundleWindow = Duration(minutes: 15);
  static const _streakRiskId = 8000;
  static const _weeklyDigestId = 9000;

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

      // Signed: added, never subtracted. A negative value (the "before"
      // case) shifts backwards on its own — no separate branch needed, and
      // no second global offset stacked on top of it anymore.
      final offset = Duration(minutes: habit.reminderOffsetMinutes);

      if (habit.clockTime != null) {
        fireTime =
            _nextInstanceOf(habit.clockTime!.hour, habit.clockTime!.minute)
                .add(offset);
        // An offset can pull an already-imminent clock time into the past
        // (e.g. it's 8:58, the habit is set for 9:00, and the offset is
        // -15 min) — the wall-clock time repeats daily, so the fix is just
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
          candidate = candidate.add(offset);
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
            candidate = candidate.add(offset);
          }
        }
        fireTime = candidate;
      }

      if (fireTime == null) {
        await _plugin.cancel(_habitReminderId(habit.id));
        continue;
      }

      // Two ways to be exempt: a prayer-linked reminder (whose whole point
      // is landing near a prayer that's often inside a normal night-time
      // quiet window — see quietHoursAppliesToPrayer), or this specific
      // habit having been explicitly opted out via Add Habit's "Allow
      // anyway" after being warned about the conflict.
      final exemptFromQuietHours = habit.ignoreQuietHours ||
          (isPrayerLinked && !settings.quietHoursAppliesToPrayer);
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
    final groups = groupByFireTimeWindow<_ResolvedReminder>(
      resolved,
      enabled: bundleEnabled,
      window: _bundleWindow,
      fireTimeOf: (r) => r.fireTime,
    );

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
        ? '$habitsPart. حافظ على سلسلة $streak يوم.$matrixPart'
        : '$habitsPart. Keep your $streak-day streak alive.$matrixPart';

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

  /// Friday-evening "how was your week" push — a proactive companion to
  /// Insights/Monthly Heatmap, which are both pull-only (someone has to go
  /// open them). Content is computed fresh every time this is called (from
  /// main.dart's _recomputeNotifications, alongside every other smart
  /// reminder) and baked into the text at schedule time — same constraint
  /// as every other schedule* method here, local notifications can't
  /// compute anything at fire time. The Friday timing (not Sunday) matches
  /// the app's own Sat→Fri grid week — see weekly_grid_notifier.dart's
  /// startOfGridWeek().
  Future<void> scheduleWeeklyDigest({
    required NotificationSettings settings,
    required int greenDays,
    required int streak,
    required bool isAr,
  }) async {
    if (kIsWeb) return;
    await init();

    final shouldFire = settings.masterEnabled && settings.weeklyDigestEnabled;
    if (!shouldFire) {
      await _plugin.cancel(_weeklyDigestId);
      return;
    }

    final title = isAr ? 'أسبوعك' : 'Your week';
    final body = isAr
        ? (greenDays == 0
            ? 'لم يُلوَّن أي يوم بعد هذا الأسبوع. لا يزال الوقت متاحًا.'
            : streak > 0
                ? 'لوّنت $greenDays من 7 أيام هذا الأسبوع، وسلسلة $streak يوم مستمرة.'
                : 'لوّنت $greenDays من 7 أيام هذا الأسبوع.')
        : (greenDays == 0
            ? "No days colored yet this week. There's still time."
            : streak > 0
                ? 'You colored $greenDays of 7 days this week, a $streak-day streak going.'
                : 'You colored $greenDays of 7 days this week.');

    await _plugin.zonedSchedule(
      _weeklyDigestId,
      title,
      body,
      _nextInstanceOfWeekday(DateTime.friday, 19, 0),
      _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      // Body-tap routing: the week's story lives on the Grid, on Today —
      // see main.dart's _handleNotificationBodyTap. No dedicated Insights
      // deep link exists yet; Insights is one tap from Today.
      payload: openTodayPayload,
    );
  }

  Future<void> cancelWeeklyDigest() async {
    if (kIsWeb) return;
    await _plugin.cancel(_weeklyDigestId);
  }

  // Quit check-ins get their own id range (and stale-tracking set, same
  // pattern as _habitReminderHabitIds) — a quit habit can hold BOTH a cue
  // reminder (_habitReminderId) and an evening check-in at once, so the two
  // must never share notification ids.
  static const _quitCheckInBase = 70000;

  /// Kept clear of [_quitCheckInBase]'s 70000–70999 window. Both use a
  /// `base + hash % 1000` id, so overlapping bases means one feature can
  /// cancel the other's notification by coincidence.
  static const _foregroundRoomPushBase = 72000;
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
  /// every reminder. Pure and side-effect-free on purpose — one of two
  /// pieces of the scheduling logic (see [groupByFireTimeWindow] for the
  /// other) that are meaningfully unit-testable without a device, since
  /// neither touches the plugin or the network (see
  /// test/notification_scheduling_test.dart).
  ///
  /// No longer `@visibleForTesting`: AddHabitSheet's `_quietHoursWarning`
  /// now calls this for real, to tell someone *while they're picking a
  /// time* that it lands in their quiet window — the alternative was
  /// duplicating this wrap-past-midnight logic in the UI, where it could
  /// drift out of sync with the scheduler that actually enforces it. This
  /// stays the single definition of "is this minute quiet".
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

  /// Groups [items] into clusters no wider than [window] apart, in
  /// fire-time order — [_scheduleResolved]'s "2+ habits due within the
  /// same short window combine into one notification" rule. Extracted out
  /// of that method (verbatim logic, just generic over [T] and taking a
  /// [fireTimeOf] extractor instead of reaching into `_ResolvedReminder`
  /// directly) so the windowing decision itself — which is the one part
  /// of that method with no plugin call in it — is unit-testable without
  /// scheduling a single real notification. When [enabled] is false, every
  /// item gets its own group regardless of how close together they are —
  /// mirrors the original inline `bundleEnabled &&` gate exactly, rather
  /// than e.g. passing `Duration.zero` as [window], which would still
  /// merge two items landing at the exact same instant.
  @visibleForTesting
  static List<List<T>> groupByFireTimeWindow<T>(
    List<T> items, {
    required bool enabled,
    required Duration window,
    required tz.TZDateTime Function(T) fireTimeOf,
  }) {
    final sorted = [...items]
      ..sort((a, b) => fireTimeOf(a).compareTo(fireTimeOf(b)));
    final groups = <List<T>>[];
    for (final item in sorted) {
      final current = groups.isEmpty ? null : groups.last;
      if (enabled &&
          current != null &&
          fireTimeOf(item).difference(fireTimeOf(current.first)) <= window) {
        current.add(item);
      } else {
        groups.add([item]);
      }
    }
    return groups;
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
      isAr ? 'تأجيل: حان الوقت.' : "Snoozed: it's time.",
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

  /// How many reminder slots a single task can occupy. iOS caps an app at
  /// 64 *pending* local notifications in total, app-wide — and this app is
  /// already spending that budget on habit reminders, streak nudges and
  /// quit check-ins. Without a per-task ceiling, one task with a long
  /// alarm stack would silently evict other reminders the user cares about
  /// more, with no error anywhere: the OS just stops delivering. Eight
  /// escalating nudges for one task is already well past what anyone
  /// realistically sets, so this bounds the damage while staying invisible
  /// in practice.
  ///
  /// Doubles as the cancel bound: [cancelTaskReminder] sweeps exactly this
  /// many slots, so a task can never leave an orphaned schedule behind for
  /// an index that's no longer in its list. Raising this later is safe;
  /// *lowering* it would strand already-scheduled slots above the new
  /// value, so don't, without a one-off sweep at the old bound first.
  static const kMaxTaskReminderSlots = 8;

  /// Notification id for a task's [index]-th reminder.
  ///
  /// Index 0 deliberately hashes the bare [taskId], producing the exact
  /// same id this method returned when a task could only have one
  /// reminder. That's what lets an install upgrade cleanly: reminders
  /// already sitting in the OS queue from a previous build stay
  /// addressable, so the first resync after the update replaces them in
  /// place instead of leaving a ghost that fires alongside its own
  /// replacement. Later indices hash a composite key so each gets its own
  /// slot.
  ///
  /// A hash collision between two tasks' ids (or between two slots) just
  /// means one schedule silently overwrites the other — the same accepted
  /// trade-off [_habitReminderId] already makes, against a 50,000-slot
  /// space here.
  int _taskReminderId(String taskId, [int index = 0]) =>
      _taskReminderBase +
      (index == 0 ? taskId.hashCode : '$taskId#$index'.hashCode).abs() %
          _taskReminderRange;

  /// Schedules a one-off local notification for a single Matrix task at an
  /// exact, user-picked moment — see MatrixTask.reminderAt's doc comment
  /// for why this takes a plain absolute [fireTime] rather than a
  /// recurring TimeOfDay/HabitCue-style cue: a task is a single thing to
  /// do, not a daily routine, so there's exactly one moment worth firing
  /// at, ever, and nothing here re-derives or repeats the way
  /// [scheduleSmartReminders] does.
  ///
  /// Title is a fixed, generic nudge ("It's time") rather than the task's
  /// own name — [taskTitle] carries the specifics in the body instead, the
  /// same title/body split every notification-list screenshot of this kind
  /// of app uses ("It's time" / "Buy groceries"), so what's glanceable from
  /// a lock screen is "something needs you" first, "here's what" second.
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
  /// [fireTimes] is the task's full set of still-future reminder moments,
  /// already sorted (see MatrixTask.normalizeReminders) — not a delta.
  /// Anything beyond [kMaxTaskReminderSlots] is dropped, and every slot
  /// this task isn't using anymore is cancelled in the same pass, so the
  /// OS queue always ends up matching the task's list exactly rather than
  /// accumulating stale schedules from whatever it used to hold. That
  /// makes this safe to call on every resync, which is how MatrixNotifier
  /// uses it.
  Future<void> scheduleTaskReminders({
    required String id,
    required String taskTitle,
    required List<DateTime> fireTimes,
    required bool isAr,
  }) async {
    if (kIsWeb) return;
    await init();
    final wanted = fireTimes.take(kMaxTaskReminderSlots).toList();
    for (var i = 0; i < wanted.length; i++) {
      await _plugin.zonedSchedule(
        _taskReminderId(id, i),
        isAr ? 'حان الوقت' : "It's time",
        taskTitle,
        tz.TZDateTime.from(wanted[i], tz.local),
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: id,
      );
    }
    for (var i = wanted.length; i < kMaxTaskReminderSlots; i++) {
      await _plugin.cancel(_taskReminderId(id, i));
    }
  }

  /// Catches up a task reminder whose picked moment already passed without
  /// ever reaching the user — the app was closed straight through
  /// [fireTime], the device was off, or the OS just didn't deliver it.
  /// Rather than the task's reminder silently vanishing (which is what
  /// unconditionally cancelling a past-due schedule would mean from the
  /// user's side — a reminder they set that never once fired), this fires
  /// right away instead, the moment MatrixNotifier next resyncs this task
  /// (on load, or the next time it's touched) and finds it still open with
  /// notifications still enabled — see MatrixNotifier._syncReminderSchedule.
  /// Uses [_plugin.show] (immediate) rather than [_plugin.zonedSchedule]
  /// (future-dated) since there's no future moment left to aim at — "now"
  /// already *is* the catch-up moment. Same title/body convention as
  /// [scheduleTaskReminders], and deliberately reuses slot 0's id, so a
  /// catch-up simply replaces whatever (if anything) was still pending for
  /// this task. One notification regardless of how many of the task's
  /// reminders were missed — see MatrixNotifier's overdue handling for why
  /// firing one per missed moment would be the wrong behaviour.
  Future<void> fireOverdueTaskReminder({
    required String id,
    required String taskTitle,
    required bool isAr,
  }) async {
    if (kIsWeb) return;
    await init();
    await _plugin.show(
      _taskReminderId(id),
      isAr ? 'حان الوقت' : "It's time",
      taskTitle,
      _details,
    );
  }

  /// Cancels [id]'s reminder, if one is scheduled — a no-op otherwise.
  /// Called from MatrixNotifier whenever a task's reminder is cleared,
  /// the task itself is completed or deleted, or notifications are off
  /// entirely — see MatrixNotifier._syncReminderSchedule for the exact
  /// rules. A reminder whose moment has simply passed while the task is
  /// still open does NOT go through here — see [fireOverdueTaskReminder]
  /// for that case instead.
  /// Sweeps every slot rather than just index 0 — a task whose reminders
  /// were cleared (or which was completed or deleted) must not leave a
  /// later slot still armed, and by the time this is called the task's own
  /// list is usually already empty, so there's nothing left to tell us how
  /// many it used to have. Cancelling an id that was never scheduled is a
  /// no-op, so the fixed sweep costs nothing but guarantees no stragglers.
  Future<void> cancelTaskReminder(String id) async {
    if (kIsWeb) return;
    for (var i = 0; i < kMaxTaskReminderSlots; i++) {
      await _plugin.cancel(_taskReminderId(id, i));
    }
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

  /// Same idea as [_nextInstanceOf], but rolls forward to the next
  /// occurrence of [weekday] (1=Monday..7=Sunday, per [DateTime]'s own
  /// weekday constants) instead of stopping at the next occurrence of the
  /// clock time alone — used by [scheduleWeeklyDigest] to land on Friday
  /// evening specifically.
  tz.TZDateTime _nextInstanceOfWeekday(int weekday, int hour, int minute) {
    var scheduled = _nextInstanceOf(hour, minute);
    while (scheduled.weekday != weekday) {
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
      isArabic
          ? '+$xpEarned XP · +$goldEarned ذهب'
          : '+$xpEarned XP · +$goldEarned Gold',
      _details,
    );
  }

  Future<void> showLevelUp(int newLevel) async {
    if (kIsWeb || !_celebrationsEnabled) return;
    await init();
    await _plugin.show(
      3000,
      isArabic ? 'ارتقاء مستوى!' : 'Level up!',
      isArabic
          ? 'وصلت للمستوى $newLevel.'
          : "You've reached level $newLevel.",
      _details,
    );
  }

  /// [achievementName] must already be in the right language — callers pass
  /// `AchievementModel.localName(NotificationService.instance.isArabic)`.
  /// This used to receive `a.name`, the English field, unconditionally.
  Future<void> showAchievementUnlocked(String achievementName) async {
    if (kIsWeb || !_celebrationsEnabled) return;
    await init();
    await _plugin.show(
      4000 + achievementName.hashCode.abs() % 1000,
      // Matches the in-app unlock sheet's own headline (S.achievementUnlocked)
      // so the push and the celebration read as the same event.
      isArabic ? 'إنجاز مفتوح!' : 'Achievement unlocked',
      achievementName,
      _details,
    );
  }

  /// One notification for a batch of medals earned in the same instant,
  /// instead of one per medal.
  ///
  /// A single habit completion can genuinely cross several thresholds at
  /// once — the tap that hits a streak milestone can also be the 50th
  /// lifetime completion and the 100th colored square. The callers used to
  /// loop and call [showAchievementUnlocked] per medal, so that one tap
  /// dealt three or four separate pushes on top of the habit-completed and
  /// level-up ones already firing. [names] must already be localized.
  Future<void> showAchievementsUnlocked(List<String> names) async {
    if (kIsWeb || !_celebrationsEnabled || names.isEmpty) return;
    if (names.length == 1) return showAchievementUnlocked(names.first);
    await init();
    await _plugin.show(
      4999,
      isArabic
          ? '${names.length} إنجازات مفتوحة!'
          : '${names.length} achievements unlocked',
      // Listing the names beats a bare count — "3 achievements unlocked"
      // tells you nothing about which.
      names.join(isArabic ? ' · ' : ' · '),
      _details,
    );
  }

  /// Local notification for this device noticing a room it's in has a new
  /// shared-plan habit to link (see RoomsHubScreen's own per-room check,
  /// and RoomsController.addSharedHabit's doc comment for how it got
  /// there). NOT true push - this app has no server-side component to fire
  /// one the instant a leader adds it, so this only actually fires the
  /// next time this device is open and this account's rooms sync, same
  /// honest limit as every other notification in this file. [isAr] is
  /// passed in rather than read from S.of(context) - there's no
  /// BuildContext available at the point this fires, same reasoning as
  /// [showTest].
  Future<void> showRoomHabitAdded({
    required String roomName,
    required String habitName,
    required bool isAr,
  }) async {
    if (kIsWeb || !_celebrationsEnabled) return;
    await init();
    await _plugin.show(
      60000 + roomName.hashCode.abs() % 1000,
      isAr ? 'عادة جديدة في "$roomName"' : 'New habit in "$roomName"',
      isAr
          ? 'أضاف القائد "$habitName". اربط إحدى عاداتك لمواصلة تقدمك.'
          : 'Your leader added "$habitName" - link one of your own habits to keep your progress going.',
      _details,
    );
  }

  /// Manually shows the room-finish push's title/body while this device is
  /// in the foreground - see PushNotificationService's own doc comment for
  /// why: iOS's foreground-presentation option is deliberately left off
  /// for that one push category (unlike every local notification in this
  /// file, which doesn't need the choice - there's nothing else on screen
  /// for a scheduled reminder to duplicate), so a push about a room this
  /// device is already looking at can be skipped entirely instead of
  /// showing right on top of room_reactions.dart's own in-app reaction for
  /// the exact same moment. Bypasses [_celebrationsEnabled]/master-switch
  /// gating on purpose - functions/index.js already checked
  /// NotificationSettings.roomActivityEnabled and quiet hours server-side
  /// before ever sending this, so re-checking local settings here would
  /// just be double-gating the same decision against a copy that might be
  /// stale.
  Future<void> showForegroundRoomPush({
    required String title,
    required String body,
  }) async {
    if (kIsWeb) return;
    await init();
    // 72000, not 70000: _quitCheckInBase is 70000 with a 0–999 hash spread,
    // so this shared that exact range. A foreground room push whose title
    // hashed into the same slot as a scheduled quit check-in replaced it —
    // silently cancelling a reminder the person had set.
    await _plugin.show(
      _foregroundRoomPushBase + title.hashCode.abs() % 1000,
      title,
      body,
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
      // Its own id, NOT 9000: that is _weeklyDigestId, and show() replaces
      // any pending schedule carrying the same id — so the test button was
      // quietly cancelling the scheduled Friday digest every time it was
      // tapped (until the next recompute happened to reschedule it). A
      // diagnostic must never eat a real notification.
      9990,
      isAr ? 'إشعار تجريبي' : 'Test notification',
      isAr
          ? 'هكذا تبدو إشعارات Grow Daily على جهازك.'
          : "This is what Grow Daily's notifications look like on your device.",
      _details,
    );
  }
}
