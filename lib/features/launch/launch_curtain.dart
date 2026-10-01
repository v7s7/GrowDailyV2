import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/first_run_offer_provider.dart';
import '../../core/providers/onboarding_provider.dart';
import '../../core/theme/status_bar_style.dart';
import '../../core/utils/reduced_motion.dart';
import '../auth/notifiers/auth_notifier.dart';
import '../dashboard/notifiers/dashboard_notifier.dart';
import '../grid/notifiers/weekly_grid_notifier.dart';
import '../habits/notifiers/custom_habits_notifier.dart'
    show habitListProvider, habitsHydratedProvider, habitsStillLoadingProvider;
import '../mascot/doum_language_look.dart' show kDoumFeetCentre;
import '../mascot/sprout.dart';
import 'launch_curtain_up.dart';
import 'launch_doum_handoff.dart';
import 'launch_scene.dart';
import 'launch_scenes.dart';
import 'launch_settings.dart';

export 'launch_curtain_up.dart';

/// The launch screen's cream: LaunchBackground on iOS and
/// flutter_native_splash's `color` in pubspec.yaml. The curtain's first frame
/// has to be exactly the picture the phone was already showing.
const kLaunchGround = Color(0xFFFEFAF0);

/// How much of the screen under the curtain has what it needs, 0 to 1: the
/// sign-in known, the habits, this week's squares, the day's numbers, then
/// the work run on them (this open's reminder pass, and a long return's
/// reloads). For someone signed in those are five steps; screens that load
/// nothing (sign-in, onboarding) are complete at once. The ring and the
/// checklist show this, so what they fill is real.
final launchProgressProvider = Provider<double>((ref) {
  final data = _launchData(ref);
  if (data == null) return 1;
  // The sign-in not known yet: nothing under the curtain is either.
  if (data == 0) return 0;
  final settled = !ref.watch(launchRemindersArmingProvider) &&
      !ref.watch(launchRefreshingProvider);
  return (data + (settled ? 1 : 0)) / 5;
});

/// Whether the home screen's data is in: the first four steps of
/// [launchProgressProvider], without the work run on it. What the launch's
/// reminder pass waits for (main.dart), since that pass reads all four.
final launchDataReadyProvider = Provider<bool>((ref) {
  final data = _launchData(ref);
  return data == null || data == 4;
});

/// Set with `--dart-define=GD_LAUNCH_SLOW_NETWORK_S=7` to see a slow
/// connection on a debug build: the account's data counts as still on its
/// way for that many seconds after launch, so the magnifier and the Wi-Fi
/// mark come out, and the mark lights up when it "arrives". 0, and dropped by
/// the compiler, in a profile or release build, the way GD_LAUNCH_SCENE is.
const int kLaunchSlowNetworkS =
    kDebugMode ? int.fromEnvironment('GD_LAUNCH_SLOW_NETWORK_S') : 0;

/// True while [kLaunchSlowNetworkS] holds the data back.
final launchFakeSlowNetworkProvider = StateProvider<bool>((ref) {
  if (kLaunchSlowNetworkS <= 0) return false;
  final timer = Timer(
    // 0 while the define is unset, which the analyser reads as the default.
    // ignore: avoid_redundant_argument_values
    const Duration(seconds: kLaunchSlowNetworkS),
    () => ref.controller.state = false,
  );
  ref.onDispose(timer.cancel);
  return true;
});

/// The data steps done, out of 4, or null for a screen that loads nothing.
int? _launchData(Ref ref) {
  if (!ref.watch(guestModeProvider)) {
    final auth = ref.watch(authStateProvider);
    if (auth.isLoading) return 0;
    if (auth.valueOrNull == null) return null;
  }
  if (!ref.watch(onboardingSeenProvider) ||
      !ref.watch(firstRunOfferAskedProvider)) {
    return null;
  }
  if (ref.watch(launchFakeSlowNetworkProvider)) return 1;
  var steps = 1;
  // The habit list as the server has it, not only the phone's copy
  // (habitsHydratedProvider): the copy holds no paused or archived habits,
  // so their rows and the paused line could appear after the lift. The
  // copy still paints the board meanwhile.
  if (!ref.watch(habitsStillLoadingProvider)) steps++;
  if (!ref.watch(weeklyGridProvider.select((g) => g.isLoading))) steps++;
  // The day's numbers, and a returning person's streak judged: the
  // Comeback card or a freeze's note belongs on the first look, not a
  // moment after it.
  if (!ref.watch(dashboardProvider.select((d) => d.isLoading)) &&
      !ref.watch(launchStreakJudgingProvider)) {
    steps++;
  }
  return steps;
}

/// True while the launch's streak judgement runs: a gap since the last
/// streak day (DashboardState.pendingStreakGapFrom), or an earlier charge
/// being looked at again. Set by main.dart around the call, cleared when it
/// finishes however it ends, so a judgement that fails costs the launch
/// nothing but its own time (and never more than the curtain's cap).
final launchStreakJudgingProvider = StateProvider<bool>((ref) => false);

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

/// Whether this account has a walking habit (hasWalkingHabit): null while
/// its habits are not known yet, as [launchFastingPlannedProvider]. Only
/// the walking hour asks (see pickLaunchScene).
final launchWalkerProvider = Provider<bool?>((ref) {
  if (!ref.watch(guestModeProvider)) {
    final auth = ref.watch(authStateProvider);
    if (auth.isLoading) return null;
    if (auth.valueOrNull == null) return false;
  }
  if (!ref.watch(habitsHydratedProvider)) return null;
  return hasWalkingHabit(ref.watch(habitListProvider));
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
/// finish, a summer noon's sun, an autumn afternoon's wait for winter, a
/// walker's treadmill, otherwise a ring or a turn at random), the
/// home screen builds and loads underneath, and the curtain goes: Doum and
/// his line first, the ground after, onto a screen that is already
/// complete.
///
/// ── How long ───────────────────────────────────────────────────────────
///
/// It lifts once [launchHomeReadyProvider] has said the home screen is
/// complete for [settle] AND [minShow] has passed, and at [maxShow] whatever
/// it says. Complete includes the reminder pass this open runs, which is
/// what the Grid's first seconds used to lag on. A tap anywhere lifts it at
/// once. Reduce Motion keeps the scene still (see LaunchSceneView) and
/// shortens the hold to what the load needs.
///
/// Built above the navigator (main.dart, through [LaunchCurtainHost]) and
/// drawing nothing once it has lifted. A quick return to the app never
/// shows it; a return after [kLaunchReplayAfter] away, or on a new app day,
/// builds a fresh one with [replay] (main.dart decides), which fades in
/// over the page the phone was already showing instead of cutting to the
/// cream.
class LaunchCurtain extends ConsumerStatefulWidget {
  const LaunchCurtain({
    super.key,
    this.minShow,
    this.minShowReduced = const Duration(milliseconds: 350),
    this.maxShow,
    this.settle = const Duration(milliseconds: 300),
    this.replay = false,
    this.scene,
    this.random,
    this.clock = DateTime.now,
  });

  /// The shortest time it stays: long enough for Doum's scene to read (his
  /// line, what fills, his ready moment). Three seconds since 2026-09-30
  /// (Aziz: "let the splash screen take their time to 3 sec, or the needed
  /// time so that when grid open, its fully ready"); 1.6 s read as the app
  /// opening straight onto the Grid.
  ///
  /// Null follows the admin's splash settings (LaunchSettings), 3 s built in.
  final Duration? minShow;

  /// How long the home screen has to have been ready before the curtain
  /// believes it. Covers the moment between one piece of work ending and the
  /// next it starts: a return's reload lands, and the reminder pass it asks
  /// for starts 200 ms later (main.dart's debounce). Lifting in that gap put
  /// the pass back on the Grid.
  final Duration settle;

  /// A long return's curtain rather than the launch's: it fades in over the
  /// page, since the phone shows its snapshot of that page first, and a cut
  /// from it to the cream flashed.
  final bool replay;

  /// [minShow] under Reduce Motion, where nothing moves to wait for.
  final Duration minShowReduced;

  /// The longest time it stays, ready or not. Long enough that a slow
  /// network finishes under it (Aziz, 2026-09-29: "it keeps loading then
  /// opens, so it is never slow in the app"; a slow load brings out the
  /// magnifier, see [slowAfter]), short enough that no one is kept out.
  /// Eight seconds since the hold grew to 3 s and to the reminder pass.
  ///
  /// Null follows the admin's splash settings (LaunchSettings), 8 s built in.
  final Duration? maxShow;

  /// A fixed scene instead of [pickLaunchScene]'s choice (tests).
  final LaunchScene? scene;

  /// The ordinary scenes' coin (tests).
  final math.Random? random;

  /// The time the scene is chosen for (tests move it).
  final DateTime Function() clock;

  /// How long a morning waits for this account's habits before choosing
  /// between the mug and an ordinary scene, and the walking hour between
  /// the treadmill and an ordinary scene. The cream stays on screen
  /// meanwhile, as on the launch screen.
  static const Duration fastingWait = Duration(milliseconds: 700);

  /// How long an ordinary scene waits on a slow load before he takes out
  /// his magnifier (LaunchSceneView.searching).
  static const Duration slowAfter = Duration(milliseconds: 1500);

  /// The scenes a slow load brings the magnifier out in: every one but the
  /// night's, which keeps him asleep and shows only the Wi-Fi mark (Aziz,
  /// 2026-10-01: "the connection one should appear if the network is
  /// slow"; it was the two ordinary scenes and the afternoon's two). Each
  /// ready moment still plays its own payoff after it.
  static final Set<LaunchScene> searchingScenes = {
    for (final scene in LaunchScene.values)
      if (scene != LaunchScene.nightAsleep) scene,
  };

  /// Readies the curtain. Awaited in main.dart just before runApp, while
  /// the phone's own launch screen (the same cream) is still up: reads what
  /// the scene is chosen from (LaunchMemory), then decodes the pictures of
  /// every scene this open can turn out to be, so Doum's pop never plays
  /// over an empty box and no pose change shows a blank frame. Bounded, and
  /// never throws: a slow decode costs his entrance a moment, never the
  /// launch.
  /// This launch's roll of the anytime list (see [likelyScenes]); a return
  /// that plays the curtain again rolls afresh ([reroll]).
  static int launchSeed = math.Random().nextInt(1 << 31);

  /// A new roll for a return's curtain.
  static void reroll() => launchSeed = math.Random().nextInt(1 << 31);

  static Future<void> prepare() async {
    await LaunchMemory.load();
    try {
      await _decodeLikelyPoses()
          .timeout(const Duration(milliseconds: 600), onTimeout: () {});
    } catch (_) {}
  }

  /// Every scene this open can pick at [now]: with or without a fast on
  /// the plan and a walking habit (neither known yet), and a first launch
  /// when no open is recorded. The anytime list's pick is rolled with
  /// [launchSeed], the same roll the curtain makes, so only the scene it
  /// will draw is decoded. Only the fixed one when a build's switch fixes it
  /// (launchSceneFixed).
  @visibleForTesting
  static Set<LaunchScene> likelyScenes(DateTime now) {
    final fixed = launchSceneFixed();
    if (fixed != null) return {fixed};
    final scenes = <LaunchScene>{};
    for (final fasting in const [false, true]) {
      for (final walker in const [false, true]) {
        for (final fresh in const [false, true]) {
          if (fresh && LaunchMemory.lastOpen != null) continue;
          // With and without the new version: the curtain only believes it
          // once onboarding has been seen, which is not known here.
          for (final updated in {false, LaunchMemory.updated}) {
            scenes.add(
              pickLaunchScene(
                now: now,
                lastOpen: LaunchMemory.lastOpen,
                fastingPlanned: fasting,
                freshInstall: fresh,
                installedAt: LaunchMemory.installedAt,
                updated: updated,
                updateSince: LaunchMemory.updateSince,
                lastFullDay: LaunchMemory.lastFullDay,
                lastStepsGoal: LaunchMemory.lastStepsGoal,
                walker: walker,
                lastShown: LaunchMemory.lastShown,
                lastScene: LaunchMemory.lastScene,
                random: math.Random(launchSeed),
              ),
            );
          }
        }
      }
    }
    return scenes;
  }

  /// Every pose of [likelyScenes].
  @visibleForTesting
  static Set<SproutPose> likelyPoses(DateTime now) =>
      {for (final s in likelyScenes(now)) ...launchScenePoses(s)};

  static Future<void> _decodeLikelyPoses() {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    final dpr = view?.devicePixelRatio ?? 3;
    final scale = sproutScaleFor(kLaunchDoumHeight);
    final config =
        ImageConfiguration(bundle: rootBundle, devicePixelRatio: dpr);
    return Future.wait([
      for (final pose in likelyPoses(DateTime.now()))
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

  /// What the ring and the checklist show: the lesser of the load and the
  /// pace, followed rather than jumped to. A load step landing after the
  /// pace had run out (the week or the day answering at 2 s) turned the
  /// ring a quarter in a single frame, and the summer sun, the update
  /// scene's light and the first sprout with it.
  late final AnimationController _shown = AnimationController(vsync: this);
  double _aim = 0;

  /// The curtain arriving: at once for the launch's, whose first frame is
  /// the launch screen's cream, faded in for a return's (see
  /// [LaunchCurtain.replay]).
  late final AnimationController _enter =
      AnimationController(vsync: this, value: widget.replay ? 0 : 1);

  final List<Timer> _timers = [];
  Timer? _beatTimer;

  /// Runs while the home screen has been ready for less than
  /// [LaunchCurtain.settle]; see [_readyChanged].
  Timer? _settleTimer;
  bool _readySettled = false;

  /// Which run of the curtain this is ([launchCurtainRunProvider]), so one
  /// that a long return has retired never speaks for the fresh one.
  late final int _run;
  AppLifecycleListener? _lifecycle;
  bool _initialised = false;
  bool _started = false;
  bool _doumIn = false;
  bool _nightSky = false;
  bool _reduced = false;
  bool _minShown = false;
  bool _beat = false;
  bool _leaving = false;
  bool _exiting = false;
  bool _gone = false;
  bool _searching = false;

  /// The very first open's scene, which may hand Doum to the sign-in
  /// screen under it (LaunchDoumHandoff), whether it will (decided at the
  /// ready moment: a sign-in screen is there to land on), and the flight
  /// itself, drawn by [_flyingDoum] while the ground fades.
  bool _handoff = false;
  bool _willFly = false;
  bool _flying = false;
  LaunchDoumHandoff? _handoffTo;

  /// Measured as the flight starts, in the curtain's own frame: its size,
  /// the sign-in screen's landing box, and the size he lands at.
  Size _flightSize = Size.zero;
  Rect _flightTarget = Rect.zero;
  double _flightHeight = kLaunchDoumHeight;

  /// A slow load in any scene, the night's included: what the Wi-Fi mark
  /// waits on (see [build]).
  bool _slow = false;
  bool _slowByClock = false;
  bool _slowByArrival = false;
  LaunchScene? _scene;

  Duration get _minShow => _reduced
      ? widget.minShowReduced
      : widget.minShow ?? LaunchSettings.current.minShow;

  @override
  void initState() {
    super.initState();
    _run = ref.read(launchCurtainRunProvider);
    ref.listenManual<bool>(
      launchHomeReadyProvider,
      (_, __) {
        // Off the frame that changed it: lifting writes a provider, which
        // Riverpod refuses while widgets are building.
        scheduleMicrotask(_readyChanged);
      },
      fireImmediately: true,
    );
    ref.listenManual<double>(launchProgressProvider, (_, __) {
      scheduleMicrotask(_follow);
    });
    _pace.addListener(_follow);
    _watchOpens();
  }

  /// Counts an open every time the app is on screen: this launch once it is
  /// seen, and every return to the foreground after it. Only a seen open
  /// counts, since a notification action run with the app closed starts
  /// this same process in the background (see LaunchMemory). Warm returns
  /// count as well: counting cold starts only gave someone whose app stayed
  /// in memory through three days of daily use "Back on the path" at the
  /// next cold start.
  ///
  /// The same listener starts the curtain when this process began in the
  /// background (see [_hidden]), so its clock never runs unseen and it
  /// never plays a half-finished exit on the first look.
  void _watchOpens() {
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive) {
      LaunchMemory.recordOpen(DateTime.now());
    }
    _lifecycle = AppLifecycleListener(
      onResume: () => LaunchMemory.recordOpen(DateTime.now()),
      onStateChange: (state) {
        if (_initialised &&
            !_started &&
            (state == AppLifecycleState.resumed ||
                state == AppLifecycleState.inactive)) {
          _start();
        }
      },
    );
  }

  /// Whether the system reports this process as in the background. Only
  /// that waits: a state not known yet starts at once, as a launch on
  /// screen should.
  bool get _hidden {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialised) return;
    _initialised = true;
    _reduced = prefersReducedMotion(context);
    if (!_hidden) _start();
  }

  void _start() {
    if (_started || !mounted) return;
    _started = true;
    // The clock starts once the first frame has been drawn, not when this
    // is first built: a slow first frame (a cold device, a debug build) ate
    // into Doum's second, and on the simulator on 2026-09-30 it left him
    // half a second on screen. The cream is up meanwhile, the same picture
    // as the launch screen under it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _startClock());
  }

  void _startClock() {
    if (!mounted) return;
    if (widget.replay) {
      _enter.animateTo(
        1,
        duration: _reduced ? Duration.zero : const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    }
    _pace
      ..duration = _minShow * .9
      ..forward();
    _after(_minShow, () {
      _minShown = true;
      _maybeLeave();
    });
    _after(
      widget.maxShow ?? LaunchSettings.current.maxShow,
      () => _maybeLeave(force: true),
    );
    // The earliest a load counts as slow: well past Doum's own second, so a
    // home screen that is ready by then simply lifts (see [_maybeSearch]).
    _after(_minShow + const Duration(milliseconds: 600), () {
      _slowByClock = true;
      _maybeSearch();
    });
    _chooseScene();
  }

  void _after(Duration delay, VoidCallback run) =>
      _timers.add(Timer(delay, run));

  /// The ring and the checklist follow the load (see [_shown]).
  void _follow() {
    if (!mounted || _gone) return;
    final target = math.min(ref.read(launchProgressProvider), _pace.value);
    if ((target - _aim).abs() < .001) return;
    _aim = target;
    _shown.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  /// The scene, then Doum once its poses have decoded. A morning that might
  /// be the mug's asks first whether a fast is on today's plan, and the
  /// walking hour whether this account walks; each waits
  /// [LaunchCurtain.fastingWait] at most for the answer.
  void _chooseScene() {
    final fixed = widget.scene ?? launchSceneFixed();
    if (fixed != null) return _begin(fixed);
    final now = widget.clock();
    // Nothing seen yet on this phone: the very first launch. An account
    // that has been here before but not since this was built is not.
    final seenBefore = ref.read(onboardingSeenProvider);
    final fresh = LaunchMemory.lastOpen == null && !seenBefore;
    if (fresh) LaunchMemory.recordInstall(now);
    // One roll for every pick below, so asking again once the habits are
    // known never draws a different anytime scene.
    final seed = widget.random?.nextInt(1 << 31) ?? LaunchCurtain.launchSeed;
    LaunchScene pick({required bool fasting, required bool walker}) =>
        pickLaunchScene(
          now: now,
          lastOpen: LaunchMemory.lastOpen,
          fastingPlanned: fasting,
          freshInstall: fresh,
          installedAt: LaunchMemory.installedAt,
          updated: seenBefore && LaunchMemory.updated,
          updateSince: LaunchMemory.updateSince,
          lastFullDay: LaunchMemory.lastFullDay,
          lastStepsGoal: LaunchMemory.lastStepsGoal,
          walker: walker,
          lastShown: LaunchMemory.lastShown,
          lastScene: LaunchMemory.lastScene,
          random: math.Random(seed),
        );
    // No fast and a walker: only ever wrong in the two scenes that hang on
    // the habits, and each of those waits to know.
    final hopeful = pick(fasting: false, walker: true);
    switch (hopeful) {
      case LaunchScene.morningCoffee:
        // Not known in time: no mug, since a wrong mug is the one mistake
        // here.
        _whenKnown(
          launchFastingPlannedProvider,
          unknown: true,
          (fasting) => _begin(
            fasting ? pick(fasting: true, walker: false) : hopeful,
          ),
        );
      case LaunchScene.walk:
        // The anytime list drew the walk: it plays for anyone, no need to
        // know.
        final without = pick(fasting: true, walker: false);
        if (without == LaunchScene.walk) return _begin(hopeful);
        // Not known in time: not a walker, and an ordinary scene.
        _whenKnown(
          launchWalkerProvider,
          unknown: false,
          (walker) => _begin(walker ? hopeful : without),
        );
      default:
        _begin(hopeful);
    }
  }

  /// [decide]s with what [provider] knows, waiting for it
  /// [LaunchCurtain.fastingWait] at most, then with [unknown].
  void _whenKnown(
    ProviderListenable<bool?> provider,
    void Function(bool) decide, {
    required bool unknown,
  }) {
    final known = ref.read(provider);
    if (known != null) return decide(known);
    ProviderSubscription<bool?>? sub;
    var decided = false;
    void settle(bool value) {
      if (decided || !mounted) return;
      decided = true;
      sub?.close();
      decide(value);
    }

    sub = ref.listenManual<bool?>(provider, (_, v) {
      if (v != null) scheduleMicrotask(() => settle(v));
    });
    _after(LaunchCurtain.fastingWait, () => settle(unknown));
  }

  /// Doum starts once every pose his scene draws has decoded, so the pop
  /// never plays over an empty box and no pose change shows a blank frame.
  /// Bounded: a slow decode costs his entrance a moment, never the
  /// curtain its timing.
  void _begin(LaunchScene scene) {
    if (!mounted || _leaving) return;
    _scene = scene;
    // The very first open: the sign-in screen under it holds its own Doum
    // back for this one (not on a return's curtain, which plays over a
    // page already seen, and not under Reduce Motion, which flies nothing).
    if (scene == LaunchScene.firstOpen && !widget.replay && !_reduced) {
      _handoff = true;
      final handoff = ref.read(launchDoumHandoffProvider);
      handoff.expect();
      _handoffTo = handoff;
    }
    LaunchMemory.recordShown(scene, widget.clock());
    final scale = sproutScaleFor(kLaunchDoumHeight);
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3;
    var arrived = false;
    void arrive() {
      if (arrived || !mounted || _leaving) return;
      arrived = true;
      setState(() => _doumIn = true);
      // Still loading well after he arrived: he takes out his magnifier
      // (asleep, the Wi-Fi mark alone).
      _after(LaunchCurtain.slowAfter, () {
        _slowByArrival = true;
        _maybeSearch();
      });
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

  /// A slow load, in an ordinary scene: out comes the magnifier. Only once
  /// Doum has had [LaunchCurtain.slowAfter] on screen AND the curtain has
  /// been up 600 ms past [minShow], and only while the home screen is still
  /// not ready. It used to come out 1.5 s after he arrived whatever the
  /// load said, so a launch ready at 1.6 s swapped to the magnifier and
  /// back in a tenth of a second, on most daytime opens.
  void _maybeSearch() {
    if (!mounted || _leaving || _slow) return;
    if (!_slowByClock || !_slowByArrival) return;
    if (ref.read(launchHomeReadyProvider)) return;
    setState(() {
      _slow = true;
      _searching = LaunchCurtain.searchingScenes.contains(_scene);
    });
  }

  /// Follows [launchHomeReadyProvider]: ready for [LaunchCurtain.settle]
  /// without a break is ready enough to lift on, and any break starts the
  /// wait again. A return's reload landing reads as ready until the
  /// reminder pass it asks for starts, 200 ms later; lifting on that moment
  /// ran the pass on the Grid, which is what the hold is for.
  void _readyChanged() {
    if (!mounted || _leaving) return;
    if (!ref.read(launchHomeReadyProvider)) {
      _settleTimer?.cancel();
      _settleTimer = null;
      _readySettled = false;
      return;
    }
    if (_readySettled || (_settleTimer?.isActive ?? false)) return;
    if (widget.settle == Duration.zero) {
      _readySettled = true;
      return _maybeLeave();
    }
    _settleTimer = Timer(widget.settle, () {
      if (!mounted) return;
      _readySettled = ref.read(launchHomeReadyProvider);
      _maybeLeave();
    });
  }

  void _maybeLeave({bool force = false}) {
    if (_leaving || !mounted) return;
    if (!force && !(_minShown && _readySettled)) return;
    _leaving = true;
    _settleTimer?.cancel();
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    // The scene's ready moment (the ring closing, his ready pose) only when
    // the home screen really is ready: the cap and a tap leave without
    // claiming it. The hop and the pause for it, only where there is
    // something to watch: not at night, not under Reduce Motion.
    // A sign-in screen under the first open's scene: his ready moment is
    // the wave he will fly in. Not for the cap or a tap, which leave
    // without the ready moment.
    _willFly = !force && _handoff && (_handoffTo?.canLand ?? false);
    if (!force) setState(() => _beat = true);
    final beat = !force &&
        !_reduced &&
        _scene != null &&
        _scene != LaunchScene.nightAsleep;
    if (beat) {
      _beatTimer = Timer(const Duration(milliseconds: 380), _leave);
    } else {
      _leave();
    }
  }

  /// A tap lifts it now. During the ready moment it cuts the moment short;
  /// it never reaches the page underneath while the curtain can be seen
  /// (see the IgnorePointer in [build]).
  void _skip() {
    if (!_leaving) return _maybeLeave(force: true);
    if (_beatTimer?.isActive ?? false) {
      _beatTimer!.cancel();
      _leave();
    }
  }

  void _leave() {
    if (!mounted || _exiting) return;
    _exiting = true;
    // From here the page underneath starts to show, so this is when the
    // Grid's own moments (Doum's hello, a full day's celebration) may begin.
    // Not from a curtain a long return has already replaced: its overdue
    // timers can fire in the frame before it is gone, while the fresh one
    // covers the page.
    final handoff = _handoffTo;
    if (handoff != null) {
      if (_willFly && _measureFlight(handoff)) {
        _flying = true;
        handoff.fly();
      } else {
        handoff.cancel();
      }
    }
    if (ref.read(launchCurtainRunProvider) == _run) {
      ref.read(launchCurtainUpProvider.notifier).state = false;
    }
    _exit
      ..duration = Duration(milliseconds: _reduced ? 250 : 480)
      ..forward().whenComplete(() {
        if (!mounted) return;
        // He is on the sign-in screen's spot: its Doum takes over in this
        // frame, the one the curtain stops drawing.
        if (_flying) _handoffTo?.land();
        setState(() => _gone = true);
      });
  }

  /// Where the flight goes, measured once as it starts (outside any
  /// layout, where reading another box's size is not allowed). False when
  /// there is nothing laid out to land on.
  bool _measureFlight(LaunchDoumHandoff handoff) {
    final stand = handoff.stand?.currentContext?.findRenderObject();
    final me = context.findRenderObject();
    if (stand is! RenderBox ||
        !stand.attached ||
        !stand.hasSize ||
        me is! RenderBox ||
        !me.hasSize) {
      return false;
    }
    _flightSize = me.size;
    _flightTarget =
        me.globalToLocal(stand.localToGlobal(Offset.zero)) & stand.size;
    _flightHeight = handoff.height;
    return true;
  }

  /// Doum on his way from the curtain's middle to the sign-in screen's
  /// head, at [t] of the exit: from where the scene drew him (his body on
  /// the screen's middle, his feet [kLaunchFeetBelowCentre] under it) to
  /// where that screen's Doum stands (his feet's middle on its stand's,
  /// on its floor, at its size), along a small arc. Drawn over the fading
  /// ground, so he never fades.
  Widget _flyingDoum(double t) {
    const pose = SproutPose.frontWave;
    final box = Sprout.sizeOf(pose, kLaunchDoumHeight);
    final end = _flightHeight / kLaunchDoumHeight;
    final fromLeft =
        _flightSize.width / 2 - (kLaunchBodyCentre[pose] ?? .5) * box.width;
    final fromFeet = _flightSize.height / 2 + kLaunchFeetBelowCentre;
    final toLeft = _flightTarget.center.dx -
        (kDoumFeetCentre[pose] ?? .5) * box.width * end;
    final toFeet = _flightTarget.bottom;
    final e = Curves.easeInOutCubic.transform(t);
    final scale = lerpDouble(1, end, e)!;
    final feet =
        lerpDouble(fromFeet, toFeet, e)! - math.sin(math.pi * e) * 28;
    return Positioned(
      key: kLaunchFlyingDoumKey,
      left: lerpDouble(fromLeft, toLeft, e),
      top: feet - box.height * scale,
      width: box.width,
      height: box.height,
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.topLeft,
        child: const Sprout(
          pose: pose,
          height: kLaunchDoumHeight,
          entrance: SproutEntrance.none,
          idleBreaths: 0,
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _beatTimer?.cancel();
    _settleTimer?.cancel();
    _lifecycle?.dispose();
    // Gone before he could land (a return's fresh curtain replaced this
    // one): the sign-in screen shows its own Doum.
    _handoffTo?.cancel();
    _pace.removeListener(_follow);
    _enter.dispose();
    _exit.dispose();
    _pace.dispose();
    _shown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return const SizedBox.shrink();
    final appIcons = statusIconsOver(Theme.of(context).brightness);
    // The Wi-Fi mark: a slow load still waiting on the account's data from
    // the server, not on the work run on it here (the reminder pass).
    final waitingOnNetwork = _slow && !ref.watch(launchDataReadyProvider);
    return BlockSemantics(
      child: Semantics(
        label: _scene == null
            ? 'Grow Daily'
            : _searching
                ? LaunchSettings.current.slowLine
                : LaunchSettings.current.line(_scene!),
        child: AnimatedBuilder(
          animation: Listenable.merge([_enter, _exit, _shown]),
          builder: (context, _) {
            final t = _exit.value;
            final away = Curves.easeIn.transform((t / .5).clamp(0, 1));
            final ground =
                Curves.easeInOut.transform(((t - .3) / .7).clamp(0, 1));
            final arrived = _enter.value;
            // Missing winter's sky falls dark with the load itself, so its
            // clock turns light at the load the sky's top goes dark at.
            final darkTop = _nightSky ||
                (_doumIn &&
                    _scene != null &&
                    launchTopIsDark(
                      _scene!,
                      loaded: _beat ? 1 : _shown.value,
                      reduced: _reduced,
                    ));
            return AnnotatedRegion<SystemUiOverlayStyle>(
              // The clock and battery read on what is showing: dark on the
              // cream, light under the night (and winter's evening sky), and
              // the app's own before a return's curtain is half in and once
              // any curtain is half gone, so nothing snaps. Status bar only:
              // the navigation bar is left alone.
              value: (_exiting && ground > .5) || arrived < .5
                  ? appIcons
                  : darkTop
                      ? kStatusIconsLight
                      : kStatusIconsDark,
              child: IgnorePointer(
                // Taps stay with the curtain while it can still be seen.
                // Let through from the ready moment on, a tap on Doum's hop
                // or the second tap of a double-tap skip reached the hidden
                // Grid and could mark a habit done unseen.
                ignoring: t > .6,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _skip,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Opacity(
                          opacity: arrived * (1 - ground),
                          child: ColoredBox(
                            color: kLaunchGround,
                            child: LaunchSceneView(
                              scene: _scene ?? LaunchScene.dayRing,
                              started: _doumIn && _scene != null,
                              progress: _shown.value,
                              leaving: _beat,
                              away: away,
                              reduced: _reduced,
                              searching: _searching,
                              waitingOnNetwork: waitingOnNetwork,
                              handoff: _willFly,
                              holdStill: _handoff,
                              doumFlying: _flying,
                            ),
                          ),
                        ),
                      ),
                      // On his way to the sign-in screen, over the fading
                      // ground (see _flyingDoum).
                      if (_flying) _flyingDoum(t),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The curtain main.dart builds above the navigator: the launch's, then a
/// fresh one each time a long return plays it again
/// ([launchCurtainRunProvider]). Keyed by the run, so a replay starts from
/// its first frame with none of the last one's state.
class LaunchCurtainHost extends ConsumerWidget {
  const LaunchCurtainHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = ref.watch(launchCurtainRunProvider);
    return LaunchCurtain(key: ValueKey(run), replay: run > 0);
  }
}
