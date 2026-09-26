// The share card (share_card.dart): a month for everyone, the year for
// Premium (Aziz, 2026-09-25). What is pinned here:
//  * the card draws both scopes, in both languages, inside its own 4:5 box;
//  * a month's days run left to right from Saturday, in Arabic too
//    (month-grid-direction), so day 1 sits under its real weekday;
//  * the capture is 1080 by 1350;
//  * the report hands the card the very numbers its header prints, and the
//    year's button is a paywall for a free account.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
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
import 'package:grow_daily_v2/features/milestones/reports/share_card.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';
import 'package:grow_daily_v2/features/premium/screens/premium_screen.dart';
import 'package:grow_daily_v2/shared/widgets/segmented_tabs.dart';

class _Premium extends PremiumNotifier {
  _Premium(bool value) {
    state = value;
  }
}

/// See report_header_wiring_test.dart: the body is a spinner until the
/// dashboard says it has loaded.
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

Widget _host(Widget child, {String locale = 'ar'}) => MaterialApp(
      locale: Locale(locale),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: GameTheme.dark,
      home: Scaffold(body: Center(child: child)),
    );

ShareCardData _data(ShareCardScope scope, DateTime period) => ShareCardData(
      scope: scope,
      period: period,
      periodLabel: scope == ShareCardScope.month ? 'سبتمبر 2026' : '2026',
      totalDone: 86,
      rate: '78%',
      bestDay: '14 Sep',
      longestRun: 9,
      levels: {
        for (var d = 1; d <= 25; d++)
          DateTime(2026, 9, d).toDateKey(): d % 5,
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the card', () {
    test('cell colours: a day to come, an unlit day, then the ramp', () {
      final alphas = [for (var l = 1; l <= 4; l++) shareCellColor(l).a];
      for (var i = 1; i < alphas.length; i++) {
        expect(alphas[i], greaterThan(alphas[i - 1]));
      }
      expect(shareCellColor(null).a, lessThan(shareCellColor(0).a));
      expect(shareCellColor(0).a, lessThan(alphas.first));
    });

    test('file names say what the picture is', () {
      expect(_data(ShareCardScope.month, DateTime(2026, 9)).fileName,
          'growdaily-2026-09.png');
      expect(_data(ShareCardScope.year, DateTime(2026)).fileName,
          'growdaily-2026.png');
    });

    for (final locale in ['ar', 'en']) {
      for (final scope in ShareCardScope.values) {
        testWidgets('$scope in $locale fits its own box', (tester) async {
          final period = scope == ShareCardScope.month
              ? DateTime(2026, 9)
              : DateTime(2026);
          await tester.pumpWidget(_host(
            ShareProgressCard(data: _data(scope, period)),
            locale: locale,
          ));
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(tester.getSize(find.byType(ShareProgressCard)),
              ShareProgressCard.size);
          expect(find.text('86'), findsOneWidget);
          expect(find.text('78%'), findsOneWidget);
        });
      }
    }

    testWidgets('day 1 sits under its weekday, Saturday on the left, in Arabic',
        (tester) async {
      // 1 September 2026 is a Tuesday: Saturday, Sunday, Monday, Tuesday is
      // the fourth column from the LEFT in both languages.
      await tester.pumpWidget(_host(
        ShareProgressCard(data: _data(ShareCardScope.month, DateTime(2026, 9))),
      ));
      await tester.pump();
      final one = tester.getCenter(find.text('1'));
      final two = tester.getCenter(find.text('2'));
      final four = tester.getCenter(find.text('4'));
      final five = tester.getCenter(find.text('5'));
      expect(two.dx, greaterThan(one.dx), reason: 'days run left to right');
      expect(five.dy, greaterThan(four.dy),
          reason: 'Friday the 4th ends the first row, and Saturday the 5th '
              'opens the next one in the left column');
      final cellStep = two.dx - one.dx;
      expect((one.dx - five.dx) / cellStep, closeTo(3, 0.01),
          reason: 'Tuesday is three columns right of Saturday');
    });

    testWidgets('the capture is 1080 by 1350', (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(_host(RepaintBoundary(
        key: key,
        child: ShareProgressCard(
          data: _data(ShareCardScope.month, DateTime(2026, 9)),
        ),
      )));
      await tester.pump();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 3));
      expect(image!.width, 1080);
      expect(image.height, 1350);
      final png =
          await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png));
      expect(png!.lengthInBytes, greaterThan(1000));
      image.dispose();
    });
  });

  group('in the report', () {
    late Directory tmp;
    const s = S(Locale('ar'));
    final today = DateTime.now().effectiveDay;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('share_card_report_');
      Hive.init(tmp.path);
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await tmp.delete(recursive: true);
    });

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
      createdAt: DateTime(today.year - 1),
    );
    final marks = <String, SquareState>{
      for (var i = 1; i <= 3; i++)
        DateTime(today.year, today.month, i).toDateKey(): SquareState.complete,
    };

    Future<void> settle(WidgetTester tester) async {
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
          habitYearHistoryProvider.overrideWith((ref) async => {'h1': marks}),
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

    Future<void> openTab(WidgetTester tester, int index) async {
      tester.widget<SegmentedTabs>(find.byType(SegmentedTabs)).onChanged(index);
      await settle(tester);
    }

    Finder button(String label) => find.widgetWithText(ShareCardButton, label);

    /// The TextButton itself: the row spans the width while the button sits
    /// at its start, so the row's centre is empty space.
    Future<void> tapButton(WidgetTester tester, String label) async {
      final target = find.descendant(
        of: button(label),
        matching: find.byType(TextButton),
      );
      await tester.ensureVisible(target);
      await tester.tap(target);
      await settle(tester);
    }

    testWidgets('a free month: the card carries the header\'s own numbers',
        (tester) async {
      await pump(tester, premium: false);
      await openTab(tester, 1);
      final header =
          tester.widget<ReportHeaderCard>(find.byType(ReportHeaderCard));
      expect(tester.widget<ShareCardButton>(button(s.shareMonthButton)).locked,
          isFalse);

      await tapButton(tester, s.shareMonthButton);

      final card =
          tester.widget<ShareProgressCard>(find.byType(ShareProgressCard));
      expect(card.data.scope, ShareCardScope.month);
      expect(card.data.totalDone, header.summary.totalDone);
      expect(card.data.totalDone, 3);
      final label =
          tester.widget<ReportPeriodHeader>(find.byType(ReportPeriodHeader));
      expect(card.data.periodLabel, label.label);
      expect(find.text(s.shareCardShare), findsOneWidget);
    });

    testWidgets('a free year: the button is locked and opens Premium',
        (tester) async {
      await pump(tester, premium: false);
      await openTab(tester, 2);
      expect(tester.widget<ShareCardButton>(button(s.shareYearButton)).locked,
          isTrue);

      await tapButton(tester, s.shareYearButton);
      expect(find.byType(ShareProgressCard), findsNothing);
      final paywall = tester.widget<PremiumScreen>(find.byType(PremiumScreen));
      expect(paywall.reason, PremiumReason.history);
    });

    testWidgets('a Premium year opens the year card', (tester) async {
      await pump(tester, premium: true);
      await openTab(tester, 2);
      expect(tester.widget<ShareCardButton>(button(s.shareYearButton)).locked,
          isFalse);
      await tapButton(tester, s.shareYearButton);
      final card =
          tester.widget<ShareProgressCard>(find.byType(ShareProgressCard));
      expect(card.data.scope, ShareCardScope.year);
      expect(card.data.period, DateTime(today.year));
      expect(card.data.totalDone, 3);
    });
  });
}
