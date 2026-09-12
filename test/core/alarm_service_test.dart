// The Dart end of the AlarmKit bridge (lib/core/services/alarm_service.dart),
// against a mocked channel.
//
// What is pinned: the platform gate (iOS only, everything else answers
// false without touching the channel), the argument shape the native bridge
// parses, and the promise every scheduler relies on, that a failure of any
// kind comes back as false rather than a throw, so the notification fallback
// always runs.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/services/alarm_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.growdaily.v2/alarm');
  late List<MethodCall> calls;
  late Map<String, Object?> answers;

  setUp(() {
    calls = <MethodCall>[];
    answers = <String, Object?>{
      'isSupported': true,
      'authorizationState': 'authorized',
      'requestAuthorization': true,
      'schedule': true,
      'cancel': null,
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      final answer = answers[call.method];
      if (answer is Exception) throw answer;
      return answer;
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  // The singleton caches support per process; the tests below that need a
  // fresh answer run on iOS first, where the cache is filled with true.
  test('schedule sends the shape the native bridge parses', () async {
    final ok = await AlarmService.instance.schedule(
      id: 5123,
      fireAt: DateTime(2026, 9, 7, 4, 30),
      title: 'صلاة الفجر',
      subtitle: 'باقي ١٠ دقائق',
      kind: 'habit',
      targetId: 'fajr_prayer',
      stopLabel: 'إيقاف',
    );
    expect(ok, isTrue);
    final call = calls.singleWhere((c) => c.method == 'schedule');
    expect(call.arguments, {
      'id': 5123,
      'fireAtMs': DateTime(2026, 9, 7, 4, 30).millisecondsSinceEpoch,
      'title': 'صلاة الفجر',
      'subtitle': 'باقي ١٠ دقائق',
      'kind': 'habit',
      'targetId': 'fajr_prayer',
      'stopLabel': 'إيقاف',
    });
  });

  // The habit above sends no doneLabel key at all (the map is compared
  // whole), which is what keeps a habit alarm to Stop alone.
  test('a task alarm sends its Done label to the bridge', () async {
    await AlarmService.instance.schedule(
      id: 6123,
      fireAt: DateTime(2026, 9, 7, 16),
      title: 'اتصل بأمي',
      kind: 'task',
      targetId: 'task-1',
      doneLabel: 'خلّصت المهمة',
      stopLabel: 'إيقاف',
    );
    final call = calls.singleWhere((c) => c.method == 'schedule');
    expect((call.arguments as Map)['doneLabel'], 'خلّصت المهمة');
  });

  test('a native refusal or error is a false, never a throw', () async {
    answers['schedule'] = false;
    expect(
      await AlarmService.instance.schedule(
        id: 1,
        fireAt: DateTime(2030),
        title: 't',
        kind: 'task',
        targetId: 'x',
        stopLabel: 'Stop',
      ),
      isFalse,
    );
    answers['schedule'] = PlatformException(code: 'boom');
    expect(
      await AlarmService.instance.schedule(
        id: 1,
        fireAt: DateTime(2030),
        title: 't',
        kind: 'task',
        targetId: 'x',
        stopLabel: 'Stop',
      ),
      isFalse,
      reason: 'the scheduler falls back to a notification on false',
    );
  });

  test('cancel passes the slot id and swallows failures', () async {
    await AlarmService.instance.cancel(6001);
    expect(calls.single.method, 'cancel');
    expect(calls.single.arguments, {'id': 6001});
    answers['cancel'] = PlatformException(code: 'boom');
    await AlarmService.instance.cancel(6001);
  });

  test('isAuthorized is asked fresh each time, unlike support', () async {
    expect(await AlarmService.instance.isAuthorized(), isTrue);
    answers['authorizationState'] = 'denied';
    expect(await AlarmService.instance.isAuthorized(), isFalse,
        reason: 'the person can withdraw the grant in Settings at any time');
    expect(calls.where((c) => c.method == 'isSupported').length, 0,
        reason: 'support was cached by the earlier tests in this process');
  });

  test('requestPermission reports the sheet answer', () async {
    expect(await AlarmService.instance.requestPermission(), isTrue);
    answers['requestAuthorization'] = false;
    expect(await AlarmService.instance.requestPermission(), isFalse);
  });

  test('a foreground ring from the native side reaches the listener', () async {
    final rang = <int>[];
    AlarmService.instance.onForegroundAlarm = rang.add;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // The native bridge calls INTO Dart on the same channel.
    await messenger.handlePlatformMessage(
      'com.growdaily.v2/alarm',
      const StandardMethodCodec().encodeMethodCall(const MethodCall(
        'alarmAlertingInForeground',
        {'id': 5123, 'alarmId': '47524F57-4441-494C-5900-000000001403'},
      )),
      (_) {},
    );
    expect(rang, [5123]);
    AlarmService.instance.onForegroundAlarm = null;
  });

  test('remembers what a slot was scheduled with until it is cancelled',
      () async {
    await AlarmService.instance.schedule(
      id: 7001,
      fireAt: DateTime(2030),
      title: 'قرآن',
      subtitle: 'باقي ٥ دقائق',
      kind: 'habit',
      targetId: 'quran',
      stopLabel: 'إيقاف',
    );
    final known = AlarmService.instance.scheduledFor(7001);
    expect(known?.title, 'قرآن');
    expect(known?.subtitle, 'باقي ٥ دقائق');
    expect(known?.kind, 'habit');
    expect(known?.targetId, 'quran');
    await AlarmService.instance.cancel(7001);
    expect(AlarmService.instance.scheduledFor(7001), isNull);
  });

  group('off iOS', () {
    test('Android needs no permission for its alarm channel', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(await AlarmService.instance.requestPermission(), isTrue);
      expect(await AlarmService.instance.isSupported(), isFalse,
          reason: 'no AlarmKit there; NotificationService builds the '
              'alarm-style notification itself');
      expect(await AlarmService.instance.schedule(
            id: 1,
            fireAt: DateTime(2030),
            title: 't',
            kind: 'task',
            targetId: 'x',
            stopLabel: 'Stop',
          ),
          isFalse);
      expect(calls, isEmpty, reason: 'the channel is never touched');
    });
  });
}
