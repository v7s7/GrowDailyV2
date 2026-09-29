// Which scene Doum plays on the launch curtain (Aziz, 2026-09-29: his
// coffee in the morning, sleepy after 10 pm, random when nothing is special;
// designed on the canvas's "Through the day" page).
//
// The rule these guard hardest is the mug's: it never shows with a fast on
// the day's plan, in Ramadan, or on the day before Ramadan, when the Gulf's
// moon sighting can start the fast a day ahead of the table.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/launch/launch_scene.dart';

LaunchScene at(
  DateTime now, {
  DateTime? lastOpen,
  bool fasting = false,
  bool fresh = false,
  bool updated = false,
  DateTime? fullDay,
  DateTime? stepsGoal,
  int seed = 1,
}) =>
    pickLaunchScene(
      now: now,
      lastOpen: lastOpen,
      fastingPlanned: fasting,
      freshInstall: fresh,
      updated: updated,
      lastFullDay: fullDay,
      lastStepsGoal: stepsGoal,
      random: math.Random(seed),
    );

const ordinary = {LaunchScene.dayRing, LaunchScene.turnaround};

IslamicHabitTemplate custom(String name, {List<int> days = const []}) =>
    IslamicHabitTemplate(
      id: 'c_$name',
      name: name,
      description: '',
      category: HabitCategory.faith,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      scheduledWeekdays: days,
      hasTimer: false,
      xpReward: 10,
      goldReward: 5,
    );

void main() {
  // 2026-10-05 is a Monday, far from Ramadan (1448 starts 2027-02-08).
  final monday = DateTime(2026, 10, 5);
  DateTime on(DateTime d, int h, [int m = 0]) =>
      DateTime(d.year, d.month, d.day, h, m);
  final yesterday = on(DateTime(2026, 10, 4), 21);

  group('the morning coffee', () {
    test('the first open of the day, before 11', () {
      expect(at(on(monday, 7, 30), lastOpen: yesterday),
          LaunchScene.morningCoffee);
      expect(at(on(monday, 4), lastOpen: yesterday), LaunchScene.morningCoffee);
      expect(at(on(monday, 10, 59), lastOpen: yesterday),
          LaunchScene.morningCoffee);
    });

    test('a fresh install counts as a first open', () {
      expect(at(on(monday, 8)), LaunchScene.morningCoffee);
    });

    test('not the second open of the morning', () {
      for (var seed = 0; seed < 8; seed++) {
        expect(at(on(monday, 9), lastOpen: on(monday, 7), seed: seed),
            isIn(ordinary));
      }
    });

    test('an open after midnight still belongs to the night before', () {
      // Opened at 01:00, then at 08:00: the morning's first open.
      expect(at(on(monday, 8), lastOpen: on(monday, 1)),
          LaunchScene.morningCoffee);
      expect(launchDayOf(on(monday, 1)), DateTime(2026, 10, 4));
      expect(launchDayOf(on(monday, 4)), monday);
    });

    test('never with a fast on the plan', () {
      for (var seed = 0; seed < 8; seed++) {
        expect(
          at(on(monday, 7), lastOpen: yesterday, fasting: true, seed: seed),
          isIn(ordinary),
        );
      }
    });

    test('never on the day before Ramadan, or in it', () {
      final eve = DateTime(2027, 2, 7); // 1448 starts 2027-02-08
      for (var seed = 0; seed < 8; seed++) {
        expect(at(on(eve, 7), lastOpen: on(DateTime(2027, 2, 6), 21), seed: seed),
            isIn(ordinary));
      }
      expect(at(on(DateTime(2027, 2, 8), 7), lastOpen: on(eve, 21)),
          LaunchScene.ramadanLantern);
    });

    test('back after Eid', () {
      // Eid al-Fitr 1448 is 2027-03-09 to 03-11, Eid's own scene; the mug is
      // back the morning after.
      expect(
        at(on(DateTime(2027, 3, 12), 8), lastOpen: on(DateTime(2027, 3, 11), 21)),
        LaunchScene.morningCoffee,
      );
    });
  });

  group('the rest of the day', () {
    test('asleep from 22:00 to 04:00', () {
      expect(at(on(monday, 22)), LaunchScene.nightAsleep);
      expect(at(on(monday, 23, 59)), LaunchScene.nightAsleep);
      expect(at(on(monday, 2), lastOpen: yesterday), LaunchScene.nightAsleep);
      expect(at(on(monday, 3, 59), lastOpen: yesterday),
          LaunchScene.nightAsleep);
    });

    test('the checklist from 18:00 to 22:00', () {
      expect(at(on(monday, 18), lastOpen: on(monday, 9)),
          LaunchScene.eveningChecklist);
      expect(at(on(monday, 21, 59), lastOpen: on(monday, 9)),
          LaunchScene.eveningChecklist);
    });

    test('otherwise the ring or the turn, and both come up', () {
      final seen = {
        for (var seed = 0; seed < 20; seed++)
          at(on(monday, 14), lastOpen: on(monday, 9), seed: seed),
      };
      expect(seen, ordinary);
    });
  });

  group('above the hour', () {
    test('every open in Ramadan, day or night', () {
      final r = DateTime(2027, 2, 20);
      expect(at(on(r, 3)), LaunchScene.ramadanLantern);
      expect(at(on(r, 14), lastOpen: on(r, 9)), LaunchScene.ramadanLantern);
      expect(at(on(r, 23), lastOpen: on(r, 9)), LaunchScene.ramadanLantern);
    });

    test('back after three days away, whatever the hour', () {
      final away = on(DateTime(2026, 10, 2), 20); // Friday evening
      expect(at(on(monday, 8), lastOpen: away), LaunchScene.welcomeBack);
      expect(at(on(monday, 23), lastOpen: away), LaunchScene.welcomeBack);
    });

    test('two days away is not coming back', () {
      final twoDays = on(DateTime(2026, 10, 3), 20);
      expect(at(on(monday, 8), lastOpen: twoDays), LaunchScene.morningCoffee);
    });
  });

  group('a fast on the plan', () {
    final sunnah = IslamicHabitCatalog.templates
        .firstWhere((t) => t.id == 'sunnah_fasting');

    test('the Monday and Thursday fast, on a Monday', () {
      expect(sunnah.category, HabitCategory.fasting);
      expect(fastingPlannedOn([sunnah], monday), isTrue);
    });

    test('nothing to fast: no fast', () {
      expect(fastingPlannedOn([custom('Read')], monday), isFalse);
      expect(fastingPlannedOn(const [], monday), isFalse);
    });

    test('a typed fasting habit, by its name', () {
      expect(fastingPlannedOn([custom('صيام الأيام البيض')], monday), isTrue);
      expect(fastingPlannedOn([custom('Fast on Mondays')], monday), isTrue);
    });

    test('only on the days it runs', () {
      final thursdays = custom('صوم', days: const [DateTime.thursday]);
      expect(fastingPlannedOn([thursdays], monday), isFalse);
      expect(
        fastingPlannedOn([thursdays], DateTime(2026, 10, 8)),
        isTrue,
      );
    });
  });

  test('Ramadan by the table, and its eve', () {
    expect(isRamadanDay(DateTime(2027, 2, 7)), isFalse);
    expect(isRamadanDay(DateTime(2027, 2, 8)), isTrue);
    expect(isRamadanDay(DateTime(2027, 3, 8)), isTrue);
    expect(isRamadanDay(DateTime(2027, 3, 9)), isFalse, reason: 'Eid');
    expect(isNearRamadanDay(DateTime(2027, 2, 7)), isTrue);
    expect(isNearRamadanDay(DateTime(2027, 2, 6)), isFalse);
  });

  group('the scenes for a day that is not like the others', () {
    test('the very first launch: the seed', () {
      expect(at(on(monday, 14), fresh: true), LaunchScene.firstOpen);
      expect(at(on(monday, 8), fresh: true), LaunchScene.firstOpen,
          reason: 'over the morning mug');
    });

    test('Ramadan and night keep their place over everything new', () {
      expect(at(on(monday, 23), fresh: true), LaunchScene.nightAsleep);
      expect(at(on(DateTime(2027, 2, 20), 14), fresh: true),
          LaunchScene.ramadanLantern);
      expect(at(on(monday, 23), updated: true), LaunchScene.nightAsleep);
    });

    test('a new version: the bulb, unless back after days away', () {
      expect(at(on(monday, 14), lastOpen: on(monday, 9), updated: true),
          LaunchScene.update);
      expect(
        at(on(monday, 14), lastOpen: on(DateTime(2026, 9, 30), 9), updated: true),
        LaunchScene.welcomeBack,
      );
    });

    test('Eid: its days by the table, and no others', () {
      // Eid al-Fitr 1448: 2027-03-09 to 03-11. Eid al-Adha: 05-16 to 05-19.
      for (final d in [
        DateTime(2027, 3, 9),
        DateTime(2027, 3, 11),
        DateTime(2027, 5, 16),
        DateTime(2027, 5, 19),
      ]) {
        expect(at(on(d, 14), lastOpen: on(d, 9)), LaunchScene.eid, reason: '$d');
      }
      for (final d in [DateTime(2027, 3, 12), DateTime(2027, 5, 20)]) {
        expect(at(on(d, 14), lastOpen: on(d, 9)), isNot(LaunchScene.eid),
            reason: '$d');
      }
    });

    test('yesterday full: the squares, on the first open of today', () {
      final yday = DateTime(2026, 10, 4);
      expect(at(on(monday, 8), lastOpen: yesterday, fullDay: yday),
          LaunchScene.fullDay, reason: 'over the morning mug');
      expect(at(on(monday, 14), lastOpen: yesterday, fullDay: yday),
          LaunchScene.fullDay);
      expect(at(on(monday, 15), lastOpen: on(monday, 14), fullDay: yday),
          isIn(ordinary), reason: 'once, not every open of the day');
      expect(at(on(monday, 8), lastOpen: yesterday, fullDay: DateTime(2026, 10, 2)),
          LaunchScene.morningCoffee, reason: 'an older full day is not yesterday');
    });

    test('yesterday\'s steps goal: the run, after a full day', () {
      final yday = DateTime(2026, 10, 4);
      expect(at(on(monday, 14), lastOpen: yesterday, stepsGoal: yday),
          LaunchScene.stepsGoal);
      expect(
        at(on(monday, 14), lastOpen: yesterday, fullDay: yday, stepsGoal: yday),
        LaunchScene.fullDay,
      );
    });

    test('Saturday once the recap is ready: the page turns, once', () {
      final saturday = DateTime(2026, 10, 10);
      expect(saturday.weekday, DateTime.saturday);
      expect(at(on(saturday, 10, 30), lastOpen: on(saturday, 9)),
          LaunchScene.saturday);
      expect(at(on(saturday, 12), lastOpen: on(saturday, 10, 45)),
          isIn(ordinary));
      expect(at(on(saturday, 9, 30), lastOpen: on(DateTime(2026, 10, 9), 21)),
          LaunchScene.morningCoffee, reason: 'the recap is not ready yet');
    });

    test('a summer noon: the sunglasses, June to September, 12 to 16', () {
      final july = DateTime(2026, 7, 13);
      expect(at(on(july, 13), lastOpen: on(july, 9)), LaunchScene.summerNoon);
      expect(at(on(july, 15, 59), lastOpen: on(july, 9)), LaunchScene.summerNoon);
      expect(at(on(july, 16), lastOpen: on(july, 9)), isIn(ordinary));
      expect(at(on(monday, 13), lastOpen: on(monday, 9)), isIn(ordinary),
          reason: 'October');
    });
  });

  group('the lines', () {
    final lines = [
      for (final scene in LaunchScene.values) launchLine(scene),
      kLaunchSlowLine,
    ];

    test('one short English sentence each, landing on Grow Daily', () {
      for (final l in lines) {
        expect(l, contains('Grow Daily'), reason: l);
        expect(l, matches(RegExp(r'Grow Daily\??$')), reason: l);
        expect(l, isNot(contains(' and Grow Daily')), reason: l);
        expect(l, isNot(matches(RegExp(r'[,.!]'))), reason: l);
        expect(l, matches(RegExp(r"^[A-Za-z \u2019?]+$")), reason: l);
        expect(l.length, lessThanOrEqualTo(34), reason: l);
      }
    });

    test('some say you and some say we', () {
      expect(lines.where((l) => l.contains(' you ')).length, greaterThan(3));
      expect(lines.where((l) => l.contains(' we ')).length, greaterThan(3));
    });
  });
}
