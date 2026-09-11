// The per-habit detail sheet under a pinned day clock.
//
// report_open_day_rate_test pins the month arithmetic, and
// report_open_day_wiring_test the reports hub's own wiring. The sheet a card
// opens computes the same month again, and nothing guarded that it hands
// its clock in: given `now: null`, its «هذا الشهر» read 18% at 05:19 on the
// 11th beside a card reading 22%, and a habit that owed nothing yet read 0%.
//
// The calendar's cells are read too. Its cell widget is private to
// habit_detail_sheet.dart, so it is matched by type name and read through
// its public fields.
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
import 'package:grow_daily_v2/features/milestones/notifiers/habit_history_notifier.dart';
import 'package:grow_daily_v2/features/milestones/reports/habit_detail_sheet.dart';
import 'package:grow_daily_v2/features/milestones/reports/report_sections.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';

class _Premium extends PremiumNotifier {
  _Premium() {
    state = true;
  }
}

/// Loaded, with nothing live for today: no fixture below marks the clock's
/// own day, so the sheet's live-today overlay changes nothing.
class _LoadedDash extends DashboardNotifier {
  _LoadedDash() : super(null) {
    state = const DashboardState(
      level: 1,
      currentLevelXp: 0,
      cumulativeXp: 0,
      gold: 0,
      streak: 0,
      completions: {},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('habit_detail_open_day_');
    Hive.init(tmp.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  IslamicHabitTemplate daily(String id, DateTime createdAt) =>
      IslamicHabitTemplate(
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
        createdAt: createdAt,
      );

  // أذكار الصباح on Aziz's September card: done on the 3rd and the 7th.
  final adhkar = daily('adhkar', DateTime(2026, 8));
  final adhkarMarks = {
    DateTime(2026, 9, 3).toDateKey(): SquareState.complete,
    DateTime(2026, 9, 7).toDateKey(): SquareState.complete,
  };
  // Started on the 11th, and not done yet.
  final fresh = daily('fresh', DateTime(2026, 9, 11));

  final fri0519 = DateTime(2026, 9, 11, 5, 19);
  final sat1000 = DateTime(2026, 9, 12, kDayCutoffHour);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> open(
    WidgetTester tester, {
    required DateTime clock,
    required IslamicHabitTemplate habit,
    Map<String, SquareState> marks = const {},
  }) async {
    tester.view.physicalSize = const Size(400 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        dayClockSourceProvider.overrideWithValue(() => clock),
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        premiumProvider.overrideWith((ref) => _Premium()),
        dashboardProvider.overrideWith((ref) => _LoadedDash()),
        habitYearHistoryProvider
            .overrideWith((ref) async => {habit.id: marks}),
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
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showHabitDetailSheet(context, habit),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await settle(tester);
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  /// How the sheet's calendar drew [day].
  MatrixCellState calendarCell(WidgetTester tester, DateTime day) {
    final cell = tester
        .widgetList(
          find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_DayCell',
          ),
        )
        .firstWhere((w) => (w as dynamic).day == day);
    return (cell as dynamic).state as MatrixCellState;
  }

  testWidgets('at 05:19 on the 11th the month reads 22%, as its card does',
      (tester) async {
    await open(tester, clock: fri0519, habit: adhkar, marks: adhkarMarks);
    expect(find.text('22%'), findsOneWidget, reason: '2 of the 9 closed days');
    expect(find.text('18%'), findsNothing,
        reason: 'the open 10th and 11th counted as missed');
    expect(
      calendarCell(tester, DateTime(2026, 9, 10)),
      MatrixCellState.notDue,
      reason: 'the blank 10th is still open, so its cell is not a miss',
    );
  });

  testWidgets('at 10:00 on the 12th both days have closed, and count',
      (tester) async {
    await open(tester, clock: sat1000, habit: adhkar, marks: adhkarMarks);
    expect(find.text('18%'), findsOneWidget, reason: '2 of 11');
    expect(calendarCell(tester, DateTime(2026, 9, 10)), MatrixCellState.missed);
  });

  testWidgets("a quota habit's running week owes nothing while it can still "
      'fit', (tester) async {
    // Four times a week, any four, done on Tuesday 1 and Wednesday 2
    // September, read at 10:00 on Tuesday the 8th.
    final gym4 = IslamicHabitTemplate(
      id: 'gym4',
      name: 'gym4',
      description: '',
      category: HabitCategory.fitness,
      frequencyType: HabitFrequencyType.weekly,
      frequencyTarget: 4,
      hasTimer: false,
      xpReward: 10,
      goldReward: 1,
      createdAt: DateTime(2026, 8),
    );
    await open(
      tester,
      clock: DateTime(2026, 9, 8, kDayCutoffHour),
      habit: gym4,
      marks: {
        DateTime(2026, 9).toDateKey(): SquareState.complete,
        DateTime(2026, 9, 2).toDateKey(): SquareState.complete,
      },
    );
    expect(
      find.text('50%'),
      findsOneWidget,
      reason: '2 of the 4 last week owed from the 1st; Tuesday to Friday '
          'can still hold all four of this week',
    );
    expect(
      find.text('29%'),
      findsNothing,
      reason: "judged without the month's end, the running week owed 3",
    );
  });

  testWidgets('a habit that owes nothing yet reads a placeholder, not 0%',
      (tester) async {
    await open(tester, clock: fri0519, habit: fresh);
    expect(find.text('0%'), findsNothing,
        reason: 'its only day is today, and today is still open');
    expect(find.text('–'), findsWidgets);
  });

  testWidgets('the same habit reads 0% once its first day has closed blank',
      (tester) async {
    await open(tester, clock: sat1000, habit: fresh);
    expect(find.text('0%'), findsOneWidget);
  });
}
