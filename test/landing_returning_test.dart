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
    // the empty state's add-habit buttons are gone once habits exist, so this
    // is the ONLY remaining way in, and that is why it is asserted here.
    //
    // It used to be a FloatingActionButton and is now a "+" in the Grid
    // header. The FAB floated over the board and, on a habit list long enough
    // to reach it, covered a real tappable square.
    //
    // Asserted by its visible label, not by widget type and no longer by
    // tooltip: the button carries its name on screen now, so the label is both
    // the accessible name and the thing a sighted first-run user reads. A
    // tooltip was the right assertion while it was a bare "+" glyph; asserting
    // the visible text is strictly stronger, because a tooltip can pass while
    // the control still looks like an unlabelled mystery icon.
    expect(find.byType(FloatingActionButton), findsNothing,
        reason: 'the add-habit action must not float over the grid');
    final addHabit = find.text('ADD HABIT');
    expect(addHabit, findsOneWidget);
    await tester.tap(addHabit);
    await h.settle(tester);
    // The FAB now opens the Add-a-Habit hub (Plans / Add Goal tabs), not
    // the old single "NEW HABIT" sheet that string belonged to.
    expect(find.text('Add a Habit'), findsOneWidget);
  });
}
