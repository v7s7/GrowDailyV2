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

    testWidgets('shows three tabs — Habits, Profile, Tasks — with no Today',
        (tester) async {
      await harness.pumpApp(tester);

      expect(find.text('Today'), findsNothing);
      expect(find.text('Habits'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Tasks'), findsOneWidget);
    });

    testWidgets('Grid screen (the harness home) is tab 0', (tester) async {
      await harness.pumpApp(tester);

      final navBar = tester.widget<GameNavBar>(find.byType(GameNavBar));
      expect(navBar.currentIndex, 0);
    });
  });
}
