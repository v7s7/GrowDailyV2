// Rest days, and days a habit did not ask for, on the report grids that are
// not a week: the month cards, the habit sheet's calendar and the year strips.
//
// Aziz, 2026-09-21, on the سنوي tab: "maybe here also we make the rest days
// or the not owed days have some diff than the miss days". The year strip
// knew only done and تخطّي, so a four-a-week habit's rest days were painted
// exactly like the days it was owed and missed. The month grids asked one
// day at a time, and a day on its own cannot say whether a quota owed it, so
// they called those days "not due". Only the weekly matrix, which always
// had the whole week, painted them covered.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/milestones/reports/report_period.dart';
import 'package:grow_daily_v2/features/milestones/reports/report_sections.dart';
import 'package:grow_daily_v2/features/milestones/reports/year_strip.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  IslamicHabitTemplate quota({int target = 4}) => IslamicHabitTemplate(
        id: 'q',
        name: 'q',
        description: '',
        category: HabitCategory.health,
        frequencyType: HabitFrequencyType.weekly,
        frequencyTarget: target,
        hasTimer: false,
        xpReward: 10,
        goldReward: 1,
        createdAt: DateTime(2026, 8, 1),
      );

  IslamicHabitTemplate onDays(List<int> weekdays, {DateTime? createdAt}) =>
      IslamicHabitTemplate(
        id: 's',
        name: 's',
        description: '',
        category: HabitCategory.faith,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
        scheduledWeekdays: weekdays,
        hasTimer: false,
        xpReward: 10,
        goldReward: 1,
        createdAt: createdAt ?? DateTime(2026, 8, 1),
      );

  // Monday 21 September 2026, mid-afternoon: every day before today is
  // settled.
  final today = DateTime(2026, 9, 21);
  final now = DateTime(2026, 9, 21, 15);
  String k(int month, int day) => DateTime(2026, month, day).toDateKey();
  List<DateTime> span(DateTime from, DateTime to) => [
        for (var d = from; !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1))
          d,
      ];

  // Saturday 12 to Friday 18 September: four sessions by Tuesday, so the
  // four-a-week target is met and Wednesday to Friday owe nothing.
  final metByTuesday = {
    k(9, 12): SquareState.complete,
    k(9, 13): SquareState.complete,
    k(9, 14): SquareState.complete,
    k(9, 15): SquareState.complete,
  };

  group('cellStatesByWeek', () {
    test('a four-a-week habit\'s rest days are covered, not missed', () {
      final states = cellStatesByWeek(
        habit: quota(),
        marks: metByTuesday,
        days: span(DateTime(2026, 9, 12), DateTime(2026, 9, 18)),
        today: today,
        now: now,
      );
      for (final d in [16, 17, 18]) {
        expect(states[k(9, d)], MatrixCellState.covered, reason: 'Sep $d');
      }
      for (final d in [12, 13, 14, 15]) {
        expect(states[k(9, d)], MatrixCellState.done, reason: 'Sep $d');
      }
    });

    test('gives the weekly matrix\'s own answer, day for day', () {
      final week = span(DateTime(2026, 9, 12), DateTime(2026, 9, 18));
      final matrix = weekCellStates(
        stat: HabitPeriodStat(habit: quota(), marks: metByTuesday, expected: 4),
        weekDays: week,
        today: today,
        now: now,
      );
      final byWeek = cellStatesByWeek(
        habit: quota(),
        marks: metByTuesday,
        days: week,
        today: today,
        now: now,
      );
      expect([for (final d in week) byWeek[d.toDateKey()]], matrix);
    });

    test('a month grid now agrees with the week it cuts through', () {
      // The old month card asked one day at a time, and on its own Wednesday
      // could not know the target was already met.
      final alone = cellStateFor(
        stat: HabitPeriodStat(habit: quota(), marks: metByTuesday, expected: 4),
        day: DateTime(2026, 9, 16),
        today: today,
        now: now,
      );
      expect(alone, MatrixCellState.notDue,
          reason: 'the answer the month grids used to paint');
      final september = cellStatesByWeek(
        habit: quota(),
        marks: metByTuesday,
        days: span(DateTime(2026, 9, 1), DateTime(2026, 9, 30)),
        today: today,
        now: now,
      );
      expect(september[k(9, 16)], MatrixCellState.covered);
    });

    test('the first week of a month counts sessions from the month before', () {
      // Saturday 29 August to Friday 4 September: three sessions in August
      // and one on Tuesday 1 September meet the target, so 2 to 4 September
      // owe nothing.
      final whole = {
        k(8, 29): SquareState.complete,
        k(8, 30): SquareState.complete,
        k(8, 31): SquareState.complete,
        k(9, 1): SquareState.complete,
      };
      final days = span(DateTime(2026, 9, 1), DateTime(2026, 9, 4));
      final withAugust = cellStatesByWeek(
        habit: quota(),
        marks: whole,
        days: days,
        today: today,
        now: now,
      );
      for (final d in [2, 3, 4]) {
        expect(withAugust[k(9, d)], MatrixCellState.covered, reason: 'Sep $d');
      }
      // Read with September alone, those days look owed. This is why the
      // callers hand over the habit's whole record.
      final septemberOnly = cellStatesByWeek(
        habit: quota(),
        marks: {k(9, 1): SquareState.complete},
        days: days,
        today: today,
        now: now,
      );
      expect(septemberOnly[k(9, 2)], isNot(MatrixCellState.covered));
    });

    test('a specific-days habit: off days covered, blank on days missed', () {
      final states = cellStatesByWeek(
        habit: onDays(const [DateTime.monday, DateTime.thursday]),
        marks: {k(9, 14): SquareState.complete},
        days: span(DateTime(2026, 9, 12), DateTime(2026, 9, 18)),
        today: today,
        now: now,
      );
      expect(states[k(9, 14)], MatrixCellState.done); // Monday
      expect(states[k(9, 17)], MatrixCellState.missed); // Thursday, blank
      for (final d in [12, 13, 15, 16, 18]) {
        expect(states[k(9, d)], MatrixCellState.covered, reason: 'Sep $d');
      }
    });

    test('days before the habit existed are never covered', () {
      // Soft colour there would claim a history that never was.
      final states = cellStatesByWeek(
        habit: onDays(const [DateTime.monday],
            createdAt: DateTime(2026, 9, 16)),
        marks: const {},
        days: span(DateTime(2026, 9, 12), DateTime(2026, 9, 18)),
        today: today,
        now: now,
      );
      for (final d in [12, 13, 14, 15]) {
        expect(states[k(9, d)], MatrixCellState.notDue, reason: 'Sep $d');
      }
      expect(states[k(9, 17)], MatrixCellState.covered);
    });

    test('a habit with no recorded start begins at its first mark', () {
      // A preset switched on before switch-on days were kept. Read as alive
      // forever, its off-days back to January came out as rest days, months
      // before it was ever done (الصدقة ولو بالقليل, 2026-09-21).
      final legacy = IslamicHabitTemplate(
        id: 'legacy',
        name: 'legacy',
        description: '',
        category: HabitCategory.faith,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
        scheduledWeekdays: const [DateTime.monday],
        hasTimer: false,
        xpReward: 10,
        goldReward: 1,
      );
      expect(legacy.createdAt, isNull);
      final states = cellStatesByWeek(
        habit: legacy,
        marks: {k(9, 14): SquareState.complete},
        days: span(DateTime(2026, 1, 1), DateTime(2026, 9, 20)),
        today: today,
        now: now,
      );
      // A Tuesday in March and one in August: before anything was recorded.
      expect(states[k(3, 10)], MatrixCellState.notDue);
      expect(states[k(8, 25)], MatrixCellState.notDue);
      // From the first mark on, its off-days are rest days as usual.
      expect(states[k(9, 15)], MatrixCellState.covered);
      expect(
        states.entries
            .where((e) => e.key.compareTo(k(9, 14)) < 0)
            .where((e) => e.value == MatrixCellState.covered),
        isEmpty,
      );
    });

    test('a habit with no start and no record claims no past', () {
      final states = cellStatesByWeek(
        habit: IslamicHabitTemplate(
          id: 'blank',
          name: 'blank',
          description: '',
          category: HabitCategory.faith,
          frequencyType: HabitFrequencyType.daily,
          frequencyTarget: 1,
          scheduledWeekdays: const [DateTime.monday],
          hasTimer: false,
          xpReward: 10,
          goldReward: 1,
        ),
        marks: const {},
        days: span(DateTime(2026, 9, 1), DateTime(2026, 9, 20)),
        today: today,
        now: now,
      );
      expect(states.values, everyElement(MatrixCellState.notDue));
    });

    test('keeps an archived habit\'s end when it infers the start', () {
      final archived = IslamicHabitTemplate(
        id: 'gone',
        name: 'gone',
        description: '',
        category: HabitCategory.faith,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
        scheduledWeekdays: const [DateTime.monday],
        hasTimer: false,
        xpReward: 10,
        goldReward: 1,
        archivedAt: DateTime(2026, 9, 15),
      );
      final states = cellStatesByWeek(
        habit: archived,
        marks: {k(9, 7): SquareState.complete},
        days: span(DateTime(2026, 9, 7), DateTime(2026, 9, 20)),
        today: today,
        now: now,
      );
      expect(states[k(9, 8)], MatrixCellState.covered); // alive, off-day
      expect(states[k(9, 17)], MatrixCellState.notDue); // after it was archived
    });

    test('answers exactly the days asked for, a whole year included', () {
      final year = span(DateTime(2026, 1, 1), DateTime(2026, 12, 31));
      final states = cellStatesByWeek(
        habit: quota(),
        marks: metByTuesday,
        days: year,
        today: today,
        now: now,
      );
      expect(states.length, 365);
      expect(states.keys.first.startsWith('2026'), isTrue);
      expect(states[k(12, 31)], MatrixCellState.future);
    });
  });

  group('YearStripPalette', () {
    const blue = Color(0xFF4A90E2);
    for (final dark in [true, false]) {
      final p = YearStripPalette.of(color: blue, dark: dark);
      final theme = dark ? 'dark' : 'light';

      test('$theme: a day owed nothing no longer looks like a missed one', () {
        expect(p.forState(MatrixCellState.covered), blue.withOpacity(0.18));
        expect(p.forState(MatrixCellState.covered),
            isNot(p.forState(MatrixCellState.missed)));
      });

      test('$theme: a half day is half the colour, not an empty cell', () {
        expect(p.forState(MatrixCellState.partial), blue.withOpacity(0.5));
        expect(p.forState(MatrixCellState.partial), isNot(p.empty));
      });

      test('$theme: تخطّي keeps its own grey, apart from both', () {
        expect(p.forState(MatrixCellState.rest), isNot(p.empty));
        expect(p.forState(MatrixCellState.rest), isNot(p.covered));
      });

      test('$theme: owed and blank, فشل, still open and before the habit '
          'keep the one empty tone the strip always had', () {
        for (final s in [
          MatrixCellState.missed,
          MatrixCellState.failed,
          MatrixCellState.notDue,
        ]) {
          expect(p.forState(s), p.empty, reason: s.name);
        }
      });

      test('$theme: done and bonus are the habit colour', () {
        expect(p.forState(MatrixCellState.done), blue);
        expect(p.forState(MatrixCellState.bonus), blue);
      });
    }
  });

  group('HabitMonthCard', () {
    Future<void> host(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(375 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: GameTheme.dark,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(width: 170, child: child),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Color fillOf(WidgetTester tester, String day) {
      final box = tester.widget<Container>(
        find.ancestor(of: find.text(day), matching: find.byType(Container))
            .first,
      );
      return (box.decoration! as BoxDecoration).color!;
    }

    testWidgets('paints a quota\'s rest days covered and تخطّي grey',
        (tester) async {
      final marks = {
        ...metByTuesday,
        k(9, 8): SquareState.skipped,
      };
      await host(
        tester,
        HabitMonthCard(
          stat: HabitPeriodStat(habit: quota(), marks: marks, expected: 12),
          month: DateTime(2026, 9),
          today: today,
          now: now,
          lockedBefore: null,
          allMarks: marks,
        ),
      );
      // Wednesday 16: the week's target was met on Tuesday.
      expect(fillOf(tester, '16'), GameColors.emerald.withOpacity(0.18));
      // Tuesday 8, marked تخطّي: the Grid's grey, never gold.
      expect(fillOf(tester, '8'), SquareState.skipped.fill(true));
    });
  });
}
