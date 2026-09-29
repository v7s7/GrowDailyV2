part of 'launch_scenes.dart';

// The launch scenes from the canvas's "More ideas" page (Aziz, 2026-09-29:
// "fix it all"): the first open's seed, Eid's lights, a full day's squares,
// Saturday's page, an update's bulb, the steps goal's finish flag and a
// summer noon's sun, plus the magnifier a slow load brings out. The same
// rules as the scenes in launch_scenes.dart: what fills, fills with the
// real load ([LaunchSceneView.progress]); the ready moment plays its payoff;
// nothing loops past the curtain; Reduce Motion keeps the pictures still.

const _confettiColours = [
  Color(0xFFF2A7B8),
  Color(0xFF8FD19A),
  Color(0xFFF6CF6E),
  Color(0xFF9CC3EE),
  Color(0xFFE3B04B),
];

extension _MoreScenes on _LaunchSceneViewState {
  /// How much has loaded, as the scenery shows it: all of it once ready.
  double get _loaded => widget.leaving ? 1.0 : widget.progress;

  /// Where [pose]'s picture stands on the curtain, placed as [_doum] places
  /// it (feet on the line, the body centred), before any hop or walk.
  Rect _poseBox(Offset c, SproutPose pose) {
    final size = Sprout.sizeOf(pose, kLaunchDoumHeight);
    final body = kLaunchBodyCentre[pose] ?? .5;
    return Rect.fromLTWH(
      c.dx - body * size.width,
      c.dy + kLaunchFeetBelowCentre - size.height,
      size.width,
      size.height,
    );
  }

  /// A point of [pose]'s picture, as a share of its width and height.
  Offset _prop(Offset c, SproutPose pose, double fx, double fy) {
    final box = _poseBox(c, pose);
    return Offset(box.left + fx * box.width, box.top + fy * box.height);
  }

  Widget _wash(Size size, double opacity, List<Color> colours) => Positioned(
        left: 0,
        top: 0,
        width: size.width,
        height: size.height * .6,
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: colours,
              ),
            ),
          ),
        ),
      );

  /// Bits thrown out from [at] as the app becomes ready.
  Widget _burst(Offset at, double ready, {double reach = 1}) {
    if (widget.reduced || ready <= 0 || ready >= 1) {
      return const SizedBox.shrink();
    }
    return Positioned(
      left: at.dx - 150,
      top: at.dy - 150,
      width: 300,
      height: 300,
      child: IgnorePointer(
        child: CustomPaint(painter: _BurstPainter(t: ready, reach: reach)),
      ),
    );
  }

  /// Short rays flashing out round [at] as the app becomes ready.
  Widget _rays(Offset at, double ready, double size) {
    if (widget.reduced || ready <= 0 || ready >= 1) {
      return const SizedBox.shrink();
    }
    return Positioned(
      left: at.dx - size / 2,
      top: at.dy - size / 2,
      width: size,
      height: size,
      child: CustomPaint(painter: _RaysPainter(t: ready)),
    );
  }

  // ── First open ────────────────────────────────────────────────────────

  /// A seed drops into a mound beside him; the stem climbs as the app
  /// loads and puts out a leaf at each step; when it is ready the bud opens
  /// into a flower whose middle is a square with its tick.
  void _firstOpenScene(
    Size size,
    Offset c,
    double enter,
    double ready,
    List<Widget> behind,
    List<Widget> around,
  ) {
    final feet = c.dy + kLaunchFeetBelowCentre;
    final x = math.min(c.dx + 127, size.width - 34);
    behind.add(
      _wash(size, enter, const [
        Color(0x6BFFDEB0),
        Color(0x2EFFECCE),
        Color(0x00FEFAF0),
      ]),
    );
    behind.add(
      Positioned(
        left: x - 30,
        top: feet - 6,
        width: 60,
        height: 16,
        child: Opacity(
          opacity: enter,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.all(Radius.elliptical(30, 8)),
              gradient: RadialGradient(
                center: Alignment(0, -.3),
                radius: .9,
                colors: [Color(0xFFD8BE92), Color(0xFFC9A87A)],
              ),
            ),
          ),
        ),
      ),
    );
    final t = _t;
    if (!widget.reduced && t < .8) {
      final fall = Curves.easeIn.transform(((t - .1) / .25).clamp(0.0, 1.0));
      final fade = 1 - ((t - .6) / .2).clamp(0.0, 1.0);
      behind.add(
        Positioned(
          left: x - 5,
          top: feet - 150 + 142 * fall,
          width: 10,
          height: 12,
          child: Opacity(
            opacity: (t < .1 ? 0.0 : 1.0) * fade,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFF9A7248),
                borderRadius: BorderRadius.all(Radius.elliptical(5, 6)),
              ),
            ),
          ),
        ),
      );
    }
    final landed =
        widget.reduced ? 1.0 : ((t - .35) / .25).clamp(0.0, 1.0);
    final grow = _loaded * landed;
    final bloom = widget.reduced
        ? (widget.leaving ? 1.0 : 0.0)
        : Curves.easeOutBack.transform(ready.clamp(0.0, 1.0));
    behind.add(
      Positioned(
        left: x - 30,
        top: feet - 140,
        width: 60,
        height: 142,
        child: CustomPaint(
          painter: _PlantPainter(
            grow: grow,
            bloom: bloom,
            sway: widget.reduced ? 0 : math.sin(t * 2.6) * .04,
          ),
        ),
      ),
    );
    around.add(_rays(Offset(x, feet - 128), ready, 96));
  }

  // ── Eid ───────────────────────────────────────────────────────────────

  /// A string of lights drops in and they come on one by one with the
  /// load; when the app is ready he throws confetti and it keeps falling.
  void _eidScene(
    Size size,
    Offset c,
    double enter,
    double ready,
    List<Widget> behind,
    List<Widget> around,
  ) {
    behind.add(
      _wash(size, enter, const [
        Color(0x66F6D6B0),
        Color(0x29FAE4C8),
        Color(0x00FEFAF0),
      ]),
    );
    behind.add(
      Positioned(
        left: c.dx + 77,
        top: c.dy - 210,
        width: 56,
        height: 56,
        child: Opacity(
          opacity: enter,
          child: Transform.scale(
            scale: lerpDouble(.85, 1, enter),
            child: const CustomPaint(
              painter: _CrescentPainter(Color(0xFFD9A441)),
            ),
          ),
        ),
      ),
    );
    final swing =
        widget.reduced ? 0.0 : math.sin(_t * 2) * .8 * math.pi / 180;
    behind.add(
      Positioned(
        left: 0,
        top: c.dy - 304 - 90 * (1 - enter),
        width: size.width,
        height: 150,
        child: Opacity(
          opacity: enter,
          child: Transform.rotate(
            angle: swing,
            alignment: Alignment.topCenter,
            child: CustomPaint(
              painter: _GarlandPainter(
                lit: _loaded,
                flash: widget.reduced ? 0 : math.sin(ready * math.pi),
              ),
            ),
          ),
        ),
      ),
    );
    if (widget.leaving && !widget.reduced) {
      around.add(
        Positioned(
          left: 0,
          top: 0,
          width: size.width,
          height: c.dy + kLaunchFeetBelowCentre,
          child: IgnorePointer(
            child: Opacity(
              opacity: ready.clamp(0.0, 1.0),
              child: CustomPaint(painter: _ConfettiPainter(t: _t)),
            ),
          ),
        ),
      );
    }
    around.add(_burst(Offset(c.dx, c.dy + kLaunchFeetBelowCentre - 90), ready));
  }

  // ── After a full day ──────────────────────────────────────────────────

  /// Yesterday's squares drop in full, one by one with the load; when the
  /// app is ready they hop in a wave and sparkles fly.
  void _fullDayScene(
    Offset c,
    double enter,
    double ready,
    List<Widget> behind,
    List<Widget> around,
  ) {
    behind.add(
      Positioned(
        left: c.dx - 115,
        top: c.dy - 44 - 115,
        width: 230,
        height: 230,
        child: Opacity(
          opacity: enter,
          child: Transform.scale(
            scale: 1 + .12 * math.sin(ready * math.pi),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color(0x8C96D6A0),
                    Color(0x38AADEB2),
                    Color(0x00AADEB2),
                  ],
                  stops: [0, .45, .7],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    const n = 5;
    final x0 = c.dx - (n * 30 + (n - 1) * 9) / 2;
    for (var i = 0; i < n; i++) {
      final wave = widget.reduced
          ? 0.0
          : math.sin(((ready - i * .08) / .5).clamp(0.0, 1.0) * math.pi);
      behind.add(
        Positioned(
          left: x0 + i * 39,
          top: c.dy - 174 - 12 * wave,
          width: 30,
          height: 30,
          child: _DropSquare(
            shown: _loaded >= (i + 1) / n - .001,
            reduced: widget.reduced,
          ),
        ),
      );
    }
    if (widget.leaving) {
      const stars = [
        (-125.0, -122.0, 18.0),
        (123.0, -132.0, 22.0),
        (-137.0, -12.0, 12.0),
        (135.0, -22.0, 14.0),
        (-85.0, -208.0, 12.0),
        (87.0, -216.0, 13.0),
      ];
      for (var i = 0; i < stars.length; i++) {
        final (dx, dy, s) = stars[i];
        final tw = widget.reduced
            ? 1.0
            : .4 + .6 * (.5 + .5 * math.sin((_t / 1.8 + i / 6) * 2 * math.pi));
        around.add(
          Positioned(
            left: c.dx + dx - s / 2,
            top: c.dy + dy - s / 2,
            width: s,
            height: s,
            child: Opacity(
              opacity: (ready * tw).clamp(0.0, 1.0),
              child: const CustomPaint(painter: _StarPainter()),
            ),
          ),
        );
      }
    }
    around.add(_burst(Offset(c.dx, c.dy - 159), ready));
  }

  // ── Saturday ──────────────────────────────────────────────────────────

  /// Last week's page over his head, its days filling as he goes over them
  /// with his chart; when the app is ready the page turns over to a fresh
  /// week and he is set for it.
  void _saturdayScene(
    Offset c,
    double enter,
    double ready,
    List<Widget> behind,
    List<Widget> around,
  ) {
    final turn = widget.reduced
        ? (widget.leaving ? 1.0 : 0.0)
        : Curves.easeIn.transform((ready / .6).clamp(0.0, 1.0));
    behind.add(
      Positioned(
        left: c.dx - 44,
        top: c.dy - 226 - 20 * (1 - enter),
        width: 88,
        height: 96,
        child: Opacity(
          opacity: enter,
          child: _WeekPage(reviewed: _loaded, turn: turn),
        ),
      ),
    );
    // A glint across his chart while he goes over it.
    if (_pose == SproutPose.chart && !widget.reduced) {
      final box = _poseBox(c, SproutPose.chart);
      final board = Rect.fromLTRB(
        box.left + box.width * 640 / 1044,
        box.top + box.height * 122 / 745,
        box.left + box.width * 1010 / 1044,
        box.top + box.height * 502 / 745,
      );
      final sweep = ((_t - .35) / .45).clamp(0.0, 1.0);
      if (sweep > 0 && sweep < 1) {
        around.add(
          Positioned.fromRect(
            rect: board,
            child: ClipRect(
              child: CustomPaint(painter: _GlintPainter(at: sweep)),
            ),
          ),
        );
      }
    }
  }

  // ── After an update ───────────────────────────────────────────────────

  /// The room starts dim; his bulb flickers on and brings the light up with
  /// the load; when the app is ready it flashes, and the room is bright.
  void _updateScene(
    Size size,
    Offset c,
    double enter,
    double ready,
    List<Widget> around,
  ) {
    final bulb = _prop(c, SproutPose.idea, .842, .176);
    final t = _t;
    final dimIn = widget.reduced ? 1.0 : (t / .25).clamp(0.0, 1.0);
    final flick = !widget.reduced &&
        ((t > .45 && t < .5) || (t > .58 && t < .62));
    final dim = dimIn * (1 - _loaded) * (flick ? .6 : 1);
    if (dim > 0) {
      around.add(
        Positioned.fill(
          child: IgnorePointer(
            child: Opacity(
              opacity: dim.clamp(0.0, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(
                      bulb.dx / size.width * 2 - 1,
                      bulb.dy / size.height * 2 - 1,
                    ),
                    radius: 1.2,
                    colors: const [
                      Color(0x59172131),
                      Color(0x9E172131),
                      Color(0xB3172131),
                    ],
                    stops: const [0, .3, 1],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    final on = widget.reduced || t > .45;
    final glow = on
        ? (.3 + .6 * _loaded + (flick ? -.25 : 0)).clamp(0.0, 1.0)
        : 0.0;
    around.add(
      Positioned(
        left: bulb.dx - 70,
        top: bulb.dy - 70,
        width: 140,
        height: 140,
        child: IgnorePointer(
          child: Opacity(
            opacity: (glow * enter).clamp(0.0, 1.0),
            child: Transform.scale(
              scale: 1 + .5 * math.sin(ready * math.pi),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Color(0xF2FFDE78),
                      Color(0x66FFD66E),
                      Color(0x00FFD66E),
                    ],
                    stops: [0, .35, .68],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // The bulb itself reads as off until it flickers on.
    final off = widget.reduced ? 0.0 : (t < .45 ? enter : (flick ? .7 : 0.0));
    if (off > 0) {
      around.add(
        Positioned(
          left: bulb.dx - 13.5,
          top: bulb.dy - 15,
          width: 27,
          height: 27,
          child: Opacity(
            opacity: off,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0x8C787878),
              ),
            ),
          ),
        ),
      );
    }
    around.add(_rays(bulb, ready, 120));
  }

  // ── Steps goal ────────────────────────────────────────────────────────

  /// He runs in along a track, dust at his heels, to the finish flag on
  /// the side he is heading for; when the app is ready he cheers and bits
  /// fly off the flag.
  void _stepsScene(
    Size size,
    Offset c,
    bool rtl,
    double enter,
    double ready,
    List<Widget> behind,
    List<Widget> around,
  ) {
    final feet = c.dy + kLaunchFeetBelowCentre;
    final ahead = rtl ? -1.0 : 1.0;
    final running = !widget.reduced && _enter.value < .98;
    behind.add(
      Positioned(
        left: 0,
        top: feet + 2,
        width: size.width,
        height: 2,
        child: Opacity(
          opacity: enter,
          child: const ColoredBox(color: Color(0xFFE4DBC6)),
        ),
      ),
    );
    if (running) {
      behind.add(
        Positioned(
          left: 0,
          top: feet + 12,
          width: size.width,
          height: 3,
          child: Opacity(
            opacity: 1 - _enter.value,
            child: CustomPaint(
              painter: _LanePainter(shift: (_t * 80 * ahead) % 40),
            ),
          ),
        ),
      );
    }
    final flagX = c.dx + 105 * ahead;
    behind.add(
      Positioned(
        left: flagX - (rtl ? 36 : 2),
        top: feet - 84,
        width: 40,
        height: 86,
        child: Opacity(
          opacity: enter,
          child: CustomPaint(
            painter: _FlagPainter(
              wave: widget.reduced ? 0 : math.sin(_t * 5.7),
              mirror: rtl,
            ),
          ),
        ),
      ),
    );
    if (running) {
      final walk = _walk(rtl);
      final heel = c.dx + walk.dx - 50 * ahead;
      for (var i = 0; i < 3; i++) {
        final p = ((_t * 2) + i / 3) % 1;
        final r = 5 + 7 * p;
        around.add(
          Positioned(
            left: heel - 18 * p * ahead - r,
            top: feet - 8 - 8 * p - r,
            width: r * 2,
            height: r * 2,
            child: Opacity(
              opacity: (.8 * (1 - p)).clamp(0.0, 1.0),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFE4D7BC),
                ),
              ),
            ),
          ),
        );
      }
    }
    around.add(_burst(Offset(flagX + 18 * ahead, feet - 72), ready, reach: .7));
  }

  // ── Summer noon ───────────────────────────────────────────────────────

  /// The sky warms and the sun climbs with the load; he squints, then puts
  /// his sunglasses on with a glint, which comes again when the app is
  /// ready. Heat rises off the ground.
  void _summerScene(
    Size size,
    Offset c,
    double enter,
    double ready,
    List<Widget> behind,
    List<Widget> around,
  ) {
    final feet = c.dy + kLaunchFeetBelowCentre;
    behind.add(
      _wash(size, enter * (.45 + .55 * _loaded), const [
        Color(0x6BFFC478),
        Color(0x38FFD6A0),
        Color(0x00FEFAF0),
      ]),
    );
    final climb =
        Curves.easeOut.transform(math.max(.5 * enter, _loaded).clamp(0.0, 1.0));
    behind.add(
      Positioned(
        left: c.dx + 41 - 40 * (1 - climb),
        top: c.dy - 326 + 180 * (1 - climb),
        width: 128,
        height: 128,
        child: Opacity(
          opacity: enter,
          child: CustomPaint(
            painter: _SunPainter(spin: widget.reduced ? 0 : _t * .4),
          ),
        ),
      ),
    );
    if (!widget.reduced) {
      const spots = [(-125.0, -54.0), (-97.0, -38.0), (97.0, -58.0), (123.0, -40.0)];
      for (var i = 0; i < spots.length; i++) {
        final p = ((_t / 2.2) + i / 4) % 1;
        behind.add(
          Positioned(
            left: c.dx + spots[i].$1,
            top: feet + spots[i].$2 - 36 * p,
            width: 12,
            height: 42,
            child: Opacity(
              opacity: (enter * (p < .3 ? p / .3 : 1 - (p - .3) / .7) * .75)
                  .clamp(0.0, 1.0),
              child: const CustomPaint(painter: _HeatPainter()),
            ),
          ),
        );
      }
    }
    // The glint across his lenses: once as they go on, once more when ready.
    if (_pose == SproutPose.sunglasses && !widget.reduced) {
      final on = _shadesAt;
      final first = on == null ? 1.0 : ((_t - on) / .35).clamp(0.0, 1.0);
      final sweep = widget.leaving ? (ready / .6).clamp(0.0, 1.0) : first;
      if (sweep > 0 && sweep < 1) {
        final box = _poseBox(c, SproutPose.sunglasses);
        for (final (a, b, cc, d) in const [
          (124.0, 362.0, 320.0, 482.0),
          (336.0, 362.0, 490.0, 482.0),
        ]) {
          around.add(
            Positioned.fromRect(
              rect: Rect.fromLTRB(
                box.left + box.width * a / 640,
                box.top + box.height * b / 792,
                box.left + box.width * cc / 640,
                box.top + box.height * d / 792,
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(3),
                  bottom: Radius.circular(10),
                ),
                child: CustomPaint(painter: _GlintPainter(at: sweep)),
              ),
            ),
          );
        }
      }
    }
  }

  // ── A slow load ───────────────────────────────────────────────────────

  /// A glint going round his magnifier's lens while he looks.
  Widget _lens(Offset c) {
    if (widget.reduced) return const SizedBox.shrink();
    final lens = _prop(c, SproutPose.magnifier, .698, .562);
    final since = _searchedAt == null ? 1.0 : ((_t - _searchedAt!) / .2);
    return Positioned(
      left: lens.dx - 13,
      top: lens.dy - 13,
      width: 26,
      height: 26,
      child: Opacity(
        opacity: since.clamp(0.0, 1.0),
        child: CustomPaint(painter: _LensGlintPainter(angle: _t * 4.5)),
      ),
    );
  }
}

/// One of the Grid's squares, full, dropping in when [shown].
class _DropSquare extends StatelessWidget {
  const _DropSquare({required this.shown, required this.reduced});

  final bool shown;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: shown ? 1 : 0),
      duration: Duration(milliseconds: reduced ? 0 : 320),
      curve: Curves.easeOutBack,
      builder: (_, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, -14 * (1 - v)),
          child: Transform.scale(scale: lerpDouble(.5, 1, v), child: child),
        ),
      ),
      child: const DecoratedBox(
        decoration: BoxDecoration(
          color: _green,
          borderRadius: BorderRadius.all(Radius.circular(9)),
        ),
        child: Center(
          child: CustomPaint(size: Size(16, 16), painter: _TickPainter()),
        ),
      ),
    );
  }
}

/// A tear-off calendar page: last week's days filling ([reviewed], 0 to 1)
/// on the top leaf, which [turn] (0 to 1) folds back over the top to show
/// a fresh week underneath.
class _WeekPage extends StatelessWidget {
  const _WeekPage({required this.reviewed, required this.turn});

  final double reviewed;
  final double turn;

  static const _paper = Color(0xFFFFFDF6);
  static const _edge = Color(0xFFDCD3BC);

  Widget _dots(Color Function(int i) colour) => SizedBox(
        width: 60,
        child: Wrap(
          spacing: 7,
          runSpacing: 6,
          children: [
            for (var i = 0; i < 7; i++)
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: colour(i),
                  borderRadius: const BorderRadius.all(Radius.circular(3)),
                ),
              ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final angle = -turn * 92 * math.pi / 180;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          top: 10,
          width: 88,
          height: 86,
          child: Container(
            decoration: BoxDecoration(
              color: _paper,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _edge, width: 1.5),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x143C321E),
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 14,
          top: 48,
          child: _dots((_) => const Color(0xFFEFE9D8)),
        ),
        if (turn < 1)
          Positioned(
            left: 0,
            top: 34,
            width: 88,
            height: 62,
            child: Transform(
              alignment: Alignment.topCenter,
              transform: Matrix4.identity()
                ..setEntry(3, 2, .004)
                ..rotateX(angle),
              child: Container(
                decoration: const BoxDecoration(
                  color: _paper,
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
                  border: Border(
                    left: BorderSide(color: _edge, width: 1.5),
                    right: BorderSide(color: _edge, width: 1.5),
                    bottom: BorderSide(color: _edge, width: 1.5),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(12.5, 12.5, 0, 0),
                alignment: Alignment.topLeft,
                child: _dots(
                  (i) => reviewed >= (i + 1) / 7 - .001
                      ? const Color(0xFFCDBEA3)
                      : const Color(0xFFEFE9D8),
                ),
              ),
            ),
          ),
        Positioned(
          left: 0,
          top: 10,
          width: 88,
          height: 24,
          child: Container(
            decoration: const BoxDecoration(
              color: _green,
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            ),
          ),
        ),
        for (final x in const [22.0, 59.0])
          Positioned(
            left: x,
            top: 2,
            width: 7,
            height: 16,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                color: kLaunchInk,
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
            ),
          ),
      ],
    );
  }
}

/// The first open's plant: a stem climbing to [grow] of its height, three
/// leaves opening on the way, a bud at the top, and at [bloom] a flower of
/// Doum's cream petals round a square with its tick.
class _PlantPainter extends CustomPainter {
  const _PlantPainter({
    required this.grow,
    required this.bloom,
    required this.sway,
  });

  final double grow;
  final double bloom;
  final double sway;

  static const _leafAt = [(112.0, -1.0, .35), (84.0, 1.0, .6), (58.0, -1.0, .82)];

  @override
  void paint(Canvas canvas, Size size) {
    if (grow <= 0 && bloom <= 0) return;
    canvas.save();
    canvas.translate(30, 140);
    canvas.rotate(sway);
    canvas.translate(-30, -140);
    final stem = Path()
      ..moveTo(30, 140)
      ..cubicTo(26, 112, 34, 86, 30, 58)
      ..cubicTo(27, 38, 31, 24, 30, 12);
    final metric = stem.computeMetrics().first;
    final drawn = metric.extractPath(0, metric.length * grow.clamp(0.0, 1.0));
    canvas.drawPath(
      drawn,
      Paint()
        ..color = _green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    final outline = Paint()
      ..color = kLaunchInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round;
    for (final (y, side, at) in _leafAt) {
      final open = Curves.easeOutBack
          .transform(((grow - at) / .15).clamp(0.0, 1.0));
      if (open <= 0) continue;
      canvas.save();
      canvas.translate(30, y);
      canvas.scale(open);
      final leaf = Path()
        ..moveTo(0, 0)
        ..cubicTo(8 * side, 0, 17 * side, -6, 19 * side, -16)
        ..cubicTo(10 * side, -18, 2 * side, -10, 0, 0)
        ..close();
      canvas.drawPath(leaf, Paint()..color = const Color(0xFF74C878));
      canvas.drawPath(leaf, outline);
      canvas.restore();
    }
    final bud = Curves.easeOutBack.transform(((grow - .9) / .1).clamp(0.0, 1.0)) *
        (1 - bloom).clamp(0.0, 1.0);
    if (bud > 0) {
      canvas.drawCircle(
        const Offset(30, 12),
        7 * bud,
        Paint()..color = const Color(0xFF74C878),
      );
      canvas.drawCircle(const Offset(30, 12), 7 * bud, outline);
    }
    if (bloom > 0) {
      canvas.save();
      canvas.translate(30, 12);
      canvas.scale(bloom);
      canvas.rotate((1 - bloom) * -.7);
      final petal = Paint()..color = const Color(0xFFF5F0E1);
      for (final (dx, dy, w, h) in const [
        (0.0, -13.0, 14.0, 20.0),
        (0.0, 13.0, 14.0, 20.0),
        (-13.0, 0.0, 20.0, 14.0),
        (13.0, 0.0, 20.0, 14.0),
      ]) {
        final r = Rect.fromCenter(center: Offset(dx, dy), width: w, height: h);
        canvas.drawOval(r, petal);
        canvas.drawOval(r, outline);
      }
      final square = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 15, height: 15),
        const Radius.circular(4),
      );
      canvas.drawRRect(square, Paint()..color = _green);
      canvas.drawRRect(square, outline);
      canvas.drawPath(
        Path()
          ..moveTo(-4, .5)
          ..lineTo(-1, 3.2)
          ..lineTo(4, -3),
        Paint()
          ..color = const Color(0xFFFEFAF0)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PlantPainter old) =>
      old.grow != grow || old.bloom != bloom || old.sway != sway;
}

/// Eid's string of seven lights, hanging in a curve across the screen:
/// each lit once [lit] passes its share, all flaring with [flash].
class _GarlandPainter extends CustomPainter {
  const _GarlandPainter({required this.lit, required this.flash});

  final double lit;
  final double flash;

  static const _colours = [
    Color(0xFFF6CF6E),
    Color(0xFFF2A7B8),
    Color(0xFF8FD19A),
    Color(0xFF9CC3EE),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    canvas.drawPath(
      Path()
        ..moveTo(-4, 0)
        ..quadraticBezierTo(w / 2, 114, w + 4, 0),
      Paint()
        ..color = const Color(0xFF8C7A5B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    for (var i = 0; i < 7; i++) {
      final t = (i + 1) / 8;
      final x = w * t;
      final y = 2 * (1 - t) * t * 114;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - 3, y, 6, 5),
          const Radius.circular(1),
        ),
        Paint()..color = const Color(0xFF8C7A5B),
      );
      final bulb = Rect.fromCenter(center: Offset(x, y + 12), width: 13, height: 16);
      final on = lit >= (i + 1) / 7 - .001;
      final colour = _colours[i % _colours.length];
      if (on) {
        canvas.drawCircle(
          bulb.center,
          10 + 8 * flash,
          Paint()
            ..color = colour.withValues(alpha: .55)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
        );
      }
      canvas.drawOval(bulb, Paint()..color = on ? colour : const Color(0xFFEFE9D8));
      if (!on) {
        canvas.drawOval(
          bulb,
          Paint()
            ..color = const Color(0xFFDCD3BC)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GarlandPainter old) =>
      old.lit != lit || old.flash != flash;
}

/// Confetti falling from the top, swaying and turning, on a loop of [t].
class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter({required this.t});

  final double t;

  static const _pieces = [
    (.06, 0.0, 7.0, 11.0, 2.6), (.15, 1.3, 6.0, 9.0, 2.9),
    (.25, .5, 8.0, 5.0, 2.4), (.34, 2.0, 6.0, 10.0, 3.0),
    (.44, .9, 7.0, 7.0, 2.7), (.53, 1.7, 5.0, 10.0, 2.5),
    (.61, .2, 8.0, 6.0, 2.8), (.69, 1.1, 6.0, 11.0, 2.6),
    (.78, 2.3, 7.0, 8.0, 3.1), (.87, .6, 6.0, 10.0, 2.5),
    (.94, 1.5, 8.0, 6.0, 2.9), (.1, 2.6, 5.0, 9.0, 2.8),
    (.39, 2.8, 7.0, 5.0, 2.6), (.65, 2.9, 6.0, 9.0, 3.0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < _pieces.length; i++) {
      final (x, delay, w, h, dur) = _pieces[i];
      final p = ((t + delay) / dur) % 1;
      canvas.save();
      canvas.translate(
        size.width * x + math.sin(p * 2 * math.pi) * 8,
        -20 + (size.height + 40) * p,
      );
      canvas.rotate(p * 9.8);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: w, height: h),
          const Radius.circular(2),
        ),
        Paint()..color = _confettiColours[i % _confettiColours.length],
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}

/// Bits flying out from the middle as [t] runs 0 to 1, then falling away.
class _BurstPainter extends CustomPainter {
  const _BurstPainter({required this.t, this.reach = 1});

  final double t;
  final double reach;

  static const _dirs = [
    (-96.0, -76.0), (-62.0, -118.0), (-14.0, -134.0), (40.0, -124.0),
    (88.0, -88.0), (112.0, -30.0), (-116.0, -24.0), (66.0, -146.0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final out = Curves.easeOutCubic.transform((t / .6).clamp(0.0, 1.0));
    final fade = 1 - ((t - .55) / .45).clamp(0.0, 1.0);
    if (fade <= 0) return;
    final c = size.center(Offset.zero);
    for (var i = 0; i < _dirs.length; i++) {
      final (dx, dy) = _dirs[i];
      canvas.save();
      canvas.translate(
        c.dx + dx * reach * out,
        c.dy + dy * reach * out + 22 * ((t - .5).clamp(0.0, 1.0)),
      );
      canvas.rotate(out * 3.5 * (i.isEven ? 1 : -1));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 7, height: 9),
          const Radius.circular(2),
        ),
        Paint()
          ..color = _confettiColours[i % _confettiColours.length]
              .withValues(alpha: fade),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) => old.t != t;
}

/// Eight short rays flashing out as [t] runs 0 to 1.
class _RaysPainter extends CustomPainter {
  const _RaysPainter({required this.t});

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final a = t < .25 ? t / .25 : 1 - (t - .25) / .75;
    if (a <= 0) return;
    final c = size.center(Offset.zero);
    final r = size.width / 2 * lerpDouble(.55, 1, t)!;
    final paint = Paint()
      ..color = const Color(0xFFE3B04B).withValues(alpha: a.clamp(0.0, 1.0))
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4;
      final d = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(c + d * r * .62, c + d * r * .82, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RaysPainter old) => old.t != t;
}

/// A four-point sparkle, gold.
class _StarPainter extends CustomPainter {
  const _StarPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    canvas.scale(s);
    canvas.drawPath(
      Path()
        ..moveTo(12, 0)
        ..cubicTo(13, 7, 17, 11, 24, 12)
        ..cubicTo(17, 13, 13, 17, 12, 24)
        ..cubicTo(11, 17, 7, 13, 0, 12)
        ..cubicTo(7, 11, 11, 7, 12, 0)
        ..close(),
      Paint()..color = const Color(0xFFF2C14E),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// A soft white bar sweeping across the box, [at] 0 to 1.
class _GlintPainter extends CustomPainter {
  const _GlintPainter({required this.at});

  final double at;

  @override
  void paint(Canvas canvas, Size size) {
    final x = -16 + (size.width + 32) * at;
    canvas.save();
    canvas.translate(x, size.height / 2);
    canvas.rotate(20 * math.pi / 180);
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: 12,
      height: size.height * 2,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0x00FFFFFF), Color(0xBFFFFFFF), Color(0x00FFFFFF)],
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GlintPainter old) => old.at != at;
}

/// A short bright arc going round the magnifier's lens.
class _LensGlintPainter extends CustomPainter {
  const _LensGlintPainter({required this.angle});

  final double angle;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawArc(
      Rect.fromCircle(center: size.center(Offset.zero), radius: 9.5),
      angle,
      .9,
      false,
      Paint()
        ..color = const Color(0xD9FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _LensGlintPainter old) => old.angle != angle;
}

/// The track's lane marks, drifting back as he runs.
class _LanePainter extends CustomPainter {
  const _LanePainter({required this.shift});

  final double shift;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFE4DBC6);
    for (var x = -40.0 - shift; x < size.width + 40; x += 40) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 20, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LanePainter old) => old.shift != shift;
}

/// The finish: a pole and a chequered flag waving ([wave], -1 to 1),
/// flying away from the side he comes from.
class _FlagPainter extends CustomPainter {
  const _FlagPainter({required this.wave, required this.mirror});

  final double wave;
  final bool mirror;

  @override
  void paint(Canvas canvas, Size size) {
    if (mirror) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, 4, size.height),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFF8C7A5B),
    );
    canvas.save();
    canvas.translate(4, 2);
    canvas.skew(0, math.tan(wave * 4 * math.pi / 180));
    const cell = 34 / 6;
    for (var r = 0; r < 4; r++) {
      for (var col = 0; col < 6; col++) {
        canvas.drawRect(
          Rect.fromLTWH(col * cell, r * 6, cell, 6),
          Paint()
            ..color = (r + col).isEven ? kLaunchInk : const Color(0xFFFEFAF0),
        );
      }
    }
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 34, 24),
      Paint()
        ..color = kLaunchInk
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FlagPainter old) =>
      old.wave != wave || old.mirror != mirror;
}

/// The summer sun: a warm glow, rays turning slowly ([spin]), the disc.
class _SunPainter extends CustomPainter {
  const _SunPainter({required this.spin});

  final double spin;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.drawCircle(
      c,
      80,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x73FFC460), Color(0x2EFFCE78), Color(0x00FFCE78)],
          stops: [0, .5, 1],
        ).createShader(Rect.fromCircle(center: c, radius: 80)),
    );
    final ray = Paint()
      ..color = const Color(0xFFF2BF55)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 12; i++) {
      final a = spin + i * math.pi / 6;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * 38, c + d * 50, ray);
    }
    canvas.drawCircle(c, 24, Paint()..color = const Color(0xFFF6C35B));
  }

  @override
  bool shouldRepaint(covariant _SunPainter old) => old.spin != spin;
}

/// One wavy line of heat rising off the ground.
class _HeatPainter extends CustomPainter {
  const _HeatPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(6, 41)
        ..cubicTo(1, 34, 11, 28, 6, 21)
        ..cubicTo(1, 14, 11, 8, 6, 1),
      Paint()
        ..color = const Color(0x99D6A060)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
