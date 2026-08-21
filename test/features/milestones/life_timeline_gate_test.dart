// Life Timeline, after the gate moved off the years and onto the days.
//
// ── What was wrong, in both directions at once ────────────────────────────
// The roadmap decided this screen is free for everyone, with no
// premiumProvider check anywhere in it. The code did the opposite AND the
// wrong opposite: it hid every past year behind Premium, while drawing the
// one year it did show unmuted all the way back to 1 January. So it was
// stricter than its own spec about which years you may see, and looser than
// the Monthly Heatmap about which DAYS you may read, on the same screen.
//
// It now lists every year for everyone, mutes the days behind the free
// window, and counts each year's own total from what the grid actually
// shows, which is the rule the reports hub's habit rows and header both
// already follow.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/core/utils/western_digits.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/milestones/notifiers/habit_history_notifier.dart';
import 'package:grow_daily_v2/features/milestones/screens/life_timeline_screen.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';

class _Premium extends PremiumNotifier {
  _Premium(bool value) {
    state = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('life_timeline_gate_');
    Hive.init(tmp.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  final today = DateTime.now().effectiveDay;

  // Last year is walled whatever day this suite runs on: the free floor
  // never reaches back further than kFreeHistoryMonths.
  const walledCount = 6;

  /// The habit-history mirror, which is what the screen actually counts from.
  ///
  /// Overriding this rather than leaning on DashboardState.dailyGreenCounts
  /// matters: the rollup is only the loading fallback now, so a test that
  /// left the mirror unresolved would exercise the wrong path entirely and
  /// pass whatever the real one did.
  final mirror = <String, Map<String, SquareState>>{
    'h1': {
      for (var i = 1; i <= walledCount; i++)
        DateTime(today.year - 1, 6, i).toDateKey(): SquareState.complete,
      DateTime(today.year, today.month, 1).toDateKey(): SquareState.complete,
    },
  };

  /// A dashboard that is already loaded. Its day counts are only the loading
  /// fallback now, but it still supplies the account's creation date and
  /// keeps the screen out of its spinner path.
  DashboardNotifier dash() => _LoadedDash(
        const <String, int>{},
        DateTime(today.year - 2, 1, 1),
      );

  final habit = IslamicHabitTemplate(
    id: 'h1',
    name: 'Fajr',
    description: '',
    category: HabitCategory.faith,
    frequencyType: HabitFrequencyType.daily,
    frequencyTarget: 1,
    scheduledWeekdays: const [],
    hasTimer: false,
    xpReward: 10,
    goldReward: 1,
    createdAt: DateTime(today.year - 2),
  );

  Future<void> pump(WidgetTester tester, {required bool premium}) async {
    tester.view.physicalSize = const Size(400 * 3, 2200 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        premiumProvider.overrideWith((ref) => _Premium(premium)),
        dashboardProvider.overrideWith((ref) => dash()),
        allHabitsEverProvider.overrideWithValue([habit]),
        habitYearHistoryProvider.overrideWith((ref) async => mirror),
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
        home: const LifeTimelineScreen(),
      ),
    ));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  const s = S(Locale('ar'));

  testWidgets('free: every year is listed, which is what the spec asked for',
      (tester) async {
    await pump(tester, premium: false);
    expect(find.text('${today.year}', skipOffstage: false), findsOneWidget);
    expect(find.text('${today.year - 1}', skipOffstage: false), findsOneWidget,
        reason: 'hiding past years behind Premium was the thing that '
            'contradicted the roadmap');
  });

  testWidgets("free: a walled year's own total is not printed",
      (tester) async {
    await pump(tester, premium: false);
    // The year card has to be ON SCREEN for this assertion to mean anything.
    // Against the old build it was absent entirely, so "no total" was true
    // for the wrong reason.
    expect(find.text('${today.year - 1}', skipOffstage: false), findsOneWidget);
    expect(
      find.text(s.lifeTimelineYearTotal(walledCount), skipOffstage: false),
      findsNothing,
      reason: 'the grid for that year is muted, so a total beside it would '
          'be the walled number arriving by another door',
    );
  });

  // ── The lifetime header ────────────────────────────────────────────────
  //
  // The screen's reason to exist. Its door was removed once because it only
  // re-rendered the Heatmap's grid; what earns it back is saying the two
  // things nothing else says, when the record starts and what all of it adds
  // up to. These figures are scalars, not browsable history, so they stay
  // free: the Profile hero already gives the lifetime totals away two taps
  // to the left, and gating them here would only be inconsistent.

  testWidgets('the header states when the record begins', (tester) async {
    await pump(tester, premium: false);
    final since = westernDate(DateTime(today.year - 2, 1, 1), 'MMMM yyyy', 'ar');
    expect(find.text(s.lifeTimelineSince(since), skipOffstage: false),
        findsOneWidget);
  });

  testWidgets('free: the lifetime totals are NOT floored', (tester) async {
    // walledCount days last year plus one this month, all of them counted.
    await pump(tester, premium: false);
    expect(find.text('${walledCount + 1}', skipOffstage: false), findsWidgets,
        reason: 'a lifetime scalar is not browsable history, and the Profile '
            'hero already shows these totals for free');
  });

  testWidgets('premium: the walled year reads in full', (tester) async {
    // The control. Without it the test above would pass just as happily
    // against a build that had broken the year card for everyone.
    await pump(tester, premium: true);
    expect(find.text('${today.year - 1}', skipOffstage: false), findsOneWidget);
    expect(
      find.text(s.lifeTimelineYearTotal(walledCount), skipOffstage: false),
      findsOneWidget,
      reason: 'paying accounts must be untouched by the floor',
    );
  });
}

class _LoadedDash extends DashboardNotifier {
  _LoadedDash(Map<String, int> counts, DateTime createdAt) : super(null) {
    state = DashboardState(
      level: 1,
      currentLevelXp: 0,
      cumulativeXp: 0,
      gold: 0,
      streak: 0,
      completions: const {},
      dailyGreenCounts: counts,
      accountCreatedAt: createdAt,
    );
  }
}
