// Does the reports hub actually WIRE its header to the floored view?
//
// report_aggregate_floor_test.dart proves the pure pieces: visibleDaysFrom
// drops walled days, and a summary built from them prints the smaller
// number. Neither of those can catch the mistake that actually shipped,
// which was not bad arithmetic but bad plumbing: the header was handed the
// whole-window stats while the strips underneath were handed a floor.
//
// So this file mounts the real PeriodReportSection, steps it to a year that
// is entirely behind the paywall, and reads the number the header is holding.
// The control case (the same account, premium) is what stops it passing for
// the wrong reason.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/milestones/notifiers/habit_history_notifier.dart';
import 'package:grow_daily_v2/features/milestones/reports/period_report_section.dart';
import 'package:grow_daily_v2/features/milestones/reports/report_sections.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';
import 'package:grow_daily_v2/shared/widgets/segmented_tabs.dart';

class _Premium extends PremiumNotifier {
  _Premium(bool value) {
    state = value;
  }
}

/// A dashboard that is already loaded.
///
/// The reports body renders a spinner while `dash.isLoading` is true, and a
/// guest dashboard finishes loading through real Hive I/O that a widget
/// test's fake clock never lets run. Left alone, the whole screen under the
/// period stepper is a CircularProgressIndicator and nothing can be
/// asserted. Only the loaded/not-loaded flag matters here: every number
/// these tests read comes from the history override, not from this state.
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
    tmp = await Directory.systemTemp.createTemp('report_header_wiring_');
    Hive.init(tmp.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  const habitId = 'h1';
  final today = DateTime.now().effectiveDay;

  // LAST year is the one period that is walled whatever day this suite runs
  // on: the free floor never reaches further back than kFreeHistoryMonths,
  // so every day of it sits behind the wall in January and in December
  // alike. Eight completions there, and a couple in the current month so the
  // stepper has somewhere to start.
  const walledCount = 8;
  final marks = <String, SquareState>{
    for (var i = 1; i <= walledCount; i++)
      DateTime(today.year - 1, 6, i).toDateKey(): SquareState.complete,
    // A year further back still, so the delta test below is exercising the
    // FLOOR and nothing else. periodDelta already returns null when the
    // period being compared against predates the account, and without these
    // the delta assertion passed even against the old, leaky wiring.
    for (var i = 1; i <= 5; i++)
      DateTime(today.year - 2, 6, i).toDateKey(): SquareState.complete,
    for (var i = 1; i <= 2; i++)
      DateTime(today.year, today.month, i).toDateKey(): SquareState.complete,
  };

  final habit = IslamicHabitTemplate(
    id: habitId,
    name: 'Fajr',
    description: '',
    category: HabitCategory.faith,
    frequencyType: HabitFrequencyType.daily,
    frequencyTarget: 1,
    scheduledWeekdays: const [],
    hasTimer: false,
    xpReward: 10,
    goldReward: 1,
    // Born well before the walled year. Without a birth date the period
    // math treats the habit as not yet existing back then, every stat comes
    // out zero, and the tab renders its empty state instead of a header.
    createdAt: DateTime(today.year - 3),
  );

  /// Advances animations without demanding quiescence.
  ///
  /// pumpAndSettle cannot be used on this screen: the reports hub runs
  /// flutter_animate effects that never reach a still frame, so settling
  /// times out before a single assertion runs. Fixed pumps get the layout
  /// built and the providers resolved, which is all these assertions need.
  Future<void> settle(WidgetTester tester) async {
    // Not pumpAndSettle: the reports hub runs flutter_animate effects that
    // never reach a still frame, so settling times out before a single
    // assertion runs. Fixed pumps carry the period transition through and
    // leave the tree built, which is all these assertions need.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> pump(WidgetTester tester, {required bool premium}) async {
    tester.view.physicalSize = const Size(400 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        premiumProvider.overrideWith((ref) => _Premium(premium)),
        dashboardProvider.overrideWith((ref) => _LoadedDash()),
        allHabitsEverProvider.overrideWithValue([habit]),
        habitYearHistoryProvider.overrideWith((ref) async => {habitId: marks}),
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
  }

  /// Drives the real controls through their own callbacks rather than by
  /// hunting chevron glyphs, which mirror under RTL and would make this test
  /// about icon direction instead of about the number in the header.
  Future<void> stepToLastYear(WidgetTester tester) async {
    tester.widget<SegmentedTabs>(find.byType(SegmentedTabs)).onChanged(2);
    await settle(tester);
    final header =
        tester.widget<ReportPeriodHeader>(find.byType(ReportPeriodHeader));
    expect(header.canGoBack, isTrue,
        reason: 'there is recorded data last year, so the arrow must live');
    header.onBack();
    await settle(tester);
  }

  int headerTotal(WidgetTester tester) => tester
      .widget<ReportHeaderCard>(find.byType(ReportHeaderCard))
      .summary
      .totalDone;

  testWidgets('free: the header prints nothing for a fully walled year',
      (tester) async {
    await pump(tester, premium: false);
    await stepToLastYear(tester);
    expect(headerTotal(tester), 0,
        reason: 'every strip in this year renders muted and reads zero, so a '
            'header printing $walledCount would be the walled number arriving '
            'by another door');
  });

  testWidgets('free: no year-over-year delta against a walled year',
      (tester) async {
    await pump(tester, premium: false);
    await stepToLastYear(tester);
    final card =
        tester.widget<ReportHeaderCard>(find.byType(ReportHeaderCard));
    expect(card.delta, isNull,
        reason: 'a delta is subtraction, and subtraction hands back the '
            'number the floor is withholding');
  });

  testWidgets('premium: the same year reads in full', (tester) async {
    // The control. Without this, the test above would pass just as happily
    // against a build that had broken the year tab for everyone.
    await pump(tester, premium: true);
    await stepToLastYear(tester);
    expect(headerTotal(tester), walledCount,
        reason: 'paying accounts must be untouched by the floor');
  });
}
