import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/landing_harness.dart';

/// A returning user (habits already equipped) lands directly on the living
/// grid. Intention setting is available from the Profile hub, not imposed at
/// launch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final h = LandingHarness();

  setUp(() => h.prepare(activeCatalogIds: ['morning_athkar']));
  tearDown(h.dispose);

  testWidgets('returning user: opens directly on the living grid',
      (tester) async {
    await h.pumpApp(tester);

    expect(find.text('Set your intention'), findsNothing);

    // The grid shows the habit row, summary and slogan. No legend assertion
    // any more: the grid's colour legend was removed from the screen
    // outright (nothing in lib/ references it), so this was asserting a
    // widget that no longer exists rather than catching a regression.
    expect(find.text('Morning Athkar'), findsOneWidget);
    expect(find.text('Squares filled'), findsOneWidget);
    expect(find.text('Points'), findsOneWidget);
    // The slogan sits at the bottom of the scroll — bring it into view.
    await tester.scrollUntilVisible(
      find.text('Color your life, one square at a time.'),
      120,
    );
    expect(
      find.text('Color your life, one square at a time.'),
      findsOneWidget,
    );

    // A user with habits already equipped must still be able to add more —
    // the empty state's add-habit buttons are gone once habits exist, so
    // the FAB is the only remaining way in. That is now a single
    // FloatingActionButton.small whose "ADD HABIT" wording lives in its
    // tooltip rather than as visible text, so this asserts one button and
    // taps it by type; the old two-FABs-and-tap-the-label expectation
    // described a layout the grid no longer has.
    expect(find.byType(FloatingActionButton), findsOneWidget);
    await tester.tap(find.byType(FloatingActionButton));
    await h.settle(tester);
    // The FAB now opens the Add-a-Habit hub (Plans / Add Goal tabs), not
    // the old single "NEW HABIT" sheet that string belonged to.
    expect(find.text('Add a Habit'), findsOneWidget);
  });
}
