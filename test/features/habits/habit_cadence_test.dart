// A habit remembers the schedules it ran on, so a past day is judged by the
// schedule it had then.
//
// Aziz, 2026-09-18: "i had a habit that is spec days, and after some weeks, i
// made it daily habit, it should still for the previous days that is spec
// days, like rest rest days and the other, and the days after are daily. so
// its fair for the user."
//
// This file pins the record itself: how an edit adds to it, how a day finds
// its schedule in it, and that it survives every copy and every store the
// habit passes through. What the surfaces do with it is pinned in
// schedule_change_history_test.dart.
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_cadence.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/catalog_overrides_notifier.dart';

const monThu = HabitCadence(
  frequencyType: HabitFrequencyType.weekly,
  frequencyTarget: 2,
  scheduledWeekdays: [DateTime.monday, DateTime.thursday],
);
const daily = HabitCadence(
  frequencyType: HabitFrequencyType.daily,
  frequencyTarget: 1,
);
const fourAWeek = HabitCadence(
  frequencyType: HabitFrequencyType.weekly,
  frequencyTarget: 4,
);

IslamicHabitTemplate habit({
  HabitCadence cadence = daily,
  List<PastCadence> past = const [],
  DateTime? createdAt,
}) =>
    IslamicHabitTemplate(
      id: 'h',
      name: 'Sadaqah',
      description: '',
      category: HabitCategory.custom,
      frequencyType: cadence.frequencyType,
      frequencyTarget: cadence.frequencyTarget,
      scheduledWeekdays: cadence.scheduledWeekdays,
      hasTimer: false,
      xpReward: 10,
      goldReward: 5,
      createdAt: createdAt ?? DateTime(2026, 8, 1),
      pastCadences: past,
    );

void main() {
  // Wednesday 16 September 2026, the day of the change in every scenario.
  final wed16 = DateTime(2026, 9, 16);
  final born = DateTime(2026, 8, 1);

  group('an edit adds to the record', () {
    test('Monday-and-Thursday made daily keeps its schedule up to yesterday',
        () {
      final past = pastCadencesAfterChange(
        past: const [],
        current: monThu,
        next: daily,
        bornOn: born,
        today: wed16,
      );
      expect(past, hasLength(1));
      expect(past.single.until, DateTime(2026, 9, 15));
      expect(past.single.cadence.sameAs(monThu), isTrue);
    });

    test('a save that keeps the schedule records nothing', () {
      // Weekday order is not a schedule: [4, 1] is still Monday and Thursday.
      const reordered = HabitCadence(
        frequencyType: HabitFrequencyType.weekly,
        frequencyTarget: 2,
        scheduledWeekdays: [DateTime.thursday, DateTime.monday],
      );
      final past = pastCadencesAfterChange(
        past: const [],
        current: monThu,
        next: reordered,
        bornOn: born,
        today: wed16,
      );
      expect(past, isEmpty);
    });

    test('a later change adds a second period after the first', () {
      final first = pastCadencesAfterChange(
        past: const [],
        current: monThu,
        next: daily,
        bornOn: born,
        today: wed16,
      );
      final second = pastCadencesAfterChange(
        past: first,
        current: daily,
        next: fourAWeek,
        bornOn: born,
        today: DateTime(2026, 10, 3),
      );
      expect(second, hasLength(2));
      expect(second[0].until, DateTime(2026, 9, 15));
      expect(second[0].cadence.sameAs(monThu), isTrue);
      expect(second[1].until, DateTime(2026, 10, 2));
      expect(second[1].cadence.sameAs(daily), isTrue);
    });

    test('two edits on one day are one change: the last save is the day', () {
      final once = pastCadencesAfterChange(
        past: const [],
        current: monThu,
        next: daily,
        bornOn: born,
        today: wed16,
      );
      final twice = pastCadencesAfterChange(
        past: once,
        current: daily,
        next: fourAWeek,
        bornOn: born,
        today: wed16,
      );
      expect(twice, hasLength(1),
          reason: 'daily governed no finished day, so it is not history');
      expect(twice.single.until, DateTime(2026, 9, 15));
      expect(twice.single.cadence.sameAs(monThu), isTrue);
    });

    test('changing it straight back the same day leaves no trace', () {
      final changed = pastCadencesAfterChange(
        past: const [],
        current: monThu,
        next: daily,
        bornOn: born,
        today: wed16,
      );
      final back = pastCadencesAfterChange(
        past: changed,
        current: daily,
        next: monThu,
        bornOn: born,
        today: wed16,
      );
      expect(back, isEmpty,
          reason: 'Monday and Thursday simply carries on, as if never touched');
    });

    test('changing back to the older of two schedules reopens its period', () {
      final past = [
        PastCadence(until: DateTime(2026, 9, 5), cadence: monThu),
        PastCadence(until: DateTime(2026, 9, 15), cadence: daily),
      ];
      // fourAWeek has governed only today, and the person goes back to daily.
      final back = pastCadencesAfterChange(
        past: past,
        current: fourAWeek,
        next: daily,
        bornOn: born,
        today: wed16,
      );
      expect(back, hasLength(1));
      expect(back.single.cadence.sameAs(monThu), isTrue);
      expect(cadenceOnDay(back, daily, DateTime(2026, 9, 10)).sameAs(daily),
          isTrue);
    });

    test('a habit born today is simply re-scheduled', () {
      final past = pastCadencesAfterChange(
        past: const [],
        current: monThu,
        next: daily,
        bornOn: wed16,
        today: wed16,
      );
      expect(past, isEmpty);
    });

    test('a habit with no known birth date still records its first change',
        () {
      final past = pastCadencesAfterChange(
        past: const [],
        current: monThu,
        next: daily,
        bornOn: null,
        today: wed16,
      );
      expect(past.single.until, DateTime(2026, 9, 15));
    });
  });

  group('a day finds the schedule it had', () {
    final past = [
      PastCadence(until: DateTime(2026, 9, 5), cadence: monThu),
      PastCadence(until: DateTime(2026, 9, 15), cadence: fourAWeek),
    ];

    test('each period covers its days, the current one everything after', () {
      expect(cadenceOnDay(past, daily, DateTime(2026, 8, 20)), same(monThu));
      expect(cadenceOnDay(past, daily, DateTime(2026, 9, 5)), same(monThu),
          reason: 'until is inclusive');
      expect(cadenceOnDay(past, daily, DateTime(2026, 9, 6)), same(fourAWeek));
      expect(cadenceOnDay(past, daily, DateTime(2026, 9, 15)),
          same(fourAWeek));
      expect(cadenceOnDay(past, daily, DateTime(2026, 9, 16)), same(daily));
      expect(cadenceOnDay(past, daily, DateTime(2027, 1, 1)), same(daily));
    });

    test('the time of day never moves a day into another period', () {
      expect(
        cadenceOnDay(past, daily, DateTime(2026, 9, 15, 23, 59, 59)),
        same(fourAWeek),
      );
    });

    test('no record means the current schedule, every day', () {
      expect(cadenceOnDay(const [], daily, DateTime(2020, 1, 1)), same(daily));
    });

    test('the template reads its own record', () {
      final h = habit(
        cadence: daily,
        past: [PastCadence(until: DateTime(2026, 9, 15), cadence: monThu)],
      );
      // Tuesday 8 September: an off-day then, whatever the habit is now.
      expect(h.runsOn(DateTime(2026, 9, 8)), isFalse);
      expect(h.isScheduledFor(DateTime(2026, 9, 8)), isFalse);
      expect(h.isScheduledFor(DateTime(2026, 9, 7)), isTrue); // Monday
      // Tuesday 22 September: daily now.
      expect(h.isScheduledFor(DateTime(2026, 9, 22)), isTrue);
      expect(h.cadenceOn(DateTime(2026, 9, 22)).sameAs(daily), isTrue);
    });
  });

  group('the record survives every store and every copy', () {
    final past = [
      PastCadence(until: DateTime(2026, 9, 5), cadence: monThu),
      PastCadence(until: DateTime(2026, 9, 15), cadence: fourAWeek),
    ];

    void expectSameRecord(List<PastCadence> actual) {
      expect(actual, hasLength(2));
      expect(actual[0].until, DateTime(2026, 9, 5));
      expect(actual[0].cadence.sameAs(monThu), isTrue);
      expect(actual[1].until, DateTime(2026, 9, 15));
      expect(actual[1].cadence.sameAs(fourAWeek), isTrue);
    }

    test('habit document round trip', () {
      final stored = habit(past: past).toFirestore();
      expect(stored['scheduleHistory'], [
        {
          'until': '2026-09-05',
          'frequencyType': 'weekly',
          'frequencyTarget': 2,
          'scheduledWeekdays': [DateTime.monday, DateTime.thursday],
        },
        {
          'until': '2026-09-15',
          'frequencyType': 'weekly',
          'frequencyTarget': 4,
        },
      ]);
      expectSameRecord(IslamicHabitTemplate.fromMap('h', stored).pastCadences);
    });

    test('a habit that never changed stores no history key at all', () {
      expect(habit().toFirestore().containsKey('scheduleHistory'), isFalse);
    });

    test('Hive-shaped maps read back the same', () {
      // Hive hands nested maps back as Map<dynamic, dynamic> and numbers as
      // num; the guest store and the launch mirror both go through it.
      final hiveShaped = <dynamic, dynamic>{
        'name': 'Sadaqah',
        'frequencyType': 'daily',
        'frequencyTarget': 1,
        'scheduleHistory': <dynamic>[
          <dynamic, dynamic>{
            'until': '2026-09-15',
            'frequencyType': 'weekly',
            'frequencyTarget': 4.0,
          },
          <dynamic, dynamic>{
            'until': '2026-09-05',
            'frequencyType': 'weekly',
            'frequencyTarget': 2,
            'scheduledWeekdays': <dynamic>[4, 1.0],
          },
        ],
      };
      final read = IslamicHabitTemplate.fromMap(
        'h',
        Map<String, dynamic>.from(hiveShaped),
      );
      expectSameRecord(read.pastCadences);
    });

    test('junk entries cost themselves, never the habit', () {
      final read = parsePastCadences([
        'nonsense',
        {'until': 'not a date', 'frequencyType': 'daily'},
        {'frequencyType': 'daily'},
        {
          'until': '2026-09-05',
          'frequencyType': 'weekly',
          'frequencyTarget': 2,
          'scheduledWeekdays': [0, 1, 4, 9, 'x'],
        },
      ]);
      expect(read, hasLength(1));
      expect(read.single.cadence.scheduledWeekdays,
          [DateTime.monday, DateTime.thursday]);
      expect(parsePastCadences(null), isEmpty);
      expect(parsePastCadences({'not': 'a list'}), isEmpty);
    });

    test('two entries for one day keep the later one', () {
      final read = parsePastCadences([
        {'until': '2026-09-05', 'frequencyType': 'daily'},
        {'until': '2026-09-05', 'frequencyType': 'weekly', 'frequencyTarget': 4},
      ]);
      expect(read.single.cadence.sameAs(fourAWeek), isTrue);
    });

    test('every copy helper carries it', () {
      final h = habit(past: past);
      expectSameRecord(h.withDates(
        createdAt: DateTime(2026, 9, 1),
        archivedAt: DateTime(2026, 9, 20),
      ).pastCadences);
      expectSameRecord(h.withCreatedAt(DateTime(2026, 9, 1)).pastCadences);
      expectSameRecord(h.withReminderOffset(-15).pastCadences);
    });

    test('a preset override carries it, stores it and reads it back', () {
      final o = CatalogHabitOverride(pastCadences: past);
      expect(o.isEmpty, isFalse,
          reason: 'a preset edited back to its catalog schedule still has a '
              'history, and dropping the entry would lose it');
      final preset = IslamicHabitCatalog.templates.first;
      expectSameRecord(o.applyTo(preset).pastCadences);
      final stored = o.toMap();
      expect(stored.keys, ['scheduleHistory']);
      expectSameRecord(CatalogHabitOverride.fromMap(stored).pastCadences);
    });

    test('an override with no history stores no history key', () {
      const o = CatalogHabitOverride(frequencyTarget: 3);
      expect(o.toMap().containsKey('scheduleHistory'), isFalse);
      expect(const CatalogHabitOverride().isEmpty, isTrue);
    });
  });
}
