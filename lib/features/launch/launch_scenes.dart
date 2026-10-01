import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../mascot/sprout.dart';
import 'launch_scene.dart';
import 'launch_settings.dart';

part 'launch_scenes_afternoon.dart';
part 'launch_scenes_more.dart';

/// Doum's size on the curtain (the reference pose's height) and where his
/// feet stand: this far under the screen's centre, just over his line.
const double kLaunchDoumHeight = 150;
const double kLaunchFeetBelowCentre = 40;

/// Where his line starts: this far under the screen's centre, two rows, the
/// scene's words and then "Grow Daily" (see [launchLine]).
const double kLaunchLineBelowCentre = 73;

/// Doum's line on the curtain, for tests.
const kLaunchLineKey = ValueKey('launch-line');

/// Doum's shadow on the curtain, for tests.
const kLaunchShadowKey = ValueKey('launch-shadow');

/// Doum on the curtain. Keyed so that he keeps his Sprout while scenery
/// comes and goes round him in the same Stack (a slow load's lens, the
/// deck's shadow, the breeze): unkeyed, a list changing length handed his
/// element to the next Positioned, and he popped in again from nothing.
const kLaunchDoumKey = ValueKey('launch-doum');

/// Doum on his way to the sign-in screen (the first open's hand-off), for
/// tests.
const kLaunchFlyingDoumKey = ValueKey('launch-flying-doum');

/// Missing winter's sky and dunes, for tests.
const kLaunchBackdropKey = ValueKey('launch-backdrop');

/// The Wi-Fi mark a slow connection shows over Doum, for tests.
const kLaunchWifiKey = ValueKey('launch-wifi');

/// The line's ink, and the colours the scenes paint with.
const kLaunchInk = Color(0xFF23352A);
const kLaunchNight = Color(0xFF172131);
const _green = Color(0xFF4A8A57);
const _nightGreen = Color(0xFFA9D3B0);
const _cream = Color(0xFFEFE6D2);
const _dayShadow = Color(0x1A28283C);

/// Where Doum's body is across each pose's picture. The sheets do not centre
/// the body (the checklist's clipboard pushes it to 40%), so the curtain
/// centres the BODY on the screen, not the picture. Measured from the green
/// of the body in each file (2026-09-29).
const Map<SproutPose, double> kLaunchBodyCentre = {
  SproutPose.frontWave: .490,
  SproutPose.threeQuarterWave: .447,
  SproutPose.mug: .532,
  SproutPose.sleeping: .569,
  SproutPose.walkBackpack: .521,
  SproutPose.checklist: .398,
  SproutPose.thumbsUp: .434,
  SproutPose.back: .499,
  SproutPose.backThreeQuarter: .500,
  SproutPose.sideRight: .480,
  SproutPose.pointer: .437,
  SproutPose.happySparkles: .495,
  SproutPose.confetti: .486,
  SproutPose.chart: .407,
  SproutPose.determined: .486,
  SproutPose.idea: .331,
  SproutPose.magnifier: .529,
  SproutPose.running: .538,
  SproutPose.cheer: .513,
  SproutPose.sunglasses: .441,
  // Measured on the boards (2026-09-30): the two winter poses so that his
  // eyes sit on the same x in both, and his face stays put across the swap;
  // the treadmill and the wink jump by the green of the body.
  SproutPose.winterHourglass: .44,
  SproutPose.winterHappyHeart: .50,
  SproutPose.treadmill: .459,
  SproutPose.winkJump: .458,
};

/// Every pose [scene] draws, decoded before it starts (LaunchCurtain), so
/// no pose change ever shows a blank frame: its own, and the magnifier a
/// slow load brings out in every scene but the night's
/// (LaunchCurtain.searchingScenes).
List<SproutPose> launchScenePoses(LaunchScene scene) => [
      ..._ownPoses(scene),
      if (scene != LaunchScene.nightAsleep &&
          !_ownPoses(scene).contains(SproutPose.magnifier))
        SproutPose.magnifier,
    ];

List<SproutPose> _ownPoses(LaunchScene scene) => switch (scene) {
      LaunchScene.morningCoffee => const [SproutPose.mug],
      LaunchScene.dayRing => const [
          SproutPose.threeQuarterWave,
          SproutPose.frontWave,
          SproutPose.magnifier,
        ],
      LaunchScene.ramadanLantern =>
        const [SproutPose.threeQuarterWave, SproutPose.frontWave],
      LaunchScene.turnaround => const [
          SproutPose.back,
          SproutPose.backThreeQuarter,
          SproutPose.sideRight,
          SproutPose.threeQuarterWave,
          SproutPose.frontWave,
          SproutPose.magnifier,
        ],
      LaunchScene.eveningChecklist =>
        const [SproutPose.checklist, SproutPose.thumbsUp],
      LaunchScene.nightAsleep => const [SproutPose.sleeping],
      LaunchScene.welcomeBack =>
        const [SproutPose.walkBackpack, SproutPose.frontWave],
      // The wave too: on a first open with the sign-in screen under him, he
      // waves instead of his sparkles and flies there (LaunchDoumHandoff).
      LaunchScene.firstOpen => const [
          SproutPose.pointer,
          SproutPose.happySparkles,
          SproutPose.frontWave,
        ],
      LaunchScene.eid =>
        const [SproutPose.threeQuarterWave, SproutPose.confetti],
      LaunchScene.fullDay =>
        const [SproutPose.frontWave, SproutPose.happySparkles],
      LaunchScene.saturday => const [SproutPose.chart, SproutPose.determined],
      LaunchScene.update => const [SproutPose.idea],
      LaunchScene.stepsGoal => const [SproutPose.running, SproutPose.cheer],
      LaunchScene.summerNoon =>
        const [SproutPose.threeQuarterWave, SproutPose.sunglasses],
      LaunchScene.winterWait => const [
          SproutPose.winterHourglass,
          SproutPose.winterHappyHeart,
          SproutPose.magnifier,
        ],
      LaunchScene.walk => const [
          SproutPose.treadmill,
          SproutPose.winkJump,
          SproutPose.magnifier,
        ],
    };

/// Whether the top of the screen is dark in [scene] with [loaded] of the
/// home screen in (1 from the ready moment on), so the curtain asks for the
/// light clock and battery. Missing winter's sky falls from late summer to
/// night with the load ([reduced] shows its night from the start); the
/// night scene's own dark is timed by the curtain.
bool launchTopIsDark(
  LaunchScene scene, {
  required double loaded,
  required bool reduced,
}) =>
    scene == LaunchScene.winterWait &&
    (reduced || loaded >= kWinterLightIconsFrom);

/// One launch scene, drawn over the curtain's cream: nothing but the cream
/// until [started], then Doum, what goes round him and his line.
///
/// The curtain owns the timing; this only draws. [progress] is how much of
/// the home screen has loaded (already paced, see LaunchCurtain), which the
/// ring and the checklist show honestly. [leaving] is the home screen being
/// ready: each scene plays its moment for it (a hop, the ring closing, the
/// lantern flaring), except the night, which stays quiet. [away] fades Doum,
/// his line and the scenery out ahead of the ground (the curtain's exit);
/// missing winter's sky stays for the ground, as the night's navy does.
/// [searching] is a slow load: he takes out his magnifier and his line says
/// so, until the app is ready. [waitingOnNetwork] is a slow load still
/// waiting on the account's data from the server: the Wi-Fi mark over him
/// searches for the signal, and lights up whole and goes once the data is
/// in (Aziz, 2026-10-01: "the connection one should appear if the network
/// is slow and the wifi mark should appear"). The night keeps him asleep
/// and shows only the mark.
///
/// Nothing loops for ever: every loop here stops with the curtain. Reduce
/// Motion ([reduced]) keeps the pictures and drops the movement: no steam,
/// no swing, no walk, no rising z's, and Doum's own moves (see Sprout).
///
/// [handoff] is the very first open's scene about to hand Doum to the
/// sign-in screen under it (LaunchDoumHandoff): his ready moment is his
/// wave, without the hop, so he is standing still when he flies.
/// [doumFlying] is that flight: the curtain draws him on his way, so the
/// scene leaves him and his shadow out.
class LaunchSceneView extends StatefulWidget {
  const LaunchSceneView({
    super.key,
    required this.scene,
    required this.started,
    required this.progress,
    required this.leaving,
    required this.away,
    required this.reduced,
    this.searching = false,
    this.waitingOnNetwork = false,
    this.handoff = false,
    this.holdStill = false,
    this.doumFlying = false,
  });

  final LaunchScene scene;
  final bool started;
  final double progress;
  final bool leaving;
  final double away;
  final bool reduced;
  final bool searching;
  final bool waitingOnNetwork;
  final bool handoff;
  final bool doumFlying;

  /// No idle breath for Doum: the first open's scene that may hand him to
  /// the sign-in screen keeps him still, so the flight starts from exactly
  /// the picture the sign-in screen's Doum lands as.
  final bool holdStill;

  @override
  State<LaunchSceneView> createState() => _LaunchSceneViewState();
}

class _LaunchSceneViewState extends State<LaunchSceneView>
    with TickerProviderStateMixin {
  /// Seconds since the scene started, for the loops (steam, z's, stars, the
  /// lantern's swing, the dial). Bounded: the curtain is gone long before.
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 60),
  );

  /// The scene's own arrival (the night falling, the sun rising, the walk).
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  /// The ready moment's scenery (the ring's halo, the lantern's flare).
  late final AnimationController _ready = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  final SproutController _moves = SproutController();
  late SproutPose _pose = _firstPose;
  final List<Timer> _turns = [];

  SproutPose get _firstPose => switch (widget.scene) {
        LaunchScene.morningCoffee => SproutPose.mug,
        LaunchScene.dayRing ||
        LaunchScene.ramadanLantern =>
          SproutPose.threeQuarterWave,
        LaunchScene.turnaround => SproutPose.back,
        LaunchScene.eveningChecklist => SproutPose.checklist,
        LaunchScene.nightAsleep => SproutPose.sleeping,
        LaunchScene.welcomeBack => SproutPose.walkBackpack,
        LaunchScene.firstOpen => SproutPose.pointer,
        LaunchScene.eid || LaunchScene.summerNoon => SproutPose.threeQuarterWave,
        LaunchScene.fullDay => SproutPose.frontWave,
        LaunchScene.saturday => SproutPose.chart,
        LaunchScene.update => SproutPose.idea,
        LaunchScene.stepsGoal => SproutPose.running,
        // Reduce Motion shows the afternoon's two as their boards do: the
        // end, laughing by the fire under the cool night, his wink off the
        // treadmill, never the worried wait or the machine.
        LaunchScene.winterWait => widget.reduced
            ? SproutPose.winterHappyHeart
            : SproutPose.winterHourglass,
        LaunchScene.walk =>
          widget.reduced ? SproutPose.winkJump : SproutPose.treadmill,
      };

  /// The pose he turns to when the home screen is ready.
  SproutPose? get _readyPose => switch (widget.scene) {
        LaunchScene.dayRing ||
        LaunchScene.ramadanLantern ||
        LaunchScene.turnaround ||
        LaunchScene.welcomeBack =>
          SproutPose.frontWave,
        LaunchScene.eveningChecklist => SproutPose.thumbsUp,
        LaunchScene.firstOpen || LaunchScene.fullDay => SproutPose.happySparkles,
        LaunchScene.eid => SproutPose.confetti,
        LaunchScene.saturday => SproutPose.determined,
        LaunchScene.stepsGoal => SproutPose.cheer,
        LaunchScene.summerNoon => SproutPose.sunglasses,
        LaunchScene.winterWait => SproutPose.winterHappyHeart,
        LaunchScene.walk => SproutPose.winkJump,
        LaunchScene.morningCoffee ||
        LaunchScene.nightAsleep ||
        LaunchScene.update =>
          null,
      };

  @override
  void initState() {
    super.initState();
    if (widget.started) _start();
  }

  @override
  void didUpdateWidget(covariant LaunchSceneView old) {
    super.didUpdateWidget(old);
    if (!old.started && widget.started) _start();
    if (!old.searching && widget.searching && !widget.leaving) _search();
    if (!old.waitingOnNetwork && widget.waitingOnNetwork) {
      _wifiOnAt = _t;
      _wifiFoundAt = null;
    }
    if (old.waitingOnNetwork && !widget.waitingOnNetwork && _wifiOnAt != null) {
      _wifiFoundAt = _t;
    }
    if (!old.leaving && widget.leaving) _onReady();
    if (widget.scene == LaunchScene.winterWait) _markStars();
  }

  /// When the home screen was ready (seconds on [_clock]), and the pose he
  /// was in then: the afternoon's payoffs run on the time since, past
  /// [_ready]'s 600 ms, and the walk only springs off a treadmill.
  double? _readyAt;
  SproutPose? _readyFrom;

  /// When each of missing winter's stars came out (seconds on [_clock]),
  /// by star: one at each step of the load, so a stalled load shows as
  /// stars that wait.
  final Map<int, double> _starAt = {};

  /// When the magnifier came out (seconds on [_clock]), for its glint.
  double? _searchedAt;

  /// When the Wi-Fi mark came out, and when the data came in (seconds on
  /// [_clock]): it searches between the two, then lights whole and goes.
  double? _wifiOnAt;
  double? _wifiFoundAt;

  /// A slow load: the turn stops where it is and he looks.
  void _search() {
    _stopTurning();
    _searchedAt = _t;
    setState(() => _pose = SproutPose.magnifier);
  }

  /// When his sunglasses went on (seconds on [_clock]), for their glint.
  double? _shadesAt;

  void _start() {
    if (widget.reduced) {
      _enter.value = 1;
    } else {
      _clock.forward();
      _enter.forward();
    }
    if (widget.scene == LaunchScene.turnaround) _turnRound();
    if (widget.scene == LaunchScene.summerNoon) {
      // He squints into the sun a moment, then puts his sunglasses on.
      _turns.add(
        Timer(Duration(milliseconds: widget.reduced ? 0 : 600), () {
          if (!mounted || _pose == SproutPose.sunglasses) return;
          _shadesAt = _t;
          setState(() => _pose = SproutPose.sunglasses);
        }),
      );
    }
    if (widget.searching) _search();
    if (widget.waitingOnNetwork) _wifiOnAt = 0;
    if (widget.leaving) _onReady();
    if (widget.scene == LaunchScene.winterWait) _markStars();
  }

  /// Back, three-quarter back, side, three-quarter, front: one turn, a pose
  /// every 220 ms once the pop has landed.
  void _turnRound() {
    const steps = [
      SproutPose.backThreeQuarter,
      SproutPose.sideRight,
      SproutPose.threeQuarterWave,
      SproutPose.frontWave,
    ];
    for (var i = 0; i < steps.length; i++) {
      _turns.add(
        Timer(Duration(milliseconds: 450 + 220 * i), () {
          if (mounted && !widget.leaving) setState(() => _pose = steps[i]);
        }),
      );
    }
  }

  void _onReady() {
    _stopTurning(); // a turn still running stops where it is
    _readyAt = _t;
    _readyFrom = _pose;
    // Handing him to the sign-in screen: the wave he lands in, no hop.
    final handoff = widget.handoff && widget.scene == LaunchScene.firstOpen;
    // Found it: the ordinary scenes wave; the afternoon's two go on to
    // their own payoff.
    final to = handoff
        ? SproutPose.frontWave
        : _pose == SproutPose.magnifier
            ? (_readyPose ?? SproutPose.frontWave)
            : _readyPose;
    if (to == SproutPose.sunglasses && _shadesAt == null) _shadesAt = _t;
    if (to != null) setState(() => _pose = to);
    if (widget.reduced) {
      _ready.value = 1;
      return;
    }
    _ready.forward();
    if (widget.scene != LaunchScene.nightAsleep && !handoff) _moves.hop();
  }

  void _stopTurning() {
    for (final t in _turns) {
      t.cancel();
    }
    _turns.clear();
  }

  @override
  void dispose() {
    _stopTurning();
    _clock.dispose();
    _enter.dispose();
    _ready.dispose();
    _moves.dispose();
    super.dispose();
  }

  double get _t => _clock.value * 60;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final c = Offset(size.width / 2, size.height / 2);
        return AnimatedBuilder(
          animation: Listenable.merge([_clock, _enter, _ready]),
          builder: (context, _) => _stage(context, size, c),
        );
      },
    );
  }

  Widget _stage(BuildContext context, Size size, Offset c) {
    final scene = widget.scene;
    final started = widget.started;
    final enter = Curves.easeOutCubic.transform(_enter.value);
    final ready = Curves.easeOut.transform(_ready.value);
    final night = scene == LaunchScene.nightAsleep && started
        ? Curves.easeInOut.transform(((_enter.value - .12) / .7).clamp(0, 1))
        : 0.0;
    final keep = 1 - widget.away;
    final rtl = Directionality.of(context) == TextDirection.rtl;

    // Full-bleed scenery that goes with the ground, as the night's navy
    // does, not with Doum: missing winter's sky and dunes. Faded with him,
    // the sky was gone while the cream was still up (a flash of cream
    // between the night and the Grid) and the light clock and battery,
    // handed back with the ground, sat on the cream; shrunk with him, it
    // opened a cream frame round the navy.
    final backdrop = <Widget>[];
    final behind = <Widget>[];
    final around = <Widget>[];
    if (started) {
      switch (scene) {
        case LaunchScene.morningCoffee:
          behind.add(_sun(c, enter));
          around.add(_steam(c, started: _enter.value > .35));
        case LaunchScene.dayRing:
          behind.add(_ring(c, enter, ready));
        case LaunchScene.turnaround:
          behind.add(_dial(c, enter, ready));
        case LaunchScene.eveningChecklist:
          behind.add(_dusk(size, enter));
          around.add(_squares(c, enter));
        case LaunchScene.nightAsleep:
          behind.add(_sky(size, c, enter));
          around.add(_zs(c, enter));
        case LaunchScene.ramadanLantern:
          behind.add(_moon(c, enter));
          behind.add(_lantern(c, enter, ready));
        case LaunchScene.welcomeBack:
          behind.add(_footprints(c, rtl));
        case LaunchScene.firstOpen:
          _firstOpenScene(size, c, enter, ready, behind, around);
        case LaunchScene.eid:
          _eidScene(size, c, enter, ready, behind, around);
        case LaunchScene.fullDay:
          _fullDayScene(c, enter, ready, behind, around);
        case LaunchScene.saturday:
          _saturdayScene(c, enter, ready, behind, around);
        case LaunchScene.update:
          _updateScene(size, c, enter, ready, around);
        case LaunchScene.stepsGoal:
          _stepsScene(size, c, rtl, enter, ready, behind, around);
        case LaunchScene.summerNoon:
          _summerScene(size, c, enter, ready, behind, around);
        case LaunchScene.winterWait:
          _winterScene(size, c, enter, backdrop, behind);
        case LaunchScene.walk:
          _walkScene(size, c, rtl, behind);
      }
      if (_pose == SproutPose.magnifier) around.add(_lens(c));
      if (_wifiOnAt != null) around.add(_wifi(c, night));
    }

    return Stack(
      children: [
        // The night falling: over the curtain's cream, under everything.
        if (night > 0)
          Positioned.fill(
            child: ColoredBox(color: kLaunchNight.withValues(alpha: night)),
          ),
        if (backdrop.isNotEmpty)
          Positioned.fill(
            key: kLaunchBackdropKey,
            child: Stack(children: backdrop),
          ),
        Positioned.fill(
          child: Opacity(
            opacity: keep,
            child: Transform.scale(
              scale: widget.reduced ? 1 : 1 - .06 * widget.away,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ...behind,
                  if (started && !widget.doumFlying)
                    _shadow(c, rtl, night, enter),
                  if (started && !widget.doumFlying) _doum(c, rtl, enter),
                  ...around,
                  if (started) _line(c, night),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── His line ──────────────────────────────────────────────────────────

  /// The scene's one sentence under him, rising in just after he lands:
  /// its own words, then "Grow Daily" on a row of its own in green. Cream
  /// and a lighter green once the night has fallen. On a slow load it gives
  /// way to [kLaunchSlowLine].
  Widget _line(Offset c, double night) {
    final show = widget.reduced
        ? 1.0
        : Curves.easeOut.transform(((_t - .12) / .3).clamp(0.0, 1.0));
    // Once the magnifier has come out its line stays, through his "found
    // it" wave and the exit: the words change at most once.
    // The admin's splash page may rewrite either line; one without "Grow
    // Daily" is drawn whole, with no green row.
    final settings = LaunchSettings.current;
    final text = _searchedAt != null
        ? settings.slowLine
        : settings.line(widget.scene);
    final split = text.indexOf('Grow Daily');
    final lead = split < 0 ? text : text.substring(0, split).trimRight();
    final rest = split < 0 ? '' : text.substring(split + 'Grow Daily'.length);
    final base = GoogleFonts.getFont(
      'IBM Plex Sans Arabic',
      fontWeight: FontWeight.w700,
      fontSize: 26,
      height: 34 / 26,
      letterSpacing: -.4,
      color: Color.lerp(kLaunchInk, _cream, night),
      // The curtain sits above the app's pages, outside any Material, where
      // Flutter would mark plain text with its yellow underline.
      decoration: TextDecoration.none,
    );
    return Positioned(
      key: kLaunchLineKey,
      left: 16,
      right: 16,
      top: c.dy + kLaunchLineBelowCentre,
      child: Opacity(
        opacity: show,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - show)),
          child: AnimatedSwitcher(
            duration: Duration(milliseconds: widget.reduced ? 0 : 320),
            // One sentence at a time: the old one leaves in the first half,
            // the new one comes in the second, never two lines on top of
            // each other.
            switchInCurve: const Interval(.5, 1, curve: Curves.easeOut),
            switchOutCurve: const Interval(.5, 1, curve: Curves.easeIn),
            child: Text.rich(
              key: ValueKey(text),
              TextSpan(
                children: [
                  TextSpan(text: split < 0 ? lead : '$lead\n'),
                  if (split >= 0)
                    TextSpan(
                      text: 'Grow Daily',
                      style: TextStyle(
                        fontSize: 29,
                        letterSpacing: -.5,
                        color: Color.lerp(_green, _nightGreen, night),
                      ),
                    ),
                  TextSpan(text: rest),
                ],
              ),
              style: base,
              textAlign: TextAlign.center,
              // English on every phone, in Arabic too: the question mark
              // stays at the end.
              textDirection: TextDirection.ltr,
              // Grows with the phone's text size, but only so far: at the
              // largest accessibility sizes three rows of 26pt ran off the
              // bottom of the screen.
              textScaler: MediaQuery.textScalerOf(context)
                  .clamp(maxScaleFactor: 1.25),
            ),
          ),
        ),
      ),
    );
  }

  // ── Doum ──────────────────────────────────────────────────────────────

  /// Whether he comes in on foot rather than popping up: the welcome back
  /// walks in, the steps goal runs.
  bool get _onFoot =>
      widget.scene == LaunchScene.welcomeBack ||
      widget.scene == LaunchScene.stepsGoal;

  /// The walk in, for the welcome back, and the run in, for the steps goal:
  /// from the side reading starts on, facing the way he goes, a bob in his
  /// step (quicker running).
  ({double dx, double dy, bool mirror}) _walk(bool rtl) {
    // The treadmill runs the way reading goes, like the walk in and the
    // run; he springs off it at the ready moment (see _leap).
    if (widget.scene == LaunchScene.walk) {
      return (dx: 0, dy: _leap(), mirror: rtl);
    }
    if (!(widget.scene == LaunchScene.welcomeBack &&
            _pose == SproutPose.walkBackpack) &&
        !(widget.scene == LaunchScene.stepsGoal &&
            _pose == SproutPose.running)) {
      return (dx: 0, dy: 0, mirror: false);
    }
    // The art faces right; in Arabic he comes in from the right, so he is
    // mirrored to face left.
    final from = rtl ? 1.0 : -1.0;
    if (widget.reduced) return (dx: 0, dy: 0, mirror: rtl);
    final running = widget.scene == LaunchScene.stepsGoal;
    final along = Curves.easeOutCubic.transform(_enter.value);
    final stepping = along < .98;
    final step = running ? .15 : .21;
    return (
      dx: (1 - along) * (running ? 320 : 260) * from,
      dy: stepping ? -(math.sin(_t * math.pi / step)).abs() * (running ? 7 : 6) : 0,
      mirror: rtl,
    );
  }

  Widget _doum(Offset c, bool rtl, double enter) {
    final pose = _pose;
    final box = Sprout.sizeOf(pose, kLaunchDoumHeight);
    final body = (0.5 - (kLaunchBodyCentre[pose] ?? .5)) * box.width;
    final walk = _walk(rtl);
    final sleeping = widget.scene == LaunchScene.nightAsleep;
    final layers = _poseLayers(pose);
    Widget doum = Sprout(
      pose: pose,
      height: kLaunchDoumHeight,
      controller: _moves,
      mirror: walk.mirror,
      // The walk, the run and the night bring him in themselves; everything
      // else pops.
      entrance: _onFoot || sleeping ? SproutEntrance.none : SproutEntrance.pop,
      // No breath on the treadmill: it would squash the machine.
      idleBreaths: sleeping
          ? 2
          : pose == SproutPose.treadmill || widget.holdStill
              ? 0
              : 1,
      underlay: layers.under,
      overlay: layers.over,
      pictureBuilder: pose == SproutPose.treadmill ? _runningOnBelt : null,
      // The afternoon's two cut every pose change in one frame, as their
      // boards do: the walk moves the whole Sprout off the belt at the
      // swap, and winter lines his face up across two pictures, so the old
      // pose held for a crossfade showed two of him.
      cutSwap: widget.scene == LaunchScene.winterWait ||
          widget.scene == LaunchScene.walk,
    );
    if (sleeping) doum = Opacity(opacity: enter, child: doum);
    if (widget.scene == LaunchScene.walk) {
      doum = Transform.scale(
        scale: _takeOff(),
        alignment: Alignment.bottomCenter,
        child: doum,
      );
    }
    return Positioned(
      key: kLaunchDoumKey,
      left: 0,
      right: 0,
      bottom: c.dy * 2 - (c.dy + kLaunchFeetBelowCentre),
      child: Center(
        child: TweenAnimationBuilder<double>(
          // A pose change moves the body's centre a little; slide it back
          // under the words instead of jumping. Not in missing winter, whose
          // two poses are centred so that his eyes stay put: sliding there
          // would move his face. Its swaps are cuts (cutSwap), so the new
          // pose simply stands in its own place.
          tween: Tween(end: walk.mirror ? -body : body),
          duration: widget.scene == LaunchScene.winterWait
              ? Duration.zero
              : const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          builder: (_, dx, child) => Transform.translate(
            offset: Offset(dx + walk.dx, walk.dy),
            child: child,
          ),
          child: doum,
        ),
      ),
    );
  }

  /// His shadow on the ground, which arrives with him and moves with him.
  Widget _shadow(Offset c, bool rtl, double night, double enter) {
    final feet = c.dy + kLaunchFeetBelowCentre;
    if (widget.scene == LaunchScene.nightAsleep) {
      // Lying down he touches the ground from paw to paw, so his shadow is
      // his whole length, soft, centred on his body and 2pt above the
      // picture's foot, where his underside is: it hugs him rather than
      // lying under him. It fades in with him, and widens as he breathes out.
      const w = 144.0, h = 12.0;
      final breaths = Sprout.sleepBreathDuration.inMilliseconds / 1000;
      final breath = widget.reduced || _t >= breaths * 2
          ? 1.0
          : Sprout.sleepBreathWidthAt(_t % breaths / breaths);
      return Positioned(
        key: kLaunchShadowKey,
        left: c.dx - w / 2,
        top: feet - 2 - h / 2,
        width: w,
        height: h,
        child: Opacity(
          opacity: enter,
          child: Transform.scale(
            scaleX: breath,
            child: CustomPaint(
              painter: _ShadowPainter(
                color: Color.lerp(_dayShadow, const Color(0x8C000000), night)!,
                blur: 1.8,
              ),
            ),
          ),
        ),
      );
    }
    // Standing: up from nothing as he pops in (Sprout's own 420 ms and
    // overshoot), smaller and fainter while a hop has him in the air.
    final walk = _walk(rtl);
    var grow = 1.0, fade = 1.0;
    if (!widget.reduced && !_onFoot) {
      final e = (_t / .42).clamp(0.0, 1.0);
      grow = lerpDouble(.3, 1, Curves.easeOutBack.transform(e))!;
      fade = Curves.easeOut.transform((e / .35).clamp(0.0, 1.0));
    }
    // The ready moment starts with the hop (see _onReady).
    final lift = _ready.isAnimating
        ? Sprout.hopLiftAt(
            _ready.value *
                _ready.duration!.inMilliseconds /
                Sprout.hopDuration.inMilliseconds,
          )
        : 0.0;
    var opacity = fade * (1 - .4 * lift);
    var sx = grow * (1 - .3 * lift), sy = sx;
    // Missing winter's sits wider under the seated figure and his fire,
    // warmer on the sand (the board's). The walk's is the deck's while he
    // is on the treadmill, then keeps to his leap (see _walkShadow).
    final winter = widget.scene == LaunchScene.winterWait;
    final w = winter ? 150.0 : 96.0;
    final own = widget.scene == LaunchScene.walk ? _walkShadow() : null;
    if (own != null) (opacity, sx, sy) = own;
    return Positioned(
      key: kLaunchShadowKey,
      left: c.dx - w / 2 + walk.dx + (winter ? -3 : 0),
      top: feet - 7,
      width: w,
      height: 14,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.scale(
          scaleX: sx,
          scaleY: sy,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.all(Radius.elliptical(w / 2, 7)),
              color: winter ? _winterShadow : _dayShadow,
            ),
          ),
        ),
      ),
    );
  }

  // ── Morning ───────────────────────────────────────────────────────────

  Widget _sun(Offset c, double enter) => Positioned(
        left: c.dx - 140,
        top: c.dy - 190 + (1 - enter) * 40,
        width: 280,
        height: 280,
        child: Opacity(
          opacity: enter,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Color(0x8CFFCD8C),
                  Color(0x40FFD6A0),
                  Color(0x00FFD6A0),
                ],
                stops: [0, .45, .7],
              ),
            ),
          ),
        ),
      );

  /// Three wisps off the mug, curling up and to the left like the art's
  /// own steam, one after another.
  Widget _steam(Offset c, {required bool started}) {
    // Off the mug once a slow load has him take out his magnifier.
    if (widget.reduced || !started || _pose != SproutPose.mug) {
      return const SizedBox.shrink();
    }
    final fade = 1 - _ready.value;
    // The mug's steam in the art starts at 14% across, 55% down the picture.
    final box = Sprout.sizeOf(SproutPose.mug, kLaunchDoumHeight);
    final body = (0.5 - kLaunchBodyCentre[SproutPose.mug]!) * box.width;
    final origin = Offset(
      c.dx - box.width / 2 + body + box.width * .14,
      c.dy + kLaunchFeetBelowCentre - box.height + box.height * .55,
    );
    return Positioned(
      left: origin.dx - 12,
      top: origin.dy - 60,
      width: 40,
      height: 70,
      child: CustomPaint(
        painter: _SteamPainter(t: _t, opacity: fade),
      ),
    );
  }

  // ── Day ───────────────────────────────────────────────────────────────

  Widget _ring(Offset c, double enter, double ready) {
    final pulse = math.sin(ready * math.pi) * .05;
    return Positioned(
      left: c.dx - 100,
      top: c.dy - 150,
      width: 200,
      height: 200,
      child: Opacity(
        opacity: enter,
        child: Transform.scale(
          scale: lerpDouble(.8, 1, enter)! + pulse,
          child: CustomPaint(
            painter: _RingPainter(
              progress: widget.leaving ? 1 : widget.progress,
              halo: widget.reduced ? 0 : ready,
            ),
          ),
        ),
      ),
    );
  }

  // ── Turnaround ────────────────────────────────────────────────────────

  Widget _dial(Offset c, double enter, double ready) => Positioned(
        left: c.dx - 80,
        top: c.dy + kLaunchFeetBelowCentre - 20,
        width: 160,
        height: 40,
        child: Opacity(
          opacity: enter,
          child: CustomPaint(
            painter: _DialPainter(
              turn: widget.reduced ? 0 : _t / 2.8,
              join: ready,
            ),
          ),
        ),
      );

  // ── Evening ───────────────────────────────────────────────────────────

  Widget _dusk(Size size, double enter) => Positioned(
        left: 0,
        top: 0,
        width: size.width,
        height: size.height * .55,
        child: Opacity(
          opacity: enter,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x59F6D6B0), Color(0x00FEFAF0)],
              ),
            ),
          ),
        ),
      );

  /// Three of the Grid's own squares beside his clipboard, each turning
  /// green as a part of the home screen lands: the habits, the week, the
  /// day's numbers.
  Widget _squares(Offset c, double enter) => Positioned(
        left: c.dx + 81,
        top: c.dy - 80,
        width: 30,
        height: 106,
        child: Opacity(
          opacity: enter,
          child: Column(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                _Square(
                  done: widget.leaving || widget.progress >= (i + 1) / 3 - .001,
                  reduced: widget.reduced,
                ),
              ],
            ],
          ),
        ),
      );

  // ── Night ─────────────────────────────────────────────────────────────

  Widget _sky(Size size, Offset c, double enter) {
    final show = Curves.easeOut.transform(((enter - .25) / .75).clamp(0, 1));
    const stars = [
      (-131.0, -272.0, 4.0),
      (-75.0, -326.0, 3.0),
      (19.0, -352.0, 4.0),
      (135.0, -208.0, 3.0),
      (-99.0, -186.0, 3.0),
    ];
    return Positioned.fill(
      child: Opacity(
        opacity: show,
        child: Stack(
          children: [
            Positioned(
              left: c.dx + 77,
              top: c.dy - 304,
              width: 60,
              height: 60,
              child: const CustomPaint(
                painter: _CrescentPainter(Color(0xFFF2DFA8)),
              ),
            ),
            for (var i = 0; i < stars.length; i++)
              Positioned(
                left: c.dx + stars[i].$1,
                top: c.dy + stars[i].$2,
                width: stars[i].$3,
                height: stars[i].$3,
                child: Opacity(
                  opacity: widget.reduced
                      ? .8
                      : .35 + .65 * (.5 + .5 * math.sin((_t / 2.4 + i / 4) * 2 * math.pi)),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFF4EBD5),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// z's drifting up off him, one after another, while he sleeps.
  Widget _zs(Offset c, double enter) {
    if (widget.reduced || enter < .3) return const SizedBox.shrink();
    final fade = 1 - _ready.value;
    const sizes = [18.0, 22.0, 16.0];
    return Positioned(
      left: c.dx + 67,
      top: c.dy - 122,
      width: 70,
      height: 90,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < 3; i++)
            Builder(builder: (context) {
              final p = ((_t / 2.1) + i / 3) % 1;
              final a = (p < .25 ? p / .25 : 1 - (p - .25) / .75) * fade;
              return Positioned(
                left: 4.0 * i + 16 * p,
                top: 50 - 42 * p,
                child: Opacity(
                  opacity: a.clamp(0, 1),
                  child: Transform.scale(
                    scale: .7 + .45 * p,
                    child: Text(
                      'z',
                      style: TextStyle(
                        fontSize: sizes[i],
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFA9C4AE),
                        height: 1,
                      ),
                    ),
                  ),
                ),
              );
            },),
        ],
      ),
    );
  }

  // ── Ramadan ───────────────────────────────────────────────────────────

  Widget _moon(Offset c, double enter) => Positioned(
        left: c.dx + 67,
        top: c.dy - 272,
        width: 64,
        height: 64,
        child: Opacity(
          opacity: enter,
          child: Transform.scale(
            scale: lerpDouble(.8, 1, enter),
            child: const CustomPaint(
              painter: _CrescentPainter(Color(0xFFD9A441)),
            ),
          ),
        ),
      );

  /// A lantern hanging from the top of the screen on its cord, swinging a
  /// little, its light breathing while the app loads and flaring when it is
  /// ready.
  Widget _lantern(Offset c, double enter, double ready) {
    final cord = c.dy - 254;
    final swing =
        widget.reduced ? 0.0 : 4 * math.sin(_t / 2.8 * 2 * math.pi) * math.pi / 180;
    final breath = widget.reduced ? .6 : .45 + .25 * math.sin(_t * 2.4);
    final glow = lerpDouble(breath, 1, ready)!;
    return Positioned(
      left: c.dx - 125,
      top: -40 * (1 - enter),
      width: 80,
      height: cord + 110,
      child: Opacity(
        opacity: enter,
        child: Transform.rotate(
          angle: swing,
          alignment: Alignment.topCenter,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 39,
                top: 0,
                width: 2,
                height: cord + 8,
                child: const ColoredBox(color: Color(0xFFB8A27A)),
              ),
              Positioned(
                left: -20,
                top: cord + 2,
                width: 120,
                height: 120,
                child: Opacity(
                  opacity: glow.clamp(0, 1),
                  child: Transform.scale(
                    scale: lerpDouble(.95, 1.25, ready),
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [Color(0xBFFFC86E), Color(0x00FFC86E)],
                          stops: [0, .65],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: cord,
                width: 80,
                height: 110,
                child: const CustomPaint(painter: _LanternPainter()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Welcome back ──────────────────────────────────────────────────────

  /// His steps on the way in, left behind him on the side he came from,
  /// each as he passes it, fading once he has arrived.
  Widget _footprints(Offset c, bool rtl) {
    if (widget.reduced) return const SizedBox.shrink();
    final from = rtl ? 1.0 : -1.0;
    final walkedTo = _walk(rtl).dx * from; // how far out he still is
    final arrived = _enter.value >= .98;
    final fade = arrived ? 1 - _ready.value : 1.0;
    const steps = [67.0, 95.0, 123.0, 151.0];
    return Positioned.fill(
      child: Stack(
        children: [
          for (var i = 0; i < steps.length; i++)
            if (walkedTo < steps[i])
              Positioned(
                left: c.dx + steps[i] * from - 6,
                top: c.dy + kLaunchFeetBelowCentre + (i.isOdd ? 6 : 0),
                width: 12,
                height: 6,
                child: Opacity(
                  opacity: (.55 - .04 * i) * fade,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.all(Radius.elliptical(6, 3)),
                      color: Color(0xFF9E9278),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// One of the Grid's squares: empty, then green with its check.
class _Square extends StatelessWidget {
  const _Square({required this.done, required this.reduced});

  final bool done;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 30,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFEFE9D8),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: const Color(0xFFDCD3BC), width: 1.5),
              ),
            ),
          ),
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: done ? 1 : 0),
              duration: Duration(milliseconds: reduced ? 0 : 320),
              curve: Curves.easeOutBack,
              builder: (_, v, child) => Transform.scale(
                scale: v.clamp(0, 1.2),
                child: child,
              ),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: _green,
                  borderRadius: BorderRadius.all(Radius.circular(9)),
                ),
                child: Center(child: CustomPaint(size: Size(16, 16), painter: _TickPainter())),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TickPainter extends CustomPainter {
  const _TickPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFFFEFAF0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(3.5, 8.5)
        ..lineTo(6.8, 11.5)
        ..lineTo(12.5, 4.8),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// A soft oval filling the box, its edge blurred by [blur] points.
class _ShadowPainter extends CustomPainter {
  const _ShadowPainter({required this.color, required this.blur});

  final Color color;
  final double blur;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawOval(
      Offset.zero & size,
      Paint()
        ..color = color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
    );
  }

  @override
  bool shouldRepaint(covariant _ShadowPainter old) =>
      old.color != color || old.blur != blur;
}

class _SteamPainter extends CustomPainter {
  const _SteamPainter({required this.t, required this.opacity});

  final double t;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 3; i++) {
      final p = ((t / 1.5) + i / 3) % 1;
      final a = (p < .3 ? p / .3 : 1 - (p - .3) / .7) * .8 * opacity;
      if (a <= 0) continue;
      final paint = Paint()
        ..color = const Color(0xFFC9BCA5).withValues(alpha: a.clamp(0, 1))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      final x = 10.0 + 8 * i - 10 * p;
      final y = 60 - 44 * p;
      canvas.drawPath(
        Path()
          ..moveTo(x, y)
          ..cubicTo(x - 6, y - 8, x + 6, y - 16, x, y - 24)
          ..cubicTo(x - 5, y - 31, x + 3, y - 36, x, y - 42),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SteamPainter old) =>
      old.t != t || old.opacity != opacity;
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.progress, required this.halo});

  final double progress;
  final double halo;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    const r = 88.0;
    final track = Paint()
      ..color = const Color(0xFFEAE3D1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    canvas.drawCircle(centre, r, track);
    final arc = Paint()
      ..color = _green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    final sweep = progress.clamp(0.0, 1.0) * 2 * math.pi;
    if (sweep > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: r),
        -math.pi / 2,
        sweep,
        false,
        arc,
      );
    }
    if (halo > 0 && halo < 1) {
      canvas.drawCircle(
        centre,
        r * (1 + .22 * halo),
        Paint()
          ..color = _green.withValues(alpha: .5 * (1 - halo))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.halo != halo;
}

class _DialPainter extends CustomPainter {
  const _DialPainter({required this.turn, required this.join});

  /// Turns of the dial so far (it creeps round while he turns).
  final double turn;

  /// 0 while loading (beige dashes); 1 once ready (one green line).
  final double join;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: 144,
      height: 30,
    );
    canvas.drawOval(
      Rect.fromCenter(center: size.center(Offset.zero), width: 72, height: 12),
      Paint()..color = const Color(0x1F3A4A30),
    );
    final path = Path()..addOval(rect);
    final metric = path.computeMetrics().first;
    final length = metric.length;
    const dashes = 8;
    final period = length / dashes;
    final dash = lerpDouble(period * .27, period, join)!;
    final paint = Paint()
      ..color = Color.lerp(const Color(0xFFD3C9AE), _green, join)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final shift = (turn % 1) * period;
    for (var i = 0; i < dashes; i++) {
      final start = (i * period + shift) % length;
      final end = start + dash;
      if (end <= length) {
        canvas.drawPath(metric.extractPath(start, end), paint);
      } else {
        canvas.drawPath(metric.extractPath(start, length), paint);
        canvas.drawPath(metric.extractPath(0, end - length), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DialPainter old) =>
      old.turn != turn || old.join != join;
}

class _CrescentPainter extends CustomPainter {
  const _CrescentPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final outer = Path()
      ..addOval(Rect.fromCircle(center: Offset(s * .44, s * .56), radius: s * .4));
    final bite = Path()
      ..addOval(Rect.fromCircle(center: Offset(s * .62, s * .42), radius: s * .33));
    canvas.drawPath(
      Path.combine(PathOperation.difference, outer, bite),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _CrescentPainter old) => old.color != color;
}

/// A fanous: ring, cap, glass body with one bar, base and finial.
class _LanternPainter extends CustomPainter {
  const _LanternPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const brass = Color(0xFF9C7A3C);
    const gold = Color(0xFFB8883A);
    final stroke = Paint()
      ..color = brass
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round;
    canvas.drawCircle(const Offset(40, 8), 5, stroke);
    canvas.drawPath(
      Path()
        ..moveTo(24, 26)
        ..lineTo(40, 13)
        ..lineTo(56, 26)
        ..close(),
      Paint()..color = gold,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(22, 26, 58, 32, const Radius.circular(2)),
      Paint()..color = brass,
    );
    final glass = Path()
      ..moveTo(24, 32)
      ..lineTo(56, 32)
      ..lineTo(60, 70)
      ..lineTo(20, 70)
      ..close();
    canvas.drawPath(glass, Paint()..color = const Color(0xFFF6D58C));
    canvas.drawPath(glass, stroke);
    canvas.drawLine(
      const Offset(40, 32),
      const Offset(40, 70),
      Paint()
        ..color = brass
        ..strokeWidth = 2,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(18, 70, 62, 77, const Radius.circular(2)),
      Paint()..color = brass,
    );
    canvas.drawPath(
      Path()
        ..moveTo(30, 77)
        ..lineTo(50, 77)
        ..lineTo(40, 90)
        ..close(),
      Paint()..color = gold,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
