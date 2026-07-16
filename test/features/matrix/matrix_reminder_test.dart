// Pure-logic tests for the Matrix task-reminder feature — formatReminderMoment
// (reminder_picker.dart) and shouldScheduleTaskReminder (matrix_notifier.dart)
// are both plain, Firestore/Hive/NotificationService-free functions by
// design (same reasoning as rooms_notifier_test.dart's nextLeaderAfter and
// prayer_times_service_test.dart's resolveRegion), so this file never spins
// up a ProviderContainer or touches flutter_local_notifications' platform
// channel at all.
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:grow_daily_v2/features/matrix/models/matrix_task.dart';
import 'package:grow_daily_v2/features/matrix/notifiers/matrix_notifier.dart';
import 'package:grow_daily_v2/features/matrix/widgets/reminder_picker.dart';

MatrixTask _task({DateTime? reminderAt, bool isDone = false}) => MatrixTask(
      id: 't1',
      title: 'Test task',
      quadrant: MatrixQuadrant.doFirst,
      isDone: isDone,
      createdAt: DateTime(2026, 7, 16),
      reminderAt: reminderAt,
      order: 0,
    );

void main() {
  // formatReminderMoment formats through intl's DateFormat, which throws
  // LocaleDataException on any locale whose symbol data was never loaded —
  // main.dart loads 'en'/'ar' once at startup (see its own initializeDate
  // Formatting calls); this file has to do the same before either is used.
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ar');
  });

  group('formatReminderMoment', () {
    final now = DateTime(2026, 7, 16, 9, 0);

    test('same calendar day as now reads "Today"', () {
      expect(
        formatReminderMoment(DateTime(2026, 7, 16, 17, 0), false, now: now),
        'Today · 5:00 PM',
      );
    });

    test('the very next calendar day reads "Tomorrow"', () {
      expect(
        formatReminderMoment(DateTime(2026, 7, 17, 9, 30), false, now: now),
        'Tomorrow · 9:30 AM',
      );
    });

    test('anything further out falls back to a month/day date', () {
      expect(
        formatReminderMoment(DateTime(2026, 7, 20, 14, 0), false, now: now),
        'Jul 20 · 2:00 PM',
      );
    });

    test('Arabic uses the Arabic Today/Tomorrow labels', () {
      expect(
        formatReminderMoment(DateTime(2026, 7, 16, 17, 0), true, now: now),
        startsWith('اليوم'),
      );
      expect(
        formatReminderMoment(DateTime(2026, 7, 17, 9, 0), true, now: now),
        startsWith('غدًا'),
      );
    });

    test('follows the real calendar day, not the app\'s 3am cutoff', () {
      // A reminder 20 minutes after an 11:50pm "now" is technically still
      // "tonight," but it's a different calendar date — this documents
      // that formatReminderMoment deliberately ignores
      // DateTimeGameExt.effectiveDay's 3am cutoff (see the function's own
      // doc comment): a reminder fires at a real wall-clock moment, so
      // "Today" here means the device's actual calendar today.
      final lateNow = DateTime(2026, 7, 16, 23, 50);
      expect(
        formatReminderMoment(DateTime(2026, 7, 17, 0, 10), false,
            now: lateNow),
        'Tomorrow · 12:10 AM',
      );
    });
  });

  group('shouldScheduleTaskReminder', () {
    final now = DateTime(2026, 7, 16, 9, 0);
    final future = DateTime(2026, 7, 16, 17, 0);
    final past = DateTime(2026, 7, 16, 8, 0);

    test('fires when reminderAt is future, task is open, master switch is on',
        () {
      expect(
        shouldScheduleTaskReminder(_task(reminderAt: future),
            masterEnabled: true, now: now),
        isTrue,
      );
    });

    test('does not fire when there is no reminderAt at all', () {
      expect(
        shouldScheduleTaskReminder(_task(), masterEnabled: true, now: now),
        isFalse,
      );
    });

    test('does not fire once the task is already done', () {
      expect(
        shouldScheduleTaskReminder(_task(reminderAt: future, isDone: true),
            masterEnabled: true, now: now),
        isFalse,
      );
    });

    test('does not fire once the picked moment has already passed', () {
      expect(
        shouldScheduleTaskReminder(_task(reminderAt: past),
            masterEnabled: true, now: now),
        isFalse,
      );
    });

    test('a reminderAt exactly equal to now does not fire (strict isAfter)',
        () {
      expect(
        shouldScheduleTaskReminder(_task(reminderAt: now),
            masterEnabled: true, now: now),
        isFalse,
      );
    });

    test(
        'does not fire when the app-wide master notification switch is off',
        () {
      expect(
        shouldScheduleTaskReminder(_task(reminderAt: future),
            masterEnabled: false, now: now),
        isFalse,
      );
    });
  });

  group('MatrixTask.reminderAt persistence', () {
    test('toMap/fromMap round-trips reminderAt', () {
      final original = _task(reminderAt: DateTime(2026, 7, 18, 14, 30));
      final restored = MatrixTask.fromMap(original.toMap());
      expect(restored.reminderAt, original.reminderAt);
    });

    test('toMap omits reminderAt entirely when unset', () {
      expect(_task().toMap().containsKey('reminderAt'), isFalse);
    });

    test('copyWith(clearReminderAt: true) clears an existing value', () {
      final task = _task(reminderAt: DateTime(2026, 7, 18, 14, 30));
      expect(task.copyWith(clearReminderAt: true).reminderAt, isNull);
    });

    test(
        'copyWith with neither reminderAt nor the clear flag leaves it '
        'untouched', () {
      final original = DateTime(2026, 7, 18, 14, 30);
      final task = _task(reminderAt: original);
      expect(task.copyWith(title: 'Renamed').reminderAt, original);
    });
  });
}
