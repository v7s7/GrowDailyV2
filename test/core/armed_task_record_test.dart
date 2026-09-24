// The record a task ticked outside the app reads to take its own reminders
// down with it (lib/core/services/armed_task_record.dart).
//
// Two buttons apply it, both in Swift: the Matrix widget's checkmark and
// «خلّصت المهمة» on a ringing task alarm. Neither can work the ids out for
// itself, so what is pinned here is the contract between them: which ids a
// task holds, and what a reader may conclude from a record it cannot read.
// The Swift twin is ios/GrowDailyWidget/TaskReminderStandDown.swift, and the
// ids are cross-checked against the ones the real service arms and cancels in
// alarm_reminder_scheduling_test.dart.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/services/armed_task_record.dart';

void main() {
  Map<String, Object?> decode(String json) =>
      jsonDecode(json) as Map<String, Object?>;

  group('taskReminderId', () {
    test('slot 0 is the bare id a single-reminder task always had', () {
      // An install upgrading from the build where a task had one reminder
      // must keep addressing the schedule already sitting in the OS queue,
      // or it fires alongside its own replacement.
      expect(taskReminderId('task-1'), taskReminderId('task-1', 0));
    });

    test('every slot of a task is its own id, inside the task band', () {
      final ids = {
        for (var i = 0; i < kTaskReminderSlots; i++) taskReminderId('task-1', i),
      };
      expect(ids, hasLength(kTaskReminderSlots),
          reason: 'two slots sharing an id would silence each other');
      for (final id in ids) {
        expect(id, inInclusiveRange(10000, 59999),
            reason: 'a task id must never land in a habit band');
      }
    });

    test('two tasks do not share slot 0', () {
      expect(taskReminderId('task-1'), isNot(taskReminderId('task-2')));
    });
  });

  group('ArmedTaskRecord.encode', () {
    test('names every slot a task can hold, not just the ones set', () {
      // The record is read to cancel, and cancelTaskReminder sweeps all
      // eight: a stack shortened a moment ago, whose resync has not landed,
      // still has to go down whole.
      final record = decode(
          ArmedTaskRecord.encode([(taskId: 'groceries', alarm: false)]));
      final task = (record['tasks']! as Map)['groceries']! as Map;
      expect(
        task['notifications'],
        [for (var i = 0; i < kTaskReminderSlots; i++) taskReminderId('groceries', i)],
      );
      expect(task.containsKey('alarms'), isFalse,
          reason: 'a task that does not ring as an alarm holds none');
    });

    test('an alarm-mode task files the same ids under both kinds', () {
      // Which one is really armed is not knowable here: AlarmKit takes the
      // slot when it can, and the app falls back to a notification under the
      // same id when it cannot.
      final record =
          decode(ArmedTaskRecord.encode([(taskId: 'call', alarm: true)]));
      final task = (record['tasks']! as Map)['call']! as Map;
      expect(task['alarms'], task['notifications']);
    });

    test('several tasks each get their own entry', () {
      final record = decode(ArmedTaskRecord.encode([
        (taskId: 'a', alarm: false),
        (taskId: 'b', alarm: true),
      ]));
      expect((record['tasks']! as Map).keys, ['a', 'b']);
      expect(record['v'], ArmedTaskRecord.version);
    });

    test('a record for no tasks at all is still a record', () {
      // What an account with no timed task writes. It has to read as "this
      // task holds nothing", not as "no record", or every tick would fall
      // back to leaving the reminders to the app.
      final plan =
          ArmedTaskRecord.standDownFor(ArmedTaskRecord.encode([]), taskId: 'x');
      expect(plan, isNotNull);
      expect(plan!.notifications, isEmpty);
      expect(plan.alarms, isEmpty);
    });
  });

  group('ArmedTaskRecord.standDownFor', () {
    final record = ArmedTaskRecord.encode([
      (taskId: 'plain', alarm: false),
      (taskId: 'ringing', alarm: true),
    ]);

    test('takes down every id the finished task holds', () {
      final plan = ArmedTaskRecord.standDownFor(record, taskId: 'plain')!;
      expect(
        plan.notifications,
        {for (var i = 0; i < kTaskReminderSlots; i++) taskReminderId('plain', i)},
      );
      expect(plan.alarms, isEmpty);
    });

    test('an alarm-mode task takes down both systems', () {
      final plan = ArmedTaskRecord.standDownFor(record, taskId: 'ringing')!;
      expect(plan.alarms, plan.notifications);
      expect(plan.alarms, hasLength(kTaskReminderSlots));
    });

    test('touches nothing of any other task', () {
      final plan = ArmedTaskRecord.standDownFor(record, taskId: 'plain')!;
      final others = {
        for (var i = 0; i < kTaskReminderSlots; i++) taskReminderId('ringing', i),
      };
      expect(plan.notifications.intersection(others), isEmpty);
    });

    test('a task the record does not name holds nothing', () {
      final plan = ArmedTaskRecord.standDownFor(record, taskId: 'unknown')!;
      expect(plan.notifications, isEmpty);
      expect(plan.alarms, isEmpty);
    });

    test('no readable record answers null, and the caller falls back', () {
      // Null is not "nothing to do": it is "this build wrote no record", and
      // the tick then leaves the task's reminders to the app's next open,
      // exactly as before any of this existed.
      for (final unreadable in [null, '', 'not json', '[]', '"a string"']) {
        expect(
          ArmedTaskRecord.standDownFor(unreadable, taskId: 'plain'),
          isNull,
          reason: 'unreadable: ${unreadable ?? "null"}',
        );
      }
    });

    test('a record of the right version with no tasks map holds nothing', () {
      final plan = ArmedTaskRecord.standDownFor(
          '{"v":${ArmedTaskRecord.version}}',
          taskId: 'plain')!;
      expect(plan.notifications, isEmpty);
    });

    test('another version reads as no record at all', () {
      final future = jsonEncode({
        'v': ArmedTaskRecord.version + 1,
        'tasks': {
          'plain': {'notifications': [10001]},
        },
      });
      expect(ArmedTaskRecord.standDownFor(future, taskId: 'plain'), isNull);
    });

    test('a damaged entry costs only what cannot be read', () {
      final damaged = jsonEncode({
        'v': ArmedTaskRecord.version,
        'tasks': {
          'plain': {
            'notifications': [10001, 'nonsense', 10002],
            'alarms': 'nonsense',
          },
        },
      });
      final plan = ArmedTaskRecord.standDownFor(damaged, taskId: 'plain')!;
      expect(plan.notifications, {10001, 10002});
      expect(plan.alarms, isEmpty);
    });
  });
}
