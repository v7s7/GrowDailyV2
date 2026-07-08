import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/shared/widgets/game_nav_bar.dart';

import 'helpers/landing_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GameNavBar', () {
    late LandingHarness harness;

    setUp(() async {
      harness = LandingHarness();
      await harness.prepare();
    });

    tearDown(() => harness.dispose());

    testWidgets('shows "Today" (not "Dashboard") with a checklist icon',
        (tester) async {
      await harness.pumpApp(tester);

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Dashboard'), findsNothing);
      expect(find.byIcon(Icons.checklist_rounded), findsOneWidget);
      expect(find.byIcon(Icons.home_rounded), findsNothing);
    });

    testWidgets('keeps the Grid — Today — Focus — Profile order',
        (tester) async {
      await harness.pumpApp(tester);

      final navBar = tester.widget<GameNavBar>(find.byType(GameNavBar));
      // GridScreen (the harness's home) is tab 0.
      expect(navBar.currentIndex, 0);
      expect(find.text('Grid'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Focus'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
    });
  });
}
