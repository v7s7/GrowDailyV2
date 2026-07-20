// Tests for the habit "birth date" rule — see IslamicHabitTemplate.
// createdAt and isScheduledFor: a habit must never read as scheduled (and
// therefore never as "missed") on any day before it existed, for daily,
// weekly-scheduled, and legacy (no-date) habits alike.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';

IslamicHabitTemplate habit({
  DateTime? createdAt,
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
}
