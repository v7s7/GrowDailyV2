part of 'launch_scenes.dart';

// The afternoon's two launch scenes (Aziz, 2026-09-30): "Missing winter"
// and "Every step", built from their boards on the canvas (Winter.dc.html
// and Walk.dc.html, reviewed and published), whose numbers these are. The
// boards are 390 x 844 with the centre at (195, 422) and the feet on 462, so
// a board x is placed from the screen's centre and a board y from the feet.
// The house rules hold: what fills, fills with the real load
// ([LaunchSceneView.progress]); the payoff starts on the ready moment and
// never before; nothing loops past the curtain; Reduce Motion keeps the
// pictures still (both boards show their end from the start).

/// The load missing winter's clock and battery turn light at: where the top
/// of its sky, dusk falling into night, reads better under white than under
/// black (a luminance of .18, worked out from the board's colours).
const double kWinterLightIconsFrom = .47;

/// Missing winter's shadow: warmer and a little deeper on the sand.
const _winterShadow = Color(0x213C2814);

/// The sky over the dunes, from the top of the screen to 22pt above his
/// feet: dusk, night, and the cool night the first breeze brings.
const _duskSky = [
  Color(0xFF8C7BA8),
  Color(0xFFB690A8),
  Color(0xFFE3A99A),
  Color(0xFFF4C592),
  Color(0x00FEFAF0),
];
const _duskStops = [0.0, .34, .62, .84, 1.0];
const _nightSky = [
  Color(0xFF1E2B47),
  Color(0xFF2F416A),
  Color(0xFF66709A),
  Color(0xFFC49AA2),
  Color(0xFFF0C7A2),
  Color(0x00FEFAF0),
];
const _coolSky = [
  Color(0xFF1C2944),
  Color(0xFF2B3D66),
  Color(0xFF52658E),
  Color(0xFF8DA4C4),
  Color(0xFFD3DFEA),
  Color(0x00FEFAF0),
];
const _nightStops = [0.0, .34, .60, .80, .92, 1.0];

/// The still star dust of the night sky: board x (of 390) and y (of the
/// sky's 440).
const _starDust = [
  (24.0, 150.0), (70.0, 40.0), (168.0, 176.0), (176.0, 30.0),
  (240.0, 160.0), (250.0, 22.0), (300.0, 150.0), (372.0, 58.0),
  (120.0, 250.0), (366.0, 250.0), (30.0, 260.0), (226.0, 232.0),
];

/// The seven stars: board centre x (of 390) and y (of the sky's 440), size,
/// and how long after the ready moment the breeze's ripple reaches it (it
/// runs left to right under the cool wipe). Star i comes out as the load
/// passes .34 + .1 i.
const _winterStars = [
  (52.0, 96.0, 15.0, 54.0),
  (132.0, 58.0, 11.0, 77.0),
  (206.0, 118.0, 16.0, 97.0),
  (284.0, 66.0, 12.0, 120.0),
  (346.0, 128.0, 14.0, 140.0),
  (92.0, 196.0, 10.0, 67.0),
  (318.0, 214.0, 11.0, 130.0),
];

/// Share of the treadmill picture's height the belt sits at above the
/// floor: where he runs, and where he springs off from.
const double _beltHeight = .2311;

extension _AfternoonScenes on _LaunchSceneViewState {
  /// Milliseconds since the home screen was ready, or null before it.
  double? get _sinceReady =>
      _readyAt == null ? null : (_t - _readyAt!) * 1000;

  /// What is painted in a pose's own box, under and over its picture
  /// (Sprout.underlay and overlay), so it moves with him and leaves with
  /// the pose: the small fire's glow and the sand running in the hourglass,
  /// the big fire's flare and its embers, the treadmill's belt and the
  /// sweat flying off him.
  ({Widget? under, Widget? over}) _poseLayers(SproutPose pose) =>
      switch (pose) {
        SproutPose.winterHourglass => (
            under: _smallFire(),
            over: CustomPaint(painter: _HourglassPainter(loaded: _loaded)),
          ),
        SproutPose.winterHappyHeart => (under: _bigFire(), over: _embers()),
        SproutPose.treadmill => (
            under: null,
            over: Stack(
              children: [
                Positioned.fill(child: _belt()),
                Positioned.fill(child: _sweat()),
              ],
            ),
          ),
        _ => (under: null, over: null),
      };

  // ── Missing winter ────────────────────────────────────────────────────

  /// Notes when each star comes out (see _LaunchSceneViewState._starAt).
  void _markStars() {
    if (!widget.started || widget.reduced) return;
    for (var i = 0; i < _winterStars.length; i++) {
      if (!_starAt.containsKey(i) && _loaded >= .34 + .1 * i - 1e-6) {
        _starAt[i] = _t;
      }
    }
  }

  /// Late summer: a warm wash and a low sun over the dunes. With the load
  /// the sun sinks behind them, the sky deepens through dusk to night, and
  /// the stars come out one at each step; when the app is ready the first
  /// cool breeze sweeps past behind him, wiping the warm horizon into an
  /// icy blue as the stars flare in a ripple under it, and his fire flares
  /// (its layers ride on his poses, see [_poseLayers]).
  void _winterScene(
    Size size,
    Offset c,
    double enter,
    List<Widget> backdrop,
    List<Widget> behind,
  ) {
    final feet = c.dy + kLaunchFeetBelowCentre;
    final sky = feet - 22;
    final reduced = widget.reduced;
    final load = reduced ? 1.0 : _loaded;
    final dusk = math.min(1.0, load / .5);
    final night = math.max(0.0, (load - .3) / .7);
    final since = _sinceReady;
    final wipe = reduced
        ? 1.0
        : since == null
            ? 0.0
            : const Cubic(.3, .7, .2, 1).transform((since / 384).clamp(0.0, 1.0));

    // The heat, down to just under his feet, draining as dusk comes.
    backdrop.add(
      Positioned(
        left: 0,
        top: 0,
        width: size.width,
        height: feet + 27.5,
        child: Opacity(
          opacity: (enter * (1 - dusk)).clamp(0.0, 1.0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: const [
                  Color(0x8CFFBA6C),
                  Color(0x52FFCE92),
                  Color(0x00FEFAF0),
                ],
                stops: [0, (feet - 124.4) / (feet + 27.5), 1],
              ),
            ),
          ),
        ),
      ),
    );
    Widget layer(List<Color> colours, List<double> stops, {bool dust = false}) =>
        SizedBox(
          width: size.width,
          height: sky,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: colours,
                      stops: stops,
                    ),
                  ),
                ),
              ),
              if (dust)
                for (final (x, y) in _starDust)
                  Positioned(
                    left: x / 390 * size.width,
                    top: y / 440 * sky,
                    width: 2.4,
                    height: 2.4,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xBFF4EBD5),
                      ),
                    ),
                  ),
            ],
          ),
        );
    Widget top(double opacity, Widget child) => Positioned(
          left: 0,
          top: 0,
          width: size.width,
          height: sky,
          child: Opacity(opacity: opacity.clamp(0.0, 1.0), child: child),
        );
    backdrop.add(top(enter * dusk, layer(_duskSky, _duskStops)));
    backdrop.add(top(enter * night, layer(_nightSky, _nightStops, dust: true)));
    if (wipe > 0) {
      // Left to right with a soft edge a fifth of its travel wide.
      backdrop.add(
        top(
          enter,
          ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) {
              final span = rect.width * 2.5;
              return const LinearGradient(
                colors: [
                  Color(0xFFFFFFFF),
                  Color(0xFFFFFFFF),
                  Color(0x00FFFFFF),
                  Color(0x00FFFFFF),
                ],
                stops: [0, .4, .6, 1],
              ).createShader(
                Rect.fromLTWH(
                  -(span - rect.width) * (1 - wipe),
                  0,
                  span,
                  rect.height,
                ),
              );
            },
            child: layer(_coolSky, _nightStops, dust: true),
          ),
        ),
      );
    }

    // The low sun, sinking behind the dunes (painted before them, so they
    // hide it) and gone by the time night has come.
    if (!reduced) {
      final gone =
          Curves.easeInOut.transform(((load - .76) / .1).clamp(0.0, 1.0));
      backdrop.add(
        Positioned(
          left: c.dx - 125 - 60,
          top: feet - 108 - 60 + 120 * math.min(1.0, load / .8),
          width: 120,
          height: 120,
          child: Opacity(
            opacity: (enter * (1 - gone)).clamp(0.0, 1.0),
            child: Transform.scale(
              scale: lerpDouble(.9, 1, enter),
              child: const Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _GlowPainter(
                        at: Offset(.5, .5),
                        across: 1,
                        colours: [Color(0x80FFA054), Color(0x00FFA054)],
                        stops: [0, .62],
                      ),
                    ),
                  ),
                  Center(
                    child: SizedBox(
                      width: 50,
                      height: 50,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            center: Alignment(-.16, -.24),
                            // To the farthest corner from its centre, as
                            // the board's gradient runs.
                            radius: .849,
                            colors: [Color(0xFFFCCB76), Color(0xFFF29A4C)],
                            stops: [0, .8],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // The stars: out one at each step of the load, twinkling slowly, and
    // flaring as the breeze passes under them.
    for (var i = 0; i < _winterStars.length; i++) {
      final (x, y, s, ripple) = _winterStars[i];
      var scale = 1.0, spin = 0.0, alpha = 1.0;
      if (!reduced) {
        final at = _starAt[i];
        if (at == null) continue;
        final u = (_t - at) * 1000;
        if (u < 83) {
          final e = Curves.easeOut.transform(u / 83);
          scale = 1.45 * e;
          spin = -30 * (1 - e);
          alpha = e;
        } else if (u < 166) {
          scale = lerpDouble(1.45, 1, Curves.easeInOut.transform((u - 83) / 83))!;
        }
        final p = ((_t + .43 * i) / 2.6) % 1;
        final tw = Curves.easeInOut.transform(p < .5 ? p * 2 : 2 - p * 2);
        scale *= .82 + .18 * tw;
        alpha *= .7 + .3 * tw;
        if (since != null) {
          final r = since - ripple;
          if (r > 0 && r < 70) {
            scale *= lerpDouble(1, 1.4, Curves.easeOut.transform(r / 70))!;
          } else if (r >= 70 && r < 204) {
            scale *= lerpDouble(
              1.4,
              1,
              Curves.easeInOut.transform((r - 70) / 134),
            )!;
          }
        }
      }
      backdrop.add(
        Positioned(
          left: x / 390 * size.width - s / 2,
          top: y / 440 * sky - s / 2,
          width: s,
          height: s,
          child: Opacity(
            opacity: (alpha * enter).clamp(0.0, 1.0),
            child: Transform.rotate(
              angle: spin * math.pi / 180,
              child: Transform.scale(
                scale: scale,
                child: const CustomPaint(painter: _WinterStarPainter()),
              ),
            ),
          ),
        ),
      );
    }

    // The dunes, settling in with him and cooling with the night.
    backdrop.add(
      Positioned(
        left: 0,
        top: feet - 80 + 10 * (1 - enter),
        width: size.width,
        height: math.max(0, size.height - (feet - 80)),
        child: Opacity(
          opacity: enter,
          child: CustomPaint(painter: _DunesPainter(night: night)),
        ),
      ),
    );

    // The first cool breeze: two gusts sweeping past behind him.
    if (!reduced && since != null && since < 520) {
      behind.add(
        Positioned(
          left: c.dx - 195,
          top: feet - 462,
          width: 390,
          height: 480,
          child: IgnorePointer(
            child: CustomPaint(painter: _GustPainter(since: since)),
          ),
        ),
      );
    }
  }

  /// The small fire's glow by the hourglass pose's own fire: in just after
  /// him, then flickering calmly.
  Widget _smallFire() {
    var opacity = 1.0, scale = 1.0;
    if (!widget.reduced) {
      final e = Curves.easeOut.transform(((_t - .064) / .512).clamp(0.0, 1.0));
      opacity = .85 * e;
      scale = lerpDouble(.4, 1, e)!;
      final p = (_t / 1.3) % 1;
      final (a, s) = p < .4
          ? _between(p / .4, (.8, 1.0), (1.0, 1.06))
          : p < .7
              ? _between((p - .4) / .3, (1.0, 1.06), (.86, .97))
              : _between((p - .7) / .3, (.86, .97), (.8, 1.0));
      opacity *= a;
      scale *= s;
    }
    return CustomPaint(
      painter: _GlowPainter(
        at: const Offset(.8667, .7585),
        across: 68 / 210.04,
        colours: const [Color(0x8CFFB05A), Color(0x00FFB05A)],
        stops: const [0, .65],
        opacity: opacity,
        scale: scale,
      ),
    );
  }

  /// The big fire's glow in his arms: it flares when the app is ready,
  /// settles, then breathes.
  Widget _bigFire() {
    var opacity = 1.0, scale = 1.0;
    final since = _sinceReady;
    if (!widget.reduced && since != null) {
      if (since < 288) {
        final e = const Cubic(.2, .9, .3, 1.2).transform(since / 288);
        opacity = lerpDouble(.75, 1, e)!;
        scale = lerpDouble(.5, 1.25, e)!;
      } else if (since < 640) {
        scale = lerpDouble(
          1.25,
          1,
          Curves.easeInOut.transform((since - 288) / 352),
        )!;
      }
      final p = (_t / 1.7) % 1;
      scale *= 1 + .07 * Curves.easeInOut.transform(p < .5 ? p * 2 : 2 - p * 2);
    }
    return CustomPaint(
      painter: _GlowPainter(
        at: const Offset(.7115, .5547),
        across: 180 / 181.29,
        colours: const [Color(0x9EFFBA60), Color(0x42FFC478), Color(0x00FFC478)],
        stops: const [0, .4, .68],
        opacity: opacity,
        scale: scale,
      ),
    );
  }

  /// Embers rising off the big fire, one after another, from the ready
  /// moment.
  Widget _embers() => CustomPaint(
        painter: _EmbersPainter(
          since: widget.reduced ? null : _sinceReady,
        ),
      );

  // ── Every step ────────────────────────────────────────────────────────

  /// The treadmill's belt, running back under him at a steady pace once
  /// the pop has landed. Steady, not with the load: a stalled load reads as
  /// running in place, never as a frozen app.
  Widget _belt() {
    final t = _t - .384;
    return CustomPaint(
      painter: _BeltPainter(
        shift: t <= 0 ? 0 : (t * 56.25) % 18,
        opacity: widget.reduced ? 1 : (t / .128).clamp(0.0, 1.0),
      ),
    );
  }

  /// Seconds he has been running: from the moment the pop lands, as the
  /// belt starts.
  double get _running => math.max(0, _t - .384);

  /// One step every .3 s: he dips at each footfall and rises between them,
  /// leaning a little to each side in turn (Aziz, 2026-10-01: "it should be
  /// animation running on the treadmill"). Down from where the picture has
  /// him, never up: his feet stay on the belt.
  ({double dip, double lean}) _stride() {
    if (widget.reduced) return (dip: 0, lean: 0);
    final run = _running;
    // Into the stride over the first step, not at full bounce at once.
    final into = (run / .3).clamp(0.0, 1.0);
    final phase = run / .3;
    final dip = 2.8 * into * (.5 + .5 * math.cos(2 * math.pi * phase));
    final lean = .021 * into * math.sin(math.pi * phase);
    return (dip: dip, lean: lean);
  }

  /// The treadmill picture with him running on it: the machine still, and
  /// him cut out of it, dipping and leaning with each step. The console
  /// stays in front of the hand he holds it by, as in the picture; his
  /// feet may come down over the belt.
  Widget _runningOnBelt(Widget picture) {
    final stride = _stride();
    return Stack(
      children: [
        Positioned.fill(
          child: ClipPath(clipper: const _MachineClipper(), child: picture),
        ),
        // Him as the picture has him, by the console only: where a step
        // moves him off its edge, the gap shows his own body, not the
        // ground through a sliver.
        Positioned.fill(
          child: ClipPath(
            clipper: const _RunnerClipper(byConsole: true),
            child: picture,
          ),
        ),
        Positioned.fill(
          child: ClipPath(
            clipper: const _InFrontOfConsoleClipper(),
            child: Transform(
              alignment: Alignment.bottomCenter,
              transform: Matrix4.translationValues(0, stride.dip, 0)
                ..rotateZ(stride.lean),
              child: ClipPath(
                clipper: const _RunnerClipper(),
                child: picture,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Drops of sweat flying back off his head as he runs, one every .4 s
  /// from either temple, in place of the two the picture holds still
  /// (Aziz, 2026-10-01: "and the sweating").
  Widget _sweat() {
    if (widget.reduced) return const SizedBox.shrink();
    return CustomPaint(
      painter: _SweatPainter(
        run: _running,
        dip: _stride().dip,
      ),
    );
  }

  /// How far above the line he is as he springs off the belt: from the
  /// belt, over the hop's top, down onto the line on the hop's own landing
  /// squash (.74 of it). Only off the treadmill, and never under Reduce
  /// Motion.
  double _leap() {
    final since = _sinceReady;
    if (since == null ||
        widget.reduced ||
        _readyFrom != SproutPose.treadmill) {
      return 0;
    }
    final belt = Sprout.sizeOf(SproutPose.treadmill, kLaunchDoumHeight).height *
        _beltHeight;
    final hop = since / Sprout.hopDuration.inMilliseconds;
    return -belt * (1 - Curves.easeInCubic.transform((hop / .74).clamp(0.0, 1.0)));
  }

  /// His size as he springs off: the wink jump is drawn about a tenth
  /// bigger than the Doum running on the treadmill, so it takes off at the
  /// runner's size and grows to its own by the top of the hop's stretch
  /// (the board's take-off); a full-size wink out of the swap popped him
  /// bigger.
  double _takeOff() {
    final since = _sinceReady;
    if (since == null ||
        widget.reduced ||
        _readyFrom != SproutPose.treadmill ||
        since >= 247) {
      return 1;
    }
    if (since <= 91) return .9;
    return lerpDouble(.9, 1, Curves.easeInOut.transform((since - 91) / 156))!;
  }

  /// His own shadow in the walk, as opacity and scale: none while he is on
  /// the treadmill (the deck's shows), then small and faint while the leap
  /// has him up, full as he lands. Null for the house's own (a slow load's
  /// magnifier, Reduce Motion).
  (double, double, double)? _walkShadow() {
    if (_pose == SproutPose.treadmill) return (0, 1, 1);
    final since = _sinceReady;
    if (since == null ||
        widget.reduced ||
        _readyFrom != SproutPose.treadmill) {
      return null;
    }
    if (since < 229) return (.3 * since / 229, .6, .6);
    if (since < 481) {
      final u = Curves.easeIn.transform((since - 229) / 252);
      return (
        lerpDouble(.3, 1, u)!,
        lerpDouble(.6, 1.06, u)!,
        lerpDouble(.6, 1, u)!,
      );
    }
    if (since < 572) {
      final u = Curves.easeInOut.transform((since - 481) / 91);
      return (1, lerpDouble(1.06, .98, u)!, 1);
    }
    if (since < 650) {
      final u = Curves.easeInOut.transform((since - 572) / 78);
      return (1, lerpDouble(.98, 1, u)!, 1);
    }
    return (1, 1, 1);
  }

  /// A mint morning-fresh wash; the deck's shadow; and, when the app is
  /// ready, the machine tucking away as he springs off it. No footprints:
  /// he runs on the belt itself (Aziz, 2026-10-01: "it should not show
  /// footsteps").
  void _walkScene(Size size, Offset c, bool rtl, List<Widget> behind) {
    final feet = c.dy + kLaunchFeetBelowCentre;
    final ahead = rtl ? -1.0 : 1.0;
    final reduced = widget.reduced;
    final since = _sinceReady;
    final leapt = !reduced && _readyFrom == SproutPose.treadmill;
    final deck = _poseBox(c, SproutPose.treadmill, mirror: rtl);

    behind.add(
      _wash(
        size,
        reduced ? 1 : Curves.easeInOut.transform(_enter.value),
        const [Color(0x6BC6E8CA), Color(0x29D6EED6), Color(0x00FEFAF0)],
        height: .56,
        stops: const [0, 34 / 56, 1],
      ),
    );

    // The deck's shadow, popping up with the machine, and narrowing away
    // with it as it tucks.
    final onBelt = _pose == SproutPose.treadmill;
    final tucking = leapt && since != null && since < 200;
    if (!reduced && (onBelt || tucking)) {
      final u = onBelt ? 0.0 : Curves.easeIn.transform(since! / 200);
      final e = (_t / .42).clamp(0.0, 1.0);
      final grow = lerpDouble(.3, 1, Curves.easeOutBack.transform(e))!;
      final fade = Curves.easeOut.transform((e / .35).clamp(0.0, 1.0));
      const w = 181.54;
      behind.add(
        Positioned(
          left: deck.center.dx - w / 2 - 8 * ahead * u,
          top: feet - 7,
          width: w,
          height: 14,
          child: Opacity(
            opacity: (fade * (1 - u)).clamp(0.0, 1.0),
            child: Transform.scale(
              scaleX: grow * lerpDouble(1, .55, u)!,
              scaleY: grow * lerpDouble(1, .8, u)!,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.elliptical(90.77, 7)),
                  color: _dayShadow,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // The machine alone (him cut out: he is the Sprout now, springing off
    // it) fades, sinks and slides back the way the belt ran.
    if (tucking) {
      final u = Curves.easeIn.transform(since / 200);
      final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3;
      Widget machine = ClipPath(
        clipper: const _MachineClipper(),
        child: Image(
          image: sproutImage(
            SproutPose.treadmill,
            sproutScaleFor(kLaunchDoumHeight),
            dpr,
          ),
          width: deck.width,
          height: deck.height,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          excludeFromSemantics: true,
        ),
      );
      if (rtl) machine = Transform.flip(flipX: true, child: machine);
      final s = 1 - .08 * u;
      behind.add(
        Positioned.fromRect(
          rect: deck,
          child: Opacity(
            opacity: (1 - u).clamp(0.0, 1.0),
            child: Transform(
              alignment: Alignment.bottomCenter,
              transform: Matrix4.translationValues(-8 * ahead * u, 6 * u, 0)
                ..multiply(Matrix4.diagonal3Values(s, s, 1)),
              child: machine,
            ),
          ),
        ),
      );
    }
  }
}

/// (opacity, scale) eased from [a] to [b] at [u].
(double, double) _between(double u, (double, double) a, (double, double) b) {
  final e = Curves.easeInOut.transform(u.clamp(0.0, 1.0));
  return (lerpDouble(a.$1, b.$1, e)!, lerpDouble(a.$2, b.$2, e)!);
}

/// A round glow at [at] (shares of the box), [across] the box's width wide
/// (times [scale]), its [colours] running out to the corners of its square
/// as the boards' CSS radial gradients do, and cut to its circle.
class _GlowPainter extends CustomPainter {
  const _GlowPainter({
    required this.at,
    required this.across,
    required this.colours,
    required this.stops,
    this.opacity = 1,
    this.scale = 1,
  });

  final Offset at;
  final double across;
  final List<Color> colours;
  final List<double> stops;
  final double opacity;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0 || scale <= 0) return;
    final centre = Offset(at.dx * size.width, at.dy * size.height);
    final half = size.width * across * scale / 2;
    canvas.drawCircle(
      centre,
      half,
      Paint()
        ..shader = RadialGradient(
          colors: [
            for (final c in colours)
              c.withValues(alpha: c.a * opacity.clamp(0.0, 1.0)),
          ],
          stops: stops,
        ).createShader(
          Rect.fromCircle(center: centre, radius: half * math.sqrt2),
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _GlowPainter old) =>
      old.opacity != opacity ||
      old.scale != scale ||
      old.at != at ||
      old.across != across;
}

/// A winter star: a soft halo round a four-point sparkle, pale gold.
class _WinterStarPainter extends CustomPainter {
  const _WinterStarPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    const centre = Offset(12, 12);
    canvas.drawCircle(
      centre,
      15,
      Paint()
        ..shader = const RadialGradient(
          colors: [
            Color(0x6BFFECB4),
            Color(0x3DFFECB4),
            Color(0x12FFECB4),
            Color(0x00FFECB4),
          ],
          stops: [0, .3, .62, 1],
        ).createShader(Rect.fromCircle(center: centre, radius: 15)),
    );
    canvas.drawPath(
      Path()
        ..moveTo(12, 0)
        ..cubicTo(13, 7, 17, 11, 24, 12)
        ..cubicTo(17, 13, 13, 17, 12, 24)
        ..cubicTo(11, 17, 7, 13, 0, 12)
        ..cubicTo(7, 11, 11, 7, 12, 0)
        ..close(),
      Paint()..color = const Color(0xFFFFF0C4),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Two soft dune ridges from 80pt above his feet down to the bottom of the
/// screen, their sand running into the curtain's cream before his line,
/// cooling from day to night with [night].
class _DunesPainter extends CustomPainter {
  const _DunesPainter({required this.night});

  final double night;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 390;
    final bottom = size.height;
    final far = Path()
      ..moveTo(0, 34)
      ..cubicTo(50 * k, 20, 110 * k, 18, 170 * k, 28)
      ..cubicTo(230 * k, 38, 300 * k, 30, 390 * k, 14)
      ..lineTo(size.width, bottom)
      ..lineTo(0, bottom)
      ..close();
    final near = Path()
      ..moveTo(0, 46)
      ..cubicTo(44 * k, 34, 96 * k, 30, 140 * k, 38)
      ..cubicTo(184 * k, 46, 214 * k, 48, 260 * k, 40)
      ..cubicTo(306 * k, 32, 352 * k, 30, 390 * k, 38)
      ..lineTo(size.width, bottom)
      ..lineTo(0, bottom)
      ..close();
    final n = night.clamp(0.0, 1.0);
    canvas.drawPath(
      far,
      Paint()
        ..color = Color.lerp(
          const Color(0xFFEFDDBE),
          const Color(0xFFD8C3A6),
          n,
        )!,
    );
    // The board's gradient runs over the near ridge's own height (from its
    // crest, 33, to 436 below the dunes' top).
    canvas.drawPath(
      near,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(const Color(0xFFEAD3AA), const Color(0xFFE2C9A0), n)!,
            const Color(0xFFF7EBD3),
            const Color(0xFFFEFAF0),
          ],
          stops: const [0, .18, .32],
        ).createShader(Rect.fromLTWH(0, 33, size.width, 403)),
    );
  }

  @override
  bool shouldRepaint(covariant _DunesPainter old) => old.night != night;
}

/// The first cool breeze, on the board's 390 x 480: a long stroke ending in
/// an open hook with a shorter one under it, at head height, then the same
/// pair higher up a moment later. Each draws across left to right as a
/// window sliding along its path and fades out along its hook.
class _GustPainter extends CustomPainter {
  const _GustPainter({required this.since});

  /// Milliseconds since the ready moment.
  final double since;

  static Path _long(double dy) => Path()
    ..moveTo(-40, 345 + dy)
    ..cubicTo(40, 333 + dy, 110, 357 + dy, 190, 345 + dy)
    ..cubicTo(270, 333 + dy, 300, 331 + dy, 334, 343 + dy)
    ..cubicTo(352, 350 + dy, 356, 365 + dy, 344, 370 + dy);

  static Path _short(double dy) => Path()
    ..moveTo(-40, 361 + dy)
    ..cubicTo(20, 353 + dy, 80, 371 + dy, 150, 363 + dy)
    ..cubicTo(220, 355 + dy, 220, 355 + dy, 250, 359 + dy);

  /// Path, start and end (ms after ready), window (% of the path), width.
  static final _strokes = [
    (_long(0), 0.0, 390.4, 55.0, 3.4),
    (_short(0), 38.4, 428.8, 40.0, 2.55),
    (_long(-113), 57.6, 467.2, 55.0, 3.0),
    (_short(-113), 96.0, 505.6, 40.0, 2.25),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final (path, start, end, window, width) in _strokes) {
      final u = ((since - start) / (end - start)).clamp(0.0, 1.0);
      if (u <= 0 || u >= 1) continue;
      final from = lerpDouble(-window, 100, const Cubic(.3, .6, .3, 1).transform(u))!;
      final fade = 1 - ((u - .551) / .449).clamp(0.0, 1.0);
      final metric = path.computeMetrics().first;
      final a = from.clamp(0.0, 100.0) * metric.length / 100;
      final b = (from + window).clamp(0.0, 100.0) * metric.length / 100;
      if (b <= a || fade <= 0) continue;
      canvas.drawPath(
        metric.extractPath(a, b),
        Paint()
          ..color = const Color(0xFFC4E0F4).withValues(alpha: fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GustPainter old) => old.since != since;
}

/// Four embers drifting up off the big fire in his arms and fading, one
/// after another from the ready moment (in the happy pose's picture, 181.29
/// wide on the board).
class _EmbersPainter extends CustomPainter {
  const _EmbersPainter({required this.since});

  /// Milliseconds since the ready moment; null draws none.
  final double? since;

  /// Start (ms), centre, size, colour, and where it has drifted at the end
  /// of each of its three stretches.
  static const _embers = [
    (77.0, Offset(140, 46.2), 3.4, Color(0xFFFFE3A3),
        [Offset(.6, -6.1), Offset(3, -22.8), Offset(.9, -38)]),
    (384.0, Offset(145.1, 51.2), 3.0, Color(0xFFFFC867),
        [Offset(-.6, -5.8), Offset(-3, -21.6), Offset(-.9, -36)]),
    (691.0, Offset(136.9, 49.7), 3.2, Color(0xFFFFE3A3),
        [Offset(.8, -6.4), Offset(4, -24), Offset(1.2, -40)]),
    (998.0, Offset(142.4, 48.1), 3.0, Color(0xFFFFC867),
        [Offset(-.4, -5.9), Offset(-2, -22.2), Offset(-.6, -37)]),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final since = this.since;
    if (since == null) return;
    canvas.scale(size.width / 181.29);
    for (final (start, at, d, colour, drift) in _embers) {
      final u = since - start;
      if (u <= 0 || u >= 1297) continue;
      double alpha, s;
      Offset move;
      if (u < 179) {
        final e = Curves.easeOut.transform(u / 179);
        alpha = e;
        s = lerpDouble(.6, 1, e)!;
        move = drift[0] * e;
      } else if (u < 717) {
        final e = (u - 179) / 538;
        alpha = lerpDouble(1, .85, e)!;
        s = lerpDouble(1, .85, e)!;
        move = Offset.lerp(drift[0], drift[1], e)!;
      } else {
        final e = Curves.easeInOut.transform((u - 717) / 580);
        alpha = lerpDouble(.85, 0, e)!;
        s = lerpDouble(.85, .4, e)!;
        move = Offset.lerp(drift[1], drift[2], e)!;
      }
      final centre = at + move;
      final r = d / 2 * s;
      canvas.drawCircle(
        centre,
        r + 1.5 * s,
        Paint()
          ..color = const Color(0xB3FF963C).withValues(alpha: .7 * alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
      canvas.drawCircle(
        centre,
        r,
        Paint()..color = colour.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EmbersPainter old) => old.since != since;
}

/// The sand running in his hourglass, painted over the glass drawn in the
/// winter hourglass picture, in the picture's own pixels (1074 wide): the
/// glass and its tint, the top sand falling by AREA (faster where the bulb
/// narrows), a thin stream while anything is left to run, the pile growing
/// from the floor, then the glass's white rim and its highlights. The top
/// is empty exactly as the load completes.
class _HourglassPainter extends CustomPainter {
  const _HourglassPainter({required this.loaded});

  final double loaded;

  /// The inner wall of the drawn glass, traced off the picture (x, y pairs,
  /// down the left side, across the floor, up the right side).
  static const List<double> _glass = [
    732.5, 338.5, 731.5, 342, 731.5, 346, 730.5, 348, 730.5, 394, 731.5, 396,
    731.5, 406, 732.5, 408, 732.5, 412, 734.5, 420, 737.5, 426, 737.5, 428,
    744.5, 442, 746.5, 444, 748.5, 448, 754.5, 456, 779.5, 480, 781.5, 484,
    781.5, 490, 778.5, 496, 758.5, 516, 750.5, 526, 743.5, 538, 741.5, 540,
    734.5, 556, 730.5, 572, 730.5, 576, 729.5, 578, 729.5, 586, 728.5, 588,
    728.5, 642, 731.5, 644, 750.5, 646, 766.5, 647, 766.5, 649.5, 836.5, 649.5,
    836.5, 647, 847.5, 646, 862.5, 644, 867.5, 642, 867.5, 628, 868.5, 626,
    868.5, 600, 867.5, 598, 867.5, 582, 866.5, 580, 865.5, 568, 862.5, 556,
    860.5, 552, 860.5, 550, 850.5, 530, 844.5, 522, 840.5, 518, 839.5, 516,
    818.5, 496, 815.5, 492, 815.5, 484, 818.5, 478, 834.5, 464, 845.5, 452,
    852.5, 442, 859.5, 428, 859.5, 426, 861.5, 422, 861.5, 420, 864.5, 412,
    864.5, 408, 866.5, 400, 866.5, 392, 867.5, 390, 867.5, 338.5,
  ];

  /// The load at each of the board's steps, how far the top sand has
  /// fallen then (picture px), and how full the pile is. Eased out within
  /// each step, as the board runs it: the sand rushes as a step of the load
  /// lands, then settles.
  static const _steps = [0.0, .32, .40, .76, .86, 1.0];
  static const _fallen = [0.0, 32.0, 40.0, 80.0, 93.0, 138.0];
  static const _piled = [.001, .45, .527, .825, .9, 1.0];

  static double _along(double at, List<double> ys) {
    for (var i = 1; i < _steps.length; i++) {
      if (at <= _steps[i]) {
        final u = (at - _steps[i - 1]) / (_steps[i] - _steps[i - 1]);
        return lerpDouble(ys[i - 1], ys[i], Curves.easeOut.transform(u))!;
      }
    }
    return ys.last;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final load = loaded.clamp(0.0, 1.0);
    canvas.scale(size.width / 1074);
    final glass = Path()..moveTo(_glass[0], _glass[1]);
    for (var i = 2; i < _glass.length; i += 2) {
      glass.lineTo(_glass[i], _glass[i + 1]);
    }
    glass.close();
    canvas.save();
    canvas.clipPath(glass);
    const all = Rect.fromLTWH(724, 330, 151, 327);
    canvas.drawRect(
      all,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFC6DCE7),
            Color(0xFFD7E8EF),
            Color(0xFFE4EDF0),
            Color(0xFFE6E6E6),
            Color(0xFFD3D0D1),
            Color(0xFFDCD4CD),
          ],
          stops: [0, .16, .44, .52, .62, 1],
        ).createShader(const Rect.fromLTRB(724, 340, 875, 647)),
    );
    // The fire's warmth on the lower bulb's side nearest it.
    const lower = Rect.fromLTWH(724, 484, 151, 173);
    canvas.drawRect(
      lower,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0x00FFE3C0), Color(0xCCFFE3C0)],
          stops: [.45, 1],
        ).createShader(const Rect.fromLTRB(730, 484, 866, 657)),
    );
    canvas.save();
    canvas.clipRect(const Rect.fromLTWH(724, 330, 151, 154));
    final fallen = _along(load, _fallen);
    canvas.drawRect(
      Rect.fromLTWH(724, 356 + fallen, 151, 168),
      Paint()..color = const Color(0xFFE98D46),
    );
    canvas.drawRect(
      Rect.fromLTWH(724, 356 + fallen, 151, 6),
      Paint()..color = const Color(0xFFF5B775),
    );
    canvas.restore();
    if (load > 0 && load < 1) {
      canvas.drawLine(
        const Offset(798.5, 482),
        const Offset(798.5, 647),
        Paint()
          ..color = const Color(0xFFEEA05A)
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.save();
    canvas.translate(0, 648);
    canvas.scale(1, _along(load, _piled));
    canvas.translate(0, -648);
    canvas.drawPath(
      Path()
        ..moveTo(728, 650)
        ..lineTo(728, 625)
        ..cubicTo(762, 623, 785, 589, 798.5, 589)
        ..cubicTo(812, 589, 835, 623, 869, 625)
        ..lineTo(869, 650)
        ..close(),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF3AC62), Color(0xFFE8914A)],
        ).createShader(const Rect.fromLTRB(728, 589, 869, 650)),
    );
    canvas.restore();
    canvas.drawPath(
      glass,
      Paint()
        ..color = const Color(0xFFFDFEFE)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      Path()
        ..moveTo(760, 353)
        ..cubicTo(766, 353, 768, 365, 767, 380)
        ..cubicTo(766, 391, 763, 400, 760, 402)
        ..cubicTo(757, 400, 754, 391, 753, 380)
        ..cubicTo(752, 365, 754, 353, 760, 353)
        ..close(),
      Paint()..color = const Color(0xD9FFFFFF),
    );
    canvas.drawPath(
      Path()
        ..moveTo(835, 351)
        ..cubicTo(842, 351, 846, 364, 845, 380)
        ..cubicTo(844, 392, 839, 402, 835, 403)
        ..cubicTo(831, 402, 826, 392, 825, 380)
        ..cubicTo(824, 364, 828, 351, 835, 351)
        ..close(),
      Paint()..color = const Color(0xBFFFFFFF),
    );
    canvas.save();
    canvas.translate(766, 547);
    canvas.rotate(18 * math.pi / 180);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 16, height: 28),
      Paint()..color = const Color(0xCCFFFFFF),
    );
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HourglassPainter old) => old.loaded != loaded;
}

/// The treadmill's belt: faint slanted stripes running back under him, on
/// the running surface of the treadmill picture (187.16 wide on the board).
class _BeltPainter extends CustomPainter {
  const _BeltPainter({required this.shift, required this.opacity});

  final double shift;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    canvas.scale(size.width / 187.16);
    canvas.translate(32.86, 157.24);
    canvas.clipPath(
      Path()
        ..moveTo(18.38, 0)
        ..lineTo(97.2, 3.13)
        ..lineTo(97.2, 12.32)
        ..lineTo(0, 9.19)
        ..close(),
    );
    final paint = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: .16 * opacity)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    for (var k = 0; k < 9; k++) {
      final x = 18.0 * k - shift;
      canvas.drawLine(Offset(x, 0), Offset(x - 24.64, 12.32), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BeltPainter old) =>
      old.shift != shift || old.opacity != opacity;
}

/// The treadmill picture's machine alone, him cut out: what tucks away as
/// he springs off it. As shares of the picture, traced on the board.
class _MachineClipper extends CustomClipper<Path> {
  const _MachineClipper();

  static const List<double> _keep = [
    0.0, 100.0, 0.0, 75.22, 21.32, 75.22, 21.73, 76.0, 22.57, 75.81,
    30.51, 75.71, 50.57, 76.79, 56.43, 76.84, 58.10, 77.18, 60.19, 76.93,
    62.28, 76.98, 62.70, 77.18, 72.31, 77.57, 74.40, 77.57, 75.86, 77.18,
    73.67, 68.56, 71.06, 59.55, 69.38, 59.35, 67.71, 58.67, 66.04, 58.67,
    65.20, 58.47, 64.37, 57.59, 63.74, 56.42, 63.64, 55.63, 63.74, 55.24,
    64.79, 54.06, 74.09, 46.62, 78.89, 43.10, 79.31, 42.70, 79.52, 41.92,
    79.94, 41.53, 82.65, 39.76, 83.59, 37.81, 100.0, 37.81, 100.0, 100.0,
  ];

  /// The machine's outline in a picture [size] big.
  static Path outline(Size size) {
    Offset at(int i) =>
        Offset(_keep[i] / 100 * size.width, _keep[i + 1] / 100 * size.height);
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 2; i < _keep.length; i += 2) {
      final p = at(i);
      path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  @override
  Path getClip(Size size) => outline(size);

  @override
  bool shouldReclip(covariant CustomClipper<Path> old) => false;
}

/// Him alone in the treadmill picture: the machine cut away, and the two
/// drops of sweat the picture holds still beside his head, which fly
/// instead (_SweatPainter). As shares of the picture.
class _RunnerClipper extends CustomClipper<Path> {
  const _RunnerClipper({this.byConsole = false});

  /// Only the part of him beside the treadmill's console.
  final bool byConsole;

  @override
  Path getClip(Size size) {
    final w = size.width, h = size.height;
    final him = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      _MachineClipper.outline(size),
    );
    if (byConsole) {
      return Path.combine(
        PathOperation.intersect,
        him,
        Path()..addRect(Rect.fromLTRB(.56 * w, .36 * h, w, .8 * h)),
      );
    }
    final drops = Path()
      ..addRect(Rect.fromLTRB(.16 * w, .345 * h, .245 * w, .41 * h))
      ..addRect(Rect.fromLTRB(.10 * w, .425 * h, .20 * w, .495 * h));
    return Path.combine(PathOperation.difference, him, drops);
  }

  @override
  bool shouldReclip(covariant _RunnerClipper old) =>
      old.byConsole != byConsole;
}

/// Everything but the treadmill's console: what his moving picture may
/// paint over. The console stays in front of the hand he holds it by;
/// the belt below it lets his feet come down over it.
class _InFrontOfConsoleClipper extends CustomClipper<Path> {
  const _InFrontOfConsoleClipper();

  @override
  Path getClip(Size size) {
    final console = Path.combine(
      PathOperation.intersect,
      _MachineClipper.outline(size),
      Path()
        ..addRect(
          Rect.fromLTRB(.6 * size.width, 0, size.width, .775 * size.height),
        ),
    );
    return Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      console,
    );
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> old) => false;
}

/// Sweat flying back off his head as he runs, in the treadmill picture's
/// box: a drop every .4 s from his temple or his cheek in turn, thrown
/// back and a little up, falling away as it fades, in the picture's own
/// sky blue. [run] is seconds running; [dip] his stride's dip now.
class _SweatPainter extends CustomPainter {
  const _SweatPainter({required this.run, required this.dip});

  final double run;
  final double dip;

  static const _every = .4;
  static const _life = .6;

  /// Where the drops leave him, as shares of the picture: his temple and
  /// his cheek, where the picture's own two drops sit.
  static const _from = [Offset(.255, .385), Offset(.245, .455)];

  @override
  void paint(Canvas canvas, Size size) {
    if (run <= 0) return;
    final newest = (run / _every).floor();
    for (var k = newest; k >= 0 && run - k * _every < _life; k--) {
      final u = (run - k * _every) / _life;
      final from = _from[k % 2];
      final start = Offset(from.dx * size.width, from.dy * size.height + dip);
      // Back, up a little, then down: thrown off a runner.
      final at = start + Offset(-40 * u, -12 * u + 30 * u * u);
      final heading = Offset(-40, -12 + 60 * u);
      final fade = (u / .08).clamp(0.0, 1.0) *
          (1 - Curves.easeIn.transform(((u - .65) / .35).clamp(0.0, 1.0)));
      _drop(canvas, at, heading, 1 - .2 * u, fade);
    }
  }

  /// A drop at [at], its point trailing back along [heading].
  void _drop(Canvas canvas, Offset at, Offset heading, double scale, double o) {
    if (o <= 0) return;
    // About the picture's own drops: 9 wide, 15 long.
    const r = 4.5;
    canvas.save();
    canvas.translate(at.dx, at.dy);
    // Drawn with its point up; turned so the point trails back toward
    // his head, the way it came, as the picture's own drops are drawn.
    canvas.rotate(math.atan2(-heading.dx, heading.dy));
    canvas.scale(scale);
    final path = Path()
      ..moveTo(0, -2.5 * r)
      ..cubicTo(r * .45, -1.6 * r, r, -.8 * r, r, 0)
      ..arcToPoint(const Offset(-r, 0), radius: const Radius.circular(r))
      ..cubicTo(-r, -.8 * r, -r * .45, -1.6 * r, 0, -2.5 * r)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF9AD6FA).withValues(alpha: o),
            const Color(0xFF3FA7EE).withValues(alpha: o),
          ],
        ).createShader(const Rect.fromLTRB(-r, -2.5 * r, r, r)),
    );
    canvas.drawCircle(
      const Offset(-r * .35, -r * .2),
      r * .32,
      Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: .75 * o),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SweatPainter old) =>
      old.run != run || old.dip != dip;
}

