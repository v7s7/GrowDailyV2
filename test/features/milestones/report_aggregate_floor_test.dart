// The reports hub's aggregate cards, under the free-history floor.
//
// ── What was wrong ────────────────────────────────────────────────────────
// The سنوي tab is deliberately never blocked at the navigation level: the
// muting IS its gate (see reportPeriodUnlocked). Each per-habit row already
// honoured that, counting only what its strip shows, because "a full-history
// count beside a mostly-muted strip read as a bug on the free tier".
//
// The aggregates directly above those rows did not. A free account could
// step the year tab back to a year whose every strip rendered blank with a
// lock icon and read, in the header, that year's real completion total, its
// completion rate, its strongest and weakest weekday, and the year-over-year
// delta. One screen, two rules, and the aggregate is the thing this file's
// own gating comment calls "the thing actually being sold".
//
// These tests pin the two pure pieces that fix it, so the split between
// "everything, for the strips" and "only what is visible, for the numbers"
// cannot quietly collapse back into one.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/milestones/reports/report_period.dart';

void main() {
  IslamicHabitTemplate habit({String id = 'h1'}) => IslamicHabitTemplate(
        id: id,
        name: id,
        description: '',
        category: HabitCategory.faith,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
        scheduledWeekdays: const [],
        hasTimer: false,
        xpReward: 10,
        goldReward: 1,
      );

  Map<String, Map<String, SquareState>> historyOf(List<DateTime> days) => {
        'h1': {for (final d in days) d.toDateKey(): SquareState.complete},
      };

  group('visibleDaysFrom', () {
    final days = [
      for (var i = 1; i <= 31; i++) DateTime(2026, 5, i),
      for (var i = 1; i <= 30; i++) DateTime(2026, 6, i),
    ];

    test('returns the very same list when there is no floor', () {
      final out = visibleDaysFrom(days: days, floor: null);
      expect(identical(out, days), isTrue,
          reason: 'premium and unwalled periods must skip the copy, which is '
              'also what lets the caller short-circuit recomputing stats');
    });

    test('drops every day before the floor', () {
      final out = visibleDaysFrom(days: days, floor: DateTime(2026, 6));
      expect(out, hasLength(30));
      expect(out.first, DateTime(2026, 6, 1));
      expect(out.every((d) => !d.isBefore(DateTime(2026, 6))), isTrue);
    });

    test('keeps the floor day itself, which is free', () {
      final out = visibleDaysFrom(days: days, floor: DateTime(2026, 6));
      expect(out.contains(DateTime(2026, 6, 1)), isTrue);
      expect(out.contains(DateTime(2026, 5, 31)), isFalse);
    });

    test('a floor past everything leaves nothing', () {
      expect(visibleDaysFrom(days: days, floor: DateTime(2027)), isEmpty);
    });

    test('a floor before everything keeps everything', () {
      expect(visibleDaysFrom(days: days, floor: DateTime(2020)),
          hasLength(days.length));
    });
  });

  group('the header total counts only what the strips show', () {
    // The whole point, expressed as the two numbers a free user sees at once:
    // the aggregate above, and the per-habit count below it.
    test('a walled month is excluded from the total the header prints', () {
      final today = DateTime(2026, 8, 21);
      final floor = freeHistoryFloor(today); // 2026-06-01
      expect(floor, DateTime(2026, 6));

      // Ten days done inside the free window, seven behind the wall.
      final history = historyOf([
        for (var i = 1; i <= 10; i++) DateTime(2026, 7, i),
        for (var i = 1; i <= 7; i++) DateTime(2026, 3, i),
      ]);
      final yearDays = elapsedDaysIn(
        start: DateTime(2026),
        end: DateTime(2026, 12, 31),
        today: today,
      );

      final wholeYear = computeHabitPeriodStats(
        habits: [habit()],
        history: history,
        days: yearDays,
      );
      final visible = computeHabitPeriodStats(
        habits: [habit()],
        history: history,
        days: visibleDaysFrom(days: yearDays, floor: floor),
      );

      expect(wholeYear.single.doneCount, 17,
          reason: 'the unfloored view is what the header used to print');
      expect(visible.single.doneCount, 10,
          reason: 'the floored view is what every strip already showed');

      // And the summary built from the floored view agrees with the row.
      final summary = computePeriodSummary(
        dayCounts: dayCountsFrom(visible),
        days: visibleDaysFrom(days: yearDays, floor: floor),
        habitStats: visible,
      );
      expect(summary.totalDone, 10,
          reason: 'header and row must print the same number');
    });

    test('premium still sees the whole year', () {
      final today = DateTime(2026, 8, 21);
      final history = historyOf([
        for (var i = 1; i <= 10; i++) DateTime(2026, 7, i),
        for (var i = 1; i <= 7; i++) DateTime(2026, 3, i),
      ]);
      final yearDays = elapsedDaysIn(
        start: DateTime(2026),
        end: DateTime(2026, 12, 31),
        today: today,
      );
      final floor = historyFloorFor(
        windowStart: DateTime(2026),
        today: today,
        isPremium: true,
      );
      expect(floor, isNull);
      final stats = computeHabitPeriodStats(
        habits: [habit()],
        history: history,
        days: visibleDaysFrom(days: yearDays, floor: floor),
      );
      expect(stats.single.doneCount, 17,
          reason: 'the fix must not restrict anyone who paid');
    });
  });

  group('periodDelta under a floor', () {
    test('no delta when the previous year is entirely walled', () {
      final today = DateTime(2026, 8, 21);
      final history = historyOf([
        for (var i = 1; i <= 10; i++) DateTime(2026, 7, i),
        for (var i = 1; i <= 20; i++) DateTime(2025, 7, i),
      ]);
      final delta = periodDelta(
        scope: ReportScope.year,
        anchor: DateTime(2026),
        history: history,
        habits: [habit()],
        today: today,
        earliestData: DateTime(2025),
        floor: freeHistoryFloor(today),
      );
      expect(delta, isNull,
          reason: 'a delta against a year you cannot open hands back the '
              'walled number by subtraction');
    });

    test('the same comparison IS shown without a floor', () {
      // Guards the test above from passing for the wrong reason.
      final today = DateTime(2026, 8, 21);
      final history = historyOf([
        for (var i = 1; i <= 10; i++) DateTime(2026, 7, i),
        for (var i = 1; i <= 20; i++) DateTime(2025, 7, i),
      ]);
      final delta = periodDelta(
        scope: ReportScope.year,
        anchor: DateTime(2026),
        history: history,
        habits: [habit()],
        today: today,
        earliestData: DateTime(2025),
        floor: null,
      );
      expect(delta, isNotNull);
    });

    test('a previous month that merely reaches into the walled past is '
        'suppressed too', () {
      final today = DateTime(2026, 8, 21);
      final history = historyOf([
        for (var i = 1; i <= 10; i++) DateTime(2026, 6, i),
        for (var i = 1; i <= 10; i++) DateTime(2026, 5, i),
      ]);
      // June is the floor month, so its predecessor May is behind the wall.
      final delta = periodDelta(
        scope: ReportScope.month,
        anchor: DateTime(2026, 6),
        history: history,
        habits: [habit()],
        today: today,
        earliestData: DateTime(2026),
        floor: freeHistoryFloor(today),
      );
      expect(delta, isNull);
    });

    test('an unwalled comparison inside the free window still reads', () {
      final history = historyOf([
        for (var i = 1; i <= 10; i++) DateTime(2026, 8, i),
        for (var i = 1; i <= 4; i++) DateTime(2026, 7, i),
      ]);
      final delta = periodDelta(
        scope: ReportScope.month,
        anchor: DateTime(2026, 8, 10),
        history: history,
        habits: [habit()],
        today: DateTime(2026, 8, 10),
        earliestData: DateTime(2026),
        floor: freeHistoryFloor(DateTime(2026, 8, 10)),
      );
      expect(delta, 6,
          reason: 'July and August are both inside the free window, so the '
              'floor must not suppress a comparison it does not touch');
    });
  });
}
