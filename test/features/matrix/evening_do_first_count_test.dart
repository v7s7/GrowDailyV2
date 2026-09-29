import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/matrix/models/matrix_task.dart';
import 'package:grow_daily_v2/features/matrix/task_day_outside.dart';

/// The evening note's urgent count («وعندك مهمتين عاجلتين»), main.dart's
/// _openDoFirstCount: open Do First tasks whose day is today or before it.
/// It used to count every open Do First task, so next week's plans were
/// "urgent" tonight. Every clock here is a fixed date passed in.
void main() {
  // Tuesday evening, the hour the note is worded at.
  final tuesday = DateTime(2026, 9, 29, 21, 30);

  MatrixTask task({
    String id = 't',
    MatrixQuadrant quadrant = MatrixQuadrant.doFirst,
    bool isDone = false,
    DateTime? createdAt,
    List<DateTime> reminderAts = const [],
    DateTime? anchor,
    String? plannedDay,
  }) =>
      MatrixTask(
        id: id,
        title: 'Task $id',
        quadrant: quadrant,
        isDone: isDone,
        createdAt: createdAt ?? DateTime(2026, 9, 29, 8),
        completedAt: isDone ? DateTime(2026, 9, 29, 12) : null,
        reminderAts: MatrixTask.normalizeReminders(reminderAts),
        reminderAnchorAt: anchor,
        plannedDay: plannedDay,
        order: 0,
      );

  test('an open Do First task made today counts', () {
    expect(openDoFirstDueCount([task()], tuesday), 1);
  });

  test('a carried-over Do First task still counts', () {
    // Open and past its day is exactly what "urgent" is for.
    final t = task(createdAt: DateTime(2026, 9, 25, 10));
    expect(openDoFirstDueCount([t], tuesday), 1);
  });

  test('a Do First task planned for next week does not count', () {
    final t = task(plannedDay: '2026-10-06');
    expect(openDoFirstDueCount([t], tuesday), 0);
  });

  test('a task timed for tomorrow does not count, even with a warning today',
      () {
    // The warning rings tonight, but the task's day is Wednesday.
    final anchor = DateTime(2026, 9, 30, 9);
    final t = task(
      reminderAts: [DateTime(2026, 9, 29, 22), anchor],
      anchor: anchor,
    );
    expect(openDoFirstDueCount([t], tuesday), 0);
  });

  test('a task made Sunday for Tuesday 17:00 counts on Tuesday', () {
    final anchor = DateTime(2026, 9, 29, 17);
    final t = task(
      createdAt: DateTime(2026, 9, 27, 20),
      reminderAts: [anchor],
      anchor: anchor,
    );
    expect(openDoFirstDueCount([t], tuesday), 1);
  });

  test('done tasks and other quadrants never count', () {
    final tasks = [
      task(id: 'done', isDone: true),
      task(id: 'schedule', quadrant: MatrixQuadrant.schedule),
      task(id: 'delegate', quadrant: MatrixQuadrant.delegate),
      task(id: 'eliminate', quadrant: MatrixQuadrant.eliminate),
      task(id: 'open'),
    ];
    expect(openDoFirstDueCount(tasks, tuesday), 1);
  });

  test('the count rolls at real midnight, not at 10:00', () {
    final wednesdays = task(plannedDay: '2026-09-30');
    expect(
      openDoFirstDueCount([wednesdays], DateTime(2026, 9, 29, 23, 59)),
      0,
    );
    expect(openDoFirstDueCount([wednesdays], DateTime(2026, 9, 30, 0, 1)), 1);
  });

  test('the time of day passed in does not matter, only its day', () {
    final t = task(plannedDay: '2026-09-29');
    expect(openDoFirstDueCount([t], DateTime(2026, 9, 29)), 1);
    expect(openDoFirstDueCount([t], DateTime(2026, 9, 29, 23, 59, 59)), 1);
  });
}
