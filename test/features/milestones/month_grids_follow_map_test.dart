// Every month calendar in the record reads the way the map's does: Saturday
// in the leftmost column and the days running left to right, in Arabic too.
//
// Aziz, 2026-09-21, asked which way the month grids should run once the
// reports, the timeline and the map become one page: "the one in map is the
// correct style". The map had turned its grid left to right on purpose (a
// month is a number line, and its western digits read left to right; see
// HeatmapMonthSection in monthly_heatmap_screen.dart), while the monthly report's
// habit cards and the habit sheet's calendar still mirrored theirs, so the
// same month ran two opposite ways a tap apart.
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
import 'package:grow_daily_v2/features/milestones/reports/report_period.dart';
import 'package:grow_daily_v2/features/milestones/reports/report_sections.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';

class _Premium extends PremiumNotifier {
  _Premium() {
    state = true;
  }
}

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

  final habit = IslamicHabitTemplate(
    id: 'adhkar',
    name: 'adhkar',
    description: '',
    category: HabitCategory.faith,
    frequencyType: HabitFrequencyType.daily,
    frequencyTarget: 1,
    scheduledWeekdays: const [],
    hasTimer: false,
    xpReward: 10,
    goldReward: 1,
    createdAt: DateTime(2026, 8),
  );
  final marks = {
    DateTime(2026, 9, 3).toDateKey(): SquareState.complete,
    DateTime(2026, 9, 7).toDateKey(): SquareState.complete,
  };

  // Saturday 5 and Friday 11 September 2026 share a week.
  final saturday = DateTime(2026, 9, 5);
  final friday = DateTime(2026, 9, 11);

  Rect cellOf(WidgetTester tester, String type, DateTime day) {
    final finder = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == type && (w as dynamic).day == day,
    );
    expect(finder, findsOneWidget, reason: '$type for $day');
    return tester.getRect(finder);
  }

  testWidgets('the monthly report\'s habit card puts Saturday on the left',
      (tester) async {
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
          child: SizedBox(
            width: 170,
            child: HabitMonthCard(
              stat: HabitPeriodStat(habit: habit, marks: marks, expected: 20),
              month: DateTime(2026, 9),
              today: DateTime(2026, 9, 21),
              now: DateTime(2026, 9, 21, 15),
              lockedBefore: null,
              allMarks: marks,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final sat = cellOf(tester, '_MonthDayCell', saturday);
    final fri = cellOf(tester, '_MonthDayCell', friday);
    expect(sat.top, fri.top, reason: 'the same week, the same row');
    expect(sat.left, lessThan(fri.left),
        reason: 'Saturday leads on the left, as on the map');
  });

  group('the habit sheet\'s calendar', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('month_grids_follow_map_');
      Hive.init(tmp.path);
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await tmp.delete(recursive: true);
    });

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
    }

    testWidgets('puts Saturday on the left, its weekday letters with it',
        (tester) async {
      tester.view.physicalSize = const Size(400 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          dayClockSourceProvider
              .overrideWithValue(() => DateTime(2026, 9, 21, 15)),
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

      final sat = cellOf(tester, '_DayCell', saturday);
      final fri = cellOf(tester, '_DayCell', friday);
      expect(sat.top, fri.top, reason: 'the same week, the same row');
      expect(sat.left, lessThan(fri.left),
          reason: 'Saturday leads on the left, as on the map');

      // The column letters travel with their days: Saturday's «س» heads
      // the left column, Friday's «ج» the right one.
      expect(tester.getRect(find.text('س')).center.dx,
          closeTo(sat.center.dx, sat.width / 2));
      expect(tester.getRect(find.text('ج')).center.dx,
          closeTo(fri.center.dx, fri.width / 2));
    });
  });
}
