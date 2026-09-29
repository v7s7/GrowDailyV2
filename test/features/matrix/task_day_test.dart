import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/matrix/models/matrix_task.dart';
import 'package:grow_daily_v2/features/matrix/task_day.dart';

/// The day rule in task_day.dart: which day a task belongs to, which boards
/// it shows on, and how the three lenses split the open tasks. Every clock
/// here is a fixed date passed in, so none of this depends on when it runs.
void main() {
  MatrixTask task({
    String id = 't',
    bool isDone = false,
    DateTime? createdAt,
    DateTime? completedAt,
    List<DateTime> reminderAts = const [],
    DateTime? anchor,
    String? plannedDay,
  }) =>
      MatrixTask(
        id: id,
        title: 'Task $id',
        quadrant: MatrixQuadrant.doFirst,
        isDone: isDone,
        createdAt: createdAt ?? DateTime(2026, 9, 27, 9),
        completedAt: completedAt,
        reminderAts: MatrixTask.normalizeReminders(reminderAts),
        reminderAnchorAt: anchor,
        plannedDay: plannedDay,
        order: 0,
      );

  group('taskDay precedence', () {
    test('the picked reminder decides the day over plannedDay and createdAt',
        () {
      final t = task(
        createdAt: DateTime(2026, 9, 27, 9),
        plannedDay: '2026-09-28',
        reminderAts: [DateTime(2026, 9, 30, 17)],
        anchor: DateTime(2026, 9, 30, 17),
      );
      expect(taskDay(t), DateTime(2026, 9, 30));
    });

    test('a task created Sunday for Tuesday 17:00 is Tuesday\'s', () {
      // The verified bug: filed by createdAt, this task sat under «مُرحّلة»
      // on the very Tuesday it was for.
      final t = task(
        createdAt: DateTime(2026, 9, 27, 20),
        reminderAts: [DateTime(2026, 9, 29, 17)],
        anchor: DateTime(2026, 9, 29, 17),
      );
      final tuesday = DateTime(2026, 9, 29, 8);
      expect(taskDay(t), DateTime(2026, 9, 29));
      expect(isOpenOnDay(t, tuesday), isTrue);
      expect(isCarriedOver(t, tuesday), isFalse);
      expect(openOnDayCount([t], tuesday), 1);
    });

    test('a "2 days before" warning files on the anchor day, not the warning',
        () {
      final anchor = DateTime(2026, 10, 1, 17);
      final t = task(
        reminderAts: [anchor.subtract(const Duration(days: 2)), anchor],
        anchor: anchor,
      );
      expect(taskDay(t), DateTime(2026, 10, 1));
      // On the warning's day the task is still ahead, not today's.
      final warningDay = DateTime(2026, 9, 29, 17, 30);
      expect(isUpcoming(t, warningDay), isTrue);
      expect(isOpenOnDay(t, warningDay), isFalse);
    });

    test('a task saved before the anchor existed falls back to its last '
        'reminder, the same guess resolveAnchor makes', () {
      final t = task(
        reminderAts: [DateTime(2026, 9, 28, 15), DateTime(2026, 9, 30, 17)],
      );
      expect(t.reminderAnchorAt, isNull);
      expect(taskDay(t), DateTime(2026, 9, 30));

      // And the same through the storage read, where resolveAnchor runs.
      final read = MatrixTask.fromMap(t.toMap());
      expect(taskDay(read), DateTime(2026, 9, 30));
    });

    test('an anchor that is not one of the reminders is not trusted', () {
      final t = task(
        reminderAts: [DateTime(2026, 9, 30, 17)],
        anchor: DateTime(2026, 10, 9, 17),
      );
      expect(taskDay(t), DateTime(2026, 9, 30));
    });

    test('an untimed task with a plannedDay is on that day', () {
      final t = task(
        createdAt: DateTime(2026, 9, 27, 9),
        plannedDay: '2026-10-02',
      );
      expect(taskDay(t), DateTime(2026, 10, 2));
    });

    test('with neither, the day it was created, as every old task', () {
      final t = task(createdAt: DateTime(2026, 9, 27, 23, 10));
      expect(taskDay(t), DateTime(2026, 9, 27));
    });

    test('a plannedDay that does not parse falls through to createdAt', () {
      for (final bad in ['2026-02-30', '2026-9-30', 'soon', '']) {
        final t = task(createdAt: DateTime(2026, 9, 27, 9), plannedDay: bad);
        expect(taskDay(t), DateTime(2026, 9, 27), reason: bad);
      }
    });
  });

  group('dayKey and parseDayKey', () {
    test('a day key is the calendar date, time ignored', () {
      expect(dayKey(DateTime(2026, 1, 5, 23, 59)), '2026-01-05');
      expect(dayKey(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('parse is strict and round trips', () {
      expect(parseDayKey('2026-10-02'), DateTime(2026, 10, 2));
      expect(parseDayKey(dayKey(DateTime(2027, 2, 28, 8))),
          DateTime(2027, 2, 28));
      expect(parseDayKey(null), isNull);
      expect(parseDayKey('2026-02-30'), isNull);
      expect(parseDayKey('2026-13-01'), isNull);
      expect(parseDayKey('2026-10-02T00:00:00'), isNull);
    });
  });

  group('showsOnDay: planned for it, or done on it', () {
    test('a task done early shows on its planned day and its done day', () {
      final t = task(
        isDone: true,
        plannedDay: '2026-10-01',
        completedAt: DateTime(2026, 9, 29, 14),
      );
      expect(showsOnDay(t, DateTime(2026, 10, 1)), isTrue);
      expect(showsOnDay(t, DateTime(2026, 9, 29, 23, 59)), isTrue);
      expect(showsOnDay(t, DateTime(2026, 9, 30)), isFalse);
      expect(showsOnDay(t, DateTime(2026, 9, 27)), isFalse,
          reason: 'the created day is not one of its days any more');
    });

    test('a done task with no completedAt shows on its own day only', () {
      final t = task(isDone: true, plannedDay: '2026-10-01');
      expect(showsOnDay(t, DateTime(2026, 10, 1)), isTrue);
      expect(showsOnDay(t, DateTime(2026, 9, 29)), isFalse);
    });

    test('an open task shows on its day only, whatever day it was typed', () {
      final t = task(
        createdAt: DateTime(2026, 9, 27, 9),
        plannedDay: '2026-10-01',
      );
      expect(showsOnDay(t, DateTime(2026, 10, 1, 12)), isTrue);
      expect(showsOnDay(t, DateTime(2026, 9, 27)), isFalse);
    });
  });

  group('the three lenses split every open task exactly once', () {
    final today = DateTime(2026, 9, 29, 13, 20);
    final tasks = [
      task(id: 'old', createdAt: DateTime(2026, 9, 20, 8)),
      task(id: 'yday-timed', reminderAts: [DateTime(2026, 9, 28, 17)]),
      task(id: 'today-new', createdAt: DateTime(2026, 9, 29, 7)),
      task(id: 'today-planned', plannedDay: '2026-09-29'),
      task(
        id: 'today-late',
        reminderAts: [DateTime(2026, 9, 29, 23, 59)],
        anchor: DateTime(2026, 9, 29, 23, 59),
      ),
      task(id: 'next-week', plannedDay: '2026-10-06'),
      task(
        id: 'warned-early',
        reminderAts: [DateTime(2026, 9, 29, 9), DateTime(2026, 10, 1, 9)],
        anchor: DateTime(2026, 10, 1, 9),
      ),
      task(id: 'done', isDone: true, completedAt: DateTime(2026, 9, 29, 8)),
    ];

    test('each open task is in exactly one place', () {
      for (final t in tasks.where((t) => !t.isDone)) {
        final places = [
          isCarriedOver(t, today),
          isOpenOnDay(t, today),
          isUpcoming(t, today),
        ].where((p) => p).length;
        expect(places, 1, reason: t.id);
      }
    });

    test('and lands where its day says', () {
      List<String> ids(bool Function(MatrixTask) f) =>
          tasks.where(f).map((t) => t.id).toList();
      expect(ids((t) => isCarriedOver(t, today)), ['old', 'yday-timed']);
      expect(ids((t) => isOpenOnDay(t, today)),
          ['today-new', 'today-planned', 'today-late']);
      expect(ids((t) => isUpcoming(t, today)), ['next-week', 'warned-early']);
      expect(openOnDayCount(tasks, today), 3);
    });

    test('a done task is in none of them', () {
      final done = tasks.last;
      expect(isCarriedOver(done, today), isFalse);
      expect(isOpenOnDay(done, today), isFalse);
      expect(isUpcoming(done, today), isFalse);
    });
  });

  group('real midnight, not the 10:00 grace', () {
    final lateTimed = task(
      reminderAts: [DateTime(2026, 9, 29, 23, 59)],
      anchor: DateTime(2026, 9, 29, 23, 59),
    );
    final midnightTimed = task(
      reminderAts: [DateTime(2026, 9, 30)],
      anchor: DateTime(2026, 9, 30),
    );

    test('23:59 is still its own day, 00:00 is the next', () {
      expect(taskDay(lateTimed), DateTime(2026, 9, 29));
      expect(taskDay(midnightTimed), DateTime(2026, 9, 30));
      expect(taskDay(task(createdAt: DateTime(2026, 9, 29, 23, 59, 59))),
          DateTime(2026, 9, 29));
      expect(taskDay(task(createdAt: DateTime(2026, 9, 30))),
          DateTime(2026, 9, 30));
    });

    test('the board rolls at 00:00, not at 10:00', () {
      final lastSecond = DateTime(2026, 9, 29, 23, 59, 59);
      final firstMoment = DateTime(2026, 9, 30);
      expect(isOpenOnDay(lateTimed, lastSecond), isTrue);
      expect(isUpcoming(midnightTimed, lastSecond), isTrue);

      expect(isCarriedOver(lateTimed, firstMoment), isTrue);
      expect(isOpenOnDay(midnightTimed, firstMoment), isTrue);
      // Still before 10:00 the next morning: already yesterday's.
      expect(isCarriedOver(lateTimed, DateTime(2026, 9, 30, 9, 59)), isTrue);
    });
  });

  group('plannedDayOnWrite: no edit moves a task by accident', () {
    test('setting reminders stores the new anchor\'s day', () {
      final before = task(plannedDay: '2026-09-29');
      expect(
        plannedDayOnWrite(
          before: before,
          newReminders: [DateTime(2026, 10, 3, 15), DateTime(2026, 10, 4, 9)],
          newAnchor: DateTime(2026, 10, 4, 9),
        ),
        '2026-10-04',
      );
    });

    test('an early warning does not pick the day', () {
      expect(
        plannedDayOnWrite(
          before: task(),
          newReminders: [DateTime(2026, 10, 2, 17), DateTime(2026, 10, 4, 17)],
          newAnchor: DateTime(2026, 10, 4, 17),
        ),
        '2026-10-04',
      );
    });

    test('with no anchor, the last reminder, as resolveAnchor guesses', () {
      expect(
        plannedDayOnWrite(
          before: task(),
          newReminders: [DateTime(2026, 10, 4, 17), DateTime(2026, 10, 2, 17)],
        ),
        '2026-10-04',
      );
    });

    test('a pre-update timed task with its reminder cleared stays on its '
        'anchor day', () {
      // Written before plannedDay existed: typed on the 27th for the 30th.
      final before = task(
        createdAt: DateTime(2026, 9, 27, 20),
        reminderAts: [DateTime(2026, 9, 30, 17)],
        anchor: DateTime(2026, 9, 30, 17),
      );
      expect(before.plannedDay, isNull);
      final key = plannedDayOnWrite(before: before, newReminders: const []);
      expect(key, '2026-09-30');
      final after = before.copyWith(
        reminderAts: const [],
        clearReminderAnchorAt: true,
        plannedDay: key,
      );
      expect(taskDay(after), taskDay(before));
    });

    test('clearing keeps a plannedDay the task already has', () {
      final before = task(
        plannedDay: '2026-10-02',
        reminderAts: [DateTime(2026, 10, 2, 8)],
        anchor: DateTime(2026, 10, 2, 8),
      );
      expect(plannedDayOnWrite(before: before, newReminders: const []),
          '2026-10-02');
      expect(
        plannedDayOnWrite(
          before: task(plannedDay: '2026-10-05'),
          newReminders: const [],
        ),
        '2026-10-05',
      );
    });

    test('clearing an untimed task that never had a day freezes its '
        'created day', () {
      final before = task(createdAt: DateTime(2026, 9, 21, 22));
      expect(plannedDayOnWrite(before: before, newReminders: const []),
          '2026-09-21');
    });
  });

  group('dayMarks', () {
    test('open beats done, done-only is allDone, empty days are absent', () {
      final marks = dayMarks([
        task(id: 'a', plannedDay: '2026-10-01'),
        task(
          id: 'b',
          isDone: true,
          plannedDay: '2026-10-01',
          completedAt: DateTime(2026, 10, 1, 9),
        ),
        task(
          id: 'c',
          isDone: true,
          plannedDay: '2026-10-03',
          completedAt: DateTime(2026, 10, 2, 18),
        ),
        task(
          id: 'd',
          reminderAts: [DateTime(2026, 10, 7, 20)],
          anchor: DateTime(2026, 10, 7, 20),
        ),
        task(id: 'e', isDone: true, plannedDay: '2026-10-09'),
      ]);
      expect(marks, {
        '2026-10-01': DayMark.open,
        // Done early: both the day it was done and the day it was for.
        '2026-10-02': DayMark.allDone,
        '2026-10-03': DayMark.allDone,
        '2026-10-07': DayMark.open,
        '2026-10-09': DayMark.allDone,
      });
      expect(marks['2026-10-04'] ?? DayMark.none, DayMark.none);
    });

    test('an open task on a day already marked done turns it open', () {
      final marks = dayMarks([
        task(
          id: 'done',
          isDone: true,
          plannedDay: '2026-10-01',
          completedAt: DateTime(2026, 10, 1, 9),
        ),
        task(id: 'open', plannedDay: '2026-10-01'),
      ]);
      expect(marks['2026-10-01'], DayMark.open);
    });

    test('every day marked is a day showsOnDay puts the task on', () {
      final tasks = [
        task(id: 'x', plannedDay: '2026-10-01'),
        task(
          id: 'y',
          isDone: true,
          plannedDay: '2026-10-03',
          completedAt: DateTime(2026, 10, 2, 18),
        ),
      ];
      final marks = dayMarks(tasks);
      for (var d = 1; d <= 31; d++) {
        final day = DateTime(2026, 10, d);
        final shows = tasks.any((t) => showsOnDay(t, day));
        expect(marks.containsKey(dayKey(day)), shows, reason: dayKey(day));
      }
    });
  });
}
