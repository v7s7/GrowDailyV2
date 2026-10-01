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
  bool walker = false,
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
      walker: walker,
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
      // 14:30, not 15:00: an October afternoon's first open from 15:00 is
      // missing winter's.
      expect(at(on(monday, 14, 30), lastOpen: on(monday, 14), fullDay: yday),
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

  group('a long return', () {
    tearDown(LaunchMemory.debugReset);

    test('chooses from when the app was last on screen, not the launch', () {
      final monday = DateTime(2026, 10, 12);
      // The process started three days ago; the app was used this morning.
      LaunchMemory.debugReset(
        lastOpen: monday.subtract(const Duration(days: 3)),
        loaded: true,
        lastVersion: '1.1.0+84',
        version: '1.1.0+84',
      );
      LaunchMemory.beginReturn(since: DateTime(2026, 10, 12, 7, 30));
      expect(LaunchMemory.lastOpen, DateTime(2026, 10, 12, 7, 30));
      expect(
        pickLaunchScene(
          now: DateTime(2026, 10, 12, 9),
          lastOpen: LaunchMemory.lastOpen,
          fastingPlanned: false,
          freshInstall: false,
          updated: LaunchMemory.updated,
          lastFullDay: null,
          lastStepsGoal: null,
          random: math.Random(1),
        ),
        isNot(LaunchScene.welcomeBack),
        reason: 'used an hour and a half ago, not three days',
      );
    });

    test('a new version plays its bulb once, not on every return', () {
      LaunchMemory.debugReset(
        lastOpen: DateTime(2026, 10, 12, 7),
        loaded: true,
        lastVersion: '1.1.0+84',
        version: '1.1.0+85',
      );
      expect(LaunchMemory.updated, isTrue, reason: 'the launch after it');
      LaunchMemory.beginReturn(since: DateTime(2026, 10, 12, 8));
      expect(LaunchMemory.updated, isFalse);
    });
  });

  // Aziz, 2026-09-30: two new scenes, "Missing winter while we Grow Daily"
  // and "Every step helps us Grow Daily", after the summer noon and before
  // the coin, every earlier rule keeping its place.
  group('missing winter: October and November, 15:00 to 17:59', () {
    final oct1 = DateTime(2026, 10); // 1 October, a Thursday
    final morning = on(oct1, 9);
    const winter = LaunchScene.winterWait;

    test('from 1 October to 30 November, and neither side of it', () {
      final sep30 = DateTime(2026, 9, 30);
      final nov30 = DateTime(2026, 11, 30);
      final dec1 = DateTime(2026, 12);
      for (var seed = 0; seed < 8; seed++) {
        final before = at(on(sep30, 16), lastOpen: on(sep30, 9), seed: seed);
        final after = at(on(dec1, 16), lastOpen: on(dec1, 9), seed: seed);
        expect(before, isIn(ordinary), reason: '30 September');
        expect(after, isIn(ordinary), reason: '1 December');
      }
      expect(at(on(oct1, 16), lastOpen: morning), winter);
      expect(at(on(nov30, 16), lastOpen: on(nov30, 9)), winter);
    });

    test('from 15:00, until the evening takes over at 18:00', () {
      for (var seed = 0; seed < 8; seed++) {
        final early = at(on(oct1, 14, 59), lastOpen: morning, seed: seed);
        expect(early, isIn(ordinary));
      }
      expect(at(on(oct1, 15), lastOpen: morning), winter);
      expect(at(on(oct1, 17, 59), lastOpen: morning), winter);
      final evening = at(on(oct1, 18), lastOpen: morning);
      expect(evening, LaunchScene.eveningChecklist);
    });

    test('the first open from 15:00 only, as Saturday\'s recap', () {
      expect(at(on(oct1, 16), lastOpen: on(oct1, 14, 59)), winter);
      final afterMidnight = at(on(oct1, 16), lastOpen: on(oct1, 1));
      expect(afterMidnight, winter, reason: 'not this afternoon\'s open');
      final noRecord = at(on(oct1, 15, 30));
      expect(noRecord, winter, reason: 'nothing recorded, not a fresh install');
      for (var seed = 0; seed < 8; seed++) {
        final again = at(on(oct1, 16), lastOpen: on(oct1, 15), seed: seed);
        final later = at(on(oct1, 17, 30), lastOpen: on(oct1, 16), seed: seed);
        expect(again, isIn(ordinary), reason: 'opened at 15:00 already');
        expect(later, isIn(ordinary));
      }
    });

    test('a fast on the plan does not keep it away (nothing to drink)', () {
      expect(at(on(oct1, 16), lastOpen: morning, fasting: true), winter);
    });

    test('every scene above it keeps its place', () {
      final monday = DateTime(2026, 10, 5);
      final yday = DateTime(2026, 10, 4);
      final lastNight = on(yday, 21);
      final saturday = DateTime(2026, 10, 3);
      // Ramadan 1456 starts 2034-11-12; Eid al-Fitr 1459 is 2037-11-09.
      final ramadan = DateTime(2034, 11, 20);
      final eid = DateTime(2037, 11, 10);
      final cases = {
        'back after days away': (
          at(on(monday, 16), lastOpen: morning),
          LaunchScene.welcomeBack,
        ),
        'the very first launch': (
          at(on(oct1, 16), fresh: true),
          LaunchScene.firstOpen,
        ),
        'a new version': (
          at(on(oct1, 16), lastOpen: morning, updated: true),
          LaunchScene.update,
        ),
        'yesterday full': (
          at(on(monday, 16), lastOpen: lastNight, fullDay: yday),
          LaunchScene.fullDay,
        ),
        'yesterday\'s steps goal': (
          at(on(monday, 16), lastOpen: lastNight, stepsGoal: yday),
          LaunchScene.stepsGoal,
        ),
        'the recap\'s first open': (
          at(on(saturday, 16), lastOpen: on(saturday, 9)),
          LaunchScene.saturday,
        ),
        'the recap already seen': (
          at(on(saturday, 16), lastOpen: on(saturday, 10, 30)),
          winter,
        ),
        'the night': (
          at(on(oct1, 22), lastOpen: morning),
          LaunchScene.nightAsleep,
        ),
        'Ramadan in November': (
          at(on(ramadan, 16), lastOpen: on(ramadan, 9)),
          LaunchScene.ramadanLantern,
        ),
        'Eid in November': (
          at(on(eid, 16), lastOpen: on(eid, 9)),
          LaunchScene.eid,
        ),
      };
      for (final MapEntry(key: why, value: (got, want)) in cases.entries) {
        expect(got, want, reason: why);
      }
    });
  });

  group('every step: 16:00 to 17:59, for someone who walks', () {
    final dec7 = DateTime(2026, 12, 7); // a Monday, no winter, no summer
    final morning = on(dec7, 9);
    const walk = LaunchScene.walk;
    LaunchScene walker(DateTime now, {DateTime? last, int seed = 1}) =>
        at(now, lastOpen: last ?? morning, walker: true, seed: seed);

    test('from 16:00, until the evening takes over at 18:00', () {
      for (var seed = 0; seed < 8; seed++) {
        expect(walker(on(dec7, 15, 59), seed: seed), isIn(ordinary));
      }
      expect(walker(on(dec7, 16)), walk);
      expect(walker(on(dec7, 17, 59)), walk);
      expect(walker(on(dec7, 18)), LaunchScene.eveningChecklist);
    });

    test('only for a walker', () {
      for (var seed = 0; seed < 8; seed++) {
        final other = at(on(dec7, 17), lastOpen: morning, seed: seed);
        expect(other, isIn(ordinary));
      }
    });

    test('every open in the hour, not only the first', () {
      expect(walker(on(dec7, 17), last: on(dec7, 16, 30)), walk);
    });

    test('a fast on the plan does not keep it away', () {
      final fasting = at(
        on(dec7, 16),
        lastOpen: morning,
        walker: true,
        fasting: true,
      );
      expect(fasting, walk);
    });

    test('the summer noon keeps its hours, winter its first open', () {
      final july = DateTime(2026, 7, 13);
      final oct1 = DateTime(2026, 10);
      expect(walker(on(july, 15, 59)), LaunchScene.summerNoon);
      expect(walker(on(july, 16)), walk);
      final first = walker(on(oct1, 16, 30), last: on(oct1, 9));
      final next = walker(on(oct1, 16, 45), last: on(oct1, 16, 30));
      expect(first, LaunchScene.winterWait, reason: 'the afternoon\'s first');
      expect(next, walk, reason: 'the opens after it');
    });

    test('every scene above it keeps its place', () {
      final yday = DateTime(2026, 12, 6);
      final lastNight = on(yday, 21);
      final saturday = DateTime(2026, 12, 5);
      final ramadan = DateTime(2027, 2, 20);
      final eid = DateTime(2027, 3, 10);
      LaunchScene walks(
        DateTime now, {
        DateTime? last,
        bool fresh = false,
        bool updated = false,
        DateTime? fullDay,
        DateTime? stepsGoal,
      }) =>
          at(
            now,
            lastOpen: fresh ? null : last ?? morning,
            fresh: fresh,
            updated: updated,
            fullDay: fullDay,
            stepsGoal: stepsGoal,
            walker: true,
          );
      final cases = {
        'back after days away': (
          walks(on(dec7, 16), last: on(DateTime(2026, 12, 3), 9)),
          LaunchScene.welcomeBack,
        ),
        'the very first launch': (
          walks(on(dec7, 16), fresh: true),
          LaunchScene.firstOpen,
        ),
        'a new version': (
          walks(on(dec7, 16), updated: true),
          LaunchScene.update,
        ),
        'yesterday full': (
          walks(on(dec7, 16), last: lastNight, fullDay: yday),
          LaunchScene.fullDay,
        ),
        'yesterday\'s steps goal': (
          walks(on(dec7, 16), last: lastNight, stepsGoal: yday),
          LaunchScene.stepsGoal,
        ),
        'the recap\'s first open': (
          walks(on(saturday, 16), last: on(saturday, 9)),
          LaunchScene.saturday,
        ),
        'the night': (
          walks(on(dec7, 22)),
          LaunchScene.nightAsleep,
        ),
        'Ramadan': (
          walks(on(ramadan, 16), last: on(ramadan, 9)),
          LaunchScene.ramadanLantern,
        ),
        'Eid': (
          walks(on(eid, 16), last: on(eid, 9)),
          LaunchScene.eid,
        ),
      };
      for (final MapEntry(key: why, value: (got, want)) in cases.entries) {
        expect(got, want, reason: why);
      }
    });
  });

  group('who walks', () {
    IslamicHabitTemplate linked(String name) => IslamicHabitTemplate(
          id: 'c_$name',
          name: name,
          description: '',
          category: HabitCategory.health,
          frequencyType: HabitFrequencyType.daily,
          frequencyTarget: 1,
          hasTimer: false,
          xpReward: 10,
          goldReward: 5,
          stepGoal: 8000,
        );

    test('a habit linked to the step count, whatever its name', () {
      expect(hasWalkingHabit([custom('Read'), linked('Move')]), isTrue);
    });

    test('the walking preset', () {
      final walk = IslamicHabitCatalog.templates
          .firstWhere((t) => t.id == 'daily_walk');
      expect(hasWalkingHabit([walk]), isTrue);
    });

    test('a name that reads as walking, in either language', () {
      expect(hasWalkingHabit([custom('Morning walk')]), isTrue);
      expect(hasWalkingHabit([custom('امشي بعد العصر')]), isTrue);
      expect(hasWalkingHabit([custom('10k steps')]), isTrue);
    });

    test('nobody else', () {
      expect(hasWalkingHabit(const []), isFalse);
      expect(hasWalkingHabit([custom('Read'), custom('Wake early')]), isFalse);
      // No preset but the walk reads as one.
      final walks = [
        for (final t in IslamicHabitCatalog.templates)
          if (hasWalkingHabit([t])) t.id,
      ];
      expect(walks, ['daily_walk']);
    });
  });

  group('GD_LAUNCH_SCENE forces one scene in a debug build', () {
    test('any scene, by its name', () {
      expect(launchSceneNamed('winterWait', debug: true), LaunchScene.winterWait);
      expect(launchSceneNamed('walk', debug: true), LaunchScene.walk);
      for (final scene in LaunchScene.values) {
        expect(launchSceneNamed(scene.name, debug: true), scene);
      }
    });

    test('never in a release build, nor for a name that is not a scene', () {
      expect(launchSceneNamed('walk', debug: false), isNull);
      expect(launchSceneNamed('', debug: true), isNull);
      expect(launchSceneNamed('Walk', debug: true), isNull);
      expect(launchSceneNamed('winter', debug: true), isNull);
    });

    test('the define itself: off in a normal run, read when given', () {
      // `flutter test --dart-define=GD_LAUNCH_SCENE=walk` checks the second
      // half.
      const raw = String.fromEnvironment('GD_LAUNCH_SCENE');
      final want = raw.isEmpty ? null : LaunchScene.values.byName(raw);
      expect(kLaunchSceneForced, want);
      expect(launchSceneFixed(), kLaunchSceneForced);
    });
  });
}
