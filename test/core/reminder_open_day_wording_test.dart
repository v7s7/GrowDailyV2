// What a habit reminder armed for tomorrow morning says about today.
//
// reminder_facts_at_fire_day_test pins NotificationService
// .reminderFactsAtFireDay with a fire time and without one. It cannot see
// the scheduler handing it no fire time: then a 07:00 reminder tomorrow
// judges today as already closed, and names a lapse for a day that can
// still be marked until 10:00 the next morning. This arms real reminders
// through scheduleSmartReminders and reads the body that was armed.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/reminder_copy.dart';
import 'package:grow_daily_v2/core/services/bahrain_prayer_table.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/core/services/prayer_times_service.dart';
import 'package:grow_daily_v2/features/settings/models/notification_settings.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

const _manama = NotificationLocation(
  lat: 26.2285,
  lng: 50.5860,
  label: 'Manama, Bahrain',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const alarmChannel = MethodChannel('com.growdaily.v2/alarm');
  const notificationsChannel =
      MethodChannel('dexterous.com/flutter/local_notifications');
  const timezoneChannel = MethodChannel('flutter_timezone');

  late List<MethodCall> notificationCalls;

  setUpAll(() async {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Bahrain'));
    IOSFlutterLocalNotificationsPlugin.registerWith();
    await BahrainPrayerTable.ensureLoaded();
  });

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    notificationCalls = <MethodCall>[];
    PrayerTimesService.resetMonthCache();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(alarmChannel, (call) async =>
        call.method == 'isSupported' ? false : null);
    messenger.setMockMethodCallHandler(notificationsChannel, (call) async {
      notificationCalls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(
        timezoneChannel, (call) async => 'Asia/Bahrain');
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(alarmChannel, null);
    messenger.setMockMethodCallHandler(notificationsChannel, null);
    messenger.setMockMethodCallHandler(timezoneChannel, null);
  });

  const settings = NotificationSettings(
    quietHoursEnabled: false,
    location: _manama,
    resolvedCountryCode: 'BH',
  );

  test('tomorrow at 07:00 names no lapse for a today that is still open',
      () async {
    // Every day, at 07:00 on the dot, last done yesterday on a 5-day streak.
    const HabitReminderInput water = (
      id: 'water',
      name: 'water',
      clockTimes: [TimeOfDay(hour: 7, minute: 0)],
      clockOffsets: [0],
      remindersPerOccurrence: 1,
      extraReminderOffsets: [],
      prayerKey: null,
      streak: 5,
      completedCount: 0,
      dailyTarget: 1,
      lastDoneDaysAgo: 1,
      timerSeconds: null,
      reminderOffsetMinutes: 0,
      ignoreQuietHours: true,
      isQuit: false,
      isLimit: false,
      alarm: false,
      scheduledWeekdays: <int>{},
      anchorLabel: null,
      weekTarget: null,
      weekDoneDays: null,
    );
    // The scheduler reads the wall clock itself, so "tomorrow" below is read
    // from the same clock, on both sides of the call: a run that crosses
    // midnight inside it armed a different tomorrow, and is armed again.
    final before = tz.TZDateTime.now(tz.local);
    await NotificationService.instance
        .scheduleSmartReminders([water], settings, isAr: true);
    var now = tz.TZDateTime.now(tz.local);
    if (now.day != before.day) {
      notificationCalls.clear();
      await NotificationService.instance
          .scheduleSmartReminders([water], settings, isAr: true);
      now = tz.TZDateTime.now(tz.local);
    }
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final tomorrowMorning = [
      for (final call in notificationCalls)
        if (call.method == 'zonedSchedule')
          if (() {
            final at = tz.TZDateTime.parse(
              tz.local,
              (call.arguments as Map)['scheduledDateTime'] as String,
            );
            return at.year == tomorrow.year &&
                at.month == tomorrow.month &&
                at.day == tomorrow.day &&
                at.hour == 7;
          }())
            call.arguments as Map,
    ];
    expect(tomorrowMorning, hasLength(1),
        reason: 'the armed window always holds tomorrow morning');
    final body = tomorrowMorning.single['body'] as String;

    // Every wording the line can rotate to for tomorrow's facts: last done
    // two calendar days before the fire day, no streak carried across the
    // day between, and [missed] days of the habit's own schedule lost.
    Set<String> linesFor({required int missed}) => {
          for (var variant = 0; variant < 12; variant++)
            habitOnTimeLine(
              streak: 0,
              completedCount: 0,
              dailyTarget: 1,
              lastDoneDaysAgo: 2,
              missedSinceLastDone: missed,
              timerSeconds: null,
              variantIndex: variant,
              isAr: true,
            ),
        };
    expect(linesFor(missed: 0), contains(body),
        reason: 'at 07:00 tomorrow today can still be marked, so nothing is '
            'lost yet');
    expect(linesFor(missed: 1), isNot(contains(body)),
        reason: 'judged without the fire time, today already read as a '
            'lapse, «صار لها يومين»');
  });
}
