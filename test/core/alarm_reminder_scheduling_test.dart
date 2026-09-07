// A task reminder chosen to ring as an alarm, through NotificationService,
// against mocked channels.
//
// Pins the contract between the two schedulers: an alarm slot is scheduled
// through the alarm channel and its notification under the same id is
// cancelled; a notification slot cancels any alarm under its id; and when
// the alarm cannot be made (a refusal) the slot falls back to a Time
// Sensitive notification rather than vanishing.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/features/settings/models/notification_settings.dart';
import 'package:timezone/data/latest.dart' as tz_data;

/// The slot id a channel call is about, for the ordered trace below.
String _idOf(MethodCall call) {
  final a = call.arguments;
  if (a is int) return '$a';
  if (a is Map) return '${a['id']}';
  return '';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const alarmChannel = MethodChannel('com.growdaily.v2/alarm');
  const notificationsChannel =
      MethodChannel('dexterous.com/flutter/local_notifications');
  const timezoneChannel = MethodChannel('flutter_timezone');

  late List<MethodCall> alarmCalls;
  late List<MethodCall> notificationCalls;
  // Both channels in the order they were called, one line per call.
  late List<String> trace;
  late bool alarmAccepts;

  setUpAll(() {
    tz_data.initializeTimeZones();
    // What the app's generated registrant does at start-up.
    IOSFlutterLocalNotificationsPlugin.registerWith();
  });

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    alarmCalls = <MethodCall>[];
    notificationCalls = <MethodCall>[];
    trace = <String>[];
    alarmAccepts = true;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(alarmChannel, (call) async {
      alarmCalls.add(call);
      if (call.method != 'isSupported') {
        trace.add('alarm:${call.method}:${_idOf(call)}');
      }
      switch (call.method) {
        case 'isSupported':
          return true;
        case 'schedule':
          return alarmAccepts;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(notificationsChannel, (call) async {
      notificationCalls.add(call);
      trace.add('notify:${call.method}:${_idOf(call)}');
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

  final fireAt = DateTime.now().add(const Duration(hours: 2));

  Iterable<MethodCall> scheduled() =>
      notificationCalls.where((c) => c.method == 'zonedSchedule');
  Iterable<int> cancelledNotifications() => notificationCalls
      .where((c) => c.method == 'cancel')
      .map((c) => c.arguments as int);
  Iterable<Map> alarmSchedules() => alarmCalls
      .where((c) => c.method == 'schedule')
      .map((c) => c.arguments as Map);
  Iterable<int> cancelledAlarms() => alarmCalls
      .where((c) => c.method == 'cancel')
      .map((c) => (c.arguments as Map)['id'] as int);

  test('an alarm task rings through the alarm channel, not a notification',
      () async {
    await NotificationService.instance.scheduleTaskReminders(
      id: 'task-1',
      taskTitle: 'اتصل بأمي',
      fireTimes: [fireAt],
      anchorAt: fireAt,
      isAr: true,
      alarm: true,
    );
    final alarm = alarmSchedules().single;
    expect(alarm['kind'], 'task');
    expect(alarm['targetId'], 'task-1');
    expect(alarm['title'], 'اتصل بأمي');
    expect(alarm['doneLabel'], 'تم');
    expect(alarm['fireAtMs'], fireAt.millisecondsSinceEpoch);
    expect(scheduled(), isEmpty,
        reason: 'the alarm replaces the notification for this slot');
    expect(cancelledNotifications(), contains(alarm['id']),
        reason: 'a notification left under the same id would ring twice');
  });

  test('a notification task clears any alarm under its slot', () async {
    await NotificationService.instance.scheduleTaskReminders(
      id: 'task-2',
      taskTitle: 'Water the plants',
      fireTimes: [fireAt],
      anchorAt: fireAt,
      isAr: false,
      alarm: false,
    );
    expect(alarmSchedules(), isEmpty);
    final notification = scheduled().single.arguments as Map;
    expect(notification['body'], 'Water the plants');
    expect(cancelledAlarms(), contains(notification['id']),
        reason: 'a task switched back from alarm must not keep the alarm');
    final platform = notification['platformSpecifics'] as Map;
    expect(platform['interruptionLevel'], isNull,
        reason: 'a plain reminder keeps the default level');
  });

  test('a refused alarm falls back to a Time Sensitive notification',
      () async {
    alarmAccepts = false;
    await NotificationService.instance.scheduleTaskReminders(
      id: 'task-3',
      taskTitle: 'Fajr',
      fireTimes: [fireAt],
      anchorAt: fireAt,
      isAr: false,
      alarm: true,
    );
    expect(alarmSchedules().length, 1, reason: 'it was tried');
    final notification = scheduled().single.arguments as Map;
    final platform = notification['platformSpecifics'] as Map;
    expect(platform['interruptionLevel'], isNotNull,
        reason: 'what the person asked for, as near as the platform allows');
  });

  test('unused slots are swept in both systems', () async {
    await NotificationService.instance.scheduleTaskReminders(
      id: 'task-4',
      taskTitle: 't',
      fireTimes: [fireAt],
      anchorAt: fireAt,
      isAr: false,
      alarm: true,
    );
    final sweptAlarms = cancelledAlarms().toSet();
    final sweptNotifications = cancelledNotifications().toSet();
    expect(sweptAlarms.length,
        NotificationService.kMaxTaskReminderSlots - 1);
    expect(sweptNotifications.length,
        greaterThanOrEqualTo(NotificationService.kMaxTaskReminderSlots - 1));
  });

  test('an alarm that rings with the app open becomes the reminder banner',
      () async {
    await NotificationService.instance.scheduleTaskReminders(
      id: 'task-6',
      taskTitle: 'اتصل بأمي',
      fireTimes: [fireAt],
      anchorAt: fireAt,
      isAr: true,
      alarm: true,
    );
    final slot = alarmSchedules().single['id'] as int;
    notificationCalls.clear();
    // What the native observer sends when the app is in front.
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      'com.growdaily.v2/alarm',
      const StandardMethodCodec().encodeMethodCall(
          MethodCall('alarmAlertingInForeground', {'id': slot})),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);
    final shown = notificationCalls.singleWhere((c) => c.method == 'show');
    final args = shown.arguments as Map;
    expect(args['id'], slot);
    expect(args['title'], 'اتصل بأمي');
    expect(args['payload'], 'task-6');
    expect((args['platformSpecifics'] as Map)['interruptionLevel'], isNotNull,
        reason: 'it stands in for an alarm the person asked for');
  });

  test('cancelTaskReminder clears every slot in both systems', () async {
    alarmCalls.clear();
    notificationCalls.clear();
    await NotificationService.instance.cancelTaskReminder('task-5');
    expect(cancelledAlarms().length,
        NotificationService.kMaxTaskReminderSlots);
    expect(cancelledNotifications().length,
        NotificationService.kMaxTaskReminderSlots);
  });

  test('passes in flight together run whole, one after the other', () async {
    Future<void> schedule() => NotificationService.instance.scheduleTaskReminders(
          id: 'task-a',
          taskTitle: 'task-a',
          fireTimes: [fireAt],
          anchorAt: fireAt,
          isAr: false,
          alarm: true,
        );
    // Warm the service up so the first real pass carries no one-off init.
    await schedule();
    trace.clear();
    await schedule();
    final alone = List.of(trace);
    trace.clear();
    // What main.dart does on a resume: several passes fired without waiting
    // for each other. Interleaved, one pass's cancel landed between
    // another's cancel and schedule of the same slot and AlarmKit refused
    // the second as a duplicate; the refused pass then cancelled the alarm
    // the first had made (seen live 2026-09-06 15:26).
    await Future.wait([schedule(), schedule()]);
    expect(
      trace,
      [...alone, ...alone],
      reason: 'each pass runs whole, never interleaved with another',
    );
  });

  test('a habit pass overtaken while queued is skipped for the newer one',
      () async {
    HabitReminderInput habit(String id) => (
          id: id,
          name: id,
          clockTimes: [TimeOfDay(hour: fireAt.hour, minute: fireAt.minute)],
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
          alarm: true,
          scheduledWeekdays: const {1, 2, 3, 4, 5, 6, 7},
          anchorLabel: null,
          weekTarget: null,
          weekDoneDays: null,
        );
    const settings = NotificationSettings(quietHoursEnabled: false);
    await Future.wait([
      NotificationService.instance
          .scheduleSmartReminders([habit('stale')], settings, isAr: false),
      NotificationService.instance
          .scheduleSmartReminders([habit('fresh')], settings, isAr: false),
    ]);
    expect(
      alarmSchedules().map((a) => a['targetId']),
      ['fresh'],
      reason: 'the older pass was overtaken before it ran',
    );
  });
}
