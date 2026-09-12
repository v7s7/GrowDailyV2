// A reminder that rings as a real alarm stays armed for thirty days.
//
// A notification keeps NotificationService.kOccurrencesPerSlot days, bound by
// iOS's 64-request budget. An alarm is outside that budget and is the
// reminder someone relies on to wake up, and four days without opening the
// app used to be all it took to lose it. These pin the month: the near days
// still go one schedule per slot, the rest in one reconciling syncWindow call,
// every moment on its own day's prayer time, with plain words, through quiet
// hours, and cleared once it is no longer wanted.
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

const _settings = NotificationSettings(
  quietHoursEnabled: false,
  location: _manama,
  resolvedCountryCode: 'BH',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const alarmChannel = MethodChannel('com.growdaily.v2/alarm');
  const notificationsChannel =
      MethodChannel('dexterous.com/flutter/local_notifications');
  const timezoneChannel = MethodChannel('flutter_timezone');

  late List<MethodCall> alarmCalls;
  late List<MethodCall> notificationCalls;
  late String authorization;

  setUpAll(() async {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Bahrain'));
    IOSFlutterLocalNotificationsPlugin.registerWith();
    await BahrainPrayerTable.ensureLoaded();
  });

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    alarmCalls = [];
    notificationCalls = [];
    authorization = 'authorized';
    PrayerTimesService.resetMonthCache();
    // Past the bundled table Bahrain would ask Aladhan for a month; the
    // offline calculation answers instead, the same tier the oracle reads.
    PrayerTimesService.debugMonthResponder = (_) async => null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(alarmChannel, (call) async {
      alarmCalls.add(call);
      switch (call.method) {
        case 'isSupported':
          return true;
        case 'authorizationState':
          return authorization;
        case 'schedule':
          return authorization == 'authorized';
        case 'syncWindow':
          return <String, int>{
            'scheduled': 0,
            'kept': 0,
            'cancelled': 0,
            'failed': 0,
          };
      }
      return null;
    });
    messenger.setMockMethodCallHandler(notificationsChannel, (call) async {
      notificationCalls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(
        timezoneChannel, (call) async => 'Asia/Bahrain');
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    PrayerTimesService.debugMonthResponder = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(alarmChannel, null);
    messenger.setMockMethodCallHandler(notificationsChannel, null);
    messenger.setMockMethodCallHandler(timezoneChannel, null);
  });

  HabitReminderInput habit({
    String id = 'fajr-alarm',
    String? prayerKey = 'fajr',
    List<TimeOfDay> clockTimes = const [],
    int primary = 0,
    List<int> extras = const [-30],
    bool alarm = true,
    int streak = 0,
  }) =>
      (
        id: id,
        name: id,
        clockTimes: clockTimes,
        clockOffsets: clockTimes.isEmpty ? const [] : [primary],
        remindersPerOccurrence: 1,
        extraReminderOffsets: extras,
        prayerKey: prayerKey,
        streak: streak,
        completedCount: 0,
        dailyTarget: 1,
        lastDoneDaysAgo: 0,
        timerSeconds: null,
        reminderOffsetMinutes: primary,
        ignoreQuietHours: false,
        isQuit: false,
        isLimit: false,
        alarm: alarm,
        scheduledWeekdays: const {},
        anchorLabel: prayerKey == null ? null : 'الفجر',
        weekTarget: null,
        weekDoneDays: null,
      );

  List<Map> calls(List<MethodCall> from, String method) => [
        for (final c in from)
          if (c.method == method) c.arguments as Map,
      ];
  Map window() => calls(alarmCalls, 'syncWindow').single;
  List<Map> windowAlarms() =>
      [for (final a in window()['alarms'] as List) a as Map];

  /// Every moment [offset] minutes from Fajr in the next thirty days, read
  /// from the same tiers the scheduler reads.
  Set<int> expectedMonth(int offset) {
    final now = tz.TZDateTime.now(tz.local);
    final horizon =
        now.add(const Duration(days: NotificationService.kAlarmWindowDays));
    final out = <int>{};
    for (var i = 0; i <= NotificationService.kAlarmWindowDays + 1; i++) {
      final moment = PrayerTimesService.calculateOfflineCorrected(
        latitude: _manama.lat,
        longitude: _manama.lng,
        date: DateTime(now.year, now.month, now.day + i),
        madhab: PrayerMadhab.shafi,
        countryCode: 'BH',
      ).fajr.add(Duration(minutes: offset));
      if (moment.isAfter(now) && moment.isBefore(horizon)) {
        out.add(moment.millisecondsSinceEpoch);
      }
    }
    return out;
  }

  test('an alarm is armed on every day of the next thirty, each on its own Fajr',
      () async {
    await NotificationService.instance
        .scheduleSmartReminders([habit()], _settings, isAr: true);

    final near = calls(alarmCalls, 'schedule');
    expect(near, hasLength(2 * NotificationService.kOccurrencesPerSlot),
        reason: 'the near days still go one by one, with a notification to '
            'fall back on');
    expect(window()['lowId'], 500000);
    expect(window()['highId'], 599999);

    final far = windowAlarms();
    expect({for (final a in far) a['id']}, hasLength(far.length),
        reason: 'one id per armed day');
    for (final a in far) {
      expect(a['id'], inInclusiveRange(500000, 599999));
      expect(a['kind'], 'habit');
      expect(a['targetId'], 'fajr-alarm');
    }

    final armed = [
      for (final a in [...near, ...far]) a['fireAtMs'] as int,
    ];
    expect(armed.toSet(), hasLength(armed.length),
        reason: 'no moment is armed twice');
    expect(armed.toSet(), {...expectedMonth(0), ...expectedMonth(-30)},
        reason: "thirty days of both reminders, each at that day's Fajr");
  });

  test('a day keeps one id however far ahead it was armed', () {
    // What lets tomorrow's open leave the month alone: an id is the day's,
    // not its distance from today.
    final first = DateTime(2027, 2, 8, 4, 29);
    final id = NotificationService.windowAlarmId('fajr-alarm', 1, first);
    expect(
      NotificationService.windowAlarmId(
          'fajr-alarm', 1, first.add(const Duration(minutes: 30))),
      id,
      reason: 'the same calendar day, whatever the minute',
    );
    final month = {
      for (var i = 0; i < NotificationService.kAlarmWindowDays; i++)
        NotificationService.windowAlarmId(
            'fajr-alarm', 1, DateTime(2027, 2, 8 + i, 4, 29)),
    };
    expect(month, hasLength(NotificationService.kAlarmWindowDays),
        reason: 'no two days of one window share an id');
    for (final windowId in month) {
      expect(windowId, inInclusiveRange(500000, 599999));
    }
  });

  test("a day that far ahead says only when, never the habit's record",
      () async {
    await NotificationService.instance
        .scheduleSmartReminders([habit(streak: 9)], _settings, isAr: true);
    final far = windowAlarms();
    final early = {
      for (final a in far)
        if (a['subtitle'] != null) a['subtitle'],
    };
    expect(early, {'باقي ${countedOffsetPhrase(30, true)} على الفجر.'});
    expect(far.where((a) => a['subtitle'] == null), isNotEmpty,
        reason: "an on-time alarm is its habit's name and nothing else");
    expect({for (final a in far) a['title']}, {'fajr-alarm'});
  });

  test('quiet hours set to cover prayers still let an alarm through',
      () async {
    // Quiet hours are on by default (22:00 to 07:00), and Fajr sits inside.
    const quietForPrayers = NotificationSettings(
      quietHoursAppliesToPrayer: true,
      location: _manama,
      resolvedCountryCode: 'BH',
    );
    await NotificationService.instance.scheduleSmartReminders(
      [habit(), habit(id: 'fajr-note', alarm: false)],
      quietForPrayers,
      isAr: true,
    );
    expect(
      calls(alarmCalls, 'schedule')
          .where((a) => a['targetId'] == 'fajr-alarm'),
      hasLength(2 * NotificationService.kOccurrencesPerSlot),
    );
    expect(windowAlarms(), isNotEmpty);
    expect(calls(notificationCalls, 'zonedSchedule'), isEmpty,
        reason: 'the plain notification habit stays silenced, as the setting '
            'says');
  });

  test('without alarm permission only the near days are armed', () async {
    authorization = 'denied';
    await NotificationService.instance
        .scheduleSmartReminders([habit()], _settings, isAr: true);
    expect(windowAlarms(), isEmpty,
        reason: 'and the call still clears any month left from before');
    expect(calls(notificationCalls, 'zonedSchedule'),
        hasLength(2 * NotificationService.kOccurrencesPerSlot),
        reason: 'each near day falls back to a Time Sensitive notification');
  });

  test('a notification reminder keeps its four days', () async {
    await NotificationService.instance
        .scheduleSmartReminders([habit(alarm: false)], _settings, isAr: true);
    expect(windowAlarms(), isEmpty);
    expect(calls(notificationCalls, 'zonedSchedule'),
        hasLength(2 * NotificationService.kOccurrencesPerSlot));
  });

  test('switching habit reminders off clears the month too', () async {
    const off = NotificationSettings(
      habitRemindersEnabled: false,
      location: _manama,
      resolvedCountryCode: 'BH',
    );
    await NotificationService.instance
        .scheduleSmartReminders([habit()], off, isAr: true);
    expect(windowAlarms(), isEmpty);
  });

  test('many alarm habits share the cap, nearest days first', () async {
    final many = [
      for (var i = 0; i < 6; i++) habit(id: 'fajr-$i', extras: const []),
    ];
    await NotificationService.instance
        .scheduleSmartReminders(many, _settings, isAr: true);
    final far = windowAlarms();
    expect(far, hasLength(NotificationService.kMaxWindowAlarms));
    final perMoment = <int, int>{};
    for (final a in far) {
      perMoment.update(a['fireAtMs'] as int, (n) => n + 1, ifAbsent: () => 1);
    }
    expect(perMoment.values.toSet(), {6},
        reason: 'a day is kept for every habit or for none');
    final kept = perMoment.keys.toList()..sort();
    final farDays = (expectedMonth(0).toList()..sort())
        .skip(NotificationService.kOccurrencesPerSlot)
        .toList();
    expect(kept, farDays.take(kept.length).toList(),
        reason: 'the days left out are the furthest');
  });

  test('a clock alarm gets the month too, at the same time every day',
      () async {
    await NotificationService.instance.scheduleSmartReminders([
      habit(
        id: 'wake',
        prayerKey: null,
        clockTimes: const [TimeOfDay(hour: 6, minute: 0)],
        extras: const [],
      ),
    ], _settings, isAr: true);
    final armed = [
      for (final a in [...calls(alarmCalls, 'schedule'), ...windowAlarms()])
        tz.TZDateTime.fromMillisecondsSinceEpoch(
            tz.local, a['fireAtMs'] as int),
    ]..sort();
    expect(armed, hasLength(NotificationService.kAlarmWindowDays));
    for (final t in armed) {
      expect((t.hour, t.minute), (6, 0));
    }
    expect({for (final t in armed) '${t.year}-${t.month}-${t.day}'},
        hasLength(armed.length));
  });
}
