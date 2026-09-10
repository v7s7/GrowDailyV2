// A day the habit asked nothing of is "covered", and only such a day.
//
// Aziz, 2026-09-08: a Monday-Wednesday-Friday habit drew four dim squares a
// week and a four-a-week habit three plain ones, and both read as missing
// days although the person did what they had to. The rule here decides
// which empty squares get the soft green instead, on every surface that
// paints a habit's week (the Grid, the recap dots, the reports matrix; the
// room strip has its own equivalent in RoomParticipant.isRestDay).
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/grid/models/covered_day.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/models/weekly_quota_plan.dart';

void main() {
  // Wednesday 19 August 2026.
  final today = DateTime(2026, 8, 19);

  IslamicHabitTemplate habit({
    List<int> weekdays = const [],
    HabitFrequencyType frequency = HabitFrequencyType.daily,
    int target = 1,
    DateTime? createdAt,
    DateTime? archivedAt,
  }) =>
      IslamicHabitTemplate(
        id: 'h',
        name: 'h',
        description: '',
        category: HabitCategory.health,
        frequencyType: frequency,
        frequencyTarget: target,
        scheduledWeekdays: weekdays,
        hasTimer: false,
        xpReward: 10,
        goldReward: 1,
        createdAt: createdAt,
        archivedAt: archivedAt,
      );

  bool covered(
    IslamicHabitTemplate h,
    DateTime day, {
    SquareState square = SquareState.none,
    DayDemand? demand,
  }) =>
      isCoveredDay(
        habit: h,
        day: day,
        today: today,
        square: square,
        demand: demand,
      );

  group('a specific-days habit', () {
    final mwf = habit(
      weekdays: const [DateTime.monday, DateTime.wednesday, DateTime.friday],
      frequency: HabitFrequencyType.weekly,
      target: 3,
    );

    test('its off-days are covered, today included', () {
      expect(covered(mwf, DateTime(2026, 8, 18)), isTrue, reason: 'Tuesday');
      expect(covered(mwf, DateTime(2026, 8, 15)), isTrue, reason: 'Saturday');
    });

    test('its due days are not, empty or not', () {
      expect(covered(mwf, DateTime(2026, 8, 17)), isFalse, reason: 'Monday');
      expect(covered(mwf, today), isFalse, reason: 'Wednesday, today');
    });

    test('a future off-day is not covered yet', () {
      expect(covered(mwf, DateTime(2026, 8, 20)), isFalse, reason: 'Thursday');
    });

    test('a marked square is never covered, whatever the day', () {
      for (final s in SquareState.values.where((s) => s != SquareState.none)) {
        expect(covered(mwf, DateTime(2026, 8, 18), square: s), isFalse,
            reason: '$s');
      }
    });
  });

  group('a flexible weekly quota', () {
    final four = habit(frequency: HabitFrequencyType.weekly, target: 4);

    test('a spare day is covered once it has passed, not while it is today',
        () {
      expect(covered(four, DateTime(2026, 8, 18), demand: DayDemand.spare),
          isTrue);
      expect(covered(four, today, demand: DayDemand.spare), isFalse,
          reason: 'still open: the plain square keeps this one meaning');
    });

    test('an earned day is covered the moment the target is met, today too',
        () {
      expect(covered(four, today, demand: DayDemand.earned), isTrue);
      expect(covered(four, DateTime(2026, 8, 18), demand: DayDemand.earned),
          isTrue);
    });

    test('an owed day is never covered', () {
      expect(covered(four, DateTime(2026, 8, 18), demand: DayDemand.owed),
          isFalse);
    });

    test('without the week in hand nothing is covered', () {
      expect(covered(four, DateTime(2026, 8, 18)), isFalse);
    });
  });

  group('the habit has to exist on the day', () {
    test('days before it was created are not covered', () {
      final h = habit(
        weekdays: const [DateTime.monday],
        frequency: HabitFrequencyType.weekly,
        createdAt: DateTime(2026, 8, 18, 14, 30),
      );
      expect(covered(h, DateTime(2026, 8, 17)), isFalse, reason: 'day before');
      expect(covered(h, DateTime(2026, 8, 18)), isTrue,
          reason: 'the creation day itself counts');
    });

    test('days after it was archived are not covered', () {
      final h = habit(
        weekdays: const [DateTime.monday],
        frequency: HabitFrequencyType.weekly,
        archivedAt: DateTime(2026, 8, 16),
      );
      expect(covered(h, DateTime(2026, 8, 18)), isFalse);
      expect(covered(h, DateTime(2026, 8, 15)), isTrue);
    });
  });

  test('a plain daily habit has no covered days', () {
    final daily = habit();
    for (var d = 15; d <= 19; d++) {
      expect(covered(daily, DateTime(2026, 8, d)), isFalse, reason: 'Aug $d');
    }
  });

  test('the covered fill is the system green, softer than a done square',
      () {
    for (final dark in [true, false]) {
      final fill = coveredDayFill(dark);
      final done = SquareState.complete.fill(dark);
      expect(fill.red, done.red);
      expect(fill.green, done.green);
      expect(fill.blue, done.blue);
      expect(fill.opacity, lessThan(done.opacity));
      expect(fill.opacity, greaterThan(0.1),
          reason: 'faint enough to vanish is the bug this replaces');
    }
  });


  // ── The gold ring ────────────────────────────────────────────────────
  //
  // Aziz, 2026-09-09: "the habits that I don't need to do today, the square
  // should not be outlined." The ring followed the calendar, so every habit
  // wore it on today's column whether or not today asked anything of it.
  group('today\'s ring is an ask, not a date stamp', () {
    bool ring({
      bool isToday = true,
      bool isScheduled = true,
      bool isCovered = false,
    }) =>
        showsTodayRing(
          isToday: isToday,
          isScheduled: isScheduled,
          isCovered: isCovered,
        );

    test('a day that is owed wears it', () {
      expect(ring(), isTrue);
    });

    test('an off-day of a specific-days habit does not', () {
      // The reported case: a Mon/Wed/Fri habit on a Tuesday. Covered and
      // unscheduled both hold here, and either alone is enough.
      expect(ring(isScheduled: false, isCovered: true), isFalse);
      expect(ring(isScheduled: false), isFalse);
    });

    test('a quota that has already been met does not', () {
      // scheduledWeekdays is empty for a flexible quota, so the day IS
      // scheduled; being covered is the whole of what stops the ring.
      expect(ring(isCovered: true), isFalse);
    });

    test('a quota still short of its target keeps it', () {
      expect(ring(isCovered: false), isTrue);
    });

    test('no other day ever wears it', () {
      for (final scheduled in [true, false]) {
        for (final covered in [true, false]) {
          expect(ring(isToday: false, isScheduled: scheduled, isCovered: covered),
              isFalse);
        }
      }
    });

    test('a day already done today still wears it', () {
      // isCoveredDay is false the moment a square carries a mark, so a
      // finished-but-owed day stays circled: the ring says "this is today's
      // business", and it was.
      final daily = habit();
      expect(covered(daily, today, square: SquareState.complete), isFalse);
      expect(ring(isCovered: false), isTrue);
    });
  });
}
