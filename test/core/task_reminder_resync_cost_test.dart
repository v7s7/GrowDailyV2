// One resync of every Matrix task's reminders, which main.dart runs on every
// recompute (two or three per open), and what it costs in platform calls.
//
// It used to cost 16 calls for every task that ever had a reminder, done or
// not: a done task's cancel swept all 8 slots blind in both systems, a
// notification cancel and an AlarmKit cancel each, for reminders that were
// almost never there. Aziz's account on 2026-09-22 had 133 tasks, 41 with
// reminders, 39 of them done, and the resync measured below cost 656 calls
// before the change (328 notification, 328 AlarmKit), all in the one serial
// lane the habit stand-downs share. Now the service reads once what the
// notification system holds and cancels only that, and every task alarm
// goes in one reap over the task band (see TaskReminderResync).
//
// Drives the real MatrixNotifier in guest mode (tasks from Hive, no
// Firestore) against a fake of both systems: the notification plugin's
// pending and delivered lists, and AlarmKit's alarms. A second "device" is
// a rewrite of the stored list followed by a fresh load, which is how a
// change made elsewhere reaches this phone.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/matrix/models/matrix_task.dart';
import 'package:grow_daily_v2/features/matrix/notifiers/matrix_notifier.dart';
import 'package:hive/hive.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import '../helpers/wait_until.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const alarmChannel = MethodChannel('com.growdaily.v2/alarm');
  const notificationsChannel =
      MethodChannel('dexterous.com/flutter/local_notifications');
  const timezoneChannel = MethodChannel('flutter_timezone');

  // Every task slot id lives here (NotificationService._taskReminderBase and
  // _taskReminderRange), clear of every habit band.
  bool inTaskBand(int id) => id >= 10000 && id <= 59999;

  late Directory tmp;
  // The fake systems.
  late Map<int, String> pending; // id -> payload (the task id)
  late Set<int> delivered;
  late Map<int, String> alarms; // id -> targetId (the task id)
  // Every call, per channel, by method.
  late Map<String, int> notifyCalls;
  late Map<String, int> alarmCalls;
  late List<Map> reaps;
  // Notification ids armed, in call order.
  late List<int> armedNotes;

  int total(Map<String, int> m) => m.values.fold(0, (a, b) => a + b);

  setUpAll(() {
    tz_data.initializeTimeZones();
    IOSFlutterLocalNotificationsPlugin.registerWith();
  });

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tmp = await Directory.systemTemp.createTemp('task_resync_cost_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings');
    pending = {};
    delivered = {};
    alarms = {};
    notifyCalls = {};
    alarmCalls = {};
    reaps = [];
    armedNotes = [];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(alarmChannel, (call) async {
      alarmCalls.update(call.method, (n) => n + 1, ifAbsent: () => 1);
      final a = call.arguments;
      switch (call.method) {
        case 'isSupported':
          return true;
        case 'authorizationState':
          return 'authorized';
        case 'schedule':
          final m = a as Map;
          // AlarmKit refuses a moment already past, as the bridge does.
          final at = DateTime.fromMillisecondsSinceEpoch(m['fireAtMs'] as int);
          if (!at.isAfter(DateTime.now())) return false;
          alarms[m['id'] as int] = m['targetId'] as String;
          return true;
        case 'cancel':
          alarms.remove((a as Map)['id'] as int);
          return null;
        case 'reapOrphans':
          final m = a as Map;
          reaps.add(m);
          final low = m['lowId'] as int;
          final high = m['highId'] as int;
          final keep = (m['keepIds'] as List).cast<int>().toSet();
          final gone = alarms.keys
              .where((id) => id >= low && id <= high && !keep.contains(id))
              .toList();
          gone.forEach(alarms.remove);
          return gone.length;
        case 'syncWindow':
          return <String, int>{'scheduled': 0, 'kept': 0, 'cancelled': 0};
      }
      return null;
    });
    messenger.setMockMethodCallHandler(notificationsChannel, (call) async {
      notifyCalls.update(call.method, (n) => n + 1, ifAbsent: () => 1);
      final a = call.arguments;
      switch (call.method) {
        case 'zonedSchedule':
          final m = a as Map;
          final id = m['id'] as int;
          pending[id] = m['payload'] as String? ?? '';
          armedNotes.add(id);
          return null;
        case 'show':
          delivered.add((a as Map)['id'] as int);
          return null;
        case 'cancel':
          // Like the plugin on iOS: pending and delivered both go.
          pending.remove(a as int);
          delivered.remove(a);
          return null;
        case 'pendingNotificationRequests':
          return [
            for (final e in pending.entries)
              {'id': e.key, 'title': '', 'body': '', 'payload': e.value},
          ];
        case 'getActiveNotifications':
          return [
            for (final id in delivered)
              {'id': id, 'title': '', 'body': '', 'payload': ''},
          ];
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
      timezoneChannel,
      (call) async => 'Asia/Bahrain',
    );
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(alarmChannel, null);
    messenger.setMockMethodCallHandler(notificationsChannel, null);
    messenger.setMockMethodCallHandler(timezoneChannel, null);
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  /// Waits until neither channel has been called for a while: the lane has
  /// drained and the bookkeeping writes behind it have settled.
  Future<void> quiesce() async {
    var last = -1;
    var still = 0;
    while (still < 8) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final now = total(notifyCalls) + total(alarmCalls);
      still = now == last ? still + 1 : 0;
      last = now;
    }
  }

  void resetCounts() {
    notifyCalls.clear();
    alarmCalls.clear();
    reaps.clear();
    armedNotes.clear();
  }

  final now = DateTime.now();
  MatrixTask task(
    String id, {
    bool done = false,
    List<DateTime> reminders = const [],
    bool alarm = false,
    int age = 0,
  }) =>
      MatrixTask(
        id: id,
        title: id,
        quadrant: MatrixQuadrant.doFirst,
        isDone: done,
        createdAt: now.subtract(Duration(days: 200 - age)),
        completedAt: done ? now.subtract(const Duration(hours: 1)) : null,
        reminderAts: MatrixTask.normalizeReminders(reminders),
        reminderAnchorAt: reminders.isEmpty ? null : reminders.last,
        alarm: alarm,
        order: age.toDouble(),
      );

  /// Aziz's shape: 133 tasks, 41 with reminders, 39 of them done. The two
  /// open ones: an alarm an hour ahead, and a notification pair tomorrow.
  List<MatrixTask> azizShape() => [
        for (var i = 0; i < 92; i++) task('plain-$i', done: i.isEven, age: i),
        for (var i = 92; i < 131; i++)
          task(
            'done-$i',
            done: true,
            reminders: [now.subtract(Duration(days: 131 - i, hours: 3))],
            alarm: i % 4 == 0,
            age: i,
          ),
        task(
          'open-alarm',
          reminders: [now.add(const Duration(hours: 1))],
          alarm: true,
          age: 131,
        ),
        task(
          'open-pair',
          reminders: [
            now.add(const Duration(days: 1)),
            now.add(const Duration(days: 1, minutes: 30)),
          ],
          age: 132,
        ),
      ];

  Future<void> store(List<MatrixTask> tasks) =>
      Hive.box<dynamic>('box_settings').put(
        LocalStoreService.guestMatrixTasksKey,
        tasks.map((t) => t.toMap()).toList(),
      );

  Future<ProviderContainer> guest() async {
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
      ],
    );
    await container.read(authStateProvider.future);
    return container;
  }

  /// Stores [tasks], then opens the app on them: the load and its resync.
  Future<ProviderContainer> openOn(List<MatrixTask> tasks) async {
    await store(tasks);
    final container = await guest();
    container.read(matrixProvider);
    await waitUntil(
      () => !container.read(matrixProvider).isLoading,
      describe: 'the guest tasks to load',
    );
    await quiesce();
    return container;
  }

  Set<String> pendingFor() => pending.entries
      .where((e) => inTaskBand(e.key))
      .map((e) => e.value)
      .toSet();
  Set<String> alarmsFor() => alarms.entries
      .where((e) => inTaskBand(e.key))
      .map((e) => e.value)
      .toSet();

  test(
      'one resync on an account shaped like Aziz\'s costs six platform calls, '
      'not 656, and leaves exactly the same reminders armed', () async {
    final container = await openOn(azizShape());
    final pendingBefore = Map.of(pending);
    final alarmsBefore = Map.of(alarms);
    resetCounts();

    container.read(matrixProvider.notifier).resyncReminders();
    await quiesce();

    expect(notifyCalls, {
      'pendingNotificationRequests': 1,
      'getActiveNotifications': 1,
      'zonedSchedule': 2,
    }, reason: 'one read of what the system holds, and the open pair '
        're-armed; the 39 done tasks hold nothing, so nothing is cancelled');
    expect(alarmCalls, {'schedule': 1, 'reapOrphans': 1},
        reason: 'the open alarm re-armed, and every other task alarm judged '
            'in one reap instead of 8 cancels per task');
    expect(total(notifyCalls) + total(alarmCalls), 6);

    expect(pending, pendingBefore);
    expect(alarms, alarmsBefore);
    expect(pendingFor(), {'open-pair'});
    expect(alarmsFor(), {'open-alarm'});
    expect(reaps.single['lowId'], 10000);
    expect(reaps.single['highId'], 59999);
    container.dispose();
  });

  test(
      'a task finished on another device loses every reminder this phone '
      'armed for it, pending, delivered and alarm', () async {
    final alarmTask = task(
      'errand',
      reminders: [
        now.add(const Duration(hours: 1)),
        now.add(const Duration(hours: 2)),
      ],
      alarm: true,
    );
    final noteTask = task(
      'call-mum',
      reminders: [
        now.add(const Duration(hours: 3)),
        now.add(const Duration(hours: 4)),
      ],
      age: 1,
    );
    // This phone arms both while they are open.
    var container = await openOn([alarmTask, noteTask]);
    expect(alarmsFor(), {'errand'});
    expect(alarms.length, 2);
    expect(pendingFor(), {'call-mum'});
    expect(pending.length, 2);
    // One of the pair already reached the lock screen here.
    final firedId = pending.keys.first;
    pending.remove(firedId);
    delivered.add(firedId);
    container.dispose();

    // Both are ticked on the other phone; the next load here sees them done.
    resetCounts();
    container = await openOn([
      alarmTask.copyWith(isDone: true, completedAt: now),
      noteTask.copyWith(isDone: true, completedAt: now),
    ]);
    expect(container.read(matrixProvider).tasks.map((t) => t.isDone),
        [true, true]);

    expect(alarms.keys.where(inTaskBand), isEmpty,
        reason: 'the reap took the alarms of a task that is done');
    expect(pending.keys.where(inTaskBand), isEmpty,
        reason: 'the read saw the waiting notification and cancelled it');
    expect(delivered, isEmpty,
        reason: 'and the delivered one, as the blind sweep did');
    expect(notifyCalls['cancel'], 2,
        reason: 'exactly the two ids the system held, nothing blind');
    expect(alarmCalls['cancel'], isNull);
    container.dispose();
  });

  test(
      'a task switched between alarm and notification keeps only the new '
      'one, either way round', () async {
    final asAlarm = task(
      'wake',
      reminders: [
        now.add(const Duration(hours: 1)),
        now.add(const Duration(hours: 2)),
      ],
      alarm: true,
    );
    var container = await openOn([asAlarm]);
    expect(alarms.length, 2);
    expect(pending, isEmpty);
    container.dispose();

    // Switched to a notification elsewhere (or here, with the switch's own
    // cancels lost): the next load arms notifications and the reap takes
    // the alarms.
    container = await openOn([asAlarm.copyWith(alarm: false)]);
    expect(alarms, isEmpty);
    expect(pending.length, 2);
    expect(pendingFor(), {'wake'});
    container.dispose();

    // And back: the alarms return and the held notifications go.
    container = await openOn([asAlarm]);
    expect(alarms.length, 2);
    expect(alarmsFor(), {'wake'});
    expect(pending, isEmpty);
    container.dispose();
  });

  test(
      'a resync before the load lands reaps nothing, and neither does one '
      'whose load an early edit superseded', () async {
    final open = task(
      'open',
      reminders: [now.add(const Duration(hours: 1))],
      alarm: true,
    );
    // An alarm this phone armed earlier for a task this notifier has not
    // loaded yet, or never will.
    const straySlot = 12345;
    alarms[straySlot] = 'not-loaded';

    // Before the load lands, the list is empty and says nothing about
    // which alarms belong to no task.
    await store([open]);
    var container = await guest();
    final notifier = container.read(matrixProvider.notifier);
    notifier.resyncReminders();
    await waitUntil(
      () => !container.read(matrixProvider).isLoading,
      describe: 'the guest tasks to load',
    );
    await quiesce();
    expect(reaps, hasLength(1),
        reason: 'only the load\'s own resync reaped, once the list was whole');
    expect(
      (reaps.single['keepIds'] as List).cast<int>(),
      alarms.entries
          .where((e) => e.value == 'open')
          .map((e) => e.key)
          .toList(),
      reason: 'and it kept the loaded task\'s alarm',
    );
    expect(alarms.containsKey(straySlot), isFalse,
        reason: 'the whole list\'s reap took the alarm no task wants');
    container.dispose();

    // An edit made before the load lands supersedes it, and the list then
    // holds only what was added: a reap would take every loaded task's
    // alarm. That notifier never reaps.
    alarms[straySlot] = 'not-loaded';
    resetCounts();
    container = await guest();
    container
        .read(matrixProvider.notifier)
        .add('Added before the load', MatrixQuadrant.doFirst);
    await waitUntil(
      () => !container.read(matrixProvider).isLoading,
      describe: 'the superseded load to settle',
    );
    container.read(matrixProvider.notifier).resyncReminders();
    await quiesce();
    expect(container.read(matrixProvider).tasks.map((t) => t.title),
        ['Added before the load']);
    expect(reaps, isEmpty);
    expect(alarms[straySlot], 'not-loaded');
    container.dispose();
  });

  group('the service, driven directly', () {
    final service = NotificationService.instance;

    test(
        'a job stopped by a moment that passed while it waited keeps the '
        'alarms it never reached', () async {
      final soon = now.add(const Duration(hours: 1));
      final later = now.add(const Duration(hours: 2));
      var resync = service.beginTaskResync(coversEveryTask: true);
      await service.scheduleTaskReminders(
        id: 'stack',
        taskTitle: 'stack',
        fireTimes: [soon, later],
        anchorAt: later,
        isAr: false,
        alarm: true,
        resync: resync,
      );
      await service.finishTaskResync(resync);
      final armed = Map.of(alarms);
      expect(armed.length, 2);

      // The next resync is handed a first moment that has passed by the
      // time its job runs: AlarmKit refuses it, zonedSchedule throws, and
      // the second slot is never reached.
      resync = service.beginTaskResync(coversEveryTask: true);
      await expectLater(
        service.scheduleTaskReminders(
          id: 'stack',
          taskTitle: 'stack',
          fireTimes: [now.subtract(const Duration(seconds: 1)), later],
          anchorAt: later,
          isAr: false,
          alarm: true,
          resync: resync,
        ),
        throwsA(isA<ArgumentError>()),
      );
      await service.finishTaskResync(resync);
      expect(alarms, armed,
          reason: 'the reap spared both slots: the later one is still this '
              'task\'s next reminder, and nothing re-armed it this time');
    });

    test(
        'a done task never cancels a reminder another task of the same '
        'resync just armed', () async {
      // Two tasks whose slots share an id, found by arming candidates and
      // reading the ids off the fake: slot ids are a hash, so it happens.
      final slotsOf = <String, List<int>>{};
      (String open, String done)? pair;
      for (var n = 0; pair == null && n < 400; n++) {
        final id = 'probe-$n';
        armedNotes.clear();
        await service.scheduleTaskReminders(
          id: id,
          taskTitle: id,
          fireTimes: [
            for (var k = 0; k < NotificationService.kMaxTaskReminderSlots; k++)
              now.add(Duration(hours: 1, minutes: k)),
          ],
          anchorAt: null,
          isAr: false,
        );
        final slots = List.of(armedNotes);
        for (final entry in slotsOf.entries) {
          if (entry.value.contains(slots.first)) pair = (id, entry.key);
        }
        slotsOf[id] = slots;
      }
      expect(pair, isNotNull, reason: 'no shared slot among 400 probes');
      final (open, done) = pair!;
      for (final id in slotsOf.keys) {
        await service.cancelTaskReminder(id);
      }
      expect(pending, isEmpty);

      // [open] has one reminder, on its slot 0; [done] is finished, and one
      // of its slots is that same id. [open] comes first in the resync.
      final shared = slotsOf[open]!.first;
      final resync = service.beginTaskResync(coversEveryTask: true);
      await service.scheduleTaskReminders(
        id: open,
        taskTitle: open,
        fireTimes: [now.add(const Duration(hours: 1))],
        anchorAt: null,
        isAr: false,
        resync: resync,
      );
      await service.cancelTaskReminder(done, resync: resync);
      await service.finishTaskResync(resync);
      expect(
        pending[shared],
        open,
        reason: 'the done task\'s sweep left the open task\'s reminder '
            'alone; the blind sweep took it',
      );
    });

    test(
        'a resync that does not cover every task cancels alarms slot by slot '
        'and reaps nothing', () async {
      final resync = service.beginTaskResync(coversEveryTask: false);
      alarmCalls.clear();
      await service.cancelTaskReminder('gone', resync: resync);
      await service.finishTaskResync(resync);
      expect(alarmCalls['cancel'], NotificationService.kMaxTaskReminderSlots);
      expect(alarmCalls['reapOrphans'], isNull);
      expect(notifyCalls['cancel'], isNull,
          reason: 'the notification side still reads what is held first');
    });

    test('a failed read falls back to cancelling blind, never to skipping',
        () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(notificationsChannel, (call) async {
        notifyCalls.update(call.method, (n) => n + 1, ifAbsent: () => 1);
        if (call.method == 'pendingNotificationRequests') {
          throw PlatformException(code: 'unreadable');
        }
        return null;
      });
      final resync = service.beginTaskResync(coversEveryTask: true);
      await service.cancelTaskReminder('done', resync: resync);
      await service.finishTaskResync(resync);
      expect(notifyCalls['cancel'], NotificationService.kMaxTaskReminderSlots);
    });
  });
}
