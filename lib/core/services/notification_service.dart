import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Real local-notification service backing daily habit reminders and
/// in-the-moment celebration pings (habit completed, level up, achievement
/// unlocked). Uses `flutter_local_notifications` — no remote push server is
/// involved, everything is scheduled/fired on-device.
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

  // ── Rotating copy ────────────────────────────────────────────
  //
  // Picked by a fixed day-based index rather than random — varies day to
  // day but won't visibly flicker between different lines if a reschedule
  // happens to fire more than once on the same day (habit list edited
  // twice, reminder time tweaked, etc).
  static const _dailyLines = [
    (
      'Time for your habits',
      "Don't break the streak — color today's square."
    ),
    (
      'Your habits are waiting',
      'A few minutes now, one more green square today.'
    ),
    ('Keep the streak alive', "You've come this far — don't stop now."),
    ('Quick check-in', 'Which habit can you knock out right now?'),
    ('Still time today', 'Small steps count. Go color your grid.'),
  ];
  static const _habitLines = [
    "It's time — keep the streak going.",
    'A few minutes for this one today.',
    "Don't let today slip by.",
    'Ready when you are.',
  ];

  int _dayIndex(int poolLength) {
    final day = DateTime.now();
    return (day.year * 400 + day.month * 31 + day.day) % poolLength;
  }

  /// Schedules (or reschedules) a repeating daily reminder at [hour]:[minute]
  /// local time. Safe to call every time the user changes the time — it
  /// replaces the previous schedule under the same notification id.
  Future<void> scheduleDailyReminder({int hour = 20, int minute = 0}) async {
    if (kIsWeb) return;
    await init();
    final (title, body) = _dailyLines[_dayIndex(_dailyLines.length)];
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
    );
    debugPrint(
        '[NotificationService] Daily reminder set — $hour:${minute.toString().padLeft(2, '0')}');
  }

  Future<void> cancelDailyReminder() async {
    if (kIsWeb) return;
    await _plugin.cancel(_dailyReminderId);
    debugPrint('[NotificationService] Daily reminder cancelled');
  }

  // Habit ids this instance currently has a reminder scheduled for, so the
  // next call can cancel exactly the ones that no longer apply (habit
  // deleted, or its cue is no longer a fixed time) instead of leaving stale
  // per-habit reminders — and any pending snooze for them — behind.
  // In-memory only — re-derived fresh from the current habit list on every
  // cold start, since main.dart calls this with fireImmediately on the
  // habit list provider.
  final Set<String> _habitReminderHabitIds = {};

  int _habitReminderId(String habitId) =>
      5000 + habitId.hashCode.abs() % 1000;
  int _snoozeId(String habitId) => 6000 + habitId.hashCode.abs() % 1000;

  /// Schedules one real reminder per habit that has a fixed clock-time cue
  /// (see HabitCue.clockTime) — named for that habit, fired at that habit's
  /// own time, instead of every habit sharing the single generic
  /// [scheduleDailyReminder] ping. Habits with a routine-anchored cue
  /// ('after Maghrib', 'before sleep') or no cue at all are left alone: we
  /// don't have real prayer-time/schedule data to fire those accurately, and
  /// a wrong-time reminder is worse than none. Safe to call any time the
  /// habit list changes — replaces the previous set of schedules entirely.
  Future<void> scheduleHabitReminders(
    List<({String id, String name, TimeOfDay time, int streak})> reminders,
  ) async {
    if (kIsWeb) return;
    await init();
    final nextHabitIds = <String>{};
    for (final r in reminders) {
      nextHabitIds.add(r.id);
      final id = _habitReminderId(r.id);
      final body = r.streak > 0
          ? "Don't lose your ${r.streak}-day streak."
          : _habitLines[_dayIndex(_habitLines.length)];
      await _plugin.zonedSchedule(
        id,
        r.name,
        body,
        _nextInstanceOf(r.time.hour, r.time.minute),
        _habitReminderDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: r.id,
      );
    }
    // Cancel anything scheduled last time that isn't in this round (habit
    // deleted, cue changed away from a fixed time, etc) — both its regular
    // reminder and any snooze that might still be pending for it.
    for (final staleId in _habitReminderHabitIds.difference(nextHabitIds)) {
      await _plugin.cancel(_habitReminderId(staleId));
      await _plugin.cancel(_snoozeId(staleId));
    }
    _habitReminderHabitIds
      ..clear()
      ..addAll(nextHabitIds);
    debugPrint(
        '[NotificationService] ${nextHabitIds.length} per-habit reminder(s) scheduled');
  }

  /// Reschedules habit [habitId]'s reminder for an hour from now, as a
  /// one-off — uses a separate notification id from the regular recurring
  /// per-habit reminder (see [_snoozeId]) so it doesn't clobber that
  /// schedule.
  Future<void> snoozeHabitReminder(String habitId, String habitName) async {
    if (kIsWeb) return;
    await init();
    await _plugin.zonedSchedule(
      _snoozeId(habitId),
      habitName,
      "Snoozed — it's time.",
      tz.TZDateTime.now(tz.local).add(const Duration(hours: 1)),
      _habitReminderDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: habitId,
    );
    debugPrint('[NotificationService] Snoozed reminder for $habitId');
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
    if (kIsWeb) return;
    await init();
    await _plugin.show(
      2000 + habitName.hashCode.abs() % 1000,
      habitName,
      '+$xpEarned XP · +$goldEarned Gold',
      _details,
    );
  }

  Future<void> showLevelUp(int newLevel) async {
    if (kIsWeb) return;
    await init();
    await _plugin.show(
      3000,
      'Level up!',
      "You've reached level $newLevel.",
      _details,
    );
  }

  Future<void> showAchievementUnlocked(String achievementName) async {
    if (kIsWeb) return;
    await init();
    await _plugin.show(
      4000 + achievementName.hashCode.abs() % 1000,
      'Achievement unlocked',
      achievementName,
      _details,
    );
  }
}
