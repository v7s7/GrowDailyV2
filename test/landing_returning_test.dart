import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/landing_harness.dart';

/// A returning user (habits already equipped) starts the day with the
/// morning intention prompt, then lands on their living grid.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final h = LandingHarness();

  setUp(() => h.prepare(activeCatalogIds: ['morning_athkar']));
  tearDown(h.dispose);

  testWidgets('returning user: intention prompt, then the living grid',
      (tester) async {
    await h.pumpApp(tester);

    // With habits equipped, the day opens with the intention prompt.
    expect(find.text('Set your intention'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await h.settle(tester);

    // The grid shows the habit row, summary, legend, and slogan.
    expect(find.text('Morning Athkar'), findsOneWidget);
    expect(find.text('Green squares'), findsOneWidget);
    expect(find.text('Points'), findsOneWidget);
    expect(find.text('LEGEND'), findsOneWidget);
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
    // the FAB is the only remaining way in.
    expect(find.byType(FloatingActionButton), findsNWidgets(2));
    await tester.tap(find.text('ADD HABIT'));
    await h.settle(tester);
    expect(find.text('NEW HABIT'), findsOneWidget);
  });
}
