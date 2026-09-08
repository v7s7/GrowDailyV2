// The window of days a habit's reminders are armed for.
//
// A slot used to hold exactly ONE pending notification: the next time it
// came round. That left a hole a person could fall through without ever
// noticing the app had gone quiet — the phone is not opened tomorrow, the
// one armed reminder fires and is gone, and nothing re-arms until the app
// is opened again. NotificationService.kOccurrencesPerSlot days are now
// armed at once.
//
// For a prayer-anchored habit that is only worth anything if each day in
// the window reads its OWN prayer times. "Fifteen minutes before Fajr" is
// 03:46 on one September morning and 04:01 a month later; four copies of
// one frozen moment would be four reminders drifting away from the prayer
// they name. Bahrain's bundled official table is the oracle here, so these
// run offline and to the minute.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
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
    // No alarms in this file: every habit here is a plain notification, so
    // the alarm channel only ever says "not supported".
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

  /// Every scheduled notification, as (id, when).
  List<({int id, tz.TZDateTime at})> armed() => [
        for (final call in notificationCalls)
          if (call.method == 'zonedSchedule')
            (
              id: (call.arguments as Map)['id'] as int,
              at: tz.TZDateTime.parse(
                tz.local,
                (call.arguments as Map)['scheduledDateTime'] as String,
              ),
            ),
      ];

  HabitReminderInput habit({
    String id = 'fajr-habit',
    String? prayerKey = 'fajr',
    List<TimeOfDay> clockTimes = const [],
    List<int> clockOffsets = const [],
    int reminderOffsetMinutes = -15,
    int completedCount = 0,
    Set<int> scheduledWeekdays = const {},
  }) =>
      (
        id: id,
        name: id,
        clockTimes: clockTimes,
        clockOffsets: clockOffsets,
        remindersPerOccurrence: 1,
        extraReminderOffsets: const [],
        prayerKey: prayerKey,
        streak: 0,
        completedCount: completedCount,
        dailyTarget: 1,
        lastDoneDaysAgo: null,
        timerSeconds: null,
        reminderOffsetMinutes: reminderOffsetMinutes,
        ignoreQuietHours: true,
        isQuit: false,
        isLimit: false,
        alarm: false,
        scheduledWeekdays: scheduledWeekdays,
        anchorLabel: 'الفجر',
        weekTarget: null,
        weekDoneDays: null,
      );

  const settings = NotificationSettings(
    quietHoursEnabled: false,
    location: _manama,
    resolvedCountryCode: 'BH',
  );

  group('a prayer-anchored habit', () {
    test('arms several mornings, each at ITS OWN day\'s Fajr', () async {
      await NotificationService.instance
          .scheduleSmartReminders([habit()], settings, isAr: true);

      final fires = armed()..sort((a, b) => a.at.compareTo(b.at));
      expect(fires, hasLength(NotificationService.kOccurrencesPerSlot),
          reason: 'one per day of the window');

      final now = tz.TZDateTime.now(tz.local);
      for (final f in fires) {
        expect(f.at.isAfter(now), isTrue, reason: 'nothing armed in the past');
        final official = BahrainPrayerTable.lookup(
          DateTime(f.at.year, f.at.month, f.at.day),
        );
        expect(official, isNotNull,
            reason: 'the bundled table covers this window');
        expect(
          f.at,
          official!.fajr.subtract(const Duration(minutes: 15)),
          reason: 'each morning is fifteen minutes before THAT morning\'s '
              'Fajr, not before the first one in the window',
        );
      }

      // Consecutive days, one apiece.
      final days = fires.map((f) => f.at.day).toList();
      expect(days.toSet(), hasLength(days.length),
          reason: 'one reminder per day, never two on the same morning');
    });

    test('the armed times are not all the same clock time', () async {
      await NotificationService.instance
          .scheduleSmartReminders([habit()], settings, isAr: true);
      final clockTimes =
          armed().map((f) => '${f.at.hour}:${f.at.minute}').toSet();
      expect(clockTimes.length, greaterThan(1),
          reason: 'Fajr moves about a minute every other day; a window of '
              'four identical times would be the frozen-schedule bug this '
              'whole mechanism exists to prevent');
    });

    test('depth 0 keeps the id it has always had, the rest get their own',
        () async {
      await NotificationService.instance
          .scheduleSmartReminders([habit()], settings, isAr: true);
      final ids = armed().map((f) => f.id).toList();
      expect(ids.toSet(), hasLength(ids.length), reason: 'no id collides');
      expect(ids.where((id) => id >= 5000 && id < 6000), hasLength(1),
          reason: 'the next occurrence still uses the band every already-'
              'scheduled reminder on an upgrading device is sitting in');
      expect(
        ids.where((id) => id >= 400000 && id < 403000),
        hasLength(NotificationService.kOccurrencesPerSlot - 1),
        reason: 'the days ahead live in bands of their own',
      );
    });

    test('done for today no longer disarms tomorrow morning', () async {
      // The bug this fixes: complete a Fajr habit after Fajr and the one
      // thing armed was TOMORROW's reminder — which completing today then
      // cancelled, leaving nothing until the app was next opened.
      await NotificationService.instance.scheduleSmartReminders(
        [habit(completedCount: 1)],
        settings,
        isAr: true,
      );
      final now = tz.TZDateTime.now(tz.local);
      final fires = armed();
      expect(fires, isNotEmpty,
          reason: 'a finished habit still has the following days to remind '
              'about');
      for (final f in fires) {
        expect(
          f.at.effectiveDay.isSameDayAs(now.effectiveDay),
          isFalse,
          reason: "today's own reminder is the only thing standing down",
        );
      }
    });

    test('a habit pinned to weekdays only lands on those days', () async {
      const sunTueThu = {DateTime.sunday, DateTime.tuesday, DateTime.thursday};
      await NotificationService.instance.scheduleSmartReminders(
        [habit(scheduledWeekdays: sunTueThu)],
        settings,
        isAr: true,
      );
      final fires = armed();
      expect(fires, hasLength(NotificationService.kOccurrencesPerSlot));
      for (final f in fires) {
        expect(sunTueThu, contains(f.at.effectiveDay.weekday));
      }
    });
  });

  group('a clock habit', () {
    test('arms the same window, rebuilt from each day\'s wall clock',
        () async {
      await NotificationService.instance.scheduleSmartReminders(
        [
          habit(
            id: 'water',
            prayerKey: null,
            clockTimes: const [TimeOfDay(hour: 20, minute: 0)],
            clockOffsets: const [0],
            reminderOffsetMinutes: 0,
          ),
        ],
        settings,
        isAr: false,
      );
      final fires = armed()..sort((a, b) => a.at.compareTo(b.at));
      expect(fires, hasLength(NotificationService.kOccurrencesPerSlot));
      for (final f in fires) {
        expect(f.at.hour, 20);
        expect(f.at.minute, 0);
      }
      for (var i = 1; i < fires.length; i++) {
        expect(fires[i].at.difference(fires[i - 1].at).inDays, 1,
            reason: 'consecutive evenings');
      }
    });
  });

  group('resolveClockOccurrences', () {
    tz.TZDateTime at(int hour, int minute, {int day = 16}) =>
        tz.TZDateTime(tz.local, 2026, 3, day, hour, minute);

    test('depth 0 is exactly what the single-occurrence resolver returns',
        () {
      final one = NotificationService.resolveClockSlots(
        const [TimeOfDay(hour: 20, minute: 0)],
        const [0],
        at(21, 0),
      );
      final many = NotificationService.resolveClockOccurrences(
        const [TimeOfDay(hour: 20, minute: 0)],
        const [0],
        at(21, 0),
        occurrences: 4,
      );
      expect(many.where((o) => o.depth == 0).single.fireTime,
          one.single.fireTime);
      expect(many, hasLength(4));
      expect(
        many.map((o) => o.fireTime),
        [at(20, 0, day: 17), at(20, 0, day: 18), at(20, 0, day: 19),
          at(20, 0, day: 20)],
      );
    });

    test('a weekday-restricted habit skips the days it does not run', () {
      // 2026-03-16 is a Monday.
      const sunTueThu = {DateTime.sunday, DateTime.tuesday, DateTime.thursday};
      final out = NotificationService.resolveClockOccurrences(
        const [TimeOfDay(hour: 20, minute: 0)],
        const [0],
        at(21, 0),
        scheduledWeekdays: sunTueThu,
        occurrences: 3,
      );
      expect(out.map((o) => o.fireTime.weekday),
          [DateTime.tuesday, DateTime.thursday, DateTime.sunday]);
    });

    test('every slot of a multi-time habit gets its own window', () {
      final out = NotificationService.resolveClockOccurrences(
        const [TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 20, minute: 0)],
        const [0, 0],
        at(9, 0),
        occurrences: 3,
      );
      expect(out.where((o) => o.slot == 0), hasLength(3));
      expect(out.where((o) => o.slot == 1), hasLength(3));
      expect(out.where((o) => o.slot == 0).map((o) => o.fireTime.hour),
          everyElement(8));
      expect(out.where((o) => o.slot == 1).map((o) => o.fireTime.hour),
          everyElement(20));
    });

    test('a corrupt weekday set still yields one reminder, not none', () {
      final out = NotificationService.resolveClockOccurrences(
        const [TimeOfDay(hour: 20, minute: 0)],
        const [0],
        at(21, 0),
        scheduledWeekdays: const {99},
        occurrences: 4,
      );
      expect(out, hasLength(1));
      expect(out.single.depth, 0);
      expect(out.single.fireTime.isAfter(at(21, 0)), isTrue);
    });
  });
}
