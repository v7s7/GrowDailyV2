import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/matrix/models/matrix_task.dart';
import 'package:grow_daily_v2/features/matrix/notifiers/matrix_notifier.dart';
import 'package:grow_daily_v2/features/matrix/task_day.dart';
import 'package:hive/hive.dart';

import '../../helpers/wait_until.dart';

/// Adding a task for a day, moving it to another day, and the move's Undo.
///
/// Two halves. The rules (taskMovedToDay, taskWithRestoredSchedule) are pure
/// with the clock passed in, so the exact boundaries are pinned with fixed
/// dates. The notifier half drives the real MatrixNotifier in guest mode
/// against a real Hive box, in plain `test()` bodies (a Hive write inside a
/// testWidgets zone never settles), with days built from the real clock and
/// far enough from now that the hour the suite runs at cannot matter.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MatrixTask timed({
    String id = 't',
    required DateTime anchor,
    Set<int> offsets = const {},
    bool alarm = false,
    bool isDone = false,
    DateTime? createdAt,
    bool storeAnchor = true,
  }) =>
      MatrixTask(
        id: id,
        title: 'Task $id',
        quadrant: MatrixQuadrant.schedule,
        isDone: isDone,
        createdAt: createdAt ?? DateTime(2026, 9, 27, 9),
        completedAt: isDone ? DateTime(2026, 9, 28, 9) : null,
        reminderAts: remindersFor(anchor: anchor, offsets: offsets),
        reminderAnchorAt: storeAnchor ? anchor : null,
        alarm: alarm,
        order: 0,
      );

  MatrixTask untimed({
    String id = 'u',
    String? plannedDay,
    bool isDone = false,
    DateTime? createdAt,
  }) =>
      MatrixTask(
        id: id,
        title: 'Task $id',
        quadrant: MatrixQuadrant.doFirst,
        isDone: isDone,
        createdAt: createdAt ?? DateTime(2026, 9, 27, 9),
        completedAt: isDone ? DateTime(2026, 9, 28, 9) : null,
        plannedDay: plannedDay,
        order: 0,
      );

  group('taskMovedToDay', () {
    final noon = DateTime(2026, 9, 29, 12);

    test('a timed task keeps its clock time, offsets and alarm', () {
      final t = timed(
        anchor: DateTime(2026, 9, 30, 17),
        offsets: {-60, 15},
        alarm: true,
      );
      final moved = taskMovedToDay(t, DateTime(2026, 10, 3), now: noon)!;
      expect(moved.reminderAts, [
        DateTime(2026, 10, 3, 16),
        DateTime(2026, 10, 3, 17),
        DateTime(2026, 10, 3, 17, 15),
      ]);
      expect(moved.reminderAnchorAt, DateTime(2026, 10, 3, 17));
      expect(moved.alarm, isTrue);
      expect(moved.plannedDay, '2026-10-03');
      expect(taskDay(moved), DateTime(2026, 10, 3));
      expect(
        offsetsFrom(anchor: moved.reminderAnchorAt, reminders: moved.reminderAts),
        {-60, 15},
      );
    });

    test('a warning that has already passed on the new day is dropped', () {
      final t = timed(anchor: DateTime(2026, 10, 1, 17), offsets: {-60});
      final moved = taskMovedToDay(
        t,
        DateTime(2026, 9, 29),
        now: DateTime(2026, 9, 29, 16, 30),
      )!;
      expect(moved.reminderAts, [DateTime(2026, 9, 29, 17)]);
      expect(moved.reminderAnchorAt, DateTime(2026, 9, 29, 17));
    });

    test('an anchor already gone on the new day is refused, not stored', () {
      final t = timed(anchor: DateTime(2026, 10, 1, 9), offsets: {-30});
      expect(taskMovedToDay(t, DateTime(2026, 9, 29), now: noon), isNull);
      // The very minute counts as gone: a reminder at "now" cannot ring.
      expect(
        taskMovedToDay(t, DateTime(2026, 9, 29),
            now: DateTime(2026, 9, 29, 9)),
        isNull,
      );
      expect(taskMovedToDay(t, DateTime(2026, 9, 20), now: noon), isNull);
    });

    test('a picked time replaces the clock time, offsets kept', () {
      final t = timed(anchor: DateTime(2026, 10, 1, 9), offsets: {-60});
      final moved = taskMovedToDay(
        t,
        DateTime(2026, 9, 29),
        time: const TimeOfDay(hour: 20, minute: 0),
        now: DateTime(2026, 9, 29, 18),
      )!;
      expect(moved.reminderAts,
          [DateTime(2026, 9, 29, 19), DateTime(2026, 9, 29, 20)]);
      expect(moved.reminderAnchorAt, DateTime(2026, 9, 29, 20));
    });

    test('a task saved before the anchor existed moves around its last '
        'reminder', () {
      final t = timed(
        anchor: DateTime(2026, 9, 30, 17),
        offsets: {-120},
        storeAnchor: false,
      );
      final moved = taskMovedToDay(t, DateTime(2026, 10, 2), now: noon)!;
      expect(moved.reminderAts,
          [DateTime(2026, 10, 2, 15), DateTime(2026, 10, 2, 17)]);
      expect(moved.reminderAnchorAt, DateTime(2026, 10, 2, 17));
    });

    test('an untimed task only changes day, and gains no reminder', () {
      final t = untimed(plannedDay: '2026-09-29');
      final moved = taskMovedToDay(
        t,
        DateTime(2026, 10, 4, 15),
        time: const TimeOfDay(hour: 9, minute: 0),
        now: noon,
      )!;
      expect(moved.plannedDay, '2026-10-04');
      expect(moved.reminderAts, isEmpty);
      // A past day is fine for an untimed task: nothing can ring.
      expect(taskMovedToDay(t, DateTime(2026, 9, 20), now: noon)!.plannedDay,
          '2026-09-20');
    });

    test('a done task is never moved', () {
      expect(
        taskMovedToDay(untimed(isDone: true), DateTime(2026, 10, 4), now: noon),
        isNull,
      );
      expect(
        taskMovedToDay(
          timed(anchor: DateTime(2026, 10, 1, 9), isDone: true),
          DateTime(2026, 10, 4),
          now: noon,
        ),
        isNull,
      );
    });

    test('a task already on the day comes back unchanged', () {
      final a = untimed(createdAt: DateTime(2026, 9, 29, 8));
      expect(identical(taskMovedToDay(a, DateTime(2026, 9, 29), now: noon), a),
          isTrue);
      final b = timed(anchor: DateTime(2026, 10, 1, 9));
      expect(identical(taskMovedToDay(b, DateTime(2026, 10, 1), now: noon), b),
          isTrue);
    });
  });

  group('taskWithRestoredSchedule', () {
    final now = DateTime(2026, 9, 29, 12);

    test('puts a future schedule back exactly', () {
      final before = timed(
        anchor: DateTime(2026, 10, 1, 17),
        offsets: {-60},
      ).copyWith(plannedDay: '2026-10-01');
      final moved = taskMovedToDay(before, DateTime(2026, 10, 5), now: now)!;
      final back = taskWithRestoredSchedule(
        moved,
        reminderAts: before.reminderAts,
        anchor: before.reminderAnchorAt,
        plannedDay: before.plannedDay,
        now: now,
      );
      expect(back.reminderAts, before.reminderAts);
      expect(back.reminderAnchorAt, before.reminderAnchorAt);
      expect(back.plannedDay, '2026-10-01');
    });

    test('drops moments that have passed, never restoring one', () {
      final back = taskWithRestoredSchedule(
        untimed(),
        reminderAts: [DateTime(2026, 9, 29, 11), DateTime(2026, 9, 29, 13)],
        anchor: DateTime(2026, 9, 29, 13),
        now: now,
      );
      expect(back.reminderAts, [DateTime(2026, 9, 29, 13)]);
      expect(back.reminderAnchorAt, DateTime(2026, 9, 29, 13));
    });

    test('a passed anchor brings back no follow-up, so the day cannot move',
        () {
      // 23:30 with a follow-up an hour after: the follow-up is past
      // midnight. Kept alone it would become the anchor and take the task
      // to the next day.
      final back = taskWithRestoredSchedule(
        untimed(),
        reminderAts: [
          DateTime(2026, 9, 28, 23, 30),
          DateTime(2026, 9, 29, 0, 30),
        ],
        anchor: DateTime(2026, 9, 28, 23, 30),
        now: DateTime(2026, 9, 29, 0, 5),
      );
      expect(back.reminderAts, isEmpty);
      expect(back.reminderAnchorAt, isNull);
      expect(back.plannedDay, '2026-09-28');
      expect(taskDay(back), DateTime(2026, 9, 28));
    });

    test('a schedule that has fully passed brings back the day, not the '
        'time', () {
      final back = taskWithRestoredSchedule(
        timed(anchor: DateTime(2026, 10, 5, 9)),
        reminderAts: [DateTime(2026, 9, 28, 16), DateTime(2026, 9, 28, 17)],
        anchor: DateTime(2026, 9, 28, 17),
        now: now,
      );
      expect(back.reminderAts, isEmpty);
      expect(back.reminderAnchorAt, isNull);
      expect(back.plannedDay, '2026-09-28');
      expect(taskDay(back), DateTime(2026, 9, 28));
    });

    test('an untimed task gets its plannedDay back as it was, null too', () {
      final moved = untimed(plannedDay: '2026-10-04');
      expect(
        taskWithRestoredSchedule(moved,
                reminderAts: const [], plannedDay: '2026-09-30', now: now)
            .plannedDay,
        '2026-09-30',
      );
      expect(
        taskWithRestoredSchedule(moved, reminderAts: const [], now: now)
            .plannedDay,
        isNull,
      );
    });
  });

  group('MatrixNotifier (guest)', () {
    late Directory tmp;
    late ProviderContainer container;
    late Box<dynamic> box;

    final today = DateTime.now();
    DateTime dayAt(int offset, [int hour = 0, int minute = 0]) =>
        DateTime(today.year, today.month, today.day + offset, hour, minute);

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('matrix_day_move_test_');
      Hive.init(tmp.path);
      box = await Hive.openBox<dynamic>('box_settings');
    });

    tearDown(() async {
      container.dispose();
      // Let the fire-and-forget saves land before the box goes away.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    Future<MatrixNotifier> start([List<MatrixTask> seed = const []]) async {
      await box.put(
        'guest_matrix_tasks',
        seed.map((t) => t.toMap()).toList(),
      );
      container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        ],
      );
      await container.read(authStateProvider.future);
      container.read(matrixProvider);
      await waitUntil(
        () => !container.read(matrixProvider).isLoading,
        describe: 'the guest board to load',
      );
      return container.read(matrixProvider.notifier);
    }

    MatrixTask taskById(String id) =>
        container.read(matrixProvider).tasks.firstWhere((t) => t.id == id);

    Future<Map<String, dynamic>> stored(
      String id,
      bool Function(Map<String, dynamic>) ready,
    ) async {
      Map<String, dynamic>? read() {
        final raw = box.get('guest_matrix_tasks');
        if (raw is! List) return null;
        for (final m in raw) {
          final map = Map<String, dynamic>.from(m as Map);
          if (map['id'] == id) return map;
        }
        return null;
      }

      await waitUntil(
        () => read() != null && ready(read()!),
        describe: 'task $id to be saved to Hive',
      );
      return read()!;
    }

    test('add writes the day it was given, or the anchor\'s day', () async {
      final notifier = await start();

      final forDay = notifier.add('Plan', MatrixQuadrant.doFirst, day: dayAt(3))!;
      expect(forDay.plannedDay, dayKey(dayAt(3)));
      expect(taskDay(forDay), dayAt(3));

      final forToday =
          notifier.add('Today', MatrixQuadrant.doFirst, day: dayAt(0))!;
      expect(forToday.plannedDay, dayKey(dayAt(0)),
          reason: 'an explicit today is written too');

      final anchor = dayAt(5, 10);
      final withTime = notifier.add(
        'Timed',
        MatrixQuadrant.schedule,
        reminderAts: [anchor.subtract(const Duration(days: 2)), anchor],
        reminderAnchorAt: anchor,
        day: dayAt(3),
      )!;
      expect(withTime.plannedDay, dayKey(anchor),
          reason: 'the reminders decide the day while they exist');

      final plain = notifier.add('Quick', MatrixQuadrant.delegate)!;
      expect(plain.plannedDay, isNull);
      expect(notifier.add('   ', MatrixQuadrant.delegate), isNull);

      final saved = await stored(forDay.id, (m) => m['plannedDay'] != null);
      expect(saved['plannedDay'], dayKey(dayAt(3)));
    });

    test('setReminders keeps a timed task on its day when the time is '
        'cleared, and follows a new date', () async {
      final legacy = timed(
        id: 'legacy',
        anchor: dayAt(1, 10),
        createdAt: dayAt(-3, 9),
      );
      final notifier = await start([legacy]);
      expect(taskById('legacy').plannedDay, isNull);

      notifier.setReminders('legacy', const []);
      expect(taskById('legacy').reminderAts, isEmpty);
      expect(taskById('legacy').plannedDay, dayKey(dayAt(1)));
      expect(taskDay(taskById('legacy')), dayAt(1));

      final next = dayAt(4, 18);
      notifier.setReminders('legacy', [next], reminderAnchorAt: next);
      expect(taskById('legacy').plannedDay, dayKey(dayAt(4)));
      expect(taskDay(taskById('legacy')), dayAt(4));
    });

    test('moveToDay moves a timed task with its offsets and alarm, and '
        'restoreSchedule undoes it', () async {
      final before = timed(
        id: 'm',
        anchor: dayAt(1, 10),
        offsets: {-60},
        alarm: true,
      ).copyWith(plannedDay: dayKey(dayAt(1)));
      final notifier = await start([before]);

      expect(notifier.moveToDay('m', dayAt(3)), isTrue);
      final moved = taskById('m');
      expect(moved.reminderAts, [dayAt(3, 9), dayAt(3, 10)]);
      expect(moved.reminderAnchorAt, dayAt(3, 10));
      expect(moved.alarm, isTrue);
      expect(moved.plannedDay, dayKey(dayAt(3)));
      final saved =
          await stored('m', (m) => m['plannedDay'] == dayKey(dayAt(3)));
      expect(saved['alarm'], isTrue);

      notifier.restoreSchedule(
        'm',
        reminderAts: before.reminderAts,
        anchor: before.reminderAnchorAt,
        plannedDay: before.plannedDay,
      );
      final back = taskById('m');
      expect(back.reminderAts, before.reminderAts);
      expect(back.reminderAnchorAt, before.reminderAnchorAt);
      expect(back.plannedDay, dayKey(dayAt(1)));
      await stored('m', (m) => m['plannedDay'] == dayKey(dayAt(1)));
    });

    test('moveToDay refuses a day whose time has gone and changes nothing',
        () async {
      final notifier = await start([timed(id: 'late', anchor: dayAt(2, 8))]);
      final before = taskById('late');
      expect(notifier.moveToDay('late', dayAt(-1)), isFalse);
      expect(identical(taskById('late'), before), isTrue);
    });

    test('moveToDay moves an untimed task by day and refuses a done one',
        () async {
      final notifier = await start([
        untimed(id: 'u', createdAt: dayAt(-2, 9)),
        untimed(id: 'd', isDone: true, plannedDay: dayKey(dayAt(0))),
      ]);
      expect(notifier.moveToDay('u', dayAt(6)), isTrue);
      expect(taskById('u').plannedDay, dayKey(dayAt(6)));
      expect(taskById('u').reminderAts, isEmpty);

      expect(notifier.moveToDay('d', dayAt(6)), isFalse);
      expect(taskById('d').plannedDay, dayKey(dayAt(0)));
      expect(notifier.moveToDay('missing', dayAt(6)), isFalse);
    });

    test('restoreSchedule drops moments that have passed', () async {
      final notifier = await start([timed(id: 'r', anchor: dayAt(4, 9))]);

      notifier.restoreSchedule(
        'r',
        reminderAts: [dayAt(-1, 10), dayAt(1, 10)],
        anchor: dayAt(1, 10),
      );
      expect(taskById('r').reminderAts, [dayAt(1, 10)]);
      expect(taskById('r').reminderAnchorAt, dayAt(1, 10));

      notifier.restoreSchedule(
        'r',
        reminderAts: [dayAt(-1, 9), dayAt(-1, 10)],
        anchor: dayAt(-1, 10),
      );
      expect(taskById('r').reminderAts, isEmpty);
      expect(taskById('r').reminderAnchorAt, isNull);
      expect(taskDay(taskById('r')), dayAt(-1),
          reason: 'the day comes back even when its time cannot');
    });
  });
}
