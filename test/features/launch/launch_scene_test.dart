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
import 'package:grow_daily_v2/core/l10n/wording_edits.dart';
import 'package:grow_daily_v2/features/launch/launch_scene.dart';
import 'package:grow_daily_v2/features/launch/launch_settings.dart';

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
  SplashEdits? edits,
  bool everyDay = true,
  Map<LaunchScene, DateTime> shown = const {},
  LaunchScene? lastScene,
  DateTime? installedAt,
  DateTime? updateSince,
}) =>
    pickLaunchScene(
      settings: LaunchSettings.from(everyDay ? onEveryDay(edits) : edits),
      lastShown: shown,
      lastScene: lastScene,
      installedAt: installedAt,
      updateSince: updateSince,
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

/// [edits] with every moment playing every day it can, so a rule's test is
/// never about which days its chance skips (pinned in its own group).
SplashEdits onEveryDay(SplashEdits? edits) => SplashEdits(
      numbers: edits?.numbers ?? const {},
      order: edits?.order,
      off: edits?.off ?? const [],
      hours: edits?.hours ?? const {},
      months: edits?.months ?? const {},
      forceScene: edits?.forceScene,
      forceFrom: edits?.forceFrom,
      forceTo: edits?.forceTo,
      pool: edits?.pool ?? const {},
      onceADay: edits?.onceADay ?? const {},
      chance: {
        for (final name in kSplashDailyChance.keys) name: 100,
        ...?edits?.chance,
      },
      lines: edits?.lines ?? const {},
      slowLine: edits?.slowLine,
    );

/// Every scene the anytime list can draw, built in (kSplashPoolWeights).
const anytime = {
  LaunchScene.dayRing,
  LaunchScene.turnaround,
  LaunchScene.walk,
  LaunchScene.stepsGoal,
  LaunchScene.firstOpen,
  LaunchScene.winterWait,
};

/// Every anytime scene played already (none is new any more).
Map<LaunchScene, DateTime> allSeen(DateTime at) => {
      for (final s in anytime) s: at,
    };

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

    test('once a morning: not after it played', () {
      for (var seed = 0; seed < 8; seed++) {
        expect(
          at(on(monday, 9),
              lastOpen: on(monday, 7),
              shown: {LaunchScene.morningCoffee: on(monday, 7)},
              seed: seed),
          isIn(anytime),
        );
      }
    });

    test('owed: a bigger moment took the first open, the mug the next', () {
      final yday = DateTime(2026, 10, 4);
      expect(at(on(monday, 7), lastOpen: yesterday, fullDay: yday),
          LaunchScene.fullDay);
      expect(
        at(on(monday, 8),
            lastOpen: on(monday, 7),
            fullDay: yday,
            shown: {LaunchScene.fullDay: on(monday, 7)}),
        LaunchScene.morningCoffee,
      );
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
          isIn(anytime),
        );
      }
    });

    test('never on the day before Ramadan, or in it', () {
      final eve = DateTime(2027, 2, 7); // 1448 starts 2027-02-08
      for (var seed = 0; seed < 8; seed++) {
        expect(at(on(eve, 7), lastOpen: on(DateTime(2027, 2, 6), 21), seed: seed),
            isIn(anytime));
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

    test('the checklist from 18:00 to 22:00, once an evening', () {
      expect(at(on(monday, 18), lastOpen: on(monday, 9)),
          LaunchScene.eveningChecklist);
      expect(at(on(monday, 21, 59), lastOpen: on(monday, 9)),
          LaunchScene.eveningChecklist);
      for (var seed = 0; seed < 12; seed++) {
        expect(
          at(on(monday, 20),
              lastOpen: on(monday, 18, 30),
              shown: {LaunchScene.eveningChecklist: on(monday, 18, 30)},
              seed: seed),
          isIn(anytime),
          reason: 'the evening\'s other opens go to the anytime list',
        );
      }
    });

    test('otherwise the anytime list, and each of its scenes comes up', () {
      final seen = {
        for (var seed = 0; seed < 60; seed++)
          at(on(monday, 14), lastOpen: on(monday, 9), seed: seed),
      };
      // Missing winter only inside its own hours, from 15:00.
      expect(seen, {
        LaunchScene.dayRing,
        LaunchScene.turnaround,
        LaunchScene.walk,
        LaunchScene.stepsGoal,
        LaunchScene.firstOpen,
      });
    });

    test('a scene never seen on this phone comes first', () {
      final seen = {...allSeen(on(monday, 8))}..remove(LaunchScene.walk);
      for (var seed = 0; seed < 12; seed++) {
        expect(
          at(on(monday, 14), lastOpen: on(monday, 9), shown: seen, seed: seed),
          LaunchScene.walk,
        );
      }
    });

    test('never the scene the last launch played', () {
      for (var seed = 0; seed < 30; seed++) {
        expect(
          at(on(monday, 14),
              lastOpen: on(monday, 9),
              shown: allSeen(on(monday, 8)),
              lastScene: LaunchScene.dayRing,
              seed: seed),
          isNot(LaunchScene.dayRing),
        );
      }
    });

    test('walking and steps come up most', () {
      final counts = <LaunchScene, int>{};
      for (var seed = 0; seed < 1200; seed++) {
        final s = at(on(monday, 14),
            lastOpen: on(monday, 9), shown: allSeen(on(monday, 8)), seed: seed);
        counts[s] = (counts[s] ?? 0) + 1;
      }
      // Shares 3, 3, 2, 2, 2 of 12: a quarter each for the two.
      expect(counts[LaunchScene.walk]!, greaterThan(counts[LaunchScene.dayRing]!));
      expect(counts[LaunchScene.stepsGoal]!,
          greaterThan(counts[LaunchScene.turnaround]!));
      expect(counts[LaunchScene.walk]!, inInclusiveRange(240, 360));
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

    test('the very first launch leads, at night and in Ramadan too', () {
      expect(at(on(monday, 23), fresh: true), LaunchScene.firstOpen);
      expect(at(on(DateTime(2027, 2, 20), 14), fresh: true),
          LaunchScene.firstOpen);
    });

    test('the seed stays owed for three days if something took it', () {
      final installed = on(monday, 8);
      final next = on(DateTime(2026, 10, 7), 13);
      expect(at(next, lastOpen: on(monday, 9), installedAt: installed),
          LaunchScene.firstOpen);
      expect(
        at(next,
            lastOpen: on(monday, 9),
            installedAt: installed,
            shown: allSeen(installed),
            edits: const SplashEdits(pool: {'firstOpen': 0})),
        isNot(LaunchScene.firstOpen),
        reason: 'it played',
      );
      final late = on(DateTime(2026, 10, 8), 13);
      expect(
        at(late,
            lastOpen: on(DateTime(2026, 10, 7), 9),
            installedAt: installed,
            shown: {...allSeen(installed)}..remove(LaunchScene.firstOpen),
            edits: const SplashEdits(pool: {'firstOpen': 0})),
        isNot(LaunchScene.firstOpen),
        reason: 'three days have passed',
      );
    });

    test('a new version waits out the night, and comes before Ramadan', () {
      expect(at(on(monday, 23), updated: true), LaunchScene.nightAsleep);
      expect(at(on(monday, 3), lastOpen: yesterday, updated: true),
          LaunchScene.nightAsleep);
      final r = DateTime(2027, 2, 20);
      expect(at(on(r, 14), lastOpen: on(r, 9), updated: true),
          LaunchScene.update);
    });

    test('the bulb stays owed for a week, then is dropped', () {
      final since = on(monday, 23);
      expect(
        at(on(DateTime(2026, 10, 11), 14),
            lastOpen: on(DateTime(2026, 10, 11), 9),
            updated: true,
            updateSince: since),
        LaunchScene.update,
      );
      expect(
        at(on(DateTime(2026, 10, 12), 14),
            lastOpen: on(DateTime(2026, 10, 12), 9),
            updated: true,
            updateSince: since),
        isNot(LaunchScene.update),
      );
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

    test('three moments one morning: the bulb, the squares, then the mug', () {
      final yday = DateTime(2026, 10, 4);
      expect(at(on(monday, 7), lastOpen: yesterday, updated: true, fullDay: yday),
          LaunchScene.update);
      expect(
        at(on(monday, 8),
            lastOpen: on(monday, 7),
            fullDay: yday,
            shown: {LaunchScene.update: on(monday, 7)}),
        LaunchScene.fullDay,
        reason: 'not lost to the bulb',
      );
      expect(
        at(on(monday, 9),
            lastOpen: on(monday, 8),
            fullDay: yday,
            shown: {
              LaunchScene.update: on(monday, 7),
              LaunchScene.fullDay: on(monday, 8),
            }),
        LaunchScene.morningCoffee,
        reason: 'not lost to the squares',
      );
    });

    test('yesterday full: the squares, on the first open of today', () {
      final yday = DateTime(2026, 10, 4);
      expect(at(on(monday, 8), lastOpen: yesterday, fullDay: yday),
          LaunchScene.fullDay, reason: 'over the morning mug');
      expect(at(on(monday, 14), lastOpen: yesterday, fullDay: yday),
          LaunchScene.fullDay);
      // 14:30, not 15:00: an October afternoon's first open from 15:00 is
      // missing winter's.
      expect(
          at(on(monday, 14, 30),
              lastOpen: on(monday, 14),
              fullDay: yday,
              shown: {LaunchScene.fullDay: on(monday, 14)}),
          isIn(anytime),
          reason: 'once, not every open of the day');
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
      expect(
        at(on(monday, 14, 40),
            lastOpen: on(monday, 14),
            fullDay: yday,
            stepsGoal: yday,
            shown: {LaunchScene.fullDay: on(monday, 14)}),
        LaunchScene.stepsGoal,
        reason: 'the run on the next open',
      );
    });

    test('Saturday once the recap is ready: the page turns, once', () {
      final saturday = DateTime(2026, 10, 10);
      expect(saturday.weekday, DateTime.saturday);
      expect(at(on(saturday, 10, 30), lastOpen: on(saturday, 9)),
          LaunchScene.saturday);
      expect(
          at(on(saturday, 12),
              lastOpen: on(saturday, 10, 45),
              shown: {LaunchScene.saturday: on(saturday, 10, 45)}),
          isIn(anytime));
      expect(
        at(on(saturday, 12),
            lastOpen: on(saturday, 10, 45),
            fullDay: DateTime(2026, 10, 9),
            shown: {LaunchScene.fullDay: on(saturday, 10, 45)}),
        LaunchScene.saturday,
        reason: 'the squares took 10:45, the page turns on the next open',
      );
      expect(at(on(saturday, 9, 30), lastOpen: on(DateTime(2026, 10, 9), 21)),
          LaunchScene.morningCoffee, reason: 'the recap is not ready yet');
    });

    test('a summer noon: the sunglasses, June to September, 12 to 16', () {
      final july = DateTime(2026, 7, 13);
      expect(at(on(july, 13), lastOpen: on(july, 9)), LaunchScene.summerNoon);
      expect(at(on(july, 15, 59), lastOpen: on(july, 9)), LaunchScene.summerNoon);
      expect(
          at(on(july, 15, 30),
              lastOpen: on(july, 13),
              shown: {LaunchScene.summerNoon: on(july, 13)}),
          isIn(anytime),
          reason: 'once a day');
      expect(at(on(july, 16), lastOpen: on(july, 9)), LaunchScene.winterWait,
          reason: 'from 16:00 a July afternoon misses winter');
      expect(at(on(monday, 13), lastOpen: on(monday, 9)), isIn(anytime),
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

    test('a new version plays its bulb once, on a return if it was owed', () {
      final since = DateTime(2026, 10, 12, 7);
      LaunchMemory.debugReset(
        lastOpen: since,
        lastVersion: '1.1.0+85',
        version: '1.1.0+85',
        newVersion: '1.1.0+85',
        newVersionSince: since,
      );
      expect(LaunchMemory.updated, isTrue, reason: 'owed until it plays');
      expect(LaunchMemory.updateSince, since);
      LaunchMemory.beginReturn(since: DateTime(2026, 10, 12, 8));
      expect(LaunchMemory.updated, isTrue, reason: 'the night took the launch');
      LaunchMemory.recordShown(LaunchScene.update, DateTime(2026, 10, 12, 9));
      expect(LaunchMemory.updated, isFalse);
      expect(LaunchMemory.lastScene, LaunchScene.update);
      expect(LaunchMemory.lastShown[LaunchScene.update],
          DateTime(2026, 10, 12, 9));
    });

    test('a fresh install has no bulb owed', () {
      LaunchMemory.debugReset(version: '1.1.0+86');
      expect(LaunchMemory.updated, isFalse);
    });
  });

  // Aziz, 2026-09-30: two new scenes, "Missing winter while we Grow Daily"
  // and "Every step helps us Grow Daily", after the summer noon, every
  // earlier rule keeping its place. 2026-10-01: winter in every month but
  // Bahrain's winter, December to February.
  group('missing winter: every month but winter, 15:00 to 17:59', () {
    final oct1 = DateTime(2026, 10); // 1 October, a Thursday
    final morning = on(oct1, 9);
    const winter = LaunchScene.winterWait;

    test('March to November, never December to February', () {
      for (final d in [
        DateTime(2026, 4, 15),
        DateTime(2026, 7, 13),
        oct1,
        DateTime(2026, 11, 30),
      ]) {
        expect(at(on(d, 16), lastOpen: on(d, 9)), winter, reason: '$d');
      }
      for (final d in [
        DateTime(2026, 12),
        DateTime(2027, 1, 12),
        DateTime(2027, 2, 2),
      ]) {
        for (var seed = 0; seed < 12; seed++) {
          expect(at(on(d, 16), lastOpen: on(d, 9), seed: seed), isNot(winter),
              reason: '$d');
        }
      }
    });

    test('from 15:00, until the evening takes over at 18:00', () {
      for (var seed = 0; seed < 12; seed++) {
        final early = at(on(oct1, 14, 59), lastOpen: morning, seed: seed);
        expect(early, isNot(winter));
      }
      expect(at(on(oct1, 15), lastOpen: morning), winter);
      expect(at(on(oct1, 17, 59), lastOpen: morning), winter);
      final evening = at(on(oct1, 18), lastOpen: morning);
      expect(evening, LaunchScene.eveningChecklist);
    });

    test('once a day as the afternoon\'s moment', () {
      expect(at(on(oct1, 16), lastOpen: on(oct1, 14, 59)), winter);
      final afterMidnight = at(on(oct1, 16), lastOpen: on(oct1, 1));
      expect(afterMidnight, winter, reason: 'not this afternoon\'s open');
      final noRecord = at(on(oct1, 15, 30));
      expect(noRecord, winter, reason: 'nothing recorded, not a fresh install');
      for (var seed = 0; seed < 12; seed++) {
        final again = at(on(oct1, 16),
            lastOpen: on(oct1, 15),
            shown: {winter: on(oct1, 15)},
            lastScene: winter,
            seed: seed);
        expect(again, isNot(winter), reason: 'played at 15:00 already');
      }
    });

    test('later opens may still draw it from the anytime list', () {
      final seen = {
        for (var seed = 0; seed < 60; seed++)
          at(on(oct1, 17),
              lastOpen: on(oct1, 16),
              shown: allSeen(on(oct1, 15)),
              lastScene: LaunchScene.dayRing,
              seed: seed),
      };
      expect(seen, contains(winter));
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
          at(on(saturday, 16),
              lastOpen: on(saturday, 10, 30),
              shown: {LaunchScene.saturday: on(saturday, 10, 30)}),
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
        expect(walker(on(dec7, 15, 59), seed: seed), isIn(anytime));
      }
      expect(walker(on(dec7, 16)), walk);
      expect(walker(on(dec7, 17, 59)), walk);
      expect(walker(on(dec7, 18)), LaunchScene.eveningChecklist);
    });

    test('once a day for a walker; for anyone else, only by the draw', () {
      final lastNight = on(DateTime(2026, 12, 6), 21);
      for (var seed = 0; seed < 12; seed++) {
        final other = at(on(dec7, 17),
            lastOpen: morning,
            shown: allSeen(lastNight),
            lastScene: walk,
            seed: seed);
        expect(other, isNot(walk), reason: 'just played: not drawn again');
        expect(
          at(on(dec7, 17),
              lastOpen: morning,
              walker: true,
              shown: allSeen(lastNight),
              lastScene: walk,
              seed: seed),
          walk,
        );
        expect(
          at(on(dec7, 17, 30),
              lastOpen: on(dec7, 17),
              walker: true,
              shown: {...allSeen(lastNight), walk: on(dec7, 17)},
              lastScene: walk,
              seed: seed),
          isNot(walk),
          reason: 'played at 17:00: once a day',
        );
      }
    });

    test('every open again when the admin turns once a day off', () {
      expect(
        at(on(dec7, 17, 30),
            lastOpen: on(dec7, 17),
            walker: true,
            shown: {walk: on(dec7, 17)},
            edits: const SplashEdits(onceADay: {'walk': 0})),
        walk,
      );
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

    test('the summer noon keeps its hours; the walk comes before winter', () {
      final july = DateTime(2026, 7, 13);
      final oct1 = DateTime(2026, 10);
      expect(walker(on(july, 15, 59)), LaunchScene.summerNoon);
      for (final d in [july, oct1]) {
        final first = walker(on(d, 16, 30), last: on(d, 9));
        final next = at(on(d, 16, 45),
            lastOpen: on(d, 16, 30),
            walker: true,
            shown: {walk: on(d, 16, 30)});
        expect(first, walk, reason: '$d afternoon\'s first');
        expect(next, LaunchScene.winterWait, reason: '$d the open after it');
      }
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
  group('the admin\'s splash settings', () {
    final wed = DateTime(2026, 10, 7);
    DateTime when(DateTime d, int h) => DateTime(d.year, d.month, d.day, h);

    test('nothing edited is the built-in rules', () {
      expect(LaunchSettings.from(null).describe(),
          LaunchSettings.builtIn.describe());
      expect(at(when(monday, 7), lastOpen: yesterday),
          LaunchScene.morningCoffee);
    });

    test('a scene switched off falls to the next rule', () {
      const off = SplashEdits(off: ['morningCoffee']);
      expect(at(when(monday, 7), lastOpen: yesterday, edits: off),
          isIn(anytime));
    });

    test('its hours move: the evening checklist from 17:00', () {
      const e = SplashEdits(hours: {'eveningChecklist': [17, 22]});
      expect(at(when(monday, 17), lastOpen: yesterday, edits: e),
          LaunchScene.eveningChecklist);
      expect(at(when(monday, 16), lastOpen: yesterday, edits: e),
          isNot(LaunchScene.eveningChecklist));
    });

    test('its months move: summer noon in May too', () {
      final may = DateTime(2026, 5, 12);
      const e = SplashEdits(months: {'summerNoon': [5, 6, 7, 8, 9]});
      expect(at(when(may, 13), lastOpen: when(may, 9), edits: e),
          LaunchScene.summerNoon);
      expect(at(when(may, 13), lastOpen: when(may, 9)), isIn(anytime));
    });

    test('an empty month list is every month', () {
      final may = DateTime(2026, 5, 12);
      const e = SplashEdits(months: {'summerNoon': []});
      expect(at(when(may, 13), lastOpen: when(may, 9), edits: e),
          LaunchScene.summerNoon);
    });

    test('the order decides: Eid above a new version, then below it', () {
      // 2026-03-20 is the first day of Eid al-Fitr 1447.
      final eid = DateTime(2026, 3, 20);
      expect(at(when(eid, 10), lastOpen: when(eid, 8), updated: true),
          LaunchScene.update);
      const e = SplashEdits(order: ['eid', 'update']);
      expect(at(when(eid, 10), lastOpen: when(eid, 8), updated: true, edits: e),
          LaunchScene.eid);
    });

    test('a stale order keeps every scene it left out', () {
      const e = SplashEdits(order: ['walk', 'nonsense', 'walk']);
      final s = LaunchSettings.from(e);
      expect(s.order.first, LaunchScene.walk);
      expect(s.order.length, kSplashSceneOrder.length);
      expect(s.order.toSet().length, s.order.length);
    });

    test('away days move: coming back after 5 days, not 3', () {
      final back = when(monday, 12);
      final last = back.subtract(const Duration(days: 4));
      expect(at(back, lastOpen: last), LaunchScene.welcomeBack);
      const e = SplashEdits(numbers: {'awayDays': 5});
      expect(at(back, lastOpen: last, edits: e), isNot(LaunchScene.welcomeBack));
    });

    test('the anytime list follows the shares', () {
      const none = {
        'dayRing': 0,
        'turnaround': 0,
        'walk': 0,
        'stepsGoal': 0,
        'firstOpen': 0,
        'winterWait': 0,
      };
      final walkOnly = SplashEdits(pool: {...none, 'walk': 4});
      final turnOnly = SplashEdits(pool: {...none, 'turnaround': 1});
      for (var seed = 0; seed < 12; seed++) {
        expect(
            at(when(monday, 11),
                lastOpen: when(monday, 9), seed: seed, edits: walkOnly),
            LaunchScene.walk);
        expect(
            at(when(monday, 11),
                lastOpen: when(monday, 9), seed: seed, edits: turnOnly),
            LaunchScene.turnaround);
      }
      expect(
          at(when(monday, 11),
              lastOpen: when(monday, 9), edits: const SplashEdits(pool: none)),
          LaunchScene.dayRing,
          reason: 'nothing in the list: the ring');
      // Only the seven anytime scenes take a share: Eid outside its days
      // would say something untrue.
      final s = LaunchSettings.from(const SplashEdits(pool: {'eid': 5}));
      expect(s.pool.containsKey(LaunchScene.eid), isFalse);
    });

    test('a switched-off scene leaves the anytime list too', () {
      for (var seed = 0; seed < 20; seed++) {
        expect(
            at(when(monday, 11),
                lastOpen: when(monday, 9),
                seed: seed,
                edits: const SplashEdits(off: ['walk'])),
            isNot(LaunchScene.walk));
      }
    });

    test('new first and no repeat can be turned off', () {
      final s = LaunchSettings.from(
          const SplashEdits(numbers: {'newFirst': 0, 'noRepeat': 0}));
      expect(s.newFirst, isFalse);
      expect(s.noRepeat, isFalse);
      expect(LaunchSettings.builtIn.newFirst, isTrue);
      expect(LaunchSettings.builtIn.noRepeat, isTrue);
    });

    test('the lines: rewritten, trimmed, too long dropped', () {
      final s = LaunchSettings.from(const SplashEdits(
        lines: {
          'walk': '  Walk   with us and Grow Daily ',
          'eid': '',
          'dayRing': 'This line is far far far far far far too long to fit under him',
        },
        slowLine: 'Hold on, we Grow Daily',
      ));
      expect(s.line(LaunchScene.walk), 'Walk with us and Grow Daily');
      expect(s.line(LaunchScene.eid), launchLine(LaunchScene.eid));
      expect(s.line(LaunchScene.dayRing), launchLine(LaunchScene.dayRing));
      expect(s.slowLine, 'Hold on, we Grow Daily');
      expect(LaunchSettings.builtIn.slowLine, kLaunchSlowLine);
    });

    test('one second more than before: 4 s at least, 9 s at most', () {
      expect(LaunchSettings.builtIn.minShowMs, 4000);
      expect(LaunchSettings.builtIn.maxShowMs, 9000);
    });

    test('one scene for everyone, between its days, over every rule', () {
      const e = SplashEdits(
        forceScene: 'eid',
        forceFrom: '2026-10-06',
        forceTo: '2026-10-08',
      );
      // Night, a fresh install: still the forced scene.
      expect(at(when(wed, 23), fresh: true, edits: e), LaunchScene.eid);
      expect(at(when(DateTime(2026, 10, 8), 9), edits: e), LaunchScene.eid);
      expect(at(when(DateTime(2026, 10, 9), 9), lastOpen: yesterday, edits: e),
          isNot(LaunchScene.eid));
      expect(at(when(DateTime(2026, 10, 5), 9), lastOpen: yesterday, edits: e),
          isNot(LaunchScene.eid));
    });

    test('a bad edit costs that edit only', () {
      const e = SplashEdits(
        numbers: {'minShowMs': 5, 'awayDays': 5},
        hours: {'winterWait': [9, 9], 'nonsense': [1, 2]},
        forceScene: 'walk',
        forceFrom: '2026-10-09',
        forceTo: '2026-10-01',
      );
      final s = LaunchSettings.from(e);
      expect(s.minShowMs, 4000);
      expect(s.awayDays, 5);
      expect(s.hours[LaunchScene.winterWait]!.from, 15);
      expect(s.forceScene, isNull);
    });

    test('the cap always leaves a second after the minimum', () {
      const e = SplashEdits(numbers: {'minShowMs': 9000, 'maxShowMs': 9500});
      expect(LaunchSettings.from(e).maxShowMs, 10000);
    });

    test('a night wrapping midnight, and 24 as its end', () {
      expect(const LaunchWindow(22, 4).contains(23), isTrue);
      expect(const LaunchWindow(22, 4).contains(3), isTrue);
      expect(const LaunchWindow(22, 4).contains(4), isFalse);
      expect(const LaunchWindow(10, 24).contains(23), isTrue);
    });
  });

  group('how often a moment plays', () {
    test('the same answer all day, and its share of days', () {
      final start = DateTime(2026, 10, 1);
      var days = 0;
      for (var d = 0; d < 1000; d++) {
        final day = DateTime(start.year, start.month, start.day + d);
        if (LaunchSettings.builtIn.playsOn(LaunchScene.eveningChecklist, day)) {
          days++;
        }
      }
      // 60% built in.
      expect(days, inInclusiveRange(540, 660));
    });

    test('a skipped evening hands every evening open to the anytime list', () {
      final start = DateTime(2026, 10, 1);
      final skipped = [
        for (var d = 0; d < 30; d++)
          DateTime(start.year, start.month, start.day + d),
      ].firstWhere((day) =>
          !LaunchSettings.builtIn.playsOn(LaunchScene.eveningChecklist, day));
      for (final h in [18, 19, 21]) {
        expect(
          at(DateTime(skipped.year, skipped.month, skipped.day, h),
              lastOpen: DateTime(skipped.year, skipped.month, skipped.day, 9),
              everyDay: false),
          isIn(anytime),
        );
      }
    });

    test('the walkers, the squares and the night play every day', () {
      for (final s in [
        LaunchScene.walk,
        LaunchScene.fullDay,
        LaunchScene.nightAsleep,
        LaunchScene.ramadanLantern,
      ]) {
        expect(LaunchSettings.builtIn.chance.containsKey(s), isFalse,
            reason: s.name);
      }
    });

    test('the roll the admin page computes too', () {
      // Pinned values: scripts/admin_lookup/wording/splash_rules.js must
      // give the same.
      final rolls = [
        for (final s in [
          LaunchScene.morningCoffee,
          LaunchScene.eveningChecklist,
          LaunchScene.winterWait,
        ])
          for (var d = 1; d <= 3; d++) launchDayRoll(s, DateTime(2026, 10, d)),
      ];
      expect(rolls, [87, 26, 65, 20, 59, 45, 15, 1, 40]);
    });

    test('100 is every day, 0 is never', () {
      final never = LaunchSettings.from(
          const SplashEdits(chance: {'eveningChecklist': 0}));
      final always = LaunchSettings.from(
          const SplashEdits(chance: {'eveningChecklist': 100}));
      for (var d = 1; d <= 30; d++) {
        final day = DateTime(2026, 10, d);
        expect(never.playsOn(LaunchScene.eveningChecklist, day), isFalse);
        expect(always.playsOn(LaunchScene.eveningChecklist, day), isTrue);
      }
    });
  });
}
