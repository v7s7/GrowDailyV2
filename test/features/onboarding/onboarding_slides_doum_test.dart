// The three onboarding slides with Doum on each picture (Aziz, 2026-10-01,
// the canvas "Doum picks the language"): he fills the week's squares with
// his pencil, stamps a task into «الآن», and claps for the room.
//
// What has to hold: every slide still fits the smallest phone in both
// languages, he stands on the picture's top edge (never over what it
// shows), the squares and the stamp play out once, and the first place on
// the board shows its number, not a cup (no medals beside Doum).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/features/mascot/sprout.dart';
import 'package:grow_daily_v2/features/matrix/models/matrix_task.dart';
import 'package:grow_daily_v2/features/onboarding/screens/onboarding_screen.dart';

import '../../helpers/landing_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LandingHarness harness;

  setUp(() async {
    harness = LandingHarness();
    await harness.prepare();
  });

  tearDown(() => harness.dispose());

  Future<void> pumpAt(WidgetTester tester, Locale locale) async {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(375, 667) * 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness.app(home: const OnboardingScreen(), locale: locale),
    );
    await tester.pump();
  }

  SproutPose pose(WidgetTester tester) =>
      tester.widget<Sprout>(find.byType(Sprout)).pose;

  Future<void> next(WidgetTester tester, S s) async {
    await tester.tap(find.text(s.onboardingNext));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  for (final locale in const [Locale('ar'), Locale('en')]) {
    final s = S(locale);
    final tag = locale.languageCode;

    testWidgets('[$tag] Doum on all three slides, each fits the small phone',
        (tester) async {
      await pumpAt(tester, locale);
      expect(tester.takeException(), isNull);
      expect(pose(tester), SproutPose.pencil);

      // The four squares before today fill, one by one.
      expect(
        tester
            .widgetList<AnimatedOpacity>(
              find.ancestor(
                of: find.byIcon(Icons.check_rounded),
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .where((o) => o.opacity == 1),
        isEmpty,
      );
      await tester.pump(const Duration(milliseconds: 1200));
      expect(
        tester
            .widgetList<AnimatedOpacity>(
              find.ancestor(
                of: find.byIcon(Icons.check_rounded),
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .where((o) => o.opacity == 1)
            .length,
        4,
      );

      await next(tester, s);
      expect(tester.takeException(), isNull);
      expect(pose(tester), SproutPose.stampCheck);
      // He stands on the «الآن» box's top edge: his feet (the picture's
      // bottom less the few clear pixels under them) on it, over the box.
      final box = find
          .ancestor(
            of: find.text(MatrixQuadrant.doFirst.localLabel(s.isAr)),
            matching: find.byType(Container),
          )
          .evaluate()
          .map((e) => tester.getRect(find.byElementPredicate((x) => x == e)))
          .firstWhere((r) => r.width > 80 && r.width < 160 && r.height < 90);
      // The box's rect includes its 4pt margin (of a 124pt cell slot).
      final edge = box.top + 4 * box.width / 124;
      final doum = tester.getRect(find.byType(Sprout));
      final feet = doum.bottom - doum.height * 14 / 770;
      expect(feet, closeTo(edge, 1.5));
      expect(doum.center.dx, closeTo(box.center.dx, box.width / 2));

      await next(tester, s);
      expect(tester.takeException(), isNull);
      expect(pose(tester), SproutPose.clap);
      expect(find.byIcon(Icons.emoji_events_rounded), findsNothing,
          reason: 'no cup beside Doum');
      expect(find.text('1'), findsOneWidget);
      await tester.pump(const Duration(seconds: 12));
    });
  }
}
