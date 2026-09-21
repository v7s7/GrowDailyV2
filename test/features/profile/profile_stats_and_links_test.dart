// The Profile page's five stat tiles and its links card
// (lib/features/profile/screens/profile_screen_hero_dashboard.dart and
// profile_screen_banners.dart).
//
// Aziz, 2026-09-21: "checking the profile page and study each option and
// fit it there if it's better, or making it cleaner", right after asking for
// the full activity map to stop being hidden. Two things came out of it:
//
//  1. The tiles. Labels were 8pt, tertiary grey and tracked 1.2, which pulls
//     Arabic letters apart, and a total of 100000 or more broke over two
//     lines because five tiles leave about 60pt each.
//  2. The map. It had no door on Profile, only a row inside خط الحياة الزمني.
//     Later the same day the card's four record rows became one, سجلّي
//     (lib/features/milestones/reports/record_screen.dart), whose row shows
//     the last two weeks as small squares; and «المجموع» became the record's
//     own count, which the map shows too.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:grow_daily_v2/core/providers/day_clock_provider.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/milestones/notifiers/habit_history_notifier.dart';
import 'package:grow_daily_v2/features/milestones/reports/record_screen.dart';
import 'package:grow_daily_v2/features/milestones/reports/record_views.dart';
import 'package:grow_daily_v2/features/profile/screens/profile_screen.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';

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

  // Totals a long-time account reaches: XP passes 100000 well before the
  // top ranks.
  const bigState = DashboardState(
    level: 40,
    currentLevelXp: 0,
    cumulativeXp: 128190,
    gold: 99999,
    streak: 365,
    longestStreak: 999,
    totalCompletions: 12345,
    completions: {},
  );

  Widget app(Widget child,
          {required Locale locale,
          List<Override> overrides = const [],
          NavigatorObserver? observer}) =>
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          locale: locale,
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: GameTheme.dark,
          navigatorObservers: [if (observer != null) observer],
          home: Scaffold(
            body: Padding(
              // The Profile page's own side margin around both.
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(child: child),
            ),
          ),
        ),
      );

  Future<void> pumpStats(WidgetTester tester,
      {required double width, Locale locale = const Locale('ar')}) async {
    tester.view.physicalSize = Size(width * 3, 874 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(
        profileStatsRowForTest(bigState,
            recordTotal: bigState.totalCompletions),
        locale: locale));
    await tester.pump();
  }

  const arabicLabels = ['السلسلة', 'أفضل', 'المجموع', 'ذهب', 'مجموع XP'];
  const values = ['365', '999', '12345', '99999', '128190'];

  for (final width in [375.0, 402.0]) {
    testWidgets(
        'a six-digit total stays on one line inside its tile '
        '(${width.toInt()}pt phone)', (tester) async {
      await pumpStats(tester, width: width);
      expect(tester.takeException(), isNull);
      for (final value in values) {
        final text = find.text(value);
        expect(text, findsOneWidget, reason: value);
        final paragraph = tester.renderObject<RenderParagraph>(text);
        // Its own height before any scaling: one 20pt line, not two.
        expect(paragraph.size.height, lessThan(30),
            reason: '$value broke over more than one line');
        final tile = tester.getRect(
            find.ancestor(of: text, matching: find.byType(InkWell)).first);
        final drawn = tester.getRect(text);
        expect(drawn.left, greaterThanOrEqualTo(tile.left - 0.5),
            reason: '$value runs past its tile');
        expect(drawn.right, lessThanOrEqualTo(tile.right + 0.5),
            reason: '$value runs past its tile');
      }
    });
  }

  testWidgets('Arabic labels are joined, readable, and one size',
      (tester) async {
    // The narrowest phone, where a label would be the first to shrink.
    await pumpStats(tester, width: 375);
    final heights = <double>{};
    for (final label in arabicLabels) {
      final finder = find.text(label);
      expect(finder, findsOneWidget, reason: label);
      final style = tester.widget<Text>(finder).style!;
      expect(style.letterSpacing ?? 0, 0,
          reason: 'tracking pulls the letters of «$label» apart');
      expect(style.fontSize, greaterThanOrEqualTo(11), reason: label);
      heights.add(tester.getRect(finder).height.roundToDouble());
    }
    expect(heights, hasLength(1),
        reason: 'every label drawn at the same size, none shrunk to fit');
  });

  testWidgets('English keeps its tracked capitals, and still fits',
      (tester) async {
    await pumpStats(tester, width: 375, locale: const Locale('en'));
    expect(tester.takeException(), isNull);
    final style = tester.widget<Text>(find.text('STREAK')).style!;
    expect(style.letterSpacing, greaterThan(0));
    // The longest label, on the narrowest phone: one line, inside its tile.
    final longest = find.text('TOTAL XP');
    expect(tester.renderObject<RenderParagraph>(longest).size.height,
        lessThan(style.fontSize! * 2));
    final tile = tester.getRect(
        find.ancestor(of: longest, matching: find.byType(InkWell)).first);
    final drawn = tester.getRect(longest);
    expect(drawn.left, greaterThanOrEqualTo(tile.left - 0.5));
    expect(drawn.right, lessThanOrEqualTo(tile.right + 0.5));
  });

  group('links card', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('profile_links_');
      Hive.init(tmp.path);
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await tmp.delete(recursive: true);
    });

    // The سجلّي row draws the last two weeks from the map's inputs, so
    // those providers are pinned too.
    final overrides = [
      myRoomCodesProvider.overrideWith((ref) => Stream.value(const <String>[])),
      dayClockSourceProvider.overrideWithValue(() => DateTime(2026, 9, 21, 15)),
      authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
      dashboardProvider.overrideWith((ref) => _LoadedDash()),
      allHabitsEverProvider.overrideWithValue(const []),
      habitYearHistoryProvider.overrideWith((ref) async => const {}),
    ];

    testWidgets('three rows: التقدّم, سجلّي with two weeks of squares, الغرف',
        (tester) async {
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(profileLinksForTest(),
          locale: const Locale('ar'), overrides: overrides));
      await tester.pump();

      const order = ['التقدّم', 'سجلّي', 'الغرف'];
      final tops = [for (final t in order) tester.getRect(find.text(t)).top];
      final sorted = [...tops]..sort();
      expect(tops, sorted, reason: 'rows out of order: $order');
      for (final gone in ['التقارير', 'خط الحياة الزمني', 'خريطة التقدّم']) {
        expect(find.text(gone), findsNothing, reason: '$gone is inside سجلّي');
      }
      final strip =
          tester.widget<RecordRecentStrip>(find.byType(RecordRecentStrip));
      expect(strip.colors, hasLength(14));
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping سجلّي opens the record page', (tester) async {
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final observer = _PushLog();
      await tester.pumpWidget(app(profileLinksForTest(),
          locale: const Locale('ar'),
          overrides: overrides,
          observer: observer));
      await tester.pump();
      observer.pushed.clear();

      await tester.tap(find.text('سجلّي'));
      // No pump after the tap: the route is recorded the moment it is
      // pushed, and building the map itself would need its whole data
      // layer. Only which screen the row asks for is under test here.
      expect(observer.pushed, hasLength(1));
      final route = observer.pushed.single as MaterialPageRoute<dynamic>;
      final built = route.builder(tester.element(find.text('الغرف')));
      expect(built, isA<RecordScreen>());
    });
  });
}

class _PushLog extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushed.add(route);
}
