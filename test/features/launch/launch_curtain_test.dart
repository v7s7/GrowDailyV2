// The launch curtain: the phone's launch screen carried on while the home
// screen loads under it, with Doum in a scene for the hour, then one fade
// to the finished screen (see LaunchCurtain and launch_scenes.dart).
//
// What these hold it to is the promise that it never makes a launch longer
// than the wait it covers plus Doum's moment: it stays until the home screen
// is complete AND Doum has had his second, lifts at its cap whatever the
// load says, lifts at once on a tap, and draws nothing once it has gone.
// Its first frame is the launch screen's own picture, the words centred,
// which is what makes the hand from the phone to the app invisible.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/providers/onboarding_provider.dart';
import 'package:grow_daily_v2/features/launch/launch_curtain.dart';
import 'package:grow_daily_v2/features/launch/launch_scene.dart';
import 'package:grow_daily_v2/features/launch/launch_scenes.dart';
import 'package:grow_daily_v2/features/mascot/sprout.dart';

final _progress = StateProvider<double>((ref) => 0);
final _fasting = StateProvider<bool?>((ref) => null);

void main() {
  late ProviderContainer container;

  setUp(() {
    LaunchMemory.debugReset();
    container = ProviderContainer(overrides: [
      launchProgressProvider.overrideWith((ref) => ref.watch(_progress)),
      launchFastingPlannedProvider.overrideWith((ref) => ref.watch(_fasting)),
      launchCurtainUpProvider.overrideWith((ref) => true),
      // Someone who has been here before: the very first launch has its
      // own scene (see "the very first launch" below).
      onboardingSeenProvider.overrideWith((ref) => true),
    ]);
  });

  tearDown(() => container.dispose());

  Future<void> pumpCurtain(
    WidgetTester tester, {
    LaunchScene? scene = LaunchScene.dayRing,
    bool reduced = false,
    DateTime? now,
  }) =>
      tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(disableAnimations: reduced),
                child: Stack(
                  children: [
                    const Center(child: Text('home')),
                    Positioned.fill(
                      child: LaunchCurtain(
                        scene: scene,
                        // The timings these tests are written against; the
                        // defaults are pinned on their own below.
                        minShow: const Duration(milliseconds: 1000),
                        maxShow: const Duration(milliseconds: 2600),
                        random: math.Random(1),
                        clock: now == null ? DateTime.now : () => now,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  /// The curtain is still drawing (it draws nothing once it has gone).
  bool up() => find.byType(LaunchSceneView).evaluate().isNotEmpty;

  /// Doum's line, as its text reads.
  String? line(WidgetTester tester) {
    final f = find.descendant(
      of: find.byKey(kLaunchLineKey),
      matching: find.byType(RichText),
    );
    if (f.evaluate().isEmpty) return null;
    return tester.widget<RichText>(f.first).text.toPlainText();
  }

  bool lifting() => !container.read(launchCurtainUpProvider);

  void ready() => container.read(_progress.notifier).state = 1;

  Sprout? doum(WidgetTester tester) {
    final f = find.byType(Sprout);
    return f.evaluate().isEmpty ? null : tester.widget<Sprout>(f);
  }

  /// Frame by frame to the one Doum comes in on.
  Future<void> untilDoum(WidgetTester tester) async {
    for (var i = 0; i < 60 && doum(tester) == null; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  group('its first frame is the launch screen', () {
    testWidgets('plain cream, nothing on it', (tester) async {
      await pumpCurtain(tester);
      expect(
        find.byWidgetPredicate(
            (w) => w is ColoredBox && w.color == kLaunchGround),
        findsOneWidget,
      );
      expect(doum(tester), isNull, reason: 'Doum arrives after, not in it');
      expect(find.byKey(kLaunchLineKey), findsNothing,
          reason: 'no words before Doum: the launch screen has none');
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('it covers the home screen, for taps and screen readers',
        (tester) async {
      await pumpCurtain(tester);
      expect(
        find.descendant(
          of: find.byType(LaunchCurtain),
          matching: find.byType(BlockSemantics),
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('his line', () {
    testWidgets('arrives just after him, the scene\'s one sentence',
        (tester) async {
      await pumpCurtain(tester, scene: LaunchScene.morningCoffee);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 600));
      expect(line(tester), 'Sip by sip you\nGrow Daily');
      final screen = tester.getSize(find.byType(MaterialApp));
      expect(tester.getTopLeft(find.byKey(kLaunchLineKey)).dy,
          screen.height / 2 + kLaunchLineBelowCentre);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a slow load: out comes the magnifier, and its line',
        (tester) async {
      await pumpCurtain(tester, scene: LaunchScene.dayRing);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100));
      expect(doum(tester)!.pose, isNot(SproutPose.magnifier));
      await tester.pump(LaunchCurtain.slowAfter);
      await tester.pump();
      expect(doum(tester)!.pose, SproutPose.magnifier);
      await tester.pump(const Duration(milliseconds: 400));
      expect(line(tester), 'Slow or fast we\nGrow Daily');
      ready();
      await tester.pump();
      await tester.pump();
      expect(doum(tester)!.pose, SproutPose.frontWave,
          reason: 'found it: he waves');
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('a quick load never brings the magnifier out',
        (tester) async {
      await pumpCurtain(tester, scene: LaunchScene.turnaround);
      await tester.pump(const Duration(milliseconds: 1100));
      ready();
      await tester.pump();
      await tester.pump(LaunchCurtain.slowAfter);
      expect(find.byType(Sprout).evaluate().isEmpty ||
          doum(tester)!.pose != SproutPose.magnifier, isTrue);
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('Doum', () {
    testWidgets('arrives, standing on the words, centred by his body',
        (tester) async {
      await pumpCurtain(tester);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 600));
      expect(doum(tester)!.pose, SproutPose.threeQuarterWave);
      final screen = tester.getSize(find.byType(MaterialApp));
      final box = tester.getRect(find.byType(Sprout));
      expect(box.bottom, closeTo(screen.height / 2 + kLaunchFeetBelowCentre, .5));
      final body = box.left +
          box.width * kLaunchBodyCentre[SproutPose.threeQuarterWave]!;
      expect(body, closeTo(screen.width / 2, .5));
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('turns to wave when the home screen is ready',
        (tester) async {
      await pumpCurtain(tester);
      await tester.pump(const Duration(milliseconds: 1100));
      ready();
      await tester.pump();
      await tester.pump();
      expect(doum(tester)!.pose, SproutPose.frontWave);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('the night keeps him asleep and goes without a beat',
        (tester) async {
      await pumpCurtain(tester, scene: LaunchScene.nightAsleep);
      await tester.pump(const Duration(milliseconds: 1100));
      expect(doum(tester)!.pose, SproutPose.sleeping);
      ready();
      await tester.pump();
      await tester.pump();
      expect(doum(tester)!.pose, SproutPose.sleeping);
      await tester.pump(const Duration(milliseconds: 500));
      expect(up(), isFalse, reason: 'no 380 ms moment before the fade');
    });

    testWidgets('asleep, his shadow lies along him and fades in with him',
        (tester) async {
      await pumpCurtain(tester, scene: LaunchScene.nightAsleep);
      await untilDoum(tester);
      await tester.pump(const Duration(milliseconds: 250));
      final shadow = find.byKey(kLaunchShadowKey);
      double shadowOpacity() => tester
          .widget<Opacity>(
            find.descendant(of: shadow, matching: find.byType(Opacity)).first,
          )
          .opacity;
      double doumOpacity() => tester
          .widget<Opacity>(
            find
                .ancestor(of: find.byType(Sprout), matching: find.byType(Opacity))
                .first,
          )
          .opacity;
      expect(shadowOpacity(), greaterThan(0));
      expect(shadowOpacity(), lessThan(1));
      expect(shadowOpacity(), doumOpacity(), reason: 'no shadow before him');
      await tester.pump(const Duration(milliseconds: 900));
      expect(shadowOpacity(), 1);
      final screen = tester.getSize(find.byType(MaterialApp));
      final rect = tester.getRect(shadow);
      final foot = tester.getRect(find.byType(Sprout)).bottom;
      expect(rect.center.dx, closeTo(screen.width / 2, .5),
          reason: 'under his body, which the curtain centres');
      expect(rect.center.dy, closeTo(foot - 2, .5),
          reason: 'at his underside, not below him');
      expect(rect.width, 144, reason: 'his length, paw to paw');
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('standing, his shadow pops in with him and shrinks as he hops',
        (tester) async {
      await pumpCurtain(tester);
      await untilDoum(tester);
      await tester.pump(const Duration(milliseconds: 16));
      final shadow = find.byKey(kLaunchShadowKey);
      double scale() => tester
          .widget<Transform>(
            find.descendant(of: shadow, matching: find.byType(Transform)).first,
          )
          .transform
          .storage[0];
      expect(scale(), lessThan(.7), reason: 'as small as he is, arriving');
      await tester.pump(const Duration(milliseconds: 1100));
      expect(scale(), closeTo(1, .001));
      ready();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16)); // the hop starts
      await tester.pump(const Duration(milliseconds: 300)); // near the top
      expect(scale(), lessThan(.8));
      await tester.pump(const Duration(milliseconds: 400)); // landed
      expect(scale(), closeTo(1, .001));
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('the turn goes round to face you', (tester) async {
      await pumpCurtain(tester, scene: LaunchScene.turnaround);
      await tester.pump(const Duration(milliseconds: 300));
      expect(doum(tester)!.pose, SproutPose.back);
      // The turn's last step is 1110 ms after the scene starts (the frame
      // at 300 ms); a slow load would bring the magnifier out 1500 ms
      // after he arrived, which is sooner (arrival is ruled at 0 here).
      await tester.pump(const Duration(milliseconds: 1150));
      expect(doum(tester)!.pose, SproutPose.frontWave);
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('the very first launch', () {
    testWidgets('nothing seen on this phone yet: the seed', (tester) async {
      container.updateOverrides([
        launchProgressProvider.overrideWith((ref) => ref.watch(_progress)),
        launchFastingPlannedProvider.overrideWith((ref) => ref.watch(_fasting)),
        launchCurtainUpProvider.overrideWith((ref) => true),
        onboardingSeenProvider.overrideWith((ref) => false),
      ]);
      await pumpCurtain(tester, scene: null, now: DateTime(2026, 10, 5, 14));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(doum(tester)!.pose, SproutPose.pointer);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('the morning mug waits to know about fasting', () {
    // A Monday, far from Ramadan, and no open recorded: the day's first.
    final morning = DateTime(2026, 10, 5, 7, 30);

    testWidgets('no fast on the plan: the mug', (tester) async {
      await pumpCurtain(tester, scene: null, now: morning);
      await tester.pump(const Duration(milliseconds: 200));
      expect(doum(tester), isNull, reason: 'still waiting to know');
      container.read(_fasting.notifier).state = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(doum(tester)!.pose, SproutPose.mug);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a fast on the plan: never the mug', (tester) async {
      await pumpCurtain(tester, scene: null, now: morning);
      container.read(_fasting.notifier).state = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(doum(tester)!.pose, isNot(SproutPose.mug));
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('not known in time: no mug', (tester) async {
      await pumpCurtain(tester, scene: null, now: morning);
      await tester.pump(LaunchCurtain.fastingWait);
      await tester.pump(const Duration(milliseconds: 300));
      expect(doum(tester)!.pose, isNot(SproutPose.mug));
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('how long it stays', () {
    test('at least 1.6 s for his scene, at most 5 s for a slow load', () {
      const curtain = LaunchCurtain();
      expect(curtain.minShow, const Duration(milliseconds: 1600));
      expect(curtain.maxShow, const Duration(milliseconds: 5000));
      expect(LaunchCurtain.slowAfter, lessThan(curtain.maxShow));
    });

    testWidgets('ready early, it still gives Doum his second', (tester) async {
      ready();
      await pumpCurtain(tester);
      await tester.pump(const Duration(milliseconds: 900));
      expect(lifting(), isFalse);
      await tester.pump(const Duration(milliseconds: 150));
      expect(lifting(), isTrue,
          reason: 'lifting starts at minShow once the home screen is ready');
      await tester.pump(const Duration(milliseconds: 380));
      await tester.pump(const Duration(milliseconds: 500));
      expect(up(), isFalse);
    });

    testWidgets('it waits for the home screen past minShow', (tester) async {
      await pumpCurtain(tester);
      await tester.pump(const Duration(milliseconds: 1800));
      expect(up(), isTrue);
      expect(lifting(), isFalse);
      ready();
      await tester.pump();
      await tester.pump();
      expect(lifting(), isTrue);
      await tester.pump(const Duration(milliseconds: 380));
      await tester.pump(const Duration(milliseconds: 500));
      expect(up(), isFalse);
    });

    testWidgets('never past its cap, ready or not', (tester) async {
      await pumpCurtain(tester);
      await tester.pump(const Duration(milliseconds: 2550));
      expect(up(), isTrue);
      await tester.pump(const Duration(milliseconds: 100));
      expect(lifting(), isTrue);
      await tester.pump(const Duration(milliseconds: 500));
      expect(up(), isFalse, reason: 'the cap goes without the beat');
    });

    testWidgets('a tap lifts it at once', (tester) async {
      await pumpCurtain(tester);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byType(LaunchCurtain));
      await tester.pump();
      expect(lifting(), isTrue);
      await tester.pump(const Duration(milliseconds: 500));
      expect(up(), isFalse);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('once gone it draws nothing and stays gone', (tester) async {
      ready();
      await pumpCurtain(tester);
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 600));
      expect(up(), isFalse);
      // A later wobble in readiness (a resume reloading the week) does not
      // bring it back.
      container.read(_progress.notifier).state = .5;
      await tester.pump();
      ready();
      await tester.pump(const Duration(seconds: 3));
      expect(up(), isFalse);
    });
  });

  group('Reduce Motion', () {
    testWidgets('it waits only for the load, and goes without a beat',
        (tester) async {
      ready();
      await pumpCurtain(tester, reduced: true);
      await tester.pump(const Duration(milliseconds: 300));
      expect(lifting(), isFalse);
      await tester.pump(const Duration(milliseconds: 60));
      expect(lifting(), isTrue);
      await tester.pump(const Duration(milliseconds: 300));
      expect(up(), isFalse);
    });
  });

  group('every scene', () {
    for (final scene in LaunchScene.values) {
      testWidgets('${scene.name} arrives, readies and goes', (tester) async {
        await pumpCurtain(tester, scene: scene);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 800));
        expect(doum(tester), isNotNull);
        expect(launchScenePoses(scene), contains(doum(tester)!.pose));
        expect(line(tester), launchLine(scene).replaceFirst(
          RegExp(r' ?Grow Daily'),
          '\nGrow Daily',
        ));
        ready();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 380));
        await tester.pump(const Duration(milliseconds: 500));
        expect(up(), isFalse);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
