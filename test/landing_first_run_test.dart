import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';

import 'helpers/landing_harness.dart';

/// The complete first-session journey, end to end through the real UI:
/// land on the empty grid → browse plans → activate one → see the board →
/// color today's first square to green → collect the First Victory
/// achievement → check the heatmap.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final h = LandingHarness();

  setUp(() => h.prepare());
  tearDown(h.dispose);

  testWidgets('first session: empty grid → plan → first green square → reward',
      (tester) async {
    await h.pumpApp(tester);

    // A brand-new user lands on the Grid — no intention prompt in the way.
    expect(find.text('Set your intention'), findsNothing);
    expect(find.text('Victory Grid'), findsOneWidget);
    expect(find.text('No habits to track yet'), findsOneWidget);

    // Recruit right on the flagship screen: browse plans in place.
    await tester.tap(find.text('Browse Plans'));
    await h.settle(tester);
    expect(find.text('Choose Your Plan'), findsOneWidget);

    // Expand a starter plan and activate it.
    await tester.tap(find.text('Islamic Daily Routine'));
    await h.settle(tester);
    await tester.tap(find.text('Start Plan'));
    await h.settle(tester);

    // Close the sheet; the board is alive now.
    Navigator.of(tester.element(find.text('Choose Your Plan'))).pop();
    await h.settle(tester);
    expect(find.text('Morning Athkar'), findsOneWidget);
    expect(find.text('Green squares'), findsOneWidget);
    expect(find.text('Legend'), findsOneWidget);

    // Tap today's cell for Morning Athkar: white → yellow.
    final todayCells = find.byWidgetPredicate((w) {
      if (w.runtimeType.toString() != '_SquareCell') return false;
      final dynamic cell = w;
      // ignore: avoid_dynamic_calls
      return (cell.isToday as bool) && !(cell.isFuture as bool);
    });
    expect(todayCells, findsWidgets);
    final today = DateTime.now();

    await tester.tap(todayCells.first);
    await h.settle(tester);
    // The plan's first habit is Morning Athkar — its square is now partial.
    final grid = h.container.read(weeklyGridProvider);
    final coloredId = ['morning_athkar', 'evening_athkar', 'quran_daily_page', 'sleep_schedule']
        .firstWhere((id) => grid.squareFor(id, today) == SquareState.partial);

    // Yellow → green: the core reward moment (burst + First Victory).
    await tester.tap(todayCells.first);
    await h.settle(tester);
    expect(
      h.container.read(weeklyGridProvider).squareFor(coloredId, today),
      SquareState.complete,
    );

    // The First Victory achievement sheet celebrates the first green square.
    expect(find.text('First Victory'), findsOneWidget);
    await tester.tap(find.text('CLAIM REWARD'));
    await h.settle(tester);

    // The heatmap is one tap from the grid header.
    await tester.tap(find.byIcon(Icons.insights_rounded));
    await h.settle(tester);
    expect(find.text('Progress Heatmap'), findsOneWidget);
  });
}
