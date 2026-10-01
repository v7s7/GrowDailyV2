// Doum's hand-off from the launch curtain to the sign-in screen (Aziz,
// 2026-10-01, the canvas "Doum picks the language"): on the very first open
// he does not fade with the curtain, he flies into the sign-in screen's head
// and that screen's Doum carries on from the same spot, then turns round
// into his language's look.
//
// What has to hold: he lands exactly where the sign-in Doum stands (no jump
// between the two drawings), the sign-in Doum never shows twice or early,
// and every way the flight cannot happen (a tap that skips the curtain,
// Reduce Motion, nothing to land on, any other scene) falls back to the
// curtain as it always was, with the sign-in Doum popping in after it.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/providers/onboarding_provider.dart';
import 'package:grow_daily_v2/features/auth/widgets/sign_in_doum.dart';
import 'package:grow_daily_v2/features/launch/launch_curtain.dart';
import 'package:grow_daily_v2/features/launch/launch_doum_handoff.dart';
import 'package:grow_daily_v2/features/launch/launch_scene.dart';
import 'package:grow_daily_v2/features/launch/launch_scenes.dart';
import 'package:grow_daily_v2/features/mascot/doum_language_look.dart';
import 'package:grow_daily_v2/features/mascot/sprout.dart';

void main() {
  late ProviderContainer container;
  late DoumLookController doum;

  setUp(() {
    LaunchMemory.debugReset();
    doum = DoumLookController();
    container = ProviderContainer(overrides: [
      // The sign-in screen loads nothing: ready at once.
      launchProgressProvider.overrideWith((ref) => 1),
      launchCurtainUpProvider.overrideWith((ref) => true),
      onboardingSeenProvider.overrideWith((ref) => false),
    ]);
  });

  tearDown(() {
    container.dispose();
    doum.dispose();
  });

  Future<void> pump(
    WidgetTester tester, {
    LaunchScene scene = LaunchScene.firstOpen,
    bool signIn = true,
    bool reduced = false,
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(402, 874) * 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data:
                  MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: Stack(
                children: [
                  // The sign-in screen's head: its Doum where the icon was.
                  if (signIn)
                    Positioned(
                      top: 80,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: SignInDoum(height: 150, controller: doum),
                      ),
                    ),
                  Positioned.fill(
                    child: LaunchCurtain(
                      scene: scene,
                      minShow: const Duration(milliseconds: 1000),
                      maxShow: const Duration(milliseconds: 2600),
                      settle: Duration.zero,
                      random: math.Random(1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  DoumHandoffPhase phase() => container.read(launchDoumHandoffProvider).phase;
  bool curtainUp() => find.byType(LaunchSceneView).evaluate().isNotEmpty;

  /// The sign-in screen's Doum, once he is on screen.
  Finder signInDoum() => find.descendant(
        of: find.byType(DoumLanguageLook),
        matching: find.byType(Sprout),
      );

  /// The Doum the curtain flies: a Sprout of the curtain's, not its scene's.
  Finder flying() => find.descendant(
        of: find.byKey(kLaunchFlyingDoumKey),
        matching: find.byType(Sprout),
      );

  testWidgets(
      'first open: he flies into the sign-in head, lands on its Doum\'s '
      'spot, and that Doum dresses', (tester) async {
    await pump(tester);
    await tester.pump();
    expect(phase(), DoumHandoffPhase.expected);
    expect(find.byType(DoumLanguageLook), findsNothing,
        reason: 'the sign-in Doum waits for the one on the curtain');

    // His second on the curtain, then the ready moment: the wave, no hop.
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump(const Duration(milliseconds: 100));
    final sceneDoum = tester.widget<Sprout>(
      find.descendant(
        of: find.byType(LaunchSceneView),
        matching: find.byType(Sprout),
      ),
    );
    expect(sceneDoum.pose, SproutPose.frontWave);

    // The beat, then the flight.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 20));
    expect(phase(), DoumHandoffPhase.flying);
    expect(flying(), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(LaunchSceneView),
        matching: find.byType(Sprout),
      ),
      findsNothing,
      reason: 'the scene leaves him to the flight',
    );
    expect(find.byType(DoumLanguageLook), findsNothing);

    // Nearly there: the flying Doum is almost on the stand.
    final stand = tester.getRect(find.byType(SignInDoum));
    await tester.pump(const Duration(milliseconds: 440));
    final late = tester.getRect(flying());
    final box = Sprout.sizeOf(SproutPose.frontWave, 150);
    final landLeft =
        stand.center.dx - kDoumFeetCentre[SproutPose.frontWave]! * box.width;
    expect(late.left, moreOrLessEquals(landLeft, epsilon: 3));
    expect(late.bottom, moreOrLessEquals(stand.bottom, epsilon: 3));

    // Landed: the curtain is gone and the sign-in Doum stands exactly where
    // the flight ended, as the everyday Doum.
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();
    // Taken over, and spent: a later sign-in screen pops its Doum in.
    expect(phase(), DoumHandoffPhase.none);
    expect(curtainUp(), isFalse);
    expect(flying(), findsNothing);
    final landed = tester.getRect(signInDoum());
    expect(landed.left, moreOrLessEquals(landLeft, epsilon: 0.01));
    expect(landed.bottom, moreOrLessEquals(stand.bottom, epsilon: 0.01));
    expect(tester.widget<Sprout>(signInDoum()).pose, SproutPose.frontWave);

    // A breath, then he turns round into his look (English here).
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump();
    expect(tester.widget<Sprout>(signInDoum()).pose, SproutPose.langSuitGreet);
    await tester.pump(const Duration(seconds: 12));
  });

  testWidgets('a tap that skips the curtain: no flight, he pops in after it',
      (tester) async {
    await pump(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.tap(find.byType(LaunchCurtain));
    await tester.pump();
    expect(phase(), DoumHandoffPhase.none);
    expect(flying(), findsNothing);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(curtainUp(), isFalse);
    expect(tester.widget<Sprout>(signInDoum()).pose, SproutPose.langSuitFront);
    await tester.pump(const Duration(seconds: 12));
  });

  testWidgets('Reduce Motion: no flight', (tester) async {
    await pump(tester, reduced: true);
    await tester.pump();
    expect(phase(), DoumHandoffPhase.none);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(curtainUp(), isFalse);
    expect(flying(), findsNothing);
    expect(tester.widget<Sprout>(signInDoum()).pose, SproutPose.langSuitFront);
    await tester.pump(const Duration(seconds: 12));
  });

  testWidgets('no sign-in screen under it: the curtain lifts as always',
      (tester) async {
    await pump(tester, signIn: false);
    await tester.pump();
    expect(phase(), DoumHandoffPhase.expected);
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(phase(), DoumHandoffPhase.none);
    expect(flying(), findsNothing);
    await tester.pump(const Duration(milliseconds: 600));
    expect(curtainUp(), isFalse);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets(
      'another scene over the sign-in screen: he waits for the curtain, '
      'then pops in', (tester) async {
    await pump(tester, scene: LaunchScene.dayRing);
    await tester.pump();
    expect(phase(), DoumHandoffPhase.none);
    expect(find.byType(DoumLanguageLook), findsNothing,
        reason: 'his pop and hello would play unseen under the curtain');
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.byType(DoumLanguageLook), findsOneWidget);
    expect(flying(), findsNothing);
    await tester.pump(const Duration(seconds: 12));
  });
}
