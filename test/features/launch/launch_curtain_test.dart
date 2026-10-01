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
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/l10n/wording_edits.dart';
import 'package:grow_daily_v2/core/providers/onboarding_provider.dart';
import 'package:grow_daily_v2/core/theme/status_bar_style.dart';
import 'package:grow_daily_v2/features/launch/launch_curtain.dart';
import 'package:grow_daily_v2/features/launch/launch_scene.dart';
import 'package:grow_daily_v2/features/launch/launch_scenes.dart';
import 'package:grow_daily_v2/features/launch/launch_settings.dart';
import 'package:grow_daily_v2/features/mascot/sprout.dart';

final _progress = StateProvider<double>((ref) => 0);
final _fasting = StateProvider<bool?>((ref) => null);
final _walker = StateProvider<bool?>((ref) => null);
final _dataReady = StateProvider<bool>((ref) => true);

void main() {
  late ProviderContainer container;

  setUp(() {
    LaunchMemory.debugReset();
    // Every moment plays every day it can: which days a moment's chance
    // skips is pinned in launch_scene_test.dart, not here.
    WordingEditsStore.live.value = WordingEdits(
      splash: SplashEdits(
        chance: {
          for (final name in kSplashDailyChance.keys) name: 100,
        },
      ),
    );
    container = ProviderContainer(overrides: [
      launchProgressProvider.overrideWith((ref) => ref.watch(_progress)),
      launchFastingPlannedProvider.overrideWith((ref) => ref.watch(_fasting)),
      launchWalkerProvider.overrideWith((ref) => ref.watch(_walker)),
      launchDataReadyProvider.overrideWith((ref) => ref.watch(_dataReady)),
      launchCurtainUpProvider.overrideWith((ref) => true),
      // Someone who has been here before: the very first launch has its
      // own scene (see "the very first launch" below).
      onboardingSeenProvider.overrideWith((ref) => true),
    ]);
  });

  tearDown(() {
    container.dispose();
    WordingEditsStore.live.value = WordingEdits.empty;
  });

  Future<void> pumpCurtain(
    WidgetTester tester, {
    LaunchScene? scene = LaunchScene.dayRing,
    bool reduced = false,
    DateTime? now,
    Duration settle = Duration.zero,
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
                        // Ready counts at once here; the wait to settle
                        // is held to its own test below.
                        settle: settle,
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

  /// Every drawing of [pose]'s picture: Doum's own, or one the scenery
  /// draws (the walk's machine as it tucks away).
  Finder picture(SproutPose pose) => find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is ResizeImage &&
            ((w.image as ResizeImage).imageProvider as AssetImage).assetName ==
                pose.asset,
      );

  /// [pose]'s picture as Doum draws it.
  Finder doumPicture(SproutPose pose) =>
      find.descendant(of: find.byType(Sprout), matching: picture(pose));

  /// How much of [f] shows through the opacities above it, the curtain's
  /// own included.
  double shown(WidgetTester tester, Finder f) {
    var o = 1.0;
    tester.element(f).visitAncestorElements((e) {
      final w = e.widget;
      if (w is Opacity) o *= w.opacity;
      if (w is FadeTransition) o *= w.opacity.value;
      return true;
    });
    return o;
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

    // Aziz, 2026-10-01: "the connection one should appear if the network
    // is slow and the wifi mark should appear".
    Finder wifi() => find.byKey(kLaunchWifiKey);

    Future<void> untilSlow(WidgetTester tester) async {
      await untilDoum(tester);
      await tester.pump(LaunchCurtain.slowAfter);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
    }

    testWidgets('a slow connection: the magnifier and the Wi-Fi mark, in '
        'every scene', (tester) async {
      container.read(_dataReady.notifier).state = false;
      await pumpCurtain(tester, scene: LaunchScene.morningCoffee);
      await tester.pump(const Duration(milliseconds: 400));
      expect(wifi(), findsNothing, reason: 'not slow yet');
      await tester.pump(LaunchCurtain.slowAfter);
      await tester.pump();
      expect(doum(tester)!.pose, SproutPose.magnifier);
      expect(wifi(), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      expect(line(tester), 'Slow or fast we\nGrow Daily');
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('slow on the work here, not the network: no Wi-Fi mark',
        (tester) async {
      await pumpCurtain(tester, scene: LaunchScene.fullDay);
      await untilSlow(tester);
      expect(doum(tester)!.pose, SproutPose.magnifier);
      expect(wifi(), findsNothing);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('the data comes in: the mark lights whole and goes',
        (tester) async {
      container.read(_dataReady.notifier).state = false;
      await pumpCurtain(tester, scene: LaunchScene.eid);
      await untilSlow(tester);
      expect(wifi(), findsOneWidget);
      container.read(_dataReady.notifier).state = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(wifi(), findsOneWidget, reason: 'lit whole, fading');
      await tester.pump(const Duration(milliseconds: 400));
      expect(wifi(), findsNothing);
      expect(doum(tester)!.pose, SproutPose.magnifier,
          reason: 'the home screen is not ready yet: still looking');
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('the night: asleep, with the mark over him', (tester) async {
      container.read(_dataReady.notifier).state = false;
      await pumpCurtain(tester, scene: LaunchScene.nightAsleep);
      await untilSlow(tester);
      expect(doum(tester)!.pose, SproutPose.sleeping);
      expect(wifi(), findsOneWidget);
      expect(tester.getRect(wifi()).bottom,
          lessThan(tester.getRect(find.byType(Sprout)).top + 4),
          reason: 'over him, not on him');
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('every scene but the night brings the magnifier', (tester) async {
      expect(LaunchCurtain.searchingScenes,
          {...LaunchScene.values}..remove(LaunchScene.nightAsleep));
      for (final scene in LaunchScene.values) {
        expect(launchScenePoses(scene).contains(SproutPose.magnifier),
            scene != LaunchScene.nightAsleep,
            reason: '${scene.name} decodes it before it starts');
      }
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
        launchWalkerProvider.overrideWith((ref) => ref.watch(_walker)),
        launchDataReadyProvider.overrideWith((ref) => ref.watch(_dataReady)),
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
      await untilDoum(tester);
      expect(doum(tester)!.pose, isNot(SproutPose.mug));
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('not known in time: no mug', (tester) async {
      await pumpCurtain(tester, scene: null, now: morning);
      await tester.pump(LaunchCurtain.fastingWait);
      await tester.pump(const Duration(milliseconds: 300));
      await untilDoum(tester);
      expect(doum(tester)!.pose, isNot(SproutPose.mug));
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('how long it stays', () {
    testWidgets('the real timings: a load ready at 0.8 s never searches',
        (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Stack(
              children: [
                const Center(child: Text('home')),
                Positioned.fill(
                  child: LaunchCurtain(
                    scene: LaunchScene.dayRing,
                    random: math.Random(1),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final seen = <SproutPose>{};
      for (var t = 0; t < 5500; t += 50) {
        if (t == 800) ready();
        await tester.pump(const Duration(milliseconds: 50));
        final d = doum(tester);
        if (d != null) seen.add(d.pose);
      }
      expect(seen, isNot(contains(SproutPose.magnifier)));
      expect(up(), isFalse);
    });

    testWidgets('a slow load keeps its line once the magnifier came out',
        (tester) async {
      await pumpCurtain(tester, scene: LaunchScene.dayRing);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pump();
      expect(doum(tester)!.pose, SproutPose.magnifier);
      await tester.pump(const Duration(milliseconds: 400));
      ready();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(line(tester), 'Slow or fast we\nGrow Daily',
          reason: 'the words change at most once');
      await tester.pump(const Duration(seconds: 2));
    });

    test('at least 4 s for his scene, at most 9 s for a slow load', () {
      // Aziz, 2026-09-30: "let the splash screen take their time to 3 sec,
      // or the needed time so that when grid open, its fully ready"; then
      // 2026-10-01: "add 1 sec for each screen".
      const curtain = LaunchCurtain();
      // Unset, they follow the admin's splash settings: 4 s and 9 s built in.
      expect(curtain.minShow, isNull);
      expect(curtain.maxShow, isNull);
      expect(LaunchSettings.builtIn.minShow, const Duration(milliseconds: 4000));
      expect(LaunchSettings.builtIn.maxShow, const Duration(milliseconds: 9000));
      expect(curtain.settle, const Duration(milliseconds: 300));
      expect(curtain.replay, isFalse);
      expect(LaunchCurtain.slowAfter, lessThan(LaunchSettings.builtIn.maxShow));
    });

    testWidgets('a moment of ready is not ready: it waits to settle',
        (tester) async {
      await pumpCurtain(tester, settle: const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 1200));
      // A reload lands; the reminder pass it asks for has not started yet.
      ready();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      container.read(_progress.notifier).state = .8;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(lifting(), isFalse);
      expect(up(), isTrue, reason: 'ready for 150 ms is not ready');
      // The pass has finished: ready from here on.
      ready();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(lifting(), isFalse, reason: 'not yet ready for 300 ms');
      await tester.pump(const Duration(milliseconds: 60));
      expect(lifting(), isFalse, reason: 'his ready moment first');
      await tester.pump(const Duration(milliseconds: 380));
      expect(lifting(), isTrue);
      await tester.pump(const Duration(milliseconds: 500));
      expect(up(), isFalse);
    });

    testWidgets('ready early, it still gives Doum his second', (tester) async {
      ready();
      await pumpCurtain(tester);
      await tester.pump(const Duration(milliseconds: 900));
      expect(lifting(), isFalse);
      await tester.pump(const Duration(milliseconds: 150));
      expect(lifting(), isFalse,
          reason: 'at minShow his ready moment plays first, still covering');
      await tester.pump(const Duration(milliseconds: 380));
      expect(lifting(), isTrue,
          reason: 'the page starts to show once the moment is over');
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
      expect(lifting(), isFalse, reason: 'his ready moment first');
      await tester.pump(const Duration(milliseconds: 380));
      expect(lifting(), isTrue);
      await tester.pump(const Duration(milliseconds: 500));
      expect(up(), isFalse);
    });

    testWidgets('the cap goes without claiming the page is ready',
        (tester) async {
      await pumpCurtain(tester);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 2250));
      final before = doum(tester)!.pose;
      expect(before, SproutPose.magnifier, reason: 'a slow load: searching');
      await tester.pump(const Duration(milliseconds: 100));
      expect(lifting(), isTrue);
      await tester.pump();
      expect(doum(tester)!.pose, before,
          reason: 'no "found it" wave over a page that is not ready');
      await tester.pump(const Duration(milliseconds: 500));
      expect(up(), isFalse);
    });

    testWidgets('a tap while it can be seen never reaches the page',
        (tester) async {
      var taps = 0;
      ready();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => taps++,
                  ),
                ),
                Positioned.fill(
                  child: LaunchCurtain(
                    scene: LaunchScene.dayRing,
                    minShow: const Duration(milliseconds: 1000),
                    maxShow: const Duration(milliseconds: 2600),
                    random: math.Random(1),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 100));
      // His ready moment: a tap on his hop.
      await tester.tapAt(const Offset(200, 300));
      await tester.pump();
      expect(taps, 0, reason: 'the ready moment is still the curtain');
      // It cut the moment short; the fade has begun and is still opaque.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(const Offset(200, 300));
      await tester.pump();
      expect(taps, 0, reason: 'the start of the fade is still the curtain');
      await tester.pump(const Duration(seconds: 1));
      expect(up(), isFalse);
      await tester.tapAt(const Offset(200, 300));
      expect(taps, 1, reason: 'once gone, the page has its taps');
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

  group('a long return plays it again', () {
    double curtainOpacity(WidgetTester tester) => tester
        .widget<Opacity>(
          find
              .descendant(
                of: find.byType(LaunchCurtain),
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity;

    /// [total] in frames, so the curtain's own animations run as on a phone.
    Future<void> frames(WidgetTester tester, int total) async {
      for (var t = 0; t < total; t += 50) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> pumpHost(WidgetTester tester) => tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: Stack(
                children: [
                  Center(child: Text('home')),
                  Positioned.fill(child: LaunchCurtainHost()),
                ],
              ),
            ),
          ),
        );

    testWidgets('the launch\'s comes in at once, a return\'s fades in',
        (tester) async {
      ready();
      await pumpHost(tester);
      expect(curtainOpacity(tester), 1,
          reason: 'the launch screen\'s own picture, no fade');
      expect(tester.widget<LaunchCurtain>(find.byType(LaunchCurtain)).replay,
          isFalse);
      await frames(tester, 5200);
      expect(up(), isFalse);

      // main.dart, on a return after 30 minutes or more.
      container.read(launchCurtainUpProvider.notifier).state = true;
      container.read(launchCurtainRunProvider.notifier).state++;
      await tester.pump();
      expect(up(), isTrue, reason: 'a fresh curtain, not the gone one');
      expect(tester.widget<LaunchCurtain>(find.byType(LaunchCurtain)).replay,
          isTrue);
      expect(curtainOpacity(tester), 0,
          reason: 'over the page the phone was already showing');
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 130));
      expect(curtainOpacity(tester), inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 200));
      expect(curtainOpacity(tester), 1);
      expect(lifting(), isFalse);

      // Its own 4 s, then it goes as the launch's does.
      await frames(tester, 3500);
      expect(lifting(), isFalse);
      await frames(tester, 1000);
      expect(lifting(), isTrue);
      await frames(tester, 700);
      expect(up(), isFalse);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('a curtain a return has replaced never says the page is '
        'showing', (tester) async {
      await pumpCurtain(tester);
      await tester.pump(const Duration(milliseconds: 100));
      // main.dart has started a fresh run; this one's overdue timers can
      // still fire before the host rebuilds.
      container.read(launchCurtainRunProvider.notifier).state++;
      await tester.tap(find.byType(LaunchCurtain));
      await tester.pump();
      expect(lifting(), isFalse,
          reason: 'the fresh curtain covers the page, not this one');
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a return waits for its reloads like a launch',
        (tester) async {
      ready();
      await pumpHost(tester);
      await frames(tester, 5200);
      expect(up(), isFalse);
      container.read(_progress.notifier).state = .8;
      container.read(launchCurtainUpProvider.notifier).state = true;
      container.read(launchCurtainRunProvider.notifier).state++;
      await tester.pump();
      await frames(tester, 4000);
      expect(up(), isTrue, reason: 'the reminder pass is still running');
      expect(lifting(), isFalse);
      ready();
      await frames(tester, 750);
      expect(lifting(), isTrue);
      await frames(tester, 700);
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

  /// The clock and battery the curtain asks for.
  SystemUiOverlayStyle statusIcons(WidgetTester tester) => tester
      .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find
            .descendant(
              of: find.byType(LaunchCurtain),
              matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
            )
            .first,
      )
      .value;

  /// Where Doum's feet stand: under the screen's centre, on his line.
  double feetLine(WidgetTester tester) =>
      tester.getSize(find.byType(MaterialApp)).height / 2 +
      kLaunchFeetBelowCentre;

  group('missing winter', () {
    testWidgets('worried by his hourglass, laughing by the fire when ready',
        (tester) async {
      await pumpCurtain(tester, scene: LaunchScene.winterWait);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 800));
      expect(doum(tester)!.pose, SproutPose.winterHourglass);
      expect(line(tester), 'Missing winter while we\nGrow Daily');
      final screen = tester.getSize(find.byType(MaterialApp));
      final box = tester.getRect(find.byType(Sprout));
      expect(box.bottom, closeTo(feetLine(tester), .5));
      expect(
        box.left + box.width * kLaunchBodyCentre[SproutPose.winterHourglass]!,
        closeTo(screen.width / 2, .5),
        reason: 'centred on his body, not on the hourglass',
      );
      ready();
      await tester.pump();
      await tester.pump();
      expect(doum(tester)!.pose, SproutPose.winterHappyHeart);
      await tester.pump(const Duration(milliseconds: 380));
      await tester.pump(const Duration(milliseconds: 500));
      expect(up(), isFalse);
    });

    testWidgets('the ready swap is a cut: one of him, his face where it was',
        (tester) async {
      await pumpCurtain(tester, scene: LaunchScene.winterWait);
      await untilDoum(tester);
      await tester.pump(const Duration(milliseconds: 1000));
      final screen = tester.getSize(find.byType(MaterialApp));
      ready();
      await tester.pump();
      await tester.pump();
      // The swap frame and the few after it, where a crossfade held the
      // worried pose (moved to the laughing one's place) under the new one.
      for (final gap in const [0, 16, 16, 34]) {
        await tester.pump(Duration(milliseconds: gap));
        expect(picture(SproutPose.winterHourglass), findsNothing);
        expect(shown(tester, doumPicture(SproutPose.winterHappyHeart)), 1);
        final box = tester.getRect(find.byType(Sprout));
        expect(
          box.left + box.width * kLaunchBodyCentre[SproutPose.winterHappyHeart]!,
          closeTo(screen.width / 2, .5),
        );
      }
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('the light clock and battery never outlast the sky',
        (tester) async {
      await pumpCurtain(tester, scene: LaunchScene.winterWait);
      await untilDoum(tester);
      await tester.pump(const Duration(milliseconds: 1000));
      ready();
      await tester.pump();
      await tester.pump();
      expect(statusIcons(tester), kStatusIconsLight);
      // The ready beat; the exit starts as it ends.
      await tester.pump(const Duration(milliseconds: 380));
      var light = 0;
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (!up()) break;
        final sky = shown(
          tester,
          find
              .descendant(
                of: find.byKey(kLaunchBackdropKey),
                matching: find.byType(Stack),
              )
              .first,
        );
        final icons = statusIcons(tester);
        if (icons == kStatusIconsLight) light++;
        expect(
          icons == kStatusIconsLight,
          sky >= .5,
          reason: 'frame $i of the exit: the sky at $sky',
        );
      }
      expect(up(), isFalse);
      // The sky goes with the ground, as the night's navy does: still most
      // of the top half way through the exit, the icons light over it.
      expect(light, greaterThan(12));
    });

    testWidgets('the sky falls dark, and the clock and battery turn light',
        (tester) async {
      await pumpCurtain(tester, scene: LaunchScene.winterWait);
      await tester.pump(const Duration(milliseconds: 300));
      expect(statusIcons(tester), kStatusIconsDark, reason: 'late summer');
      container.read(_progress.notifier).state = .3;
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 300));
      expect(statusIcons(tester), kStatusIconsDark, reason: 'still dusk');
      container.read(_progress.notifier).state = .8;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 300));
      expect(statusIcons(tester), kStatusIconsLight, reason: 'night');
      ready();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(statusIcons(tester), kStatusIconsLight);
      await tester.pump(const Duration(milliseconds: 180));
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        statusIcons(tester),
        kStatusIconsDark,
        reason: 'the app\'s own once the curtain is half gone',
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(up(), isFalse);
    });

    testWidgets('chosen for an October afternoon\'s first open',
        (tester) async {
      // Not a walker: a walker's 16:00 is the walk's first.
      container.read(_walker.notifier).state = false;
      await pumpCurtain(tester, scene: null, now: DateTime(2026, 10, 5, 16));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(doum(tester)!.pose, SproutPose.winterHourglass);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a slow load: the magnifier, and the fire once ready',
        (tester) async {
      await pumpCurtain(tester, scene: LaunchScene.winterWait);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pump();
      expect(doum(tester)!.pose, SproutPose.magnifier);
      await tester.pump(const Duration(milliseconds: 400));
      expect(line(tester), 'Slow or fast we\nGrow Daily');
      ready();
      await tester.pump();
      await tester.pump();
      expect(doum(tester)!.pose, SproutPose.winterHappyHeart);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('a slow load keeps him the same Sprout, and he hops when ready',
        (tester) async {
      await pumpCurtain(tester, scene: LaunchScene.winterWait);
      // Frame by frame to him (a cold decode holds him back up to 600
      // ms), then past both marks a slow load waits for.
      await untilDoum(tester);
      await tester.pump(const Duration(milliseconds: 800));
      final him = tester.state(find.byType(Sprout));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump();
      expect(doum(tester)!.pose, SproutPose.magnifier);
      expect(identical(tester.state(find.byType(Sprout)), him), isTrue);
      expect(picture(SproutPose.winterHourglass), findsNothing);
      // Ready well inside this test's 2.6 s cap, which leaves without it.
      await tester.pump(const Duration(milliseconds: 100));
      ready();
      await tester.pump();
      await tester.pump();
      // The lens leaves the Stack and the breeze joins it in this frame:
      // unkeyed, he was built again and popped in from nothing.
      expect(doum(tester)!.pose, SproutPose.winterHappyHeart);
      expect(identical(tester.state(find.byType(Sprout)), him), isTrue);
      expect(shown(tester, doumPicture(SproutPose.winterHappyHeart)), 1);
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.getRect(doumPicture(SproutPose.winterHappyHeart)).bottom,
        lessThan(feetLine(tester) - 8),
        reason: 'the house hop',
      );
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('Reduce Motion: laughing by the fire under the night from '
        'the start, never worried', (tester) async {
      await pumpCurtain(tester, scene: LaunchScene.winterWait, reduced: true);
      await tester.pump(const Duration(milliseconds: 200));
      expect(doum(tester)!.pose, SproutPose.winterHappyHeart);
      expect(statusIcons(tester), kStatusIconsLight);
      ready();
      await tester.pump();
      await tester.pump();
      expect(doum(tester)!.pose, SproutPose.winterHappyHeart);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 300));
      expect(up(), isFalse);
    });
  });

  group('every step', () {
    testWidgets('runs on his treadmill, then springs off it onto the line',
        (tester) async {
      await pumpCurtain(tester, scene: LaunchScene.walk);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 800));
      expect(doum(tester)!.pose, SproutPose.treadmill);
      expect(
        doum(tester)!.idleBreaths,
        0,
        reason: 'a breath would squash the machine',
      );
      expect(line(tester), 'Every step helps us\nGrow Daily');
      final feet = feetLine(tester);
      expect(tester.getRect(find.byType(Sprout)).bottom, closeTo(feet, .5));
      ready();
      await tester.pump();
      await tester.pump();
      expect(doum(tester)!.pose, SproutPose.winkJump);
      double bottom() => tester.getRect(find.byType(Sprout)).bottom;
      await tester.pump(const Duration(milliseconds: 16));
      expect(bottom(), closeTo(feet - 46.15, 1), reason: 'on the belt');
      await tester.pump(const Duration(milliseconds: 484));
      expect(bottom(), closeTo(feet, 1.5), reason: 'landed on the line');
      await tester.pump(const Duration(milliseconds: 500));
      expect(up(), isFalse);
    });

    testWidgets('the ready swap is a cut: one machine, one Doum',
        (tester) async {
      await pumpCurtain(tester, scene: LaunchScene.walk);
      await untilDoum(tester);
      await tester.pump(const Duration(milliseconds: 1000));
      expect(doumPicture(SproutPose.treadmill), findsNWidgets(3),
          reason: 'the machine still, him by the console as drawn, and him '
              'cut out of it, running');
      ready();
      await tester.pump();
      await tester.pump();
      // The swap frame and the few after it, where a crossfade lifted the
      // whole running picture off the belt over the machine tucking away.
      for (final gap in const [0, 16, 16, 34]) {
        await tester.pump(Duration(milliseconds: gap));
        expect(doumPicture(SproutPose.treadmill), findsNothing);
        expect(
          find.ancestor(
            of: picture(SproutPose.treadmill),
            matching: find.byType(ClipPath),
          ),
          findsOneWidget,
          reason: 'the only treadmill left is the machine alone',
        );
        expect(picture(SproutPose.treadmill), findsOneWidget);
        expect(shown(tester, doumPicture(SproutPose.winkJump)), 1);
      }
      await tester.pump(const Duration(seconds: 1));
    });

    // Every anytime scene seen, the walk last: the anytime list cannot
    // draw the walk on its own, so only the walkers' hour can.
    void walkJustPlayed() => LaunchMemory.debugReset(
          shown: {
            for (final s in kSplashPoolWeights.keys)
              LaunchScene.values.byName(s): DateTime(2026, 12, 6, 21),
          },
          lastScene: LaunchScene.walk,
        );

    testWidgets('a walker\'s afternoon waits to know the habits',
        (tester) async {
      walkJustPlayed();
      // A Monday in December: no winter, no summer.
      await pumpCurtain(tester, scene: null, now: DateTime(2026, 12, 7, 16, 30));
      await tester.pump(const Duration(milliseconds: 200));
      expect(doum(tester), isNull, reason: 'still waiting to know');
      container.read(_walker.notifier).state = true;
      await tester.pump();
      // Frame by frame to him: a cold decode holds him back up to 600 ms.
      await untilDoum(tester);
      expect(doum(tester)!.pose, SproutPose.treadmill);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('no walking habit: the anytime list', (tester) async {
      walkJustPlayed();
      await pumpCurtain(tester, scene: null, now: DateTime(2026, 12, 7, 16, 30));
      container.read(_walker.notifier).state = false;
      await tester.pump();
      await untilDoum(tester);
      // The ring, the turn, the run or the seed: never the walk just played.
      expect(
        doum(tester)!.pose,
        isIn([
          SproutPose.threeQuarterWave,
          SproutPose.back,
          SproutPose.running,
          SproutPose.pointer,
        ]),
      );
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('not known in time: not a walker', (tester) async {
      walkJustPlayed();
      await pumpCurtain(tester, scene: null, now: DateTime(2026, 12, 7, 16, 30));
      await tester.pump(LaunchCurtain.fastingWait);
      await untilDoum(tester);
      expect(doum(tester)!.pose, isNot(SproutPose.treadmill));
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a slow load: the magnifier, then the jump once ready',
        (tester) async {
      await pumpCurtain(tester, scene: LaunchScene.walk);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pump();
      expect(doum(tester)!.pose, SproutPose.magnifier);
      ready();
      await tester.pump();
      await tester.pump();
      expect(doum(tester)!.pose, SproutPose.winkJump);
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        tester.getRect(find.byType(Sprout)).bottom,
        closeTo(feetLine(tester), .5),
        reason: 'no belt to spring off: a hop where he stands',
      );
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('he runs on the belt and sweats, and leaves no footprints',
        (tester) async {
      // Aziz, 2026-10-01: "it should not show footsteps, it should be
      // animation running on the treadmill, and the sweating".
      await pumpCurtain(tester, scene: LaunchScene.walk);
      await untilDoum(tester);
      // His moving half: the picture cut to him alone, under a transform.
      Matrix4 stride() => tester
          .widgetList<Transform>(find.descendant(
            of: find.byType(Sprout),
            matching: find.byType(Transform),
          ))
          .firstWhere((t) =>
              t.child is ClipPath &&
              (t.child! as ClipPath).clipper.runtimeType.toString() ==
                  '_RunnerClipper')
          .transform;
      bool painted(String name) => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .any((p) => p.painter.runtimeType.toString() == name);

      await tester.pump(const Duration(milliseconds: 700));
      final a = stride().getTranslation().y;
      await tester.pump(const Duration(milliseconds: 150));
      final b = stride().getTranslation().y;
      expect((a - b).abs(), greaterThan(.5), reason: 'a step later he dips');
      expect(a, inInclusiveRange(0, 2.8), reason: 'down only: feet on belt');
      expect(b, inInclusiveRange(0, 2.8));
      expect(painted('_SweatPainter'), isTrue);
      expect(painted('_TrailPainter'), isFalse);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a slow load keeps him the same Sprout', (tester) async {
      await pumpCurtain(tester, scene: LaunchScene.walk);
      // Frame by frame to him (a cold decode holds him back up to 600
      // ms), then past both marks a slow load waits for.
      await untilDoum(tester);
      await tester.pump(const Duration(milliseconds: 800));
      final him = tester.state(find.byType(Sprout));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump();
      // The deck's shadow leaves the Stack and the lens joins it in this
      // frame: unkeyed, he was built again and popped in from nothing.
      expect(doum(tester)!.pose, SproutPose.magnifier);
      expect(identical(tester.state(find.byType(Sprout)), him), isTrue);
      expect(picture(SproutPose.treadmill), findsNothing);
      final lens = doumPicture(SproutPose.magnifier);
      expect(shown(tester, lens), 1);
      expect(
        tester.getRect(lens).height,
        greaterThan(
          .8 * Sprout.sizeOf(SproutPose.magnifier, kLaunchDoumHeight).height,
        ),
        reason: 'swapped in, not popping up again',
      );
      // Ready well inside this test's 2.6 s cap, which leaves without it.
      await tester.pump(const Duration(milliseconds: 100));
      ready();
      await tester.pump();
      await tester.pump();
      expect(doum(tester)!.pose, SproutPose.winkJump);
      expect(identical(tester.state(find.byType(Sprout)), him), isTrue);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('Reduce Motion: his wink from the start, no running',
        (tester) async {
      await pumpCurtain(tester, scene: LaunchScene.walk, reduced: true);
      await untilDoum(tester);
      expect(doum(tester)!.pose, SproutPose.winkJump);
      expect(
        tester.getRect(find.byType(Sprout)).bottom,
        closeTo(feetLine(tester), .5),
      );
      ready();
      await tester.pump();
      await tester.pump();
      expect(doum(tester)!.pose, SproutPose.winkJump);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 300));
      expect(up(), isFalse);
    });
  });

  group('before the first frame', () {
    tearDown(LaunchMemory.debugReset);

    test('the winter afternoon\'s poses are decoded', () {
      LaunchMemory.debugReset(lastOpen: DateTime(2026, 10, 5, 9));
      final now = DateTime(2026, 10, 5, 16);
      expect(LaunchCurtain.likelyScenes(now), contains(LaunchScene.winterWait));
      expect(
        LaunchCurtain.likelyPoses(now),
        containsAll([SproutPose.winterHourglass, SproutPose.winterHappyHeart]),
      );
    });

    test('the walking hour\'s, and the one anytime scene this launch draws',
        () {
      // The habits are not known yet: walker or not.
      LaunchMemory.debugReset(lastOpen: DateTime(2026, 12, 7, 9));
      final now = DateTime(2026, 12, 7, 16, 30);
      final scenes = LaunchCurtain.likelyScenes(now);
      final drawn = pickAnytimeScene(
        now: now,
        rules: LaunchSettings.builtIn,
        random: math.Random(LaunchCurtain.launchSeed),
      );
      expect(scenes, containsAll({LaunchScene.walk, drawn}));
      expect(scenes.length, lessThanOrEqualTo(2),
          reason: 'not every anytime scene: the draw is made already');
      expect(
        LaunchCurtain.likelyPoses(now),
        containsAll([SproutPose.treadmill, SproutPose.winkJump]),
      );
    });

    test('neither, outside their hours and not drawn', () {
      LaunchMemory.debugReset(
        lastOpen: DateTime(2026, 12, 7, 9),
        shown: {
          for (final s in kSplashPoolWeights.keys)
            LaunchScene.values.byName(s): DateTime(2026, 12, 7, 9),
        },
        lastScene: LaunchScene.walk,
      );
      final scenes = LaunchCurtain.likelyScenes(DateTime(2026, 12, 7, 13));
      expect(scenes, isNot(contains(LaunchScene.walk)));
      expect(scenes, isNot(contains(LaunchScene.winterWait)));
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
