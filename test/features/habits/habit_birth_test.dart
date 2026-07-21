// Tests for the habit "birth date" and "archive date" rules — see
// IslamicHabitTemplate.createdAt/archivedAt and isScheduledFor: a habit
// must never read as scheduled (and therefore never as "missed") on any
// day before it existed, and once archived it must keep reading as
// scheduled through the archive day itself and stop on every day after —
// for daily, weekly-scheduled, and legacy (no-date) habits alike.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';

IslamicHabitTemplate habit({
  DateTime? createdAt,
  DateTime? archivedAt,
  List<int> weekdays = const [],
}) =>
    IslamicHabitTemplate(
      id: 'h',
      name: 'Test',
      description: '',
      category: HabitCategory.faith,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      scheduledWeekdays: weekdays,
      hasTimer: false,
      xpReward: 10,
      goldReward: 5,
      createdAt: createdAt,
      archivedAt: archivedAt,
    );

void main() {
  // 2026-07-15 is a Wednesday.
  final born = DateTime(2026, 7, 15);

  group('isScheduledFor with a birth date', () {
    test('daily habit: unscheduled before birth, scheduled from it on', () {
      final h = habit(createdAt: born);
      expect(h.isScheduledFor(DateTime(2026, 7, 14)), isFalse); // yesterday
      expect(h.isScheduledFor(born), isTrue); // birth day itself
      expect(h.isScheduledFor(DateTime(2026, 7, 16)), isTrue); // after
    });

    test('weekly habit: birth date and weekday must BOTH hold', () {
      // Scheduled Mondays only, born Wednesday the 15th.
      final h = habit(createdAt: born, weekdays: const [DateTime.monday]);
      // The Monday before birth (July 13) — right weekday, too early.
      expect(h.isScheduledFor(DateTime(2026, 7, 13)), isFalse);
      // Birth day itself is a Wednesday — wrong weekday.
      expect(h.isScheduledFor(born), isFalse);
      // The first Monday after birth (July 20) — both hold.
      expect(h.isScheduledFor(DateTime(2026, 7, 20)), isTrue);
    });

    test('a time-of-day on createdAt never leaks into the comparison', () {
      // Born at 23:59 — the whole birth DAY still counts as scheduled.
      final h = habit(createdAt: DateTime(2026, 7, 15, 23, 59));
      expect(h.isScheduledFor(DateTime(2026, 7, 15)), isTrue);
      expect(h.isScheduledFor(DateTime(2026, 7, 14)), isFalse);
    });

    test('legacy habit with no birth date behaves exactly as before', () {
      final h = habit();
      expect(h.isScheduledFor(DateTime(2020, 1, 1)), isTrue);
    });

    test('withCreatedAt stamps the date without touching anything else', () {
      final stamped = habit(weekdays: const [DateTime.friday])
          .withCreatedAt(born);
      expect(stamped.createdAt, born);
      expect(stamped.scheduledWeekdays, const [DateTime.friday]);
      expect(stamped.id, 'h');
    });

    test('createdAt round-trips through toFirestore/fromMap as a string',
        () {
      final map = habit(createdAt: born).toFirestore();
      expect(map['createdAt'], born.toIso8601String());
      final back = IslamicHabitTemplate.fromMap('h', map);
      expect(back.createdAt, born);
    });
  });

  group('isScheduledFor with an archive date', () {
    // 2026-07-20 is a Monday.
    final archived = DateTime(2026, 7, 20);

    test('daily habit: scheduled through the archive day, not after', () {
      final h = habit(archivedAt: archived);
      expect(h.isScheduledFor(DateTime(2026, 7, 19)), isTrue); // before
      expect(h.isScheduledFor(archived), isTrue); // archive day itself
      expect(h.isScheduledFor(DateTime(2026, 7, 21)), isFalse); // after
    });

    test('weekly habit: weekday match and archive cutoff must BOTH hold',
        () {
      // Scheduled Mondays only, archived on a Monday.
      final h =
          habit(archivedAt: archived, weekdays: const [DateTime.monday]);
      // The Monday it was archived on — right weekday, still in range.
      expect(h.isScheduledFor(archived), isTrue);
      // The following Monday (July 27) — right weekday, too late.
      expect(h.isScheduledFor(DateTime(2026, 7, 27)), isFalse);
    });

    test('a time-of-day on archivedAt never leaks into the comparison', () {
      // Archived at 00:01 — the whole archive DAY still counts as
      // scheduled, exactly like createdAt's own end-of-day counterpart.
      final h = habit(archivedAt: DateTime(2026, 7, 20, 0, 1));
      expect(h.isScheduledFor(DateTime(2026, 7, 20)), isTrue);
      expect(h.isScheduledFor(DateTime(2026, 7, 21)), isFalse);
    });

    test('createdAt and archivedAt together bound an exact window', () {
      final born = DateTime(2026, 6, 1);
      final h = habit(createdAt: born, archivedAt: archived);
      expect(h.isScheduledFor(DateTime(2026, 5, 31)), isFalse); // too early
      expect(h.isScheduledFor(born), isTrue); // first day
      expect(h.isScheduledFor(DateTime(2026, 7, 1)), isTrue); // mid-window
      expect(h.isScheduledFor(archived), isTrue); // last day
      expect(h.isScheduledFor(DateTime(2026, 7, 21)), isFalse); // too late
    });

    test('an active (never archived) habit is unaffected by this rule', () {
      final h = habit();
      expect(h.isScheduledFor(DateTime(2099, 1, 1)), isTrue);
    });

    test('withDates stamps both dates without touching anything else', () {
      final born = DateTime(2026, 6, 1);
      final stamped = habit(weekdays: const [DateTime.friday])
          .withDates(createdAt: born, archivedAt: archived);
      expect(stamped.createdAt, born);
      expect(stamped.archivedAt, archived);
      expect(stamped.scheduledWeekdays, const [DateTime.friday]);
      expect(stamped.id, 'h');
    });

    test('archivedAt round-trips through toFirestore/fromMap as a string',
        () {
      final map = habit(archivedAt: archived).toFirestore();
      expect(map['archivedAt'], archived.toIso8601String());
      final back = IslamicHabitTemplate.fromMap('h', map);
      expect(back.archivedAt, archived);
    });
  });
}
