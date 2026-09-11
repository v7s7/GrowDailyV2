// The Progress tab under a pinned day clock: the completion rate under the
// chart, and the Insights preview.
//
// day_score_test and insight_engine_test pin the still-open rule inside
// computeDayScores and computeInsights. Neither can see the hub handing them
// no clock: `now: null` scores a blank today, and a blank yesterday before
// 10:00, as missed again, with every pure test still green. This mounts the
// real ProgressHubScreen and reads what it prints.
//
// Dated on a fixed day long past, Wednesday 18 June 2025, not off the real
// calendar: the Insights preview reads its 56 daily documents back from the
// day clock's own day (loadInsightsWindow), so the fixture and the pinned
// clocks agree whenever the test runs, and a preview that went back to
// reading the wall clock for its window would find none of them.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/providers/day_clock_provider.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/milestones/notifiers/habit_history_notifier.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';
import 'package:grow_daily_v2/features/profile/screens/progress_hub_screen.dart';

class _Premium extends PremiumNotifier {
  _Premium(bool value) {
    state = value;
  }
}

/// A dashboard that is already loaded, with nothing live for today: the
/// fixture below holds no mark on today, so the live-today overlay agrees
/// with the history whether or not the Grid has loaded.
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

  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  const s = S(Locale('en'));

  final today = DateTime(2025, 6, 18);
  DateTime daysAgo(int n) => DateTime(today.year, today.month, today.day - n);
  final at0519 = DateTime(today.year, today.month, today.day, 5, 19);
  final at1000 = DateTime(today.year, today.month, today.day, kDayCutoffHour);

  // Two daily habits started eight days ago. A is done every day up to and
  // including yesterday; B every day up to the day before yesterday. Today is
  // blank for both.
  IslamicHabitTemplate daily(String id) => IslamicHabitTemplate(
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
        createdAt: daysAgo(8),
      );
  final habits = [daily('A'), daily('B')];
  bool doneBy(String id, int n) => id == 'A' || n >= 2;

  final history = <String, Map<String, SquareState>>{
    for (final id in ['A', 'B'])
      id: {
        for (var n = 1; n <= 8; n++)
          if (doneBy(id, n)) daysAgo(n).toDateKey(): SquareState.complete,
      },
  };

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('progress_hub_open_day_');
    Hive.init(tmp.path);
    // The same days, as the daily documents the Insights preview reads.
    // Written here, not inside a test: a testWidgets body runs on fake time,
    // where a Hive write never completes.
    for (var n = 1; n <= 8; n++) {
      await LocalStoreService.putDailyMap(daysAgo(n).toDateKey(), {
        'squareStates': {
          for (final id in ['A', 'B'])
            if (doneBy(id, n)) id: SquareState.complete.name,
        },
      });
    }
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  Future<void> pumpHub(WidgetTester tester, DateTime clock) async {
    tester.view.physicalSize = const Size(400 * 3, 3200 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        dayClockSourceProvider.overrideWithValue(() => clock),
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        premiumProvider.overrideWith((ref) => _Premium(false)),
        dashboardProvider.overrideWith((ref) => _LoadedDash()),
        allHabitsEverProvider.overrideWithValue(habits),
        habitYearHistoryProvider.overrideWith((ref) async => history),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: GameTheme.dark,
        home: const ProgressHubScreen(),
      ),
    ));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  /// The value printed above the completion-rate label.
  String rateCell(WidgetTester tester) {
    final cell = find
        .ancestor(
          of: find.text(s.progressStatRate),
          matching: find.byType(Column),
        )
        .first;
    return tester
        .widgetList<Text>(find.descendant(of: cell, matching: find.byType(Text)))
        .first
        .data!;
  }

  String strongestYesterday() =>
      s.insightStrongestDay(DateFormat('EEEE', 'en').format(daysAgo(1)));

  testWidgets('at 05:19 the rate holds a blank yesterday and today back',
      (tester) async {
    await pumpHub(tester, at0519);
    expect(rateCell(tester), '100%',
        reason: 'A 8 of 8 and B 7 of 7; counted as closed, 15 of 18 read 83%');
  });

  testWidgets('at 10:00 yesterday has closed blank for B, and counts',
      (tester) async {
    await pumpHub(tester, at1000);
    expect(rateCell(tester), '94%', reason: '15 of 16');
  });

  testWidgets('the Insights preview at 05:19 names no pattern out of open days',
      (tester) async {
    await pumpHub(tester, at0519);
    expect(find.text(s.insightMostConsistent('A')), findsOneWidget);
    expect(find.text(strongestYesterday()), findsNothing,
        reason: 'counted as closed, the blank yesterday and today made a '
            'four-sample weekday and crowned it');
  });

  testWidgets('the Insights preview at 10:00 takes the closed yesterday in',
      (tester) async {
    await pumpHub(tester, at1000);
    expect(find.text(strongestYesterday()), findsOneWidget);
  });
}
