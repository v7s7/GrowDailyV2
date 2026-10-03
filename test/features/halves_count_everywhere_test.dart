// A جزئي is half a habit wherever the app grades a day (Aziz, 2026-10-03:
// "make all 0.5 counts"). The ring, the rooms and the reports already read
// it that way; these are the places that read it as nothing, or a counted
// habit part of the way there as a whole one:
//
//  * the map's cells and every picture graded its way (heatmapDayScore):
//    سجلّي's strips and calendars, the report's best and weakest day, the
//    share card;
//  * the report's best and weakest day themselves (dayExtremes), which
//    compare in half days so the fractions stay exact;
//  * Insights (computeInsights);
//  * the home-screen widget's row list (the half flag, TodayHabit.worth).
//
// Tallies of finished squares («مربّعات ملوّنة», المجموع) stay whole squares:
// half a square is not a finished one.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/services/home_widget_service.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/screens/monthly_heatmap_screen.dart'
    show heatLevel, heatmapDayScore;
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/insights/insight_engine.dart';
import 'package:grow_daily_v2/features/milestones/reports/report_period.dart'
    show dayExtremes;

IslamicHabitTemplate _habit(
  String id, {
  HabitFrequencyType type = HabitFrequencyType.daily,
  int target = 1,
}) =>
    IslamicHabitTemplate(
      id: id,
      name: id,
      description: '',
      category: HabitCategory.custom,
      frequencyType: type,
      frequencyTarget: target,
      hasTimer: false,
      xpReward: 10,
      goldReward: 5,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  group('the map grades a half at half', () {
    final a = _habit('a');
    final b = _habit('b');
    // Wednesday 16 September 2026.
    final day = DateTime(2026, 9, 16);

    ({double credit, int owed}) score(
      List<IslamicHabitTemplate> habits,
      Map<String, SquareState> marks,
    ) =>
        heatmapDayScore(
          habits,
          day,
          (id, d) => (marks[id] ?? SquareState.none).isGreen,
          markOn: (id, d) => marks[id] ?? SquareState.none,
          greens: marks.values.where((m) => m.isGreen).length,
        );

    test('one done and one half of two: 1.5 of 2, not 1 of 2', () {
      final s = score([a, b], {
        'a': SquareState.complete,
        'b': SquareState.partial,
      });
      expect((s.credit, s.owed), (1.5, 2));
      expect(heatLevel(s.credit, s.owed), 2, reason: '75%');
    });

    test('a day of halves is no longer a day of nothing', () {
      final s = score([a, b], {
        'a': SquareState.partial,
        'b': SquareState.partial,
      });
      expect((s.credit, s.owed), (1.0, 2));
      expect(heatLevel(s.credit, s.owed), greaterThan(0));
    });

    test('without the marks, the day is its green squares alone', () {
      final s = heatmapDayScore(
        [a, b],
        day,
        (id, d) => id == 'a',
        greens: 1,
      );
      expect((s.credit, s.owed), (1.0, 2));
    });

    test(
        'a quota half its week did not need comes in only where it does not '
        'pull the day down', () {
      final gym = _habit('gym', type: HabitFrequencyType.weekly, target: 4);
      // Saturday 12 September, the first day of a fresh week: four sessions
      // in seven days, so the day is spare and owes nothing of the quota.
      final sat = DateTime(2026, 9, 12);
      ({double credit, int owed}) on(Map<String, SquareState> marks) =>
          heatmapDayScore(
            [a, gym],
            sat,
            (id, d) => d == sat && (marks[id] ?? SquareState.none).isGreen,
            markOn: (id, d) =>
                d == sat ? marks[id] ?? SquareState.none : SquareState.none,
            greens: marks.values.where((m) => m.isGreen).length,
          );
      // Nothing else done: 0.5 of 1 lifts 0 of 1.
      final lifts = on({'gym': SquareState.partial});
      expect((lifts.credit, lifts.owed), (0.5, 2));
      // The daily habit done: 1.5 of 2 would lower 1 of 1, so it stays out.
      final full = on({'a': SquareState.complete, 'gym': SquareState.partial});
      expect((full.credit, full.owed), (1.0, 1));
    });
  });

  group("the month's best and weakest day count a half at half", () {
    final days = [for (var d = 1; d <= 3; d++) DateTime(2026, 9, d)];
    ({List<DateTime> best, List<DateTime> weakest}) run(
      Map<int, (double, int)> cells,
    ) =>
        dayExtremes(
          days: days,
          doneOn: (d) => cells[d.day]!.$1,
          owedOn: (d) => cells[d.day]!.$2,
          settledOn: (_) => true,
        );

    test('1.5 of 2 beats 1 of 2, and 1 of 2 is the weakest', () {
      final r = run({1: (1.0, 2), 2: (1.5, 2), 3: (1.0, 2)});
      expect(r.best, [DateTime(2026, 9, 2)]);
      expect(r.weakest, [DateTime(2026, 9, 1), DateTime(2026, 9, 3)]);
    });

    test('halves still tie exactly: 1.5 of 3 and 1 of 2', () {
      final r = run({1: (1.5, 3), 2: (1.0, 2), 3: (2.0, 2)});
      expect(r.best, [DateTime(2026, 9, 3)]);
      expect(r.weakest, [DateTime(2026, 9, 1)],
          reason: 'level at half, the one that asked for more');
    });
  });

  group('Insights counts a half at half', () {
    // Seven settled days, Saturday 5 to Friday 11 September 2026.
    List<(DateTime, Map<String, dynamic>)> week(
      Map<String, dynamic> Function(int i) doc,
    ) =>
        [for (var i = 0; i < 7; i++) (DateTime(2026, 9, 5 + i), doc(i))];

    test('a daily جزئي on four days of seven: 2 of 7, half a day each', () {
      final a = _habit('a');
      final r = computeInsights(
        habits: [a],
        days: week((i) => {
              'squareStates': {
                'a': i.isEven ? 'partial' : 'none',
              },
            }),
        now: DateTime(2026, 9, 20),
      );
      final p = r.patterns['a']!;
      expect((p.completed, p.scheduled), (2.0, 7),
          reason: 'four halves on the even days');
      expect(p.record.values.where((d) => d.state == InsightDayState.partial),
          hasLength(4));
    });

    test('a counted habit part of the way there is half, not whole', () {
      // Four times a day, done once a day.
      final dhikr = _habit('dhikr', target: 4);
      final r = computeInsights(
        habits: [dhikr],
        days: week((i) => {
              'habitCompletions': {'dhikr': i == 0 ? 4 : 1},
            }),
        now: DateTime(2026, 9, 20),
      );
      final p = r.patterns['dhikr']!;
      expect((p.completed, p.scheduled), (4.0, 7),
          reason: 'one whole day and six halves: until 2026-10-03 it read '
              '7 of 7');
    });
  });

  test('the widget is told which rows are halves', () {
    final rows = jsonDecode(encodeWidgetHabitRows([
      (
        id: 'a',
        name: 'a',
        done: false,
        count: 0,
        perDay: 1,
        notDue: false,
        rest: false,
        half: true,
        category: 'custom',
        color: null,
      ),
      (
        id: 'b',
        name: 'b',
        done: true,
        count: 0,
        perDay: 1,
        notDue: false,
        rest: false,
        half: false,
        category: 'custom',
        color: null,
      ),
    ])) as List;
    expect((rows[0] as Map)['half'], isTrue);
    expect((rows[1] as Map).containsKey('half'), isFalse,
        reason: 'written only when true, like rest');
  });
}
