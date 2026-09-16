// The Progress tab's day sheet on a day with a dozen habits, on a phone.
//
// Reported 2026-09-17 with twelve habits: the «اليوم» sheet painted "BOTTOM
// OVERFLOWED BY 186 PIXELS" across its rows. The sheet was opened without
// isScrollControlled, which caps a modal sheet at 9/16 of the screen, and
// its habit list was capped at 42% of the screen on its own, so header,
// score card and list together ran past the sheet. A layout overflow is a
// FlutterError, and flutter_test fails any test that reports one, so opening
// the sheet at phone size is the whole assertion.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/providers/day_clock_provider.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/milestones/notifiers/habit_history_notifier.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';
import 'package:grow_daily_v2/features/profile/screens/progress_day_chart.dart';
import 'package:grow_daily_v2/features/profile/screens/progress_hub_screen.dart';

class _Premium extends PremiumNotifier {
  _Premium(bool value) {
    state = value;
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

  setUpAll(() async {
    await initializeDateFormatting('ar');
    await initializeDateFormatting('en');
  });

  final today = DateTime(2025, 6, 18);
  DateTime daysAgo(int n) => DateTime(today.year, today.month, today.day - n);
  final noon = DateTime(today.year, today.month, today.day, 12);

  // Twelve daily habits, the count in the report. Long Arabic names, so each
  // row is as tall as a real one.
  final habits = [
    for (var i = 0; i < 12; i++)
      IslamicHabitTemplate(
        id: 'h$i',
        name: 'Habit $i',
        nameAr: 'عادة يومية طويلة الاسم رقم $i',
        description: '',
        category: HabitCategory.faith,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
        scheduledWeekdays: const [],
        hasTimer: false,
        xpReward: 10,
        goldReward: 1,
        createdAt: daysAgo(14),
      ),
  ];

  final history = <String, Map<String, SquareState>>{
    for (final h in habits)
      h.id: {
        for (var n = 1; n <= 14; n++) daysAgo(n).toDateKey(): SquareState.complete,
      },
  };

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('day_detail_sheet_fits_');
    Hive.init(tmp.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  for (final size in const [Size(402, 874), Size(375, 667)]) {
    testWidgets(
        'twelve habits fit the day sheet on a ${size.width.toInt()}x'
        '${size.height.toInt()} screen', (tester) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          dayClockSourceProvider.overrideWithValue(() => noon),
          authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
          premiumProvider.overrideWith((ref) => _Premium(false)),
          dashboardProvider.overrideWith((ref) => _LoadedDash()),
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
          home: const ProgressHubScreen(),
        ),
      ));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }

      final chart = find.byType(DayScoreChart);
      await tester.ensureVisible(chart);
      await tester.pump(const Duration(milliseconds: 300));
      final box = tester.getRect(chart);
      // RTL: yesterday, a day with all twelve marks, sits one step in from
      // the left edge; the far left is today. Any day opens the same sheet,
      // and a full one is the tall case.
      await tester.tapAt(Offset(box.left + box.width / 14 * 1.5, box.center.dy));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text(const S(Locale('ar')).progressDayBreakdown),
          findsOneWidget,
          reason: 'the day sheet did not open');
      expect(tester.takeException(), isNull);
    });
  }
}
