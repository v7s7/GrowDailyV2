// A habit ticked in the app takes today's reminder down at once, however much
// other reminder work is still queued.
//
// Seen 2026-09-22 on Aziz's phone: «صلاة الضحى» was ticked at 09:25 and its
// «باقي ٤٥ دقيقة على أذان الظهر» reminder still rang at 10:47. The tick did
// ask for the stand-down: the dashboard change recomputes, and a pass that
// sees the habit done drops today's copy. But every schedule and cancel runs
// in one lane, and that pass joined the END of it: behind the pass the app's
// own opening had started, and behind the task sweep every recompute queues
// (each task that ever had a reminder sweeps 8 slots in two systems; his
// account had 39 done ones, over 600 channel calls a recompute). iOS suspends
// an app seconds after it leaves the screen, so a tick made just after
// opening, followed by locking the phone, left the stand-down queued in a
// frozen process until the next open, and the reminder rang.
//
// These drive the real service against channels that take a little time per
// call, the way the device's do, and look at what the system still holds a
// moment after the tick.
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
  const alarmChannel = MethodChannel('com.growdaily.v2/alarm');
  const notificationsChannel =
      MethodChannel('dexterous.com/flutter/local_notifications');
  const timezoneChannel = MethodChannel('flutter_timezone');
  const backgroundTimeChannel =
      MethodChannel('com.growdaily.v2/background_time');

  // Every channel call takes this long, as a platform call does. Small, so
  // the file stays quick; the backlog below is what makes it add up.
  const perCall = Duration(milliseconds: 2);

  // What the notification system holds: id -> (when it fires, whose it is).
  late Map<int, ({tz.TZDateTime at, String payload})> pending;
  // Both channels in call order, plus the markers the tests drop in.
  late List<String> trace;
  // Makes the next notification cancel fail, as a platform call can.
  late bool failNextCancel;

  setUpAll(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Bahrain'));
    IOSFlutterLocalNotificationsPlugin.registerWith();
  });

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    pending = {};
    trace = [];
    failNextCancel = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // Alarms supported, as on iOS 26, so every task slot's sweep costs an
    // AlarmKit call beside the notification one, exactly as on the phone.
    // No habit here rings as an alarm.
    messenger.setMockMethodCallHandler(alarmChannel, (call) async {
      await Future<void>.delayed(perCall);
      trace.add('alarm:${call.method}');
      switch (call.method) {
        case 'isSupported':
        case 'schedule':
          return true;
        case 'reapOrphans':
          return 0;
        case 'syncWindow':
          return <String, int>{'scheduled': 0, 'kept': 0, 'cancelled': 0};
      }
      return null;
    });
    messenger.setMockMethodCallHandler(notificationsChannel, (call) async {
      await Future<void>.delayed(perCall);
      switch (call.method) {
        case 'zonedSchedule':
          final a = call.arguments as Map;
          final id = a['id'] as int;
          final payload = a['payload'] as String? ?? '';
          pending[id] = (
            at: tz.TZDateTime.parse(tz.local, a['scheduledDateTime'] as String),
            payload: payload,
          );
          trace.add('schedule:$payload');
          return null;
        case 'cancel':
          if (failNextCancel) {
            failNextCancel = false;
            throw PlatformException(code: 'cancel-failed');
          }
          pending.remove(call.arguments as int);
          trace.add('cancel:${call.arguments}');
          return null;
        case 'pendingNotificationRequests':
          return [
            for (final e in pending.entries)
              {
                'id': e.key,
                'title': '',
                'body': '',
                'payload': e.value.payload,
              },
          ];
        case 'getActiveNotifications':
          return const <Map<String, Object?>>[];
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
      timezoneChannel,
      (call) async => 'Asia/Bahrain',
    );
    messenger.setMockMethodCallHandler(backgroundTimeChannel, (call) async {
      trace.add('background:${call.method}');
      return null;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(alarmChannel, null);
    messenger.setMockMethodCallHandler(notificationsChannel, null);
    messenger.setMockMethodCallHandler(timezoneChannel, null);
    messenger.setMockMethodCallHandler(backgroundTimeChannel, null);
  });

  HabitReminderInput habit(String id, TimeOfDay at, {int done = 0}) => (
        id: id,
        name: id,
        clockTimes: [at],
        clockOffsets: const [0],
        remindersPerOccurrence: 1,
        extraReminderOffsets: const [],
        prayerKey: null,
        streak: 0,
        completedCount: done,
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

  // Bundling off so every habit keeps its own id and the tests can name
  // which copy is which.
  const settings =
      NotificationSettings(quietHoursEnabled: false, bundleEnabled: false);
  final service = NotificationService.instance;

  // A moment later today, or null in the last minutes of the day, when there
  // is no "later today" left to arm a copy for.
  TimeOfDay? laterToday() {
    final now = tz.TZDateTime.now(tz.local);
    final soon = now.add(const Duration(minutes: 5));
    if (soon.day != now.day) return null;
    return TimeOfDay(hour: soon.hour, minute: soon.minute);
  }

  // Ten more habits, so a pass has real work in it the way an account does,
  // each on its own hour so none of them is due at the ticked habit's time.
  List<HabitReminderInput> others(TimeOfDay from) => [
        for (var i = 1; i <= 10; i++)
          habit(
            'other-$i',
            TimeOfDay(hour: (from.hour + i) % 24, minute: from.minute),
          ),
      ];

  // What a recompute queues for tasks: one sweep per task that ever carried
  // a reminder, done ones included (MatrixNotifier._resyncAllReminders).
  List<Future<void>> queueTaskSweep(int tasks) => [
        for (var i = 0; i < tasks; i++)
          service.cancelTaskReminder('done-task-$i'),
      ];

  test(
      'a habit ticked while the app is still re-arming loses today\'s '
      'reminder at once, not after the queue behind it', () async {
    final at = laterToday();
    if (at == null) {
      markTestSkipped('needs a few minutes of today left');
      return;
    }
    final rest = others(at);

    // The evening before: today's copy of the habit is armed.
    await service.scheduleSmartReminders(
      [...rest, habit('duha', at)],
      settings,
      isAr: true,
    );
    final today = tz.TZDateTime.now(tz.local);
    final todayCopy = pending.entries
        .where(
          (e) =>
              e.value.payload == 'duha' &&
              e.value.at.day == today.day &&
              e.value.at.hour == at.hour &&
              e.value.at.minute == at.minute,
        )
        .map((e) => e.key)
        .toList();
    expect(todayCopy, hasLength(1), reason: 'today\'s copy is armed');

    // The app opens: its pass starts, and the recompute queues the task
    // sweep behind it.
    final opening = service.scheduleSmartReminders(
      [...rest, habit('duha', at)],
      settings,
      isAr: true,
    );
    final sweep = queueTaskSweep(40);

    // Ticked a moment later.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final tick = service.scheduleSmartReminders(
      [...rest, habit('duha', at, done: 1)],
      settings,
      isAr: true,
    );

    // The phone is locked a moment after that, and iOS freezes the app.
    // Whatever the system holds now is what rings.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(
      pending.containsKey(todayCopy.single),
      isFalse,
      reason: 'the habit is done: today\'s reminder must be gone before the '
          'app can be suspended, not after 40 task sweeps (640 channel '
          'calls) and the rest of the opening pass',
    );

    await Future.wait([opening, tick, ...sweep]);
    expect(
      pending.containsKey(todayCopy.single),
      isFalse,
      reason: 'and nothing that ran afterwards armed it again',
    );
    expect(
      pending.values.where((p) => p.payload == 'duha'),
      hasLength(NotificationService.kOccurrencesPerSlot - 1),
      reason: 'only today stands down; the days after it stay armed',
    );
  });

  test('a running habit pass gives way to a newer one at its next safe point',
      () async {
    final at = laterToday() ?? const TimeOfDay(hour: 12, minute: 0);
    final stale = [
      for (var i = 0; i < 6; i++)
        habit('stale-$i', TimeOfDay(hour: (at.hour + i) % 24, minute: 7)),
    ];
    final fresh = [
      for (var i = 0; i < 6; i++)
        habit('fresh-$i', TimeOfDay(hour: (at.hour + i) % 24, minute: 9)),
    ];

    final older = service.scheduleSmartReminders(stale, settings, isAr: true);
    // Let the older pass get well into arming.
    while (!trace.any((t) => t.startsWith('schedule:stale-'))) {
      await Future<void>.delayed(perCall);
    }
    trace.add('-- newer pass requested --');
    final newer = service.scheduleSmartReminders(fresh, settings, isAr: true);
    await Future.wait([older, newer]);

    final after = trace.indexOf('-- newer pass requested --');
    final staleAfter =
        trace.skip(after).where((t) => t.startsWith('schedule:stale-')).length;
    expect(
      staleAfter,
      lessThanOrEqualTo(1),
      reason: 'the older pass may finish the one reminder it was arming, '
          'then stops: its habit list is out of date',
    );
    expect(
      pending.values.where((p) => p.payload.startsWith('stale-')),
      isEmpty,
      reason: 'what the older pass armed before giving way is swept by the '
          'newer one, whose list no longer has those habits',
    );
    expect(
      pending.values.where((p) => p.payload.startsWith('fresh-')),
      hasLength(fresh.length * NotificationService.kOccurrencesPerSlot),
      reason: 'the newer pass arms its whole window',
    );
  });

  test('a habit pass does not wait behind queued task work', () async {
    final at = laterToday() ?? const TimeOfDay(hour: 12, minute: 0);
    final sweep = queueTaskSweep(40);
    final pass = service
        .scheduleSmartReminders([habit('solo', at)], settings, isAr: true);
    await Future.wait([pass, ...sweep]);
    // Task reminders live in 10000..59999, clear of every habit band.
    bool isTaskCancel(String t) {
      final id = int.tryParse(t.replaceFirst('cancel:', ''));
      return t.startsWith('cancel:') && id != null && id >= 10000 && id < 60000;
    }

    final firstArm = trace.indexWhere((t) => t == 'schedule:solo');
    final lastTaskCancel = trace.lastIndexWhere(isTaskCancel);
    expect(firstArm, isNonNegative);
    expect(lastTaskCancel, isNonNegative);
    expect(
      firstArm,
      lessThan(lastTaskCancel),
      reason: 'the habit pass runs ahead of the task sweep queued before '
          'it; that sweep changes nothing a reminder is waiting on',
    );
  });

  test(
      'a job that fails leaves the lane running, stays quiet when nobody '
      'awaits it, and still reaches a caller that does', () async {
    // Not awaited, the way main.dart fires its recompute. An error nobody
    // handles would fail this test on its own.
    failNextCancel = true;
    // ignore: unawaited_futures
    service.cancelTaskReminder('fails-unheard');
    await service.cancelTaskReminder('runs-next');
    expect(
      trace.where((t) => t.startsWith('cancel:')),
      hasLength(NotificationService.kMaxTaskReminderSlots),
      reason: 'the failed job stopped at its first cancel, and the next '
          'job ran whole behind it',
    );

    failNextCancel = true;
    await expectLater(
      service.cancelTaskReminder('fails-awaited'),
      throwsA(isA<PlatformException>()),
    );
  });

  test(
      'the lane holds background time from its first job until it is empty, '
      'so leaving the app cannot freeze a stand-down halfway', () async {
    // Measured on the simulator: the app was suspended about a second after
    // Home, before the pass carrying a tick's stand-down had run.
    final jobs = [
      service.cancelTaskReminder('a'),
      service.cancelTaskReminder('b'),
      service.cancelTaskReminder('c'),
    ];
    await Future.wait(jobs);
    final begins = [
      for (var i = 0; i < trace.length; i++)
        if (trace[i] == 'background:begin') i,
    ];
    final ends = [
      for (var i = 0; i < trace.length; i++)
        if (trace[i] == 'background:end') i,
    ];
    final cancels = [
      for (var i = 0; i < trace.length; i++)
        if (trace[i].startsWith('cancel:')) i,
    ];
    expect(begins, hasLength(1), reason: 'one hold for the whole backlog');
    expect(ends, hasLength(1), reason: 'given back once, when it is empty');
    expect(
      begins.single,
      lessThan(cancels.first),
      reason: 'held before the first job touches the system',
    );
    expect(
      ends.single,
      greaterThan(cancels.last),
      reason: 'kept until the last job is done',
    );

    trace.clear();
    await service.cancelTaskReminder('d');
    expect(
      trace.first,
      'background:begin',
      reason: 'new work after an empty lane asks again',
    );
    expect(trace.last, 'background:end');
  });
}
