// The record a real reminder pass leaves in the App Group, read back by the
// real lock screen and Watch Done handler: the two halves of one contract,
// run against each other.
//
// armed_reminder_record_test.dart pins the record's shape and rule on
// hand-built copies, and notification_action_background_test.dart the
// handler on hand-built records. Neither would notice the pass filing a copy
// under the wrong day, forgetting the alarms, or naming a bundle's members
// wrongly; this does, because what it reads is what the pass armed.
//
// The pass runs on the real clock (NotificationService reads
// tz.TZDateTime.now), so the habits are placed a few minutes either side of
// now, and a test that needs a few minutes of today left on either side is
// skipped in the minutes around midnight rather than made to lie.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/services/notification_action_background.dart';
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

  /// The App Group store, keyed the way home_widget keys it.
  late Map<String, Object?> store;
  // What each system holds: id -> when it fires, and whose it is.
  late Map<int, ({tz.TZDateTime at, String payload})> pending;
  late Map<int, DateTime> alarms;

  setUpAll(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Bahrain'));
    IOSFlutterLocalNotificationsPlugin.registerWith();
  });

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    store = {};
    pending = {};
    alarms = {};
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(widgetChannel, (call) async {
      final args = call.arguments;
      switch (call.method) {
        case 'saveWidgetData':
          store[(args as Map)['id'] as String] = args['data'];
          return true;
        case 'getWidgetData':
          return store[(args as Map)['id'] as String];
      }
      return true;
    });
    messenger.setMockMethodCallHandler(notificationsChannel, (call) async {
      switch (call.method) {
        case 'zonedSchedule':
          final a = call.arguments as Map;
          pending[a['id'] as int] = (
            at: tz.TZDateTime.parse(tz.local, a['scheduledDateTime'] as String),
            payload: a['payload'] as String? ?? '',
          );
        case 'cancel':
          pending.remove(call.arguments as int);
        case 'pendingNotificationRequests':
          return [
            for (final e in pending.entries)
              {'id': e.key, 'title': '', 'body': '', 'payload': e.value.payload},
          ];
        case 'getActiveNotifications':
          return const <Map<String, Object?>>[];
      }
      return null;
    });
    // iOS 26 with alarms allowed, keeping to the bridge's rules: a moment
    // already past is refused, and an id scheduled again replaces itself.
    messenger.setMockMethodCallHandler(alarmChannel, (call) async {
      final a = call.arguments is Map ? call.arguments as Map : const {};
      switch (call.method) {
        case 'isSupported':
          return true;
        case 'authorizationState':
          return 'authorized';
        case 'schedule':
          final at = DateTime.fromMillisecondsSinceEpoch(
              (a['fireAtMs'] as num).toInt());
          if (!at.isAfter(DateTime.now())) return false;
          alarms[a['id'] as int] = at;
          return true;
        case 'cancel':
          alarms.remove(a['id'] as int);
          return null;
        case 'reapOrphans':
          return 0;
        case 'syncWindow':
          final low = a['lowId'] as int;
          final high = a['highId'] as int;
          alarms.removeWhere((id, _) => id >= low && id <= high);
          for (final raw in a['alarms'] as List) {
            final item = raw as Map;
            alarms[item['id'] as int] = DateTime.fromMillisecondsSinceEpoch(
                (item['fireAtMs'] as num).toInt());
          }
          return <String, int>{'scheduled': 0};
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

  HabitReminderInput habit(String id, TimeOfDay at, {bool alarm = false}) => (
        id: id,
        name: id,
        clockTimes: [at],
        clockOffsets: const [0],
        remindersPerOccurrence: 1,
        extraReminderOffsets: const [],
        prayerKey: null,
        streak: 0,
        completedCount: 0,
        dailyTarget: 1,
        lastDoneDaysAgo: null,
        timerSeconds: null,
        reminderOffsetMinutes: 0,
        ignoreQuietHours: true,
        isQuit: false,
        isLimit: false,
        alarm: alarm,
        scheduledWeekdays: const {},
        anchorLabel: null,
        weekTarget: null,
        weekDoneDays: null,
      );

  final service = NotificationService.instance;

  // A minute of today [minutes] away from now, or null when that would
  // leave today.
  TimeOfDay? todayAt(int minutes) {
    final now = tz.TZDateTime.now(tz.local);
    final at = now.add(Duration(minutes: minutes));
    if (at.day != now.day) return null;
    return TimeOfDay(hour: at.hour, minute: at.minute);
  }

  String dayKey(int daysFromToday) {
    final today = DateTime.now().effectiveDay;
    return DateTime(today.year, today.month, today.day + daysFromToday)
        .toDateKey();
  }

  Map<String, Object?> recordOf(String habitId) {
    final record =
        jsonDecode(store['armedHabitRemindersJson'] as String) as Map;
    return (record['habits'] as Map)[habitId] as Map<String, Object?>;
  }

  List<int> idsOn(String habitId, int daysFromToday, String kind) {
    final days = recordOf(habitId)['days'] as Map? ?? const {};
    final day = days[dayKey(daysFromToday)] as Map? ?? const {};
    return [...(day[kind] as List? ?? const []).cast<int>()];
  }

  Future<void> tickFromLockScreen(String habitId) {
    store['todayHabitsJson'] = jsonEncode([
      {'id': habitId, 'name': habitId, 'done': false, 'count': 0, 'perDay': 1},
    ]);
    return handleBackgroundNotificationAction(
      actionId: NotificationService.actionMarkDone,
      habitId: habitId,
      now: DateTime.now(),
    );
  }

  Iterable<int> idsOf(String habitId) =>
      pending.entries.where((e) => e.value.payload == habitId).map((e) => e.key);

  test(
      "a Done outside the app takes today's reminder and leaves the days "
      "after, including a habit whose reminder today has already gone",
      () async {
    final later = todayAt(5);
    final earlier = todayAt(-5);
    if (later == null || earlier == null) {
      markTestSkipped('needs a few minutes of today on either side of now');
      return;
    }
    const settings =
        NotificationSettings(quietHoursEnabled: false, bundleEnabled: false);
    await service.scheduleSmartReminders(
      [habit('duha', later), habit('witr', earlier)],
      settings,
      isAr: true,
    );

    final duhaToday = idsOn('duha', 0, 'notifications');
    expect(duhaToday, hasLength(1), reason: "today's copy is on record");
    expect(pending[duhaToday.single]!.at.day, tz.TZDateTime.now(tz.local).day);
    for (var day = 1; day < NotificationService.kOccurrencesPerSlot; day++) {
      expect(idsOn('duha', day, 'notifications'), hasLength(1),
          reason: 'day +$day is on record under its own day');
    }
    expect(idsOn('witr', 0, 'notifications'), isEmpty,
        reason: "witr's reminder today has gone; its next is tomorrow's");
    expect(idsOn('witr', 1, 'notifications'), hasLength(1));

    final witrBefore = idsOf('witr').toSet();
    await tickFromLockScreen('witr');
    expect(idsOf('witr').toSet(), witrBefore,
        reason: "nothing of today's was left to take, and tomorrow's copy "
            'is the one the old next-occurrence guess used to cancel');

    await tickFromLockScreen('duha');
    expect(pending.containsKey(duhaToday.single), isFalse);
    expect(idsOf('duha'), hasLength(NotificationService.kOccurrencesPerSlot - 1),
        reason: 'the days after today are still armed');
  });

  test("an alarm habit's Done takes today's alarm and none of the month",
      () async {
    final later = todayAt(5);
    if (later == null) {
      markTestSkipped('needs a few minutes of today left');
      return;
    }
    const settings =
        NotificationSettings(quietHoursEnabled: false, bundleEnabled: false);
    await service.scheduleSmartReminders(
      [habit('fajr', later, alarm: true)],
      settings,
      isAr: true,
    );

    final todayAlarm = idsOn('fajr', 0, 'alarms');
    expect(todayAlarm, hasLength(1));
    expect(alarms.containsKey(todayAlarm.single), isTrue);
    expect(idsOn('fajr', 0, 'notifications'), isEmpty,
        reason: 'an alarm replaces the notification under the same id');
    // The ordinary four and the far, day-keyed rest of the month.
    expect(idsOn('fajr', 10, 'alarms'), hasLength(1));
    final armedBefore = alarms.length;
    expect(armedBefore, greaterThan(NotificationService.kOccurrencesPerSlot));

    await tickFromLockScreen('fajr');
    expect(alarms.containsKey(todayAlarm.single), isFalse);
    expect(alarms, hasLength(armedBefore - 1));
  });

  test('a bundle goes once every habit in it is done today, and not before',
      () async {
    final later = todayAt(5);
    if (later == null) {
      markTestSkipped('needs a few minutes of today left');
      return;
    }
    const settings = NotificationSettings(quietHoursEnabled: false);
    await service.scheduleSmartReminders(
      [habit('sunnah', later), habit('adhkar', later)],
      settings,
      isAr: true,
    );

    final bundle = idsOn('sunnah', 0, 'bundles');
    expect(bundle, hasLength(1));
    expect(idsOn('adhkar', 0, 'bundles'), bundle);
    expect(pending.containsKey(bundle.single), isTrue);

    // Both ticked, one after the other, from today's list.
    store['todayHabitsDay'] = dayKey(0);
    store['todayHabitsJson'] = jsonEncode([
      for (final id in ['sunnah', 'adhkar'])
        {'id': id, 'name': id, 'done': false, 'count': 0, 'perDay': 1},
    ]);
    await handleBackgroundNotificationAction(
      actionId: NotificationService.actionMarkDone,
      habitId: 'sunnah',
      now: DateTime.now(),
    );
    expect(pending.containsKey(bundle.single), isTrue,
        reason: 'it still reminds about adhkar, which is owed');
    await handleBackgroundNotificationAction(
      actionId: NotificationService.actionMarkDone,
      habitId: 'adhkar',
      now: DateTime.now(),
    );
    expect(pending.containsKey(bundle.single), isFalse);
    expect(pending.keys.where((id) => id >= 7000 && id < 8000), hasLength(3),
        reason: "the next three days' bundles stay");
  });
}
