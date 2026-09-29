// «راحة», the grey square with a dash (stored as SquareState.skipped), and
// everything it has to mean.
//
// It was «تخطّي» until 2026-09-28. Aziz asked what told it apart from
// leaving a square empty, and then: "Rename «تخطّي» to «راحة», and wire it
// correctly everywhere", a rest being the person finding the habit is not
// needed today. The personal numbers already left it out; four places still
// treated it as a day not done, and each has a group here:
//
//  - the progress map counted it in the day (4 done and 1 rested painted
//    4 of 5 while the Grid and the report read the day full);
//  - the habit's own streak counted it as a missed day and restarted at 1;
//  - that habit's reminders still rang on the day it was rested;
//  - a Grid left on another week forgot today's rests, so the widget, the
//    badge and the reminders counted those habits as owed again.
//
// And one thing a rest must never be: a full day on its own. Resting every
// habit earns no streak point (Aziz, 2026-09-22), so the Grid's ring reads
// that day 0, not the 100% it used to (see today_ratio_rest_test.dart).
import 'package:flutter/material.dart' show Locale, TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';
import 'package:grow_daily_v2/features/grid/screens/monthly_heatmap_screen.dart'
    show heatmapScheduledOn, heatLevel;
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_day_demand.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/models/habit_schedule.dart';

import '../../helpers/landing_harness.dart';
import '../../helpers/wait_until.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  IslamicHabitTemplate daily(String id) => IslamicHabitTemplate(
        id: id,
        name: id,
        description: '',
        category: HabitCategory.custom,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
        hasTimer: false,
        xpReward: 10,
        goldReward: 5,
        createdAt: DateTime(2026, 1, 1),
      );

  /// Marks read off a day-keyed table, `none` for anything not in it.
  MarkOnDay marksFrom(Map<String, Map<String, SquareState>> byDay) =>
      (id, day) => byDay[day.toDateKey()]?[id] ?? SquareState.none;

  group('the name', () {
    test('the square is called «راحة» wherever it is named', () {
      expect(SquareState.skipped.labelAr, 'راحة');
      expect(SquareState.skipped.label, 'Rest');
      expect(SquareState.skipped.localLabel(true), 'راحة');
      expect(SquareState.skipped.localLabel(false), 'rest');
    });

    test('a quit habit\'s palette says the same word', () {
      // The quit words live only in the palette; every other screen names a
      // quit habit's square with labelAr, so a second word here would call
      // one square two names.
      expect(const S(Locale('ar')).quitSquareLabel(SquareState.skipped),
          'راحة');
      expect(const S(Locale('en')).quitSquareLabel(SquareState.skipped),
          'Rest');
    });

    test('no square is called «تخطّي» any more', () {
      for (final state in SquareState.values) {
        expect(state.labelAr, isNot(contains('تخط')));
        expect(state.localLabel(true), isNot(contains('تخط')));
        expect(const S(Locale('ar')).quitSquareLabel(state),
            isNot(contains('تخط')));
      }
    });
  });

  group('the progress map', () {
    final habits = [daily('a'), daily('b')];
    final day = DateTime(2026, 9, 10);
    bool noGreen(String id, DateTime d) => false;

    test('a rested habit leaves the day\'s count', () {
      final marks = marksFrom({
        day.toDateKey(): {'a': SquareState.skipped},
      });
      expect(heatmapScheduledOn(habits, day, noGreen, markOn: marks), 1);
    });

    test('one done and one rested paints the day full, as the Grid reads it',
        () {
      final marks = marksFrom({
        day.toDateKey(): {'a': SquareState.complete, 'b': SquareState.skipped},
      });
      bool green(String id, DateTime d) => marks(id, d).isGreen;
      final owed = heatmapScheduledOn(habits, day, green, markOn: marks);
      expect(owed, 1);
      expect(heatLevel(1, owed), 4, reason: 'the deepest cell, a full day');
    });

    test('an empty square and a فشل still count, as they always did', () {
      final marks = marksFrom({
        day.toDateKey(): {'a': SquareState.failed},
      });
      expect(heatmapScheduledOn(habits, day, noGreen, markOn: marks), 2);
    });

    test('without marks nothing can be read as a rest', () {
      expect(heatmapScheduledOn(habits, day, noGreen), 2);
    });
  });

  group("the habit's own streak", () {
    final habit = daily('h');
    // 2026-09-24 is a Thursday; the display week turns on Saturday the 26th.
    final thu = DateTime(2026, 9, 24);
    final fri = DateTime(2026, 9, 25);
    final sat = DateTime(2026, 9, 26);
    final sun = DateTime(2026, 9, 27);

    test('a rested day is not one of the habit\'s days', () {
      final marks = marksFrom({
        fri.toDateKey(): {'h': SquareState.skipped},
      });
      expect(runsOnExcusing(habit, null, markOn: marks)(fri), isFalse);
      expect(runsOnExcusing(habit, null, markOn: marks)(thu), isTrue);
      bool green(String id, DateTime d) => marks(id, d).isGreen;
      expect(runsOnExcusing(habit, green, markOn: marks)(fri), isFalse,
          reason: 'with a readable week too');
      expect(runsOnExcusing(habit, null)(fri), isTrue,
          reason: 'no marks, no rest');
    });

    test('a rest never belongs to another habit', () {
      final marks = marksFrom({
        fri.toDateKey(): {'other': SquareState.skipped},
      });
      expect(runsOnExcusing(habit, null, markOn: marks)(fri), isTrue);
    });

    test('yesterday rested keeps the streak on screen', () {
      final today = DateTime.now().effectiveDay;
      final yesterday = DateTime(today.year, today.month, today.day - 1);
      final twoAgo = DateTime(today.year, today.month, today.day - 2);
      final state = DashboardState.initial().copyWith(
        habitStreakCounts: {'h': 5},
        habitLastCompletedDate: {'h': twoAgo.toDateKey()},
      );
      final rested = marksFrom({
        yesterday.toDateKey(): {'h': SquareState.skipped},
      });
      expect(
        state.habitStreak('h',
            runsOn: runsOnExcusing(habit, null, markOn: rested)),
        5,
      );
      expect(
        state.habitStreak('h',
            runsOn: runsOnExcusing(habit, null, markOn: marksFrom(const {}))),
        0,
        reason: 'an empty yesterday is still a missed day',
      );
    });

    Future<Map<String, SquareState>?> Function(DateTime) stored(
      Map<String, Map<String, SquareState>> byDay,
    ) =>
        (day) async => byDay[day.toDateKey()] ?? const {};

    test('a completion after two rests, across a week, continues the streak',
        () async {
      // Rested Friday and Saturday, the first day of the next week, and done
      // on Sunday: the gap completeHabit measures is 1, and 5 becomes 6.
      final runsOn = await streakRunsOn(
        habit: habit,
        day: sun,
        lastCompletedKey: thu.toDateKey(),
        squaresOn: stored({
          fri.toDateKey(): {'h': SquareState.skipped},
          sat.toDateKey(): {'h': SquareState.skipped},
        }),
      );
      final gap = scheduledGapBy(last: thu, day: sun, runsOn: runsOn);
      expect(gap, 1);
      expect(nextHabitStreak(gapDays: gap, previousStreak: 5), 6,
          reason: 'a rest keeps the streak and adds nothing to it');
    });

    test('the same days left empty still restart it', () async {
      final runsOn = await streakRunsOn(
        habit: habit,
        day: sun,
        lastCompletedKey: thu.toDateKey(),
        squaresOn: stored(const {}),
      );
      final gap = scheduledGapBy(last: thu, day: sun, runsOn: runsOn);
      expect(gap, 3);
      expect(nextHabitStreak(gapDays: gap, previousStreak: 5), 1);
    });

    test('one rest and one empty day is still a gap', () async {
      final runsOn = await streakRunsOn(
        habit: habit,
        day: sun,
        lastCompletedKey: thu.toDateKey(),
        squaresOn: stored({
          fri.toDateKey(): {'h': SquareState.skipped},
        }),
      );
      expect(scheduledGapBy(last: thu, day: sun, runsOn: runsOn), 2);
    });

    test('past three weeks the plain rule stands, rest or no rest', () async {
      final last = DateTime(2026, 9, 1);
      final day = DateTime(2026, 9, 27);
      final allRested = {
        for (var d = DateTime(2026, 9, 2);
            d.isBefore(day);
            d = DateTime(d.year, d.month, d.day + 1))
          d.toDateKey(): {'h': SquareState.skipped},
      };
      final runsOn = await streakRunsOn(
        habit: habit,
        day: day,
        lastCompletedKey: last.toDateKey(),
        squaresOn: stored(allRested),
      );
      expect(scheduledGapBy(last: last, day: day, runsOn: runsOn), 26);
    });
  });

  group("today's reminders", () {
    setUpAll(() {
      tz_data.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Bahrain'));
    });

    test('a rest day is one the scheduler arms nothing on', () {
      // 2026-03-16, a Monday, at 09:00: the 20:00 reminder is today's, until
      // the day is rested and its key goes with the excused days.
      final now = tz.TZDateTime(tz.local, 2026, 3, 16, 9);
      final today = DateTime(2026, 3, 16);
      final grid = WeeklyGridState(
        weekStart: startOfGridWeek(today),
        states: {
          today.toDateKey(): {'h': SquareState.skipped},
        },
        notes: const {},
      );
      final keys = grid.restDayKeysFor('h');
      expect(keys, {today.toDateKey()});
      expect(grid.restDayKeysFor('other'), isEmpty);

      List<int> days(Set<String> excused) =>
          NotificationService.resolveClockOccurrences(
            const [TimeOfDay(hour: 20, minute: 0)],
            const [0],
            now,
            excusedDayKeys: excused,
            occurrences: 2,
          ).map((o) => o.fireTime.day).toList();
      expect(days(const {}), [16, 17]);
      expect(days(keys), [17, 18], reason: 'tomorrow still rings');
    });
  });

  group('today, held while the Grid shows another week', () {
    final today = DateTime.now().effectiveDay;
    final todayKey = today.toDateKey();
    // startOfGridWeek(today), not of DateTime.now(): see
    // today_ratio_rest_test.dart for the Saturday-morning reason.
    final thisWeek = startOfGridWeek(today);
    final lastWeek = DateTime(thisWeek.year, thisWeek.month, thisWeek.day - 7);

    WeeklyGridState onThisWeek(Map<String, SquareState>? row,
            {bool loading = false}) =>
        WeeklyGridState(
          weekStart: thisWeek,
          states: {if (row != null) todayKey: row},
          notes: const {},
          isLoading: loading,
        );

    test('the current week reads today off its own row', () {
      final s = onThisWeek({'a': SquareState.skipped, 'b': SquareState.complete});
      expect(s.skippedTodayIds(), {'a'});
      expect(s.marksWithToday('a', today), SquareState.skipped);
      expect(s.marksWithToday('b', today), SquareState.complete);
    });

    test('leaving it carries today to the next week', () {
      final held = onThisWeek({'a': SquareState.skipped}).todayRowToHold;
      final parked = WeeklyGridState(
        weekStart: lastWeek,
        states: const {},
        notes: const {},
        heldToday: held,
      );
      expect(parked.skippedTodayIds(), {'a'});
      expect(parked.marksWithToday('a', today), SquareState.skipped);
      expect(parked.copyWith(isLoading: false).skippedTodayIds(), {'a'},
          reason: 'copyWith keeps it');
    });

    test('a held row from another day says nothing', () {
      final parked = WeeklyGridState(
        weekStart: lastWeek,
        states: const {},
        notes: const {},
        heldToday: (key: '2020-01-01', row: {'a': SquareState.skipped}),
      );
      expect(parked.skippedTodayIds(), isEmpty);
      expect(parked.knownTodayRow, isNull);
    });

    test('today\'s week loading again reads the held row until it lands', () {
      final back = WeeklyGridState(
        weekStart: thisWeek,
        states: const {},
        notes: const {},
        isLoading: true,
        heldToday: (key: todayKey, row: {'a': SquareState.skipped}),
      );
      expect(back.skippedTodayIds(), {'a'});
      final landed = WeeklyGridState(
        weekStart: thisWeek,
        states: {todayKey: {'a': SquareState.complete}},
        notes: const {},
        heldToday: (key: todayKey, row: {'a': SquareState.skipped}),
      );
      expect(landed.skippedTodayIds(), isEmpty,
          reason: 'the loaded row is the truth once it is there');
    });

    test('a loaded today with nothing on it is held as known-empty', () {
      final held = onThisWeek(null).todayRowToHold;
      expect(held, isNotNull);
      expect(held!.row, isEmpty);
      expect(onThisWeek(null, loading: true).todayRowToHold, isNull,
          reason: 'still loading is not known');
    });

    test('a square written into today while parked is laid over the held row',
        () {
      final parked = WeeklyGridState(
        weekStart: lastWeek,
        states: {todayKey: {'a': SquareState.complete}},
        notes: const {},
        heldToday: (
          key: todayKey,
          row: {'a': SquareState.skipped, 'b': SquareState.skipped},
        ),
      );
      expect(parked.skippedTodayIds(), {'b'});
    });

    group('through the real board', () {
      late LandingHarness h;
      setUp(() async {
        h = LandingHarness();
        await h.prepare();
        await (await LocalStoreService.dailyBox()).clear();
        await LocalStoreService.putDailyMap(todayKey, {
          'squareStates': {'a': 'skipped', 'b': 'complete'},
        });
      });
      tearDown(() => h.dispose());

      test('a rest marked today survives going back a week, and returning',
          () async {
        final grid = h.container.read(weeklyGridProvider.notifier);
        grid.goToWeek(today);
        await waitUntil(
          () {
            final s = h.container.read(weeklyGridProvider);
            return !s.isLoading && s.weekStart.isSameDayAs(thisWeek);
          },
          describe: 'today\'s week to load',
        );
        expect(h.container.read(weeklyGridProvider).skippedTodayIds(), {'a'});

        grid.previousWeek();
        expect(h.container.read(weeklyGridProvider).skippedTodayIds(), {'a'},
            reason: 'held the moment the board leaves, before anything loads');
        await waitUntil(
          () => !h.container.read(weeklyGridProvider).isLoading,
          describe: 'last week to load',
        );
        final parked = h.container.read(weeklyGridProvider);
        expect(parked.weekStart.isSameDayAs(lastWeek), isTrue);
        expect(parked.skippedTodayIds(), {'a'});
        expect(parked.marksWithToday('a', today), SquareState.skipped);

        grid.goToWeek(today);
        expect(h.container.read(weeklyGridProvider).skippedTodayIds(), {'a'},
            reason: 'and while today\'s week loads again');
        await waitUntil(
          () => !h.container.read(weeklyGridProvider).isLoading,
          describe: 'today\'s week to load again',
        );
        expect(h.container.read(weeklyGridProvider).skippedTodayIds(), {'a'});
      });
    });
  });
}
