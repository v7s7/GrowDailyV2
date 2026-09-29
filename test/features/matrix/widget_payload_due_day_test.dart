import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/matrix/models/matrix_task.dart';
import 'package:grow_daily_v2/features/matrix/task_day_outside.dart';

/// The `dueAt` main.dart hands the task widgets (widgetDueAt), which the Lock
/// Screen sorts by (ios/GrowDailyWidget/MatrixLockScreenOrder.swift): a time
/// on the day drawn, then no time, then a time on another day.
///
/// `lockScreenBand` below mirrors the Swift band rule, so the tests read in
/// the widget's own terms. Every clock is a fixed date passed in.
void main() {
  final tuesday = DateTime(2026, 9, 29, 8);

  MatrixTask task({
    String id = 't',
    DateTime? createdAt,
    List<DateTime> reminderAts = const [],
    DateTime? anchor,
    String? plannedDay,
  }) =>
      MatrixTask(
        id: id,
        title: 'Task $id',
        quadrant: MatrixQuadrant.schedule,
        isDone: false,
        createdAt: createdAt ?? DateTime(2026, 9, 29, 7),
        reminderAts: MatrixTask.normalizeReminders(reminderAts),
        reminderAnchorAt: anchor,
        plannedDay: plannedDay,
        order: 0,
      );

  /// MatrixLockScreenOrder.swift's lockScreenBand, on [day].
  String lockScreenBand(DateTime? dueAt, DateTime day) {
    if (dueAt == null) return 'untimed';
    final same = dueAt.year == day.year &&
        dueAt.month == day.month &&
        dueAt.day == day.day;
    return same ? 'today' : 'otherDay';
  }

  group('timed tasks keep the picked moment', () {
    test('a task timed today sends its anchor', () {
      final anchor = DateTime(2026, 9, 29, 17);
      final t = task(
        reminderAts: [DateTime(2026, 9, 29, 16), anchor],
        anchor: anchor,
      );
      expect(widgetDueAt(t, tuesday), anchor);
    });

    test('a task timed for a later day sends its anchor, not its day', () {
      final anchor = DateTime(2026, 10, 2, 9, 30);
      final t = task(reminderAts: [anchor], anchor: anchor);
      expect(widgetDueAt(t, tuesday), anchor);
    });

    test('a legacy timed task with no stored anchor still sends nothing', () {
      // Unchanged from before: the widget has only ever been sent the
      // stored anchor.
      final t = task(reminderAts: [DateTime(2026, 10, 2, 9)]);
      expect(widgetDueAt(t, tuesday), isNull);
    });
  });

  group('untimed tasks', () {
    test('planned for tomorrow: the last minute of tomorrow', () {
      final t = task(plannedDay: '2026-09-30');
      final due = widgetDueAt(t, tuesday);
      expect(due, DateTime(2026, 9, 30, 23, 59));
      expect(lockScreenBand(due, tuesday), 'otherDay');
    });

    test('made today with no plan: no time, as before', () {
      expect(widgetDueAt(task(), tuesday), isNull);
    });

    test('planned for today: no time, it is today\'s untimed work', () {
      expect(widgetDueAt(task(plannedDay: '2026-09-29'), tuesday), isNull);
    });

    test('carried over: no time, it stays with today\'s untimed work', () {
      final byDate = task(plannedDay: '2026-09-26');
      final byCreation = task(createdAt: DateTime(2026, 9, 25, 10));
      expect(widgetDueAt(byDate, tuesday), isNull);
      expect(widgetDueAt(byCreation, tuesday), isNull);
    });

    test('across a month and a year end', () {
      expect(
        widgetDueAt(task(plannedDay: '2026-10-01'), DateTime(2026, 9, 30, 22)),
        DateTime(2026, 10, 1, 23, 59),
      );
      expect(
        widgetDueAt(task(plannedDay: '2027-01-01'), DateTime(2026, 12, 31, 9)),
        DateTime(2027, 1, 1, 23, 59),
      );
    });

    test('after a timed task of the same later day', () {
      // The Swift side sorts the other-day band earliest first, so the
      // untimed task follows that day's times, the order a day board reads.
      final timed = DateTime(2026, 9, 30, 17);
      final due = widgetDueAt(task(plannedDay: '2026-09-30'), tuesday)!;
      expect(due.isAfter(timed), isTrue);
    });

    test('on a list still stale when its day arrives, it follows the times',
        () {
      // The app is usually not running at midnight, so the widget can draw
      // Wednesday with the list written on Tuesday. The task then falls in
      // Wednesday's "time today" band, and 23:59 keeps it after Wednesday's
      // real times instead of at the top as a 00:00 would.
      final wednesday = DateTime(2026, 9, 30, 7);
      final due = widgetDueAt(task(plannedDay: '2026-09-30'), tuesday);
      expect(lockScreenBand(due, wednesday), 'today');
      expect(due!.isAfter(DateTime(2026, 9, 30, 23, 58)), isTrue);
      // And once the app writes on Wednesday, it is plain untimed work.
      expect(widgetDueAt(task(plannedDay: '2026-09-30'), wednesday), isNull);
    });
  });
}
