// Does the reports hub hand its clock to the numbers it prints?
//
// report_open_day_rate_test.dart pins the arithmetic: at 05:19 on Friday
// 11 September 2026, أذكار الصباح owes 9 days, not 11, and reads 22%. It
// cannot catch the mistake that would bring Aziz's «2 يوم 18%» back without
// touching the arithmetic at all: the screen no longer handing its clock in.
// The clock parameters are required now, so dropping one stops compiling,
// but a screen can still hand over null, or a different clock from the one
// that picked the month.
//
// So this mounts the real PeriodReportSection under a pinned day clock, with
// the four habits his September cards imply (inferred from the screenshot,
// not read from his account), opens the شهري tab and reads what the cards
// print. The second clock, 10:00 on Saturday the 12th, is the control: once
// the 10th and the 11th have closed, the screenshot's own numbers return.
//
// A Friday read cannot see everything the screen wires, though. By Friday
// the running week already sits whole inside the days the report has lived,
// so a screen that forgot the window's end (windowEnd) prints the same
// cards. The later groups read on Tuesday 8 September, while the week still
// runs to Friday: a flexible quota habit owes nothing yet only if the screen
// hands in the window's end, and the week tab's longest run and its change
// against last week hold a still-open Monday back only if the screen hands
// in its clock. The last group reads the weekday rhythm card, which needs
// three weeks of history, on Monday 21 September.
//
// The grey cells are read too. Each grid cell is drawn with its own clock
// handed down from the screen, and a cell that silently fell back to the
// wall clock drew a still-open Monday as missed beside a percentage that
// held it back.
//
// The cell widgets are private to report_sections.dart, so they are matched
// by type name and read through their public fields.
// ignore_for_file: avoid_dynamic_calls
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/providers/day_clock_provider.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/milestones/notifiers/habit_history_notifier.dart';
import 'package:grow_daily_v2/features/milestones/reports/period_report_section.dart';
import 'package:grow_daily_v2/features/milestones/reports/report_period.dart';
import 'package:grow_daily_v2/features/milestones/reports/report_sections.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';
import 'package:grow_daily_v2/shared/widgets/segmented_tabs.dart';

class _Premium extends PremiumNotifier {
  _Premium(bool value) {
    state = value;
  }
}

/// A dashboard that is already loaded, as in report_header_wiring_test.dart:
/// the report renders a spinner while it loads, and every number read here
/// comes from the history override, not from this state. [completions] is
/// the live tally for the clock's own day, which the report lays over the
/// history for today (withLiveToday).
class _LoadedDash extends DashboardNotifier {
  _LoadedDash(Map<String, int> completions) : super(null) {
    state = DashboardState(
      level: 1,
      currentLevelXp: 0,
      cumulativeXp: 0,
      gold: 0,
      streak: 0,
      completions: completions,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('report_open_day_wiring_');
    Hive.init(tmp.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  IslamicHabitTemplate habit(
    String id, {
    HabitFrequencyType type = HabitFrequencyType.daily,
    int target = 1,
    List<int> weekdays = const [],
    required DateTime createdAt,
  }) =>
      IslamicHabitTemplate(
        id: id,
        name: id,
        description: '',
        category: HabitCategory.faith,
        frequencyType: type,
        frequencyTarget: target,
        scheduledWeekdays: weekdays,
        hasTimer: false,
        xpReward: 10,
        goldReward: 1,
        createdAt: createdAt,
      );

  final august = DateTime(2026, 8);
  String aug(int day) => DateTime(2026, 8, day).toDateKey();
  String sep(int day) => DateTime(2026, 9, day).toDateKey();

  /// Fixed pumps, not pumpAndSettle: the reports hub runs flutter_animate
  /// effects that never reach a still frame.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  /// Mounts the report at [clock] and opens [scope].
  ///
  /// [completionsToday] has to agree with any mark the history holds for the
  /// clock's own day: the report lays live state over today, and once the
  /// Grid has loaded, a today the live state knows nothing about is dropped.
  Future<void> mountAt(
    WidgetTester tester,
    DateTime clock, {
    required List<IslamicHabitTemplate> habits,
    required Map<String, Map<String, SquareState>> history,
    required ReportScope scope,
    bool premium = true,
    Map<String, int> completionsToday = const {},
  }) async {
    // Tall enough that every card is laid out.
    tester.view.physicalSize = const Size(400 * 3, 3200 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        dayClockSourceProvider.overrideWithValue(() => clock),
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        premiumProvider.overrideWith((ref) => _Premium(premium)),
        dashboardProvider
            .overrideWith((ref) => _LoadedDash(completionsToday)),
        allHabitsEverProvider.overrideWithValue(habits),
        habitYearHistoryProvider.overrideWith((ref) async => history),
      ],
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: GameTheme.dark,
        home: const Scaffold(body: PeriodReportSection()),
      ),
    ));
    await settle(tester);
    if (scope != ReportScope.week) {
      tester
          .widget<SegmentedTabs>(find.byType(SegmentedTabs))
          .onChanged(scope.index);
      await settle(tester);
    }
  }

  /// Each month card's printed percentage, by habit id.
  Map<String, String> monthCards(WidgetTester tester) => {
        for (final card
            in tester.widgetList<HabitMonthCard>(find.byType(HabitMonthCard)))
          card.stat.habit.id: card.stat.hasRate
              ? '${(card.stat.rate * 100).round()}%'
              : '–',
      };

  /// The week tab's per-habit stats, by habit id.
  Map<String, HabitPeriodStat> weekStats(WidgetTester tester) => {
        for (final card in tester
            .widgetList<WeeklyMatrixCard>(find.byType(WeeklyMatrixCard)))
          for (final stat in card.stats) stat.habit.id: stat,
      };

  ReportHeaderCard header(WidgetTester tester) =>
      tester.widget<ReportHeaderCard>(find.byType(ReportHeaderCard));

  Finder widgetsNamed(String type) =>
      find.byWidgetPredicate((w) => w.runtimeType.toString() == type);

  /// How the week tab's grid drew [habitId]'s cell for [day].
  MatrixCellState weekCell(WidgetTester tester, String habitId, DateTime day) {
    final row = find.byWidgetPredicate(
      (w) =>
          w.runtimeType.toString() == '_MatrixRow' &&
          (w as dynamic).stat.habit.id == habitId,
    );
    final weekDays = (tester.widget(row) as dynamic).weekDays as List<DateTime>;
    final cells = tester
        .widgetList(
          find.descendant(of: row, matching: widgetsNamed('_MatrixCell')),
        )
        .toList();
    return (cells[weekDays.indexOf(day)] as dynamic).state as MatrixCellState;
  }

  /// How the month tab's card drew [habitId]'s cell for [day].
  MatrixCellState monthCell(WidgetTester tester, String habitId, DateTime day) {
    final card = find.byWidgetPredicate(
      (w) => w is HabitMonthCard && w.stat.habit.id == habitId,
    );
    final cell = tester
        .widgetList(
          find.descendant(of: card, matching: widgetsNamed('_MonthDayCell')),
        )
        .firstWhere((w) => (w as dynamic).day == day);
    return (cell as dynamic).state as MatrixCellState;
  }

  group("Aziz's September cards, read on Friday the 11th", () {
    final habits = [
      habit('adhkar', createdAt: august),
      habit(
        'sadaqa',
        type: HabitFrequencyType.weekly,
        target: 2,
        weekdays: const [DateTime.monday, DateTime.thursday],
        createdAt: august,
      ),
      habit('quran', createdAt: DateTime(2026, 9, 9)),
      habit(
        'training',
        type: HabitFrequencyType.weekly,
        target: 4,
        createdAt: august,
      ),
    ];

    final history = <String, Map<String, SquareState>>{
      'adhkar': {sep(3): SquareState.complete, sep(7): SquareState.complete},
      'sadaqa': {sep(7): SquareState.complete, sep(10): SquareState.complete},
      'quran': {sep(9): SquareState.complete, sep(10): SquareState.complete},
      'training': {
        sep(2): SquareState.complete,
        sep(3): SquareState.complete,
        sep(8): SquareState.partial,
      },
    };

    testWidgets('at 05:19 on the 11th the open 10th and 11th count as nothing',
        (tester) async {
      await mountAt(
        tester,
        DateTime(2026, 9, 11, 5, 19),
        habits: habits,
        history: history,
        scope: ReportScope.month,
      );
      expect(monthCards(tester), {
        'adhkar': '22%',
        'sadaqa': '67%',
        'quran': '100%',
        'training': '42%',
      });
      expect(find.text('22%'), findsOneWidget,
          reason: 'the card prints what its stat holds');
      expect(find.text('18%'), findsNothing,
          reason: 'the number in the screenshot counted the open 11th');
    });

    testWidgets('at 10:00 on the 11th the 10th has closed, the 11th has not',
        (tester) async {
      // The state the day clock's own timer exists to deliver: a report left
      // open from 05:19 re-reads at 10:00 and lands here.
      await mountAt(
        tester,
        DateTime(2026, 9, 11, kDayCutoffHour),
        habits: habits,
        history: history,
        scope: ReportScope.month,
      );
      expect(monthCards(tester), {
        'adhkar': '20%',
        'sadaqa': '67%',
        'quran': '100%',
        'training': '36%',
      });
    });

    testWidgets('at 10:00 on the 12th both days have closed, and count',
        (tester) async {
      await mountAt(
        tester,
        DateTime(2026, 9, 12, kDayCutoffHour),
        habits: habits,
        history: history,
        scope: ReportScope.month,
      );
      expect(monthCards(tester), {
        'adhkar': '18%',
        'sadaqa': '67%',
        'quran': '67%',
        'training': '31%',
      });
    });
  });

  group('a week still running, read on Tuesday 8 September', () {
    // daily: done on the first four days of last week, and on Saturday,
    // Sunday and Tuesday of this one, with Monday the 7th blank. gym4: four
    // times a week, any four, done on Tuesday 1 and Wednesday 2 of last week
    // and not yet this week. Both date from 1 August.
    final habits = [
      habit('daily', createdAt: august),
      habit(
        'gym4',
        type: HabitFrequencyType.weekly,
        target: 4,
        createdAt: august,
      ),
    ];
    final history = <String, Map<String, SquareState>>{
      'daily': {
        for (final key in [
          aug(29),
          aug(30),
          aug(31),
          sep(1),
          sep(5),
          sep(6),
          sep(8),
        ])
          key: SquareState.complete,
      },
      'gym4': {sep(1): SquareState.complete, sep(2): SquareState.complete},
    };
    final tue0519 = DateTime(2026, 9, 8, 5, 19);
    final tue1000 = DateTime(2026, 9, 8, kDayCutoffHour);

    Future<void> mount(
      WidgetTester tester,
      DateTime clock,
      ReportScope scope, {
      bool premium = true,
    }) =>
        mountAt(
          tester,
          clock,
          habits: habits,
          history: history,
          scope: scope,
          premium: premium,
          completionsToday: const {'daily': 1},
        );

    test('the calendar these tests rest on', () {
      expect(DateTime(2026, 9, 5).weekday, DateTime.saturday);
      expect(DateTime(2026, 8, 1).weekday, DateTime.saturday);
    });

    testWidgets('أسبوعي at 05:19: Monday is still open and Friday still ahead',
        (tester) async {
      await mount(tester, tue0519, ReportScope.week);
      final stats = weekStats(tester);
      expect(stats['daily']!.expected, 3,
          reason: 'Saturday, Sunday and the ticked Tuesday; Monday can still '
              'be marked');
      expect(stats['gym4']!.expected, 0,
          reason: 'Monday to Friday can still hold all four sessions. Judged '
              "without the window's end, only up to Tuesday, it owed 2");
      final card = header(tester);
      expect(card.summary.expectedTotal, 3);
      expect(find.text('100%'), findsOneWidget, reason: 'three of three');
      expect(card.summary.longestRun, 3,
          reason: 'Saturday, Sunday and Tuesday: a Monday still open does '
              'not break the run');
      expect(card.delta, 0,
          reason: "Monday and Tuesday are still open, so last Monday's 1 and "
              "last Tuesday's 2 may not count against them yet");
      expect(
        weekCell(tester, 'daily', DateTime(2026, 9, 7)),
        MatrixCellState.notDue,
        reason: 'a blank Monday still open is not drawn as missed',
      );
    });

    testWidgets('أسبوعي at 10:00: Monday has closed blank, and counts',
        (tester) async {
      await mount(tester, tue1000, ReportScope.week);
      final stats = weekStats(tester);
      expect(stats['daily']!.expected, 4);
      expect(stats['gym4']!.expected, 0,
          reason: 'Tuesday to Friday can still hold all four. Judged without '
              "the window's end it owed 3");
      final card = header(tester);
      expect(card.summary.expectedTotal, 4);
      expect(find.text('75%'), findsOneWidget);
      expect(card.summary.longestRun, 2);
      expect(card.delta, -1,
          reason: 'Monday closed on 0 against 1; Tuesday, still open, holds '
              'its 1 against 2');
      expect(
        weekCell(tester, 'daily', DateTime(2026, 9, 7)),
        MatrixCellState.missed,
      );
    });

    testWidgets('شهري at 05:19: Monday is still open, on the card and its cell',
        (tester) async {
      await mount(tester, tue0519, ReportScope.month);
      expect(
        monthCards(tester),
        {'daily': '57%', 'gym4': '50%'},
        reason: 'daily: 4 of the 7 days closed or answered, Monday held back',
      );
      expect(
        monthCell(tester, 'daily', DateTime(2026, 9, 7)),
        MatrixCellState.notDue,
      );
    });

    testWidgets('شهري at 10:00: the running week owes gym4 nothing yet',
        (tester) async {
      await mount(tester, tue1000, ReportScope.month);
      expect(
        monthCards(tester),
        {'daily': '50%', 'gym4': '50%'},
        reason: 'gym4: 2 of the 4 last week owed from the 1st, and this week '
            "can still fit its four. Judged without the window's end the "
            'week owed 3, and the card read 29%',
      );
      expect(header(tester).summary.expectedTotal, 12);
      expect(
        monthCell(tester, 'daily', DateTime(2026, 9, 7)),
        MatrixCellState.missed,
      );
    });

    testWidgets('سنوي, free: the floored header also reads the week to its end',
        (tester) async {
      // A free account's header is measured over its unwalled days only
      // (visibleDaysFrom), which is a second stats pass with its own clock
      // and its own window end.
      await mount(tester, tue1000, ReportScope.year, premium: false);
      expect(
        header(tester).summary.expectedTotal,
        59,
        reason: 'daily 39, from 1 August to the ticked 8th; gym4 20, five '
            "closed weeks at 4 and nothing yet this week. Without the window's "
            'end, 62',
      );
    });

    // The archived fold draws its own grid, with its own clock handed down.
    // paused was put away on Monday evening after Saturday and Sunday were
    // done, so Monday is still one of its days, and at 05:19 on Tuesday it
    // can still be marked.
    final paused = IslamicHabitTemplate(
      id: 'paused',
      name: 'paused',
      description: '',
      category: HabitCategory.faith,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 10,
      goldReward: 1,
      createdAt: august,
      archivedAt: DateTime(2026, 9, 7, 20),
    );

    /// How the أسبوعي tab's archived fold drew paused's Monday at [clock].
    Future<MatrixCellState> archivedMondayAt(
      WidgetTester tester,
      DateTime clock,
    ) async {
      await mountAt(
        tester,
        clock,
        habits: [...habits, paused],
        history: {
          ...history,
          'paused': {
            sep(5): SquareState.complete,
            sep(6): SquareState.complete,
          },
        },
        scope: ReportScope.week,
        completionsToday: const {'daily': 1},
      );
      await tester.tap(
        find
            .descendant(
              of: widgetsNamed('_ArchivedFold'),
              matching: find.byType(InkWell),
            )
            .first,
      );
      await settle(tester);
      return weekCell(tester, 'paused', DateTime(2026, 9, 7));
    }

    testWidgets('أسبوعي at 05:19: the archived fold holds an open Monday back',
        (tester) async {
      expect(
        await archivedMondayAt(tester, tue0519),
        MatrixCellState.notDue,
        reason: 'the same clock as the active grid: Monday is still open',
      );
    });

    testWidgets('أسبوعي at 10:00: the archived fold draws Monday missed',
        (tester) async {
      expect(
        await archivedMondayAt(tester, tue1000),
        MatrixCellState.missed,
      );
    });
  });

  group('the weekday rhythm card, read on Monday 21 September', () {
    // Two daily habits, both done on every day from the 1st to the 19th, and
    // neither yet on Sunday the 20th or Monday the 21st.
    final habits = [
      habit('r1', createdAt: august),
      habit('r2', createdAt: august),
    ];
    final history = <String, Map<String, SquareState>>{
      for (final id in ['r1', 'r2'])
        id: {for (var d = 1; d <= 19; d++) sep(d): SquareState.complete},
    };

    testWidgets('at 05:19 every weekday that has closed is level: no card',
        (tester) async {
      await mountAt(
        tester,
        DateTime(2026, 9, 21, 5, 19),
        habits: habits,
        history: history,
        scope: ReportScope.month,
      );
      expect(find.byType(WeekdayRhythmCard), findsNothing,
          reason: 'the 20th and the 21st are still open. Averaged in, their '
              'zeros made Sunday and Monday the weak days of a month with no '
              'weak day in it');
    });

    testWidgets('at 10:00 the 20th has closed blank, and Sunday is weak',
        (tester) async {
      await mountAt(
        tester,
        DateTime(2026, 9, 21, kDayCutoffHour),
        habits: habits,
        history: history,
        scope: ReportScope.month,
      );
      expect(find.byType(WeekdayRhythmCard), findsOneWidget);
      expect(
        tester
            .widget<WeekdayRhythmCard>(find.byType(WeekdayRhythmCard))
            .insight
            .worstWeekday,
        DateTime.sunday,
      );
    });
  });
}
