// The adhan alarms (Settings › موقع الصلاة, «منبّه الأذان», Aziz 2026-10-03),
// through NotificationService's reminder pass, against mocked channels.
//
// Pins: nothing is asked of the phone until a prayer is turned on; then each
// chosen prayer rings on each of the next two weeks at that day's own
// official minute, in its own id band, with Stop only; switching off or
// clearing the place empties the band; no permission arms nothing and asks
// nothing; on Android the same alarms go out on the alarm channel as alarm
// clocks, and a pass with nothing changed re-arms nothing. The choice itself
// is saved with the settings, empty unless chosen, and written even when
// empty so the account copy follows.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
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

NotificationSettings _settings(Set<String> alarms, {bool place = true}) =>
    NotificationSettings(
      location: place ? _manama : null,
      resolvedCountryCode: place ? 'BH' : null,
      prayerAlarms: alarms,
    );

/// The pass main.dart runs, with no habits: the adhan alarms ride it.
Future<void> _pass(NotificationSettings settings, {bool isAr = true}) =>
    NotificationService.instance
        .scheduleSmartReminders(const [], settings, isAr: isAr);

/// Each official [key] moment of the next two weeks still ahead of now.
List<tz.TZDateTime> _officialAhead(String key) {
  final now = tz.TZDateTime.now(tz.local);
  return [
    for (var i = 0; i < NotificationService.kPrayerAlarmDays; i++)
      if (BahrainPrayerTable.lookup(DateTime(now.year, now.month, now.day + i))!
              .forKey(key)
          case final at? when at.isAfter(now))
        at,
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const alarmChannel = MethodChannel('com.growdaily.v2/alarm');
  const notificationsChannel =
      MethodChannel('dexterous.com/flutter/local_notifications');
  const timezoneChannel = MethodChannel('flutter_timezone');

  late List<MethodCall> alarmCalls;
  late List<MethodCall> notificationCalls;
  late String authorization;
  // Android's pending list, as the plugin keeps it: id -> payload.
  late Map<int, String> pending;

  setUpAll(() async {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Bahrain'));
    await BahrainPrayerTable.ensureLoaded();
  });

  setUp(() {
    alarmCalls = [];
    notificationCalls = [];
    authorization = 'authorized';
    pending = {};
    PrayerTimesService.resetMonthCache();
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
      final args = call.arguments;
      switch (call.method) {
        case 'zonedSchedule':
          final map = args as Map;
          pending[map['id'] as int] = map['payload'] as String;
        case 'cancel':
          pending.remove(args is Map ? args['id'] : args);
        case 'pendingNotificationRequests':
          return [
            for (final e in pending.entries)
              {'id': e.key, 'title': '', 'body': '', 'payload': e.value},
          ];
        case 'initialize':
          return true;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
      timezoneChannel,
      (call) async => 'Asia/Bahrain',
    );
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

  group('the choice', () {
    test('is empty unless chosen, and survives a save', () {
      expect(const NotificationSettings().prayerAlarms, isEmpty);
      final saved = _settings({'isha', 'fajr'}).toMap();
      expect(
        saved['prayerAlarms'],
        ['fajr', 'isha'],
        reason: "written in the day's order",
      );
      expect(
        NotificationSettings.fromMap(saved).prayerAlarms,
        {'fajr', 'isha'},
      );
    });

    test('is written even when empty, so the account copy follows', () {
      expect(_settings(const {}).toMap()['prayerAlarms'], isEmpty);
      expect(_settings(const {}).toMap().containsKey('prayerAlarms'), isTrue);
    });

    test('reads only the five prayers, and nothing from an older copy', () {
      expect(
        NotificationSettings.fromMap({
          'prayerAlarms': ['fajr', 'sunrise', 'duha', 7],
        }).prayerAlarms,
        {'fajr'},
      );
      expect(NotificationSettings.fromMap(const {}).prayerAlarms, isEmpty);
    });
  });

  group('on iOS', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      IOSFlutterLocalNotificationsPlugin.registerWith();
    });
    // Leaves nothing armed for the next test, which also starts it from
    // "nothing asked of the phone".
    tearDown(() => _pass(_settings(const {})));

    Iterable<Map> bandSyncs() => alarmCalls
        .where((c) => c.method == 'syncWindow')
        .map((c) => c.arguments as Map)
        .where((a) => a['lowId'] == 700000);

    test('with none turned on, the phone is asked nothing', () async {
      await _pass(_settings(const {}));
      expect(bandSyncs(), isEmpty);
      expect(
        alarmCalls.where((c) => c.method == 'authorizationState'),
        isEmpty,
      );
    });

    test('Fajr on: two weeks of Fajr, each on its own day\'s official minute',
        () async {
      await _pass(_settings({'fajr'}));
      final sync = bandSyncs().single;
      expect(sync['highId'], 700999);
      final alarms = (sync['alarms'] as List).cast<Map>();
      final expected = _officialAhead('fajr');
      expect(
        [for (final a in alarms) a['fireAtMs']],
        [for (final at in expected) at.millisecondsSinceEpoch],
      );
      expect(expected.length, greaterThanOrEqualTo(13));
      for (final a in alarms) {
        expect(a['title'], 'أذان الفجر');
        expect(a['subtitle'], isNull);
        expect(a['kind'], 'prayer');
        expect(a['targetId'], 'fajr');
        expect(a['stopLabel'], 'إيقاف');
        expect(a.containsKey('doneLabel'), isFalse, reason: 'Stop only');
      }
      expect(
        {for (final a in alarms) a['id']},
        hasLength(alarms.length),
        reason: 'one id a day',
      );
      for (var i = 0; i < alarms.length; i++) {
        expect(
          alarms[i]['id'],
          NotificationService.prayerAlarmId(expected[i], 'fajr'),
        );
      }
    });

    test('all five: each prayer at its own minute, soonest first', () async {
      await _pass(_settings({...kPrayerAlarmKeys}), isAr: false);
      final alarms = (bandSyncs().single['alarms'] as List).cast<Map>();
      for (final key in kPrayerAlarmKeys) {
        expect(
          [
            for (final a in alarms)
              if (a['targetId'] == key) a['fireAtMs'],
          ],
          [for (final at in _officialAhead(key)) at.millisecondsSinceEpoch],
          reason: key,
        );
      }
      final times = [for (final a in alarms) a['fireAtMs'] as int];
      expect(times, [...times]..sort());
      expect({
        for (final a in alarms) a['title'],
      }, {
        'Fajr adhan',
        'Dhuhr adhan',
        'Asr adhan',
        'Maghrib adhan',
        'Isha adhan',
      });
    });

    test('switched off, the band is emptied', () async {
      await _pass(_settings({'fajr', 'maghrib'}));
      alarmCalls.clear();
      await _pass(_settings(const {}));
      expect(bandSyncs().single['alarms'], isEmpty);
      // And from then on nothing is asked again.
      alarmCalls.clear();
      await _pass(_settings(const {}));
      expect(bandSyncs(), isEmpty);
    });

    test('a place cleared empties it too', () async {
      await _pass(_settings({'isha'}));
      alarmCalls.clear();
      await _pass(_settings({'isha'}, place: false));
      expect(bandSyncs().single['alarms'], isEmpty);
    });

    test('without the alarm permission nothing is armed, and nothing asked',
        () async {
      authorization = 'notDetermined';
      await _pass(_settings({'fajr'}));
      expect(bandSyncs(), isEmpty);
      expect(
        alarmCalls.where((c) => c.method == 'requestAuthorization'),
        isEmpty,
        reason: 'the switch asks, never a pass in the background',
      );
    });
  });

  group('on Android', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
    });
    tearDown(() => _pass(_settings(const {})));

    Iterable<Map> schedules() => notificationCalls
        .where((c) => c.method == 'zonedSchedule')
        .map((c) => c.arguments as Map)
        .where((a) => (a['id'] as int) >= 700000);

    test('rings as an alarm clock on the alarm channel', () async {
      await _pass(_settings({'fajr'}));
      final armed = schedules().toList();
      expect(armed, hasLength(_officialAhead('fajr').length));
      for (final a in armed) {
        expect(a['title'], 'أذان الفجر');
        final platform = a['platformSpecifics'] as Map;
        expect(platform['channelId'], 'growdaily_alarm');
        expect(platform['scheduleMode'], 'alarmClock');
        expect(a['payload'] as String, startsWith('alarm:prayer:ar:'));
      }
      expect(
        alarmCalls.where((c) => c.method == 'syncWindow'),
        isEmpty,
        reason: 'no AlarmKit on Android',
      );
    });

    test('a pass with nothing changed re-arms nothing', () async {
      await _pass(_settings({'fajr', 'asr'}));
      final before = Map.of(pending);
      notificationCalls.clear();
      await _pass(_settings({'fajr', 'asr'}));
      expect(schedules(), isEmpty);
      expect(pending, before);
    });

    test('a new language re-words every one', () async {
      await _pass(_settings({'dhuhr'}));
      notificationCalls.clear();
      await _pass(_settings({'dhuhr'}), isAr: false);
      expect(schedules(), hasLength(_officialAhead('dhuhr').length));
      expect({for (final a in schedules()) a['title']}, {'Dhuhr adhan'});
    });

    test('one prayer switched off takes only its own alarms', () async {
      await _pass(_settings({'fajr', 'isha'}));
      await _pass(_settings({'fajr'}));
      final left = pending.keys.where((id) => id >= 700000).toSet();
      expect(left, {
        for (final at in _officialAhead('fajr'))
          NotificationService.prayerAlarmId(at, 'fajr'),
      });
    });
  });
}
