import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../core/theme/game_theme.dart';
import '../../core/utils/reduced_motion.dart';

/// The mascot: a green sprout with white leaves and belly, drawn by Aziz with
/// ChatGPT on 2026-09-27 and recoloured, cut and upscaled by tool/mascot (see
/// design/mascot/README.md for every choice made on the art).
///
/// ── The one rule of these files ─────────────────────────────────────────
/// Every file draws the character at the SAME size. The source sheet drew its
/// rows at three different scales, and the pipeline normalised them, so a
/// pose's pixel box is its true size relative to every other pose. That is
/// why [Sprout] takes a scale rather than a height: sized to one shared
/// height, a pose with sparkles above its head would shrink the character
/// and the sleeping one (short and wide) would grow it, and a pose change in
/// place would visibly resize the sprout. [width] and [height] are the files'
/// real pixel sizes, so layout can reserve the exact box before the image has
/// decoded and nothing jumps. sprout_assets_test checks them against the
/// files on disk, and that each is declared in pubspec.yaml.
///
/// The files are lossless WebP: the same pixels as the PNGs the pipeline
/// started from, in about two thirds of the bytes.
enum SproutPose {
  frontWave('mascot_front_wave', 633, 767),
  threeQuarterWave('mascot_three_quarter_wave', 597, 750),
  sideRightLeafUp('mascot_side_right_leaf_up', 382, 787),
  happySparkles('mascot_happy_sparkles', 700, 802),
  laugh('mascot_laugh', 658, 780),
  loveHeart('mascot_love_heart', 649, 784),
  wink('mascot_wink', 669, 780),
  confused('mascot_confused', 668, 777),
  walkBackpack('mascot_walk_backpack', 713, 812),
  pencil('mascot_pencil', 700, 773),
  checklist('mascot_checklist', 679, 778),
  sleeping('mascot_sleeping', 850, 679),
  // For the launch splash (lib/features/launch/launch_scenes.dart): the
  // turn from behind (back, backThreeQuarter, sideRight), the morning mug
  // and the evening thumbs up. The mug and the thumbs up are from the second
  // sheet; the mug never shows on a fasting day or in Ramadan (see
  // pickLaunchScene).
  back('mascot_back', 591, 743),
  backThreeQuarter('mascot_back_three_quarter', 576, 750),
  sideRight('mascot_side_right', 399, 752),
  mug('mascot_mug', 698, 781),
  thumbsUp('mascot_thumbs_up', 730, 815),
  // The launch splash's other scenes (Aziz, 2026-09-29, the canvas's "More
  // ideas"): the first open's pointer, Eid's confetti, Saturday's chart and
  // the new week's fists up, an update's bulb, a slow load's magnifier, the
  // steps goal's run and cheer, a summer noon's sunglasses. All from the
  // second sheet.
  pointer('mascot_pointer', 767, 760),
  confetti('mascot_confetti', 748, 789),
  chart('mascot_chart', 1044, 745),
  determined('mascot_determined', 695, 780),
  idea('mascot_idea', 943, 851),
  magnifier('mascot_magnifier', 716, 783),
  running('mascot_running', 790, 725),
  cheer('mascot_cheer', 699, 789),
  sunglasses('mascot_sunglasses', 640, 792);

  const SproutPose(this.file, this.width, this.height);

  final String file;
  final int width;
  final int height;

  String get asset => 'assets/images/mascot/$file.webp';
}

/// Pixels of the reference pose ([SproutPose.frontWave]) per logical point
/// when the sprout is asked to stand [height] points tall. Every pose is
/// drawn at this one scale.
double sproutScaleFor(double height) => SproutPose.frontWave.height / height;

/// The decoded image for [pose] at the size it is drawn, not the file's.
/// The files are ~750px tall for the largest uses; decoding a 100pt card
/// sprout at full size would hold four times the memory it shows.
ImageProvider sproutImage(SproutPose pose, double scale, double dpr) =>
    ResizeImage(
      AssetImage(pose.asset),
      height: math.max(1, (pose.height / scale * dpr).round()),
      policy: ResizeImagePolicy.fit,
    );

/// Starts the sprout's reactions from outside it: a screen that knows
/// something happened (a square turned green, the day filled up) calls
/// [hop] or [celebrate]; the [Sprout] listening plays the move.
class SproutController extends ChangeNotifier {
  _SproutMove? _move;
  int _serial = 0;

  /// A small jump, 650 ms: something went right.
  void hop() => _fire(_SproutMove.hop);

  /// The big jump, 1.1 s: the day is complete, a streak step, a room done.
  void celebrate() => _fire(_SproutMove.celebrate);

  /// Plays [other]'s latest move here too: a second body of the same
  /// sprout (see SproutEcho) repeating what the first one just did.
  void repeat(SproutController other) {
    final move = other._move;
    if (move != null) _fire(move);
  }

  /// How far the latest move lifts the top of [pose] drawn at [height] (the
  /// Sprout's height) above where it rests, at the move's highest: what a
  /// body with little room over its head checks before playing it. The
  /// keyframes move the height and the stretch together within a segment, so
  /// the highest point is at a keyframe; a tilt lifts one top corner too.
  double lastRise(SproutPose pose, double height) {
    final move = _move;
    if (move == null) return 0;
    final keys = move == _SproutMove.celebrate
        ? _SproutState._partyKeys
        : _SproutState._hopKeys;
    final unit = height / 150;
    final box = Sprout.sizeOf(pose, height);
    var most = 0.0;
    for (final k in keys) {
      final tilt = box.width / 2 * math.sin(k[4].abs() * math.pi / 180);
      most = math.max(most, -k[1] * unit + (k[3] - 1) * box.height + tilt);
    }
    return most;
  }

  void _fire(_SproutMove move) {
    _move = move;
    _serial++;
    notifyListeners();
  }
}

enum _SproutMove { hop, celebrate }

/// How the sprout arrives the first time it is built.
enum SproutEntrance {
  /// Already there. For surfaces that animate in themselves (a sheet, a
  /// dialog) and would otherwise move twice.
  none,

  /// Pops up from its feet with a small overshoot, 420 ms.
  pop,

  /// Pops up, then celebrates: for a surface that exists to celebrate (a
  /// streak step, a room finished, Premium bought).
  popAndCelebrate,

  /// Walks in from the start side with a few small steps, 700 ms: someone
  /// arriving, for the welcome-back card.
  walkIn,
}

/// The mascot, standing on its feet at the bottom centre of its box.
///
/// Every move scales from the feet, so it squashes and stretches like
/// something soft instead of zooming like a picture. It moves when something
/// happens and then rests: the entrance, a hop, a celebration, a tap, each
/// followed by [idleBreaths] slow breaths, then stillness. Never a permanent
/// loop, for the reason _RingStat gives about this same screen: a home screen
/// that is always moving stops reading as a reward and starts reading as a
/// spinner.
///
/// Reduce Motion (see [prefersReducedMotion]) drops every movement. Pose
/// changes still cross-fade, because a fade is not motion and the new pose
/// is information.
class Sprout extends StatefulWidget {
  const Sprout({
    super.key,
    required this.pose,
    required this.height,
    this.controller,
    this.entrance = SproutEntrance.pop,
    this.idleBreaths = 3,
    this.onTap,
    this.semanticLabel,
    this.mirror = false,
  });

  final SproutPose pose;

  /// How tall the reference pose would stand, in logical points. Other poses
  /// are drawn at the same scale, so their boxes differ (see [SproutPose]).
  final double height;

  final SproutController? controller;
  final SproutEntrance entrance;

  /// Breaths after each event before the sprout goes still. 0 for surfaces
  /// that should never move on their own.
  final int idleBreaths;

  final VoidCallback? onTap;

  /// Read by screen readers. Null makes the sprout decorative: most places
  /// it appears, the text beside it already says everything.
  final String? semanticLabel;

  /// Flip it left to right. The art faces right; a pose that goes somewhere
  /// (walking) should face the way the reading goes, so an Arabic screen
  /// mirrors it. The character is symmetric, so nothing else changes.
  final bool mirror;

  /// The logical size [pose] takes at [height]: what a layout reserves.
  static Size sizeOf(SproutPose pose, double height) {
    final scale = sproutScaleFor(height);
    return Size(pose.width / scale, pose.height / scale);
  }

  /// How long a hop and a sleeping breath take.
  static const hopDuration = Duration(milliseconds: 650);
  static const sleepBreathDuration = Duration(milliseconds: 4200);

  /// For what lies on the ground under the sprout (the launch curtain's
  /// shadow), so it keeps to the sprout's own keys: how high a hop has
  /// lifted it at [t], 0 to 1 through [hopDuration], as a share of the
  /// hop's top (0 on the ground, 1 at the top).
  static double hopLiftAt(double t) =>
      -_SproutState._at(_SproutState._hopKeys, t.clamp(0.0, 1.0))[0] / 25;

  /// And how wide a sleeping breath makes it at [t], 0 to 1 through
  /// [sleepBreathDuration], as a horizontal scale.
  static double sleepBreathWidthAt(double t) =>
      _SproutState._at(_SproutState._sleepKeys, t.clamp(0.0, 1.0))[1];

  @override
  State<Sprout> createState() => _SproutState();
}

class _SproutState extends State<Sprout> with TickerProviderStateMixin {
  late final AnimationController _enter;
  late final AnimationController _move;
  late final AnimationController _breath;
  _SproutMove _current = _SproutMove.hop;
  int _seenSerial = 0;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _move = AnimationController(vsync: this);
    _breath = AnimationController(vsync: this);
    widget.controller?.addListener(_onMove);
    _seenSerial = widget.controller?._serial ?? 0;
  }

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = prefersReducedMotion(context);
    if (_started) return;
    _started = true;
    if (_reduced || widget.entrance == SproutEntrance.none) {
      _enter.value = 1;
      _breathe();
    } else if (widget.entrance == SproutEntrance.popAndCelebrate) {
      _enter.forward().whenComplete(() => _play(_SproutMove.celebrate));
    } else if (widget.entrance == SproutEntrance.walkIn) {
      _enter
        ..duration = const Duration(milliseconds: 700)
        ..forward().whenComplete(_breathe);
    } else {
      _enter.forward().whenComplete(_breathe);
    }
  }

  @override
  void didUpdateWidget(covariant Sprout old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_onMove);
      widget.controller?.addListener(_onMove);
      _seenSerial = widget.controller?._serial ?? 0;
    }
  }

  void _onMove() {
    final c = widget.controller!;
    if (c._serial == _seenSerial) return;
    _seenSerial = c._serial;
    _play(c._move!);
  }

  void _play(_SproutMove move) {
    if (_reduced || !mounted) return;
    _current = move;
    _breath.stop();
    _move
      ..duration = _current == _SproutMove.celebrate
          ? const Duration(milliseconds: 1100)
          : Sprout.hopDuration
      ..forward(from: 0).whenComplete(_breathe);
  }

  void _breathe() {
    if (!mounted || _reduced || widget.idleBreaths <= 0) return;
    final sleepy = widget.pose == SproutPose.sleeping;
    _breath
      ..duration = sleepy
          ? Sprout.sleepBreathDuration
          : const Duration(milliseconds: 3200)
      ..value = 0;
    // repeat(count:) would be neater but its future never completes when the
    // widget is disposed mid-way; a counted forward chain stops cleanly.
    var left = widget.idleBreaths;
    void next() {
      if (!mounted || left <= 0) return;
      left--;
      _breath.forward(from: 0).whenComplete(next);
    }

    next();
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onMove);
    _enter.dispose();
    _move.dispose();
    _breath.dispose();
    super.dispose();
  }

  // ── Keyframes ──────────────────────────────────────────────────────────
  // (t, dy in multiples of the jump unit, scaleX, scaleY, rotation degrees),
  // eased per segment. The same numbers as the Motion board on the design
  // canvas, so what was approved is what runs.
  static const _hopKeys = <List<double>>[
    [0.00, 0.0, 1.00, 1.00, 0],
    [0.14, 0.0, 1.08, 0.90, 0],
    [0.38, -22, 0.94, 1.08, 0],
    [0.55, -25, 1.00, 1.00, 0],
    [0.74, 0.0, 1.10, 0.88, 0],
    [0.88, 0.0, 0.97, 1.03, 0],
    [1.00, 0.0, 1.00, 1.00, 0],
  ];
  static const _partyKeys = <List<double>>[
    [0.00, 0.0, 1.00, 1.00, 0],
    [0.10, 0.0, 1.12, 0.84, 0],
    [0.34, -46, 0.92, 1.10, -7],
    [0.52, -50, 1.00, 1.00, 7],
    [0.74, 0.0, 1.12, 0.86, 0],
    [0.88, 0.0, 0.96, 1.04, 0],
    [1.00, 0.0, 1.00, 1.00, 0],
  ];
  static const _breathKeys = <List<double>>[
    [0.00, 0.0, 1.000, 1.000, 0],
    [0.25, 0.0, 1.014, 0.986, -1.2],
    [0.50, 0.0, 0.990, 1.020, 0],
    [0.75, 0.0, 1.014, 0.986, 1.2],
    [1.00, 0.0, 1.000, 1.000, 0],
  ];
  static const _sleepKeys = <List<double>>[
    [0.00, 0.0, 1.000, 1.000, 0],
    [0.50, 0.0, 1.025, 0.975, 0],
    [1.00, 0.0, 1.000, 1.000, 0],
  ];

  static List<double> _at(List<List<double>> keys, double t) {
    for (var i = 1; i < keys.length; i++) {
      final b = keys[i];
      if (t <= b[0]) {
        final a = keys[i - 1];
        final span = b[0] - a[0];
        final u = Curves.easeInOut.transform(span <= 0 ? 1 : (t - a[0]) / span);
        return [
          for (var k = 1; k < 5; k++) lerpDouble(a[k], b[k], u)!,
        ];
      }
    }
    final last = keys.last;
    return [last[1], last[2], last[3], last[4]];
  }

  Widget _mirrored(Image image) => widget.mirror
      ? Transform.flip(key: image.key, flipX: true, child: image)
      : image;

  @override
  Widget build(BuildContext context) {
    final scale = sproutScaleFor(widget.height);
    final size = Sprout.sizeOf(widget.pose, widget.height);
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3;
    // The jump is drawn for a 150pt sprout; smaller ones jump less.
    final unit = widget.height / 150;

    final image = AnimatedSwitcher(
      duration: _reduced
          ? const Duration(milliseconds: 180)
          : const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 120),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (child, animation) {
        final incoming = child.key == ValueKey(widget.pose);
        if (!incoming || _reduced) {
          return FadeTransition(opacity: animation, child: child);
        }
        // A squash at the moment of the swap, springing back: a character
        // changing its pose, not a slideshow changing its picture.
        return AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (_, c) {
            final t = animation.value;
            final spring = Curves.easeOutBack.transform(t);
            return Opacity(
              opacity: (t / 0.4).clamp(0.0, 1.0),
              child: Transform(
                alignment: Alignment.bottomCenter,
                transform: Matrix4.diagonal3Values(
                  lerpDouble(1.08, 1.0, spring)!,
                  lerpDouble(0.88, 1.0, spring)!,
                  1,
                ),
                child: c,
              ),
            );
          },
        );
      },
      child: _mirrored(
        Image(
          key: ValueKey(widget.pose),
          image: sproutImage(widget.pose, scale, dpr),
          width: size.width,
          height: size.height,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          excludeFromSemantics: true,
        ),
      ),
    );

    final moving = AnimatedBuilder(
      animation: Listenable.merge([_enter, _move, _breath]),
      child: image,
      builder: (_, child) {
        var dx = 0.0, dy = 0.0, sx = 1.0, sy = 1.0, rot = 0.0, opacity = 1.0;
        if (!_reduced) {
          final e = _enter.value;
          if (e < 1 && widget.entrance == SproutEntrance.walkIn) {
            // In from the start side, three small steps on the way.
            final along = Curves.easeOut.transform(e);
            final startSide =
                Directionality.of(context) == TextDirection.rtl ? 1.0 : -1.0;
            dx += (1 - along) * 56 * unit * startSide;
            dy -= (math.sin(e * math.pi * 3)).abs() * 5 * unit;
            opacity = Curves.easeOut.transform((e / 0.3).clamp(0.0, 1.0));
          } else if (e < 1) {
            // Entrance: up from the feet with a small overshoot.
            final pop = Curves.easeOutBack.transform(e);
            final grow = lerpDouble(0.3, 1.0, pop)!;
            sx *= grow;
            sy *= grow;
            dy += lerpDouble(40, 0, pop)! * unit;
            opacity = Curves.easeOut.transform((e / 0.35).clamp(0.0, 1.0));
          }
          if (_move.isAnimating) {
            final k = _at(
              _current == _SproutMove.celebrate ? _partyKeys : _hopKeys,
              _move.value,
            );
            dy += k[0] * unit;
            sx *= k[1];
            sy *= k[2];
            rot += k[3];
          } else if (_breath.isAnimating) {
            final k = _at(
              widget.pose == SproutPose.sleeping ? _sleepKeys : _breathKeys,
              _breath.value,
            );
            sx *= k[1];
            sy *= k[2];
            rot += k[3];
          }
        }
        return Opacity(
          opacity: opacity,
          child: Transform(
            alignment: Alignment.bottomCenter,
            transform: Matrix4.translationValues(dx, dy, 0)
              ..rotateZ(rot * math.pi / 180)
              ..multiply(Matrix4.diagonal3Values(sx, sy, 1)),
            child: child,
          ),
        );
      },
    );

    Widget result = SizedBox(
      width: size.width,
      height: size.height,
      child: OverflowBox(
        alignment: Alignment.bottomCenter,
        // Room for the widest pose that can swap in, so the outgoing picture
        // is never squeezed into the incoming one's box mid-fade.
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: moving,
      ),
    );
    if (widget.onTap != null) {
      result = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: result,
      );
    }
    return Semantics(
      label: widget.semanticLabel,
      image: widget.semanticLabel != null,
      button: widget.onTap != null,
      excludeSemantics: true,
      child: result,
    );
  }
}

/// What the sprout says: a small light bubble with its tail pointing down at
/// the sprout. Shown for a moment and gone; see DayCardSprout for when.
class SproutBubble extends StatelessWidget {
  const SproutBubble({
    super.key,
    required this.text,
    this.maxWidth = 170,
    this.tailAtStart = false,
  });

  final String text;
  final double maxWidth;

  /// Which bottom corner is the tail, the one that points at the sprout:
  /// the end corner when the bubble grows toward the start (the day card),
  /// the start corner when it sits the other way round.
  final bool tailAtStart;

  @override
  Widget build(BuildContext context) {
    // Inverted: the theme's text colour as the bubble and its background as
    // the words. The bubble is the one thing on a card that has to read as
    // speech rather than as more of the card, and taking both from the
    // palette keeps it right on every preset, light and dark.
    final gp = context.gp;
    final bg = gp.textPrimary;
    final fg = gp.bg;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadiusDirectional.only(
            topStart: const Radius.circular(14),
            topEnd: const Radius.circular(14),
            bottomStart: Radius.circular(tailAtStart ? 4 : 14),
            bottomEnd: Radius.circular(tailAtStart ? 14 : 4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            text,
            // Centred for the two-line bubbles («يوم مثالي!» over its
            // praise); a one-line bubble shrink-wraps, so it is unchanged.
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.3,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
