// A snooze the person asked for survives the next reminder pass.
//
// «تأجيل ساعة» arms one notification an hour on, in the 6000 band. Every
// reminder pass used to cancel it as soon as the slot it came from had no
// reminder left TODAY, and a snooze only ever comes from a reminder that has
// already fired, so the next app open killed it. On Android the button
// itself opens the app, so a snooze there practically never arrived
// (2026-09-24). Only a habit done for the day retires its snooze now.
//
// The pass runs on the real clock (NotificationService reads
// tz.TZDateTime.now), so the habit's reminder is placed a while before now,
// and the one test that needs that to be earlier today is skipped in the
// first hours after midnight rather than made to lie.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/features/settings/models/notification_settings.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const widgetChannel = MethodChannel('home_widget');
  const alarmChannel = MethodChannel('com.growdaily.v2/alarm');
  const notificationsChannel =
      MethodChannel('dexterous.com/flutter/local_notifications');
  const timezoneChannel = MethodChannel('flutter_timezone');

  // What the system holds: id -> payload.
  late Map<int, String> pending;

  setUpAll(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Bahrain'));
    IOSFlutterLocalNotificationsPlugin.registerWith();
  });

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    pending = {};
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(widgetChannel, (call) async => true);
    messenger.setMockMethodCallHandler(alarmChannel, (call) async =>
        call.method == 'isSupported' ? false : null);
    messenger.setMockMethodCallHandler(notificationsChannel, (call) async {
      switch (call.method) {
        case 'zonedSchedule':
          final a = call.arguments as Map;
          pending[a['id'] as int] = a['payload'] as String? ?? '';
        case 'cancel':
          pending.remove(call.arguments as int);
        case 'pendingNotificationRequests':
          return [
            for (final e in pending.entries)
              {'id': e.key, 'title': '', 'body': '', 'payload': e.value},
          ];
        case 'getActiveNotifications':
          return const <Map<String, Object?>>[];
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
        timezoneChannel, (call) async => 'Asia/Bahrain');
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [
      widgetChannel,
      alarmChannel,
      notificationsChannel,
      timezoneChannel,
    ]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  const settings = NotificationSettings(quietHoursEnabled: false);
  const habitId = 'walk';
  final snoozeId = 6000 + NotificationService.reminderSlotOffset(habitId, 0);

  HabitReminderInput walk(TimeOfDay at, {int completedCount = 0}) => (
        id: habitId,
        name: 'المشي',
        clockTimes: [at],
        clockOffsets: const [0],
        remindersPerOccurrence: 1,
        extraReminderOffsets: const [],
        prayerKey: null,
        streak: 0,
        completedCount: completedCount,
        dailyTarget: 1,
        lastDoneDaysAgo: null,
        timerSeconds: null,
        reminderOffsetMinutes: 0,
        ignoreQuietHours: true,
        isQuit: false,
        isLimit: false,
        alarm: false,
        scheduledWeekdays: const {},
        anchorLabel: null,
        weekTarget: null,
        weekDoneDays: null,
      );

  // The reminder that was snoozed: twenty minutes ago, earlier today.
  TimeOfDay? firedEarlierToday() {
    final now = tz.TZDateTime.now(tz.local);
    final at = now.subtract(const Duration(minutes: 20));
    if (at.day != now.day) return null;
    return TimeOfDay(hour: at.hour, minute: at.minute);
  }

  test('the next pass leaves a pending snooze alone while the habit is open',
      () async {
    final at = firedEarlierToday();
    if (at == null) {
      markTestSkipped('needs twenty minutes of today behind now');
      return;
    }
    // The person tapped «تأجيل ساعة» on the reminder that just fired.
    await NotificationService.instance
        .snoozeHabitReminder(habitId, 'المشي', isAr: true);
    expect(pending.keys, contains(snoozeId), reason: 'the snooze is armed');

    // Then opened the app, which runs a reminder pass.
    await NotificationService.instance
        .scheduleSmartReminders([walk(at)], settings, isAr: true);

    expect(pending.keys, contains(snoozeId),
        reason: 'the slot has nothing left today because its reminder '
            'already fired, which is exactly when a snooze exists; the '
            'habit is still open, so the hour the person asked for stands');
  });

  test('a habit done for the day retires its snooze', () async {
    final at = firedEarlierToday() ?? const TimeOfDay(hour: 23, minute: 59);
    await NotificationService.instance
        .snoozeHabitReminder(habitId, 'المشي', isAr: true);
    expect(pending.keys, contains(snoozeId));

    await NotificationService.instance.scheduleSmartReminders(
        [walk(at, completedCount: 1)], settings,
        isAr: true);

    expect(pending.keys, isNot(contains(snoozeId)),
        reason: 'done today: the snooze would ask for a finished habit');
  });
}
