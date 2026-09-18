// The Monthly Heatmap's day sheet, dated in Arabic under the real
// localization delegates.
//
// Its header came from DateFormat('EEEE, MMM d'), which in the app drew
// «الأربعاء, سبتمبر ٩»: the month before the day, a Latin comma, and an
// Arabic-Indic digit, beside cells numbered 9. It reads «الأربعاء، 9
// سبتمبر» now. Harness trimmed from heatmap_open_day_test.dart.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/providers/day_clock_provider.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/screens/monthly_heatmap_screen.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/milestones/notifiers/habit_history_notifier.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';

class _Premium extends PremiumNotifier {
  _Premium() {
    state = false;
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

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('heatmap_day_sheet_date_');
    Hive.init(tmp.path);
    // The day sheet reads a guest's day through this box; opened here
    // because opening it inside a testWidgets body never completes.
    await LocalStoreService.dailyBox();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  final fajr = IslamicHabitTemplate(
    id: 'fajr',
    name: 'fajr',
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

  Future<void> pump(WidgetTester tester, Locale locale) async {
    tester.view.physicalSize = const Size(400 * 3, 2000 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        // Friday 11 September 2026, after the day cutoff.
        dayClockSourceProvider
            .overrideWithValue(() => DateTime(2026, 9, 11, 12)),
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        premiumProvider.overrideWith((ref) => _Premium()),
        dashboardProvider.overrideWith((ref) => _LoadedDash()),
        allHabitsEverProvider.overrideWithValue([fajr]),
        habitYearHistoryProvider.overrideWith((ref) async => {
              'fajr': {DateTime(2026, 9, 9).toDateKey(): SquareState.complete},
            }),
      ],
      child: MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: GameTheme.dark,
        home: const MonthlyHeatmapScreen(),
      ),
    ));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  /// September's cell for [day]; September is the last month on screen.
  Finder cellNumber(int day) => find.text('$day').last;

  Future<void> openDay(WidgetTester tester, int day) async {
    await tester.tap(cellNumber(day));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  testWidgets('Arabic: «الأربعاء، 9 سبتمبر», day first, Latin digit',
      (tester) async {
    await pump(tester, const Locale('ar'));
    await openDay(tester, 9);
    expect(find.text('الأربعاء، 9 سبتمبر'), findsOneWidget);
    expect(find.text('الأربعاء, سبتمبر ٩'), findsNothing);
  });

  testWidgets('English keeps «Wednesday, Sep 9»', (tester) async {
    await pump(tester, const Locale('en'));
    await openDay(tester, 9);
    expect(find.text('Wednesday, Sep 9'), findsOneWidget);
  });
}
