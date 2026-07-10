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

  bool _initialized = false;

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
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );
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

  /// Schedules (or reschedules) a repeating daily reminder at [hour]:[minute]
  /// local time. Safe to call every time the user changes the time — it
  /// replaces the previous schedule under the same notification id.
  Future<void> scheduleDailyReminder({int hour = 20, int minute = 0}) async {
    if (kIsWeb) return;
    await init();
    await _plugin.zonedSchedule(
      _dailyReminderId,
      'Time for your habits',
      "Don't break the streak — color today's square.",
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

  // IDs this instance currently has scheduled via scheduleHabitReminders,
  // so the next call can cancel exactly the ones that no longer apply
  // (habit deleted, or its cue is no longer a fixed time) instead of
  // leaving stale per-habit reminders behind. In-memory only — re-derived
  // fresh from the current habit list on every cold start, since main.dart
  // calls this with fireImmediately on the habit list provider.
  final Set<int> _habitReminderIds = {};

  int _habitReminderId(String habitId) => 5000 + habitId.hashCode.abs() % 1000;

  /// Schedules one real reminder per habit that has a fixed clock-time cue
  /// (see HabitCue.clockTime) — named for that habit, fired at that habit's
  /// own time, instead of every habit sharing the single generic
  /// [scheduleDailyReminder] ping. Habits with a routine-anchored cue
  /// ('after Maghrib', 'before sleep') or no cue at all are left alone: we
  /// don't have real prayer-time/schedule data to fire those accurately, and
  /// a wrong-time reminder is worse than none. Safe to call any time the
  /// habit list changes — replaces the previous set of schedules entirely.
  Future<void> scheduleHabitReminders(
    List<({String id, String name, TimeOfDay time})> reminders,
  ) async {
    if (kIsWeb) return;
    await init();
    final nextIds = <int>{};
    for (final r in reminders) {
      final id = _habitReminderId(r.id);
      nextIds.add(id);
      await _plugin.zonedSchedule(
        id,
        r.name,
        'It\'s time — keep the streak going.',
        _nextInstanceOf(r.time.hour, r.time.minute),
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
    // Cancel anything scheduled last time that isn't in this round (habit
    // deleted, cue changed away from a fixed time, etc).
    for (final staleId in _habitReminderIds.difference(nextIds)) {
      await _plugin.cancel(staleId);
    }
    _habitReminderIds
      ..clear()
      ..addAll(nextIds);
    debugPrint(
        '[NotificationService] ${nextIds.length} per-habit reminder(s) scheduled');
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
