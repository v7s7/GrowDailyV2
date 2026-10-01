// A habit counted several times a day whose reminders ride on prayers, one
// per time (Aziz, 2026-10-01: "option 2, but user can set like 30 min before
// fajr, and 30 after fajr"). NotificationService.scheduleSmartReminders
// fires each slot at its OWN prayer and shift, names that prayer in its
// words, and stands down one slot per completion the way a habit with
// several clock times does.
//
// Bahrain's bundled official table is the oracle, so these run offline and
// to the minute.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
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

  /// Every scheduled notification: its id, when, and its words.
  List<({int id, tz.TZDateTime at, String body})> armed() => [
        for (final call in notificationCalls)
          if (call.method == 'zonedSchedule')
            (
              id: (call.arguments as Map)['id'] as int,
              at: tz.TZDateTime.parse(
                tz.local,
                (call.arguments as Map)['scheduledDateTime'] as String,
              ),
              body: '${(call.arguments as Map)['title']} '
                  '${(call.arguments as Map)['body']}',
            ),
      ]..sort((a, b) => a.at.compareTo(b.at));

  String label(String key) => switch (key) {
        'fajr' => 'الفجر',
        'dhuhr' => 'الظهر',
        'asr' => 'العصر',
        'maghrib' => 'المغرب',
        _ => 'العشاء',
      };

  HabitReminderInput habit(
    List<({String prayer, int offset})> slots, {
    int completedCount = 0,
  }) =>
      (
        id: 'water',
        name: 'شرب الماء',
        clockTimes: const [],
        clockOffsets: const [],
        remindersPerOccurrence: 1,
        extraReminderOffsets: const [],
        prayerKey: null,
        prayerSlots: [
          for (final s in slots)
            (prayerKey: s.prayer, offset: s.offset, label: label(s.prayer)),
        ],
        streak: 0,
        completedCount: completedCount,
        dailyTarget: slots.length,
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

  const settings = NotificationSettings(
    quietHoursEnabled: false,
    location: _manama,
    resolvedCountryCode: 'BH',
  );

  Future<void> schedule(HabitReminderInput h) => NotificationService.instance
      .scheduleSmartReminders([h], settings, isAr: true);

  test('30 before Fajr and 30 after it: two reminders a morning, each on '
      'that morning\'s Fajr', () async {
    await schedule(habit([
      (prayer: 'fajr', offset: -30),
      (prayer: 'fajr', offset: 30),
    ]));
    final fires = armed();
    expect(fires, hasLength(2 * NotificationService.kOccurrencesPerSlot),
        reason: 'both slots, a window of days each');
    expect(fires.map((f) => f.id).toSet(), hasLength(fires.length),
        reason: 'no two copies share an id');
    var before = 0;
    var after = 0;
    for (final f in fires) {
      final fajr = BahrainPrayerTable.lookup(
        DateTime(f.at.year, f.at.month, f.at.day),
      )!
          .fajr;
      if (f.at == fajr.subtract(const Duration(minutes: 30))) {
        before++;
      } else if (f.at == fajr.add(const Duration(minutes: 30))) {
        after++;
      } else {
        fail('${f.at} is neither 30 before nor 30 after that day\'s Fajr');
      }
    }
    expect(before, NotificationService.kOccurrencesPerSlot);
    expect(after, NotificationService.kOccurrencesPerSlot);
  });

  test('each slot rides on its own prayer and names it', () async {
    await schedule(habit([
      (prayer: 'dhuhr', offset: 0),
      (prayer: 'maghrib', offset: 10),
    ]));
    final fires = armed();
    expect(fires, hasLength(2 * NotificationService.kOccurrencesPerSlot));
    for (final f in fires) {
      final day = BahrainPrayerTable.lookup(
        DateTime(f.at.year, f.at.month, f.at.day),
      )!;
      if (f.at == day.dhuhr) {
        expect(f.body, isNot(contains('المغرب')), reason: f.body);
      } else {
        expect(f.at, day.maghrib.add(const Duration(minutes: 10)));
        expect(f.body, isNot(contains('الظهر')), reason: f.body);
      }
    }
  });

  test('a completion stands down one of today\'s, not all of them', () async {
    final slots = [
      (prayer: 'fajr', offset: 0),
      (prayer: 'dhuhr', offset: 0),
      (prayer: 'asr', offset: 0),
      (prayer: 'maghrib', offset: 0),
      (prayer: 'isha', offset: 0),
    ];
    int todayCount() {
      final today = tz.TZDateTime.now(tz.local).effectiveDay;
      return armed().where((f) => f.at.effectiveDay.isSameDayAs(today)).length;
    }

    await schedule(habit(slots));
    final none = todayCount();
    final ahead = armed().length;

    notificationCalls.clear();
    await schedule(habit(slots, completedCount: 1));
    expect(todayCount(), none == 0 ? 0 : none - 1,
        reason: 'one done is one of today\'s reminders stood down');
    expect(armed().length, ahead - (none == 0 ? 0 : 1),
        reason: 'the days ahead are untouched');

    notificationCalls.clear();
    await schedule(habit(slots, completedCount: 5));
    expect(todayCount(), 0, reason: 'all five done, nothing left today');
    expect(armed(), isNotEmpty, reason: 'tomorrow is still armed');
  });

  test('no place saved: nothing armed, nothing thrown', () async {
    await NotificationService.instance.scheduleSmartReminders(
      [
        habit([(prayer: 'fajr', offset: -30), (prayer: 'fajr', offset: 30)]),
      ],
      const NotificationSettings(quietHoursEnabled: false),
      isAr: true,
    );
    expect(armed(), isEmpty);
  });
}
