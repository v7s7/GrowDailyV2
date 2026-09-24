// What the app writes for the task widgets (HomeWidgetService.
// updateMatrixWidgetData), read back through a mocked home_widget channel.
//
// The Lock Screen task widget sorts by each task's time on its own side
// (ios/GrowDailyWidget/MatrixLockScreenOrder.swift), so the one thing this
// side owes it is the time, under the key WidgetMatrixTask decodes:
// `dueAtMs`, milliseconds since 1970, absent when the task has no reminder.
// A renamed key would not fail anywhere else: the widget decodes a missing
// key as "no time" and quietly goes back to sorting by quadrant alone.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/services/armed_task_record.dart';
import 'package:grow_daily_v2/core/services/home_widget_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const widgetChannel = MethodChannel('home_widget');

  /// The App Group store, keyed the way home_widget keys it.
  late Map<String, Object?> store;
  late List<MethodCall> widgetCalls;

  setUp(() {
    // HomeWidgetService only writes on iOS.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    store = <String, Object?>{};
    widgetCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(widgetChannel, (call) async {
      widgetCalls.add(call);
      if (call.method == 'saveWidgetData') {
        final args = call.arguments as Map;
        store[args['id'] as String] = args['data'];
      }
      return true;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(widgetChannel, null);
  });

  List<Map<String, dynamic>> written() =>
      (jsonDecode(store['matrixTasksJson']! as String) as List)
          .cast<Map<String, dynamic>>();

  test('a timed task carries its picked moment as dueAtMs, in ms', () async {
    final picked = DateTime(2026, 9, 21, 17, 0);
    await HomeWidgetService.instance.updateMatrixWidgetData(
      [
        (
          id: 'timed',
          title: 'Call the bank',
          quadrant: 'schedule',
          isDone: false,
          isFav: false,
          isLate: false,
          hasReminder: true,
          alarm: false,
          dueAt: picked,
        ),
      ],
      doneTodayCount: 0,
    );

    final task = written().single;
    expect(task['dueAtMs'], picked.millisecondsSinceEpoch);
    // A whole number: WidgetMatrixTask reads it as a Double, and a string
    // would fail the decode of the entire list, not just this task.
    expect(task['dueAtMs'], isA<int>());
  });

  test('a task with no reminder writes no dueAtMs at all', () async {
    await HomeWidgetService.instance.updateMatrixWidgetData(
      [
        (
          id: 'untimed',
          title: 'Tidy the desk',
          quadrant: 'doFirst',
          isDone: false,
          isFav: true,
          isLate: false,
          hasReminder: false,
          alarm: false,
          dueAt: null,
        ),
      ],
      doneTodayCount: 0,
    );

    expect(written().single.containsKey('dueAtMs'), isFalse);
  });

  test('the list keeps the order the app sent, for the widget to re-sort',
      () async {
    await HomeWidgetService.instance.updateMatrixWidgetData(
      [
        for (final (id, q) in [
          ('a', 'doFirst'),
          ('b', 'schedule'),
          ('c', 'eliminate'),
        ])
          (
            id: id,
            title: id,
            quadrant: q,
            isDone: false,
            isFav: false,
            isLate: false,
            hasReminder: false,
            alarm: false,
            dueAt: null,
          ),
      ],
      doneTodayCount: 0,
    );

    // The widget breaks ties by position, so this order is its tiebreak:
    // untimed tasks come out Do First first because they went in that way.
    expect(written().map((t) => t['id']), ['a', 'b', 'c']);
    final refreshed = widgetCalls
        .where((c) => c.method == 'updateWidget')
        .map((c) => (c.arguments as Map)['ios']);
    expect(refreshed, contains('GrowDailyMatrixLockScreenWidget'));
  });

  group('the reminder record written beside the rows', () {
    // What the Matrix widget's checkmark reads to take a finished task's own
    // reminders down (ArmedTaskRecord, applied by taskReminderStandDown in
    // ios/GrowDailyWidget/TaskReminderStandDown.swift). Without it a task
    // ticked on the widget went on reminding about itself until the app was
    // next opened.
    Future<void> push(
      List<({String id, bool hasReminder, bool alarm})> tasks,
    ) =>
        HomeWidgetService.instance.updateMatrixWidgetData(
          [
            for (final t in tasks)
              (
                id: t.id,
                title: t.id,
                quadrant: 'doFirst',
                isDone: false,
                isFav: false,
                isLate: false,
                hasReminder: t.hasReminder,
                alarm: t.alarm,
                dueAt: null,
              ),
          ],
          doneTodayCount: 0,
        );

    Map<String, Object?> record() =>
        jsonDecode(store['armedTaskRemindersJson']! as String)
            as Map<String, Object?>;

    test('a task with a reminder carries every id it can hold', () async {
      await push([(id: 'timed', hasReminder: true, alarm: false)]);
      final task = (record()['tasks']! as Map)['timed']! as Map;
      expect(
        task['notifications'],
        [
          for (var i = 0; i < kTaskReminderSlots; i++)
            taskReminderId('timed', i),
        ],
      );
    });

    test('a task with no reminder is not in the record at all', () async {
      await push([
        (id: 'untimed', hasReminder: false, alarm: false),
        (id: 'timed', hasReminder: true, alarm: false),
      ]);
      expect((record()['tasks']! as Map).keys, ['timed'],
          reason: 'a task with nothing armed has nothing to take down');
    });

    test('an alarm task carries its ids under both kinds', () async {
      await push([(id: 'ringing', hasReminder: true, alarm: true)]);
      final task = (record()['tasks']! as Map)['ringing']! as Map;
      expect(task['alarms'], task['notifications']);
    });

    test('the record lands before the rows it belongs to', () async {
      // A row reaches the checkmark the moment it is written; if its ids
      // followed, a tick in between would find no record and leave the
      // task's reminders to the app.
      await push([(id: 'timed', hasReminder: true, alarm: false)]);
      final keys = widgetCalls
          .where((c) => c.method == 'saveWidgetData')
          .map((c) => (c.arguments as Map)['id'])
          .toList();
      expect(keys.indexOf('armedTaskRemindersJson'),
          lessThan(keys.indexOf('matrixTasksJson')));
    });
  });
}
