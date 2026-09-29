import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/first_run_offer_provider.dart';
import '../../core/providers/onboarding_provider.dart';
import '../../core/utils/reduced_motion.dart';
import '../auth/notifiers/auth_notifier.dart';
import '../dashboard/notifiers/dashboard_notifier.dart';
import '../grid/notifiers/weekly_grid_notifier.dart';
import '../habits/notifiers/custom_habits_notifier.dart'
    show habitListProvider, habitsHydratedProvider;
import '../mascot/sprout.dart';
import 'launch_scene.dart';
import 'launch_scenes.dart';

/// The launch screen's cream: LaunchBackground on iOS and
/// flutter_native_splash's `color` in pubspec.yaml. The curtain's first frame
/// has to be exactly the picture the phone was already showing.
const kLaunchGround = Color(0xFFFEFAF0);

/// True while the [LaunchCurtain] covers the app. Seeded true by main.dart
/// on the platforms that show one, false everywhere else (tests, the web),
/// and set false by the curtain the moment it starts to lift.
///
/// Read by what would otherwise happen unseen behind it: Doum's hello on the
/// Grid and a perfect day's celebration (GridScreen passes it to the day
/// card as `onScreen`).
final launchCurtainUpProvider = StateProvider<bool>((ref) => false);

/// How much of the screen under the curtain has what it needs, 0 to 1: the
/// sign-in known, the habits, this week's squares, the day's numbers. For
/// someone signed in those are four steps; screens that load nothing
/// (sign-in, onboarding) are complete at once. The ring and the checklist
/// show this, so what they fill is real.
final launchProgressProvider = Provider<double>((ref) {
  if (!ref.watch(guestModeProvider)) {
    final auth = ref.watch(authStateProvider);
    if (auth.isLoading) return 0;
    if (auth.valueOrNull == null) return 1;
  }
  if (!ref.watch(onboardingSeenProvider) ||
      !ref.watch(firstRunOfferAskedProvider)) {
    return 1;
  }
  var steps = 1;
  if (ref.watch(habitsHydratedProvider)) steps++;
  if (!ref.watch(weeklyGridProvider.select((g) => g.isLoading))) steps++;
  if (!ref.watch(dashboardProvider.select((d) => d.isLoading))) steps++;
  return steps / 4;
});

/// Whether the screen under the curtain can be looked at without anything
/// popping in (see [launchProgressProvider]).
///
/// Not "the app is ready to use": the curtain lifts on [LaunchCurtain]'s cap
/// whatever this says, and the Grid draws the device's own copy of the week
/// in the meantime (WeeklyGridState.preview).
final launchHomeReadyProvider =
    Provider<bool>((ref) => ref.watch(launchProgressProvider) >= 1);

/// Whether a fast is on today's plan: null while this account's habits are
/// not known yet (the sign-in still resolving, the list still loading).
/// Only the morning's mug asks (see pickLaunchScene).
final launchFastingPlannedProvider = Provider<bool?>((ref) {
  if (!ref.watch(guestModeProvider)) {
    final auth = ref.watch(authStateProvider);
    if (auth.isLoading) return null;
    if (auth.valueOrNull == null) return false;
  }
  if (!ref.watch(habitsHydratedProvider)) return null;
  return fastingPlannedOn(ref.watch(habitListProvider), DateTime.now());
});

/// The app's first frame, and the moment between it and the home screen.
///
/// ── Why it exists ──────────────────────────────────────────────────────
///
/// A cold start used to be five pictures in about a second and a half: the
/// phone's own launch screen, a hard cut to the app's theme with a spinner
/// in a card, a day card reading «0 من 9» and 0%, the ring climbing to the
/// real number, then the board's rows arriving. Every one of those was the
/// app waiting on a server round trip in plain sight.
///
/// This covers that wait with Doum. Its first frame is the launch screen
/// itself, plain cream, so the hand from the phone to the app cannot be
/// seen. Then Doum arrives with his line in the scene chosen for this open
/// (see [pickLaunchScene]: his coffee on the morning's first open, asleep at
/// night, a lantern in Ramadan, walking in after days away, his checklist
/// in the evening, a seed on the very first launch, Eid's lights, a full
/// day's squares, Saturday's page, a new version's bulb, the steps goal's
/// finish, a summer noon's sun, otherwise a ring or a turn at random), the
/// home screen builds and loads underneath, and the curtain goes: Doum and
/// his line first, the ground after, onto a screen that is already
/// complete.
///
/// ── How long ───────────────────────────────────────────────────────────
///
/// Never longer than the wait it covers plus Doum's moment: it lifts once
/// [launchHomeReadyProvider] says the home screen is complete AND [minShow]
/// has passed, and at [maxShow] whatever it says, so a slow network is
/// never a longer launch than before. A tap anywhere lifts it at once.
/// Reduce Motion keeps the scene still (see LaunchSceneView) and shortens
/// the hold to what the load needs.
///
/// Once per process: it is built once above the navigator (main.dart) and
/// draws nothing after it has lifted, so resuming the app never shows it.
class LaunchCurtain extends ConsumerStatefulWidget {
  const LaunchCurtain({
    super.key,
    this.minShow = const Duration(milliseconds: 1600),
    this.minShowReduced = const Duration(milliseconds: 350),
    this.maxShow = const Duration(milliseconds: 5000),
    this.scene,
    this.random,
    this.clock = DateTime.now,
  });

  /// The shortest time it stays: long enough for Doum's scene to read (his
  /// line, what fills, his ready moment).
  final Duration minShow;

  /// [minShow] under Reduce Motion, where nothing moves to wait for.
  final Duration minShowReduced;

  /// The longest time it stays, ready or not. Long enough that a slow
  /// network finishes under it (Aziz, 2026-09-29: "it keeps loading then
  /// opens, so it is never slow in the app"; a slow load brings out the
  /// magnifier, see [slowAfter]), short enough that no one is kept out.
  final Duration maxShow;

  /// A fixed scene instead of [pickLaunchScene]'s choice (tests).
  final LaunchScene? scene;

  /// The ordinary scenes' coin (tests).
  final math.Random? random;

  /// The time the scene is chosen for (tests move it).
  final DateTime Function() clock;

  /// How long a morning waits for this account's habits before choosing
  /// between the mug and an ordinary scene. The cream stays on screen
  /// meanwhile, as on the launch screen.
  static const Duration fastingWait = Duration(milliseconds: 700);

  /// How long an ordinary scene waits on a slow load before he takes out
  /// his magnifier (LaunchSceneView.searching).
  static const Duration slowAfter = Duration(milliseconds: 1500);

  /// Readies the curtain. Awaited in main.dart just before runApp, while
  /// the phone's own launch screen (the same cream) is still up: reads what
  /// the scene is chosen from (LaunchMemory), then decodes the pictures of
  /// every scene this open can turn out to be, so Doum's pop never plays
  /// over an empty box and no pose change shows a blank frame. Bounded, and
  /// never throws: a slow decode costs his entrance a moment, never the
  /// launch.
  static Future<void> prepare() async {
    await LaunchMemory.load();
    try {
      await _decodeLikelyPoses()
          .timeout(const Duration(milliseconds: 600), onTimeout: () {});
    } catch (_) {}
  }

  /// Every pose of every scene this open can pick: with or without a fast
  /// on the plan (not known yet), a first launch when no open is recorded,
  /// and both ordinary scenes when it comes down to the coin.
  static Future<void> _decodeLikelyPoses() {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    final dpr = view?.devicePixelRatio ?? 3;
    final scenes = <LaunchScene>{};
    if (kLaunchSceneCycle) {
      scenes.add(LaunchMemory.cycledScene);
    } else {
      final now = DateTime.now();
      for (final fasting in const [false, true]) {
        for (final fresh in const [false, true]) {
          if (fresh && LaunchMemory.lastOpen != null) continue;
          scenes.add(
            pickLaunchScene(
              now: now,
              lastOpen: LaunchMemory.lastOpen,
              fastingPlanned: fasting,
              freshInstall: fresh,
              updated: LaunchMemory.updated,
              lastFullDay: LaunchMemory.lastFullDay,
              lastStepsGoal: LaunchMemory.lastStepsGoal,
            ),
          );
        }
      }
      if (scenes.contains(LaunchScene.dayRing) ||
          scenes.contains(LaunchScene.turnaround)) {
        scenes.addAll(const [LaunchScene.dayRing, LaunchScene.turnaround]);
      }
    }
    final scale = sproutScaleFor(kLaunchDoumHeight);
    final config =
        ImageConfiguration(bundle: rootBundle, devicePixelRatio: dpr);
    return Future.wait([
      for (final pose in {for (final s in scenes) ...launchScenePoses(s)})
        _decode(sproutImage(pose, scale, dpr), config),
    ]);
  }

  static Future<void> _decode(ImageProvider image, ImageConfiguration config) {
    final done = Completer<void>();
    final stream = image.resolve(config);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (_, __) {
        if (!done.isCompleted) done.complete();
        stream.removeListener(listener);
      },
      onError: (_, __) {
        if (!done.isCompleted) done.complete();
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return done.future;
  }

  @override
  ConsumerState<LaunchCurtain> createState() => _LaunchCurtainState();
}

class _LaunchCurtainState extends ConsumerState<LaunchCurtain>
    with TickerProviderStateMixin {
  /// The curtain going: Doum and the words over its first half, the ground
  /// from 30% to the end (its length is set as it starts, see [_leave]).
  late final AnimationController _exit = AnimationController(vsync: this);

  /// The pace the ring and the checklist may fill at: across [minShow], so
  /// a home screen that is ready at once still shows them fill rather than
  /// jump, and one that is slow shows where it really is.
  late final AnimationController _pace = AnimationController(vsync: this);

  final List<Timer> _timers = [];
  AppLifecycleListener? _openWatch;
  bool _initialised = false;
  bool _doumIn = false;
  bool _nightSky = false;
  bool _reduced = false;
  bool _minShown = false;
  bool _beat = false;
  bool _leaving = false;
  bool _gone = false;
  bool _searching = false;
  LaunchScene? _scene;

  @override
  void initState() {
    super.initState();
    ref.listenManual<bool>(launchHomeReadyProvider, (_, __) {
      // Off the frame that changed it: lifting writes a provider, which
      // Riverpod refuses while widgets are building.
      scheduleMicrotask(_maybeLeave);
    });
    _recordOpenWhenSeen();
  }

  /// Counts this as an open only once it is on screen: a notification
  /// action run with the app closed starts this same process in the
  /// background (see LaunchMemory).
  void _recordOpenWhenSeen() {
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive) {
      LaunchMemory.recordOpen(DateTime.now());
      return;
    }
    _openWatch = AppLifecycleListener(
      onResume: () {
        LaunchMemory.recordOpen(DateTime.now());
        _openWatch?.dispose();
        _openWatch = null;
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialised) return;
    _initialised = true;
    _reduced = prefersReducedMotion(context);
    _pace
      ..duration = (_reduced ? widget.minShowReduced : widget.minShow) * .9
      ..forward();
    _after(_reduced ? widget.minShowReduced : widget.minShow, () {
      _minShown = true;
      _maybeLeave();
    });
    _after(widget.maxShow, () => _maybeLeave(force: true));
    _chooseScene();
  }

  void _after(Duration delay, VoidCallback run) =>
      _timers.add(Timer(delay, run));

  /// The scene, then Doum once its poses have decoded. A morning that might
  /// be the mug's asks first whether a fast is on today's plan, and waits
  /// [LaunchCurtain.fastingWait] at most for the answer.
  void _chooseScene() {
    final fixed =
        widget.scene ?? (kLaunchSceneCycle ? LaunchMemory.cycledScene : null);
    if (fixed != null) return _begin(fixed);
    final now = widget.clock();
    // Nothing seen yet on this phone: the very first launch. An account
    // that has been here before but not since this was built is not.
    final seenBefore = ref.read(onboardingSeenProvider);
    LaunchScene pick(bool fasting) => pickLaunchScene(
          now: now,
          lastOpen: LaunchMemory.lastOpen,
          fastingPlanned: fasting,
          freshInstall: LaunchMemory.lastOpen == null && !seenBefore,
          updated: seenBefore && LaunchMemory.updated,
          lastFullDay: LaunchMemory.lastFullDay,
          lastStepsGoal: LaunchMemory.lastStepsGoal,
          random: widget.random,
        );
    final hopeful = pick(false);
    if (hopeful != LaunchScene.morningCoffee) return _begin(hopeful);
    final known = ref.read(launchFastingPlannedProvider);
    if (known != null) return _begin(known ? pick(true) : hopeful);
    ProviderSubscription<bool?>? sub;
    var decided = false;
    void decide(bool fasting) {
      if (decided || !mounted) return;
      decided = true;
      sub?.close();
      _begin(fasting ? pick(true) : hopeful);
    }

    sub = ref.listenManual<bool?>(launchFastingPlannedProvider, (_, v) {
      if (v != null) scheduleMicrotask(() => decide(v));
    });
    // Not known in time: no mug, since a wrong mug is the one mistake here.
    _after(LaunchCurtain.fastingWait, () => decide(true));
  }

  /// Doum starts once every pose his scene draws has decoded, so the pop
  /// never plays over an empty box and no pose change shows a blank frame.
  /// Bounded: a slow decode costs his entrance a moment, never the
  /// curtain its timing.
  void _begin(LaunchScene scene) {
    if (!mounted || _leaving) return;
    _scene = scene;
    final scale = sproutScaleFor(kLaunchDoumHeight);
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3;
    var arrived = false;
    void arrive() {
      if (arrived || !mounted || _leaving) return;
      arrived = true;
      setState(() => _doumIn = true);
      // Still loading well after he arrived: in an ordinary scene he takes
      // out his magnifier.
      if (scene == LaunchScene.dayRing || scene == LaunchScene.turnaround) {
        _after(LaunchCurtain.slowAfter, () {
          if (mounted && !_leaving) setState(() => _searching = true);
        });
      }
      // The status bar turns light once the dark has mostly fallen, not
      // before it, when light text would sit on the cream.
      if (scene == LaunchScene.nightAsleep) {
        _after(Duration(milliseconds: _reduced ? 0 : 450), () {
          if (mounted) setState(() => _nightSky = true);
        });
      }
    }

    Future.wait([
      for (final pose in launchScenePoses(scene))
        precacheImage(sproutImage(pose, scale, dpr), context),
    ]).then((_) => arrive(), onError: (Object _) => arrive());
    // Decoded before the first frame already (prepare); this is the most
    // a cold decode may hold him back.
    _after(const Duration(milliseconds: 600), arrive);
  }

  void _maybeLeave({bool force = false}) {
    if (_leaving || !mounted) return;
    if (!force && !(_minShown && ref.read(launchHomeReadyProvider))) return;
    _leaving = true;
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    ref.read(launchCurtainUpProvider.notifier).state = false;
    // The scene's ready moment first (a hop, the ring closing), unless the
    // cap forced it, the night keeps quiet, or there is nothing to watch.
    final beat = !force &&
        !_reduced &&
        _scene != null &&
        _scene != LaunchScene.nightAsleep;
    setState(() => _beat = true);
    if (beat) {
      _timers.add(Timer(const Duration(milliseconds: 380), _leave));
    } else {
      _leave();
    }
  }

  void _skip() {
    if (_leaving) return;
    _maybeLeave(force: true);
  }

  void _leave() {
    if (!mounted) return;
    _exit
      ..duration = Duration(milliseconds: _reduced ? 250 : 480)
      ..forward().whenComplete(() {
        if (mounted) setState(() => _gone = true);
      });
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _openWatch?.dispose();
    _exit.dispose();
    _pace.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return const SizedBox.shrink();
    final night = _nightSky;
    final loaded = ref.watch(launchProgressProvider);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The clock and battery read on the curtain, not on whatever theme the
      // app underneath asks for: dark on the cream, light under the night.
      value: night ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: IgnorePointer(
        ignoring: _leaving,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _skip,
          child: BlockSemantics(
            child: Semantics(
              label: _scene == null
                  ? 'Grow Daily'
                  : _searching
                      ? kLaunchSlowLine
                      : launchLine(_scene!),
              child: AnimatedBuilder(
                animation: Listenable.merge([_exit, _pace]),
                builder: (context, _) {
                  final t = _exit.value;
                  final away = Curves.easeIn.transform((t / .5).clamp(0, 1));
                  final ground = Curves.easeInOut
                      .transform(((t - .3) / .7).clamp(0, 1));
                  final progress = math.min(loaded, _pace.value);
                  return Opacity(
                    opacity: 1 - ground,
                    child: ColoredBox(
                      color: kLaunchGround,
                      child: LaunchSceneView(
                        scene: _scene ?? LaunchScene.dayRing,
                        started: _doumIn && _scene != null,
                        progress: progress,
                        leaving: _beat,
                        away: away,
                        reduced: _reduced,
                        searching: _searching,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
