import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/prestige_tier.dart';

/// The Level Prestige rank mark — one ring that closes, then a second ring
/// inside it that closes, then a solid disc.
///
/// Why this shape and not the tinted icon it replaces: rank order has to be
/// readable *without* reading a colour. Hue is a nominal channel — nothing
/// about emerald says it beats gold — and this app makes that worse than the
/// theory, because two of the eight [PrestigeCatalog] tiers read
/// `GameColors.emerald`/`GameColors.gold`, which the preset system swaps at
/// runtime. On the default preset lvl 20 and lvl 100 are the *identical* hex.
/// (game_theme.dart:105-117 records the same class of bug being fixed once
/// already, for the achievement medal ladder; the prestige ladder was missed.)
///
/// So ordering lives entirely in geometry here, and colour is demoted to a
/// name. Three things climb together and never disagree:
///   * how far the outer ring has closed (rank 1-4),
///   * how far the inner ring has closed (rank 5-7),
///   * ink — opaque coverage of the box runs 4.6% to 72.2%, strictly
///     increasing, a 15.6x spread. See prestigeMarkInkCoverage, which exists
///     so a test can assert the ladder was never accidentally inverted.
///
/// Everything is mirror-symmetric about the vertical axis: each arc is
/// centred on 12 o'clock so its gap sits at 6 o'clock. That is deliberate and
/// load-bearing. A [CustomPainter] does not mirror itself under
/// `Directionality.rtl` — Canvas x always increases left-to-right — while the
/// Row around it flips, so any left-of/right-of element would end up on the
/// wrong side in Arabic. A symmetric figure has no side to get wrong, and it
/// also sidesteps the "is a circular progress arc a progress meter (mirror)
/// or a rotation glyph (don't mirror)" question, which has no good answer.
class PrestigeMarkSpec {
  /// 1-based position on the ladder, matching [PrestigeCatalog.tiers] order.
  final int rank;

  /// Degrees of the outer ring that are drawn, 90 to 360.
  final double outerSweep;

  /// Stroke widths are in the same 100-unit box as the radii, never in
  /// logical pixels — a fixed px stroke inverts the weight ladder across
  /// render sizes (a 2px stroke is most of a 16pt mark and nothing at 200pt).
  final double outerStroke;

  /// 0 until the outer ring has closed.
  final double innerSweep;
  final double innerStroke;

  /// The apex, and the only tier that is filled. It is deliberately the
  /// *simplest* mark on the ladder rather than the busiest: every ladder
  /// surveyed breaks its pattern at the summit by subtracting detail, and the
  /// ones that add it (Dota's Immortal) turn to mush first, at exactly the
  /// size where the top rank most needs to read.
  final bool solid;

  /// The metal this rank wears. Not shown anywhere: it is documentation, and
  /// the thing a reviewer checks the hex against.
  final String metal;

  /// Pinned constants, never a theme token, so no preset can collapse two
  /// rungs together.
  ///
  /// These are the LADDER EVERY RANKED-GAME PLAYER ALREADY KNOWS — bronze,
  /// silver, gold, platinum, diamond, master, grandmaster, champion — because
  /// recognition is the one job colour is good at. Note what colour is NOT
  /// doing here: it is not carrying rank order. It cannot, since bronze is
  /// darker than silver and always will be. Order is carried entirely by ink
  /// mass in the geometry (4.6% to 72.2%, strictly increasing, unit-tested),
  /// which is what frees hue to be conventional instead of monotonic.
  ///
  /// Two colours were moved off the obvious choice because this app had
  /// already spent them: grandmaster is a crimson rather than the usual
  /// orange-red, because #FF5A52 is FAILURE and appears as red crosses in the
  /// same room strip; and diamond is an ice cyan rather than the usual mid
  /// blue, because #5DADEC is the XP icon. Both now clear deltaE 22.
  final Color onDark;

  /// Top stop of the vertical gradient: where the light catches.
  final Color highlightDark;

  /// Bottom stop: the shadowed edge. What makes it read as an object with
  /// thickness rather than a coloured outline.
  final Color shadowDark;

  /// On a light card the mark cannot be lighter than its ground, so every
  /// metal darkens. Hue is preserved so the ladder is still nameable.
  final Color onLight;
  final Color highlightLight;
  final Color shadowLight;

  const PrestigeMarkSpec({
    required this.rank,
    required this.metal,
    required this.outerSweep,
    required this.outerStroke,
    required this.innerSweep,
    required this.innerStroke,
    required this.solid,
    required this.onDark,
    required this.highlightDark,
    required this.shadowDark,
    required this.onLight,
    required this.highlightLight,
    required this.shadowLight,
  });

  Color color(bool dark) => dark ? onDark : onLight;
  Color highlight(bool dark) => dark ? highlightDark : highlightLight;
  Color shadow(bool dark) => dark ? shadowDark : shadowLight;
}

/// Radii in the 100-unit design box. The outer ring's *outer* edge is
/// `_kOuterRadius + outerStroke / 2`, which is what the solid apex fills to,
/// so the apex is also the only mark that reaches the box edge.
const double _kOuterRadius = 42.0;
const double _kInnerRadius = 26.0;

/// Keyed by [PrestigeTier.id] rather than by level, because ids are what
/// `equippedPrestigeTierId` persists and what the catalog's own comments
/// protect. The catalog has been reordered once already (the
/// steadfast/radiant title swap), so nothing here may be derived from list
/// position at runtime.
const Map<String, PrestigeMarkSpec> kPrestigeMarks = {
  'seeker': PrestigeMarkSpec(
    rank: 1,
    metal: 'Bronze',
    outerSweep: 90,
    outerStroke: 7.0,
    innerSweep: 0,
    innerStroke: 0.0,
    solid: false,
    onDark: Color(0xFFC87D3C),
    highlightDark: Color(0xFFF0AE72),
    shadowDark: Color(0xFF7A4418),
    onLight: Color(0xFF8A4E22),
    highlightLight: Color(0xFFB87A45),
    shadowLight: Color(0xFF5A3010),
  ),
  'devoted': PrestigeMarkSpec(
    rank: 2,
    metal: 'Silver',
    outerSweep: 180,
    outerStroke: 7.7,
    innerSweep: 0,
    innerStroke: 0.0,
    solid: false,
    onDark: Color(0xFFC9D2DB),
    highlightDark: Color(0xFFFFFFFF),
    shadowDark: Color(0xFF78848F),
    onLight: Color(0xFF6B7784),
    highlightLight: Color(0xFF98A3AE),
    shadowLight: Color(0xFF454E58),
  ),
  'steadfast': PrestigeMarkSpec(
    rank: 3,
    metal: 'Gold',
    outerSweep: 270,
    outerStroke: 8.4,
    innerSweep: 0,
    innerStroke: 0.0,
    solid: false,
    onDark: Color(0xFFEFB93C),
    highlightDark: Color(0xFFFFE9A8),
    shadowDark: Color(0xFF9A6E10),
    onLight: Color(0xFF8A6206),
    highlightLight: Color(0xFFC29233),
    shadowLight: Color(0xFF5C4104),
  ),
  'radiant': PrestigeMarkSpec(
    rank: 4,
    metal: 'Platinum',
    outerSweep: 360,
    outerStroke: 9.1,
    innerSweep: 0,
    innerStroke: 0.0,
    solid: false,
    onDark: Color(0xFF3FCBB4),
    highlightDark: Color(0xFFA8F0E4),
    shadowDark: Color(0xFF10786A),
    onLight: Color(0xFF0B6E60),
    highlightLight: Color(0xFF33A091),
    shadowLight: Color(0xFF06483E),
  ),
  'luminous': PrestigeMarkSpec(
    rank: 5,
    metal: 'Diamond',
    outerSweep: 360,
    outerStroke: 9.8,
    innerSweep: 90,
    innerStroke: 7.6,
    solid: false,
    onDark: Color(0xFF7FE3F5),
    highlightDark: Color(0xFFDFF9FF),
    shadowDark: Color(0xFF2E93A8),
    onLight: Color(0xFF0F6C86),
    highlightLight: Color(0xFF3C9BB5),
    shadowLight: Color(0xFF08475A),
  ),
  'exalted': PrestigeMarkSpec(
    rank: 6,
    metal: 'Master',
    outerSweep: 360,
    outerStroke: 10.5,
    innerSweep: 180,
    innerStroke: 8.6,
    solid: false,
    onDark: Color(0xFFB07BEA),
    highlightDark: Color(0xFFE2CBFF),
    shadowDark: Color(0xFF6B3EA8),
    onLight: Color(0xFF6B36B0),
    highlightLight: Color(0xFF9463D4),
    shadowLight: Color(0xFF47207A),
  ),
  'venerable': PrestigeMarkSpec(
    rank: 7,
    metal: 'Grandmaster',
    outerSweep: 360,
    outerStroke: 11.2,
    innerSweep: 270,
    innerStroke: 9.6,
    solid: false,
    onDark: Color(0xFFE03A5F),
    highlightDark: Color(0xFFFF8DA5),
    shadowDark: Color(0xFF8E1533),
    onLight: Color(0xFFA3123B),
    highlightLight: Color(0xFFCE4468),
    shadowLight: Color(0xFF700825),
  ),
  'eternal_light': PrestigeMarkSpec(
    rank: 8,
    metal: 'Champion',
    outerSweep: 360,
    outerStroke: 11.9,
    innerSweep: 360,
    innerStroke: 10.6,
    solid: true,
    onDark: Color(0xFFFFF0C2),
    highlightDark: Color(0xFFFFFFFF),
    shadowDark: Color(0xFFC9A961),
    onLight: Color(0xFF3A2C05),
    highlightLight: Color(0xFF6E5518),
    shadowLight: Color(0xFF221900),
  ),
};

PrestigeMarkSpec? prestigeMarkFor(PrestigeTier tier) => kPrestigeMarks[tier.id];

/// Opaque coverage of the design box, 0..1 — the ladder's primary ordering
/// channel, computed rather than measured so a test can assert it is strictly
/// increasing without rasterising anything.
double prestigeMarkInkCoverage(PrestigeMarkSpec s) {
  double annulus(double rCl, double stroke, double sweep) {
    final ro = rCl + stroke / 2, ri = rCl - stroke / 2;
    return math.pi * (ro * ro - ri * ri) * (sweep / 360);
  }

  if (s.solid) {
    final r = _kOuterRadius + s.outerStroke / 2;
    return math.pi * r * r / 10000;
  }
  final outer = annulus(_kOuterRadius, s.outerStroke, s.outerSweep);
  final inner = s.innerSweep <= 0
      ? 0.0
      : annulus(_kInnerRadius, s.innerStroke, s.innerSweep);
  return (outer + inner) / 10000;
}

/// Draws one rank mark at [size] logical pixels square.
///
/// Deliberately has no [PrestigeTier.icon] in it. The eight icons
/// (compass/heart/sun/shield/sparkle/diamond/flame/twilight) are a *themed*
/// set, not a ranked one — a flame will never outrank a diamond by inference
/// — so they stay as identity at large sizes only and may never be the sole
/// difference between two tiers. Delete every icon from the ladder and the
/// ordering test must give the same answer; that is only true if the icon
/// never appears at the sizes where ordering has to survive.
class PrestigeMark extends StatelessWidget {
  final PrestigeMarkSpec spec;
  final double size;

  /// Overrides the tier colour — used by the greyscale check, and by any
  /// surface that wants the mark to take the local ink colour.
  final Color? color;

  /// Runs the apex sheen. OFF by default, and deliberately opt-in rather
  /// than "on whenever the mark is big enough".
  ///
  /// Two reasons, and the second is the one that would bite. A repeating
  /// animation anywhere in the tree makes `pumpAndSettle` hang forever, so a
  /// mark that started its own ticker would break every widget test that
  /// happens to render one. And a ticker that nothing is looking at is still
  /// a ticker: the leaderboard renders six of these per screen.
  final bool animate;

  const PrestigeMark({
    super.key,
    required this.spec,
    required this.size,
    this.color,
    this.animate = false,
  });

  bool get _engraves =>
      spec.solid && color == null && size >= _kApexEngravingMinSize;

  @override
  Widget build(BuildContext context) {
    if (animate && _engraves) {
      return _AnimatedPrestigeMark(spec: spec, size: size);
    }
    return _paint(context, spec: spec, size: size, color: color, sheen: 0);
  }

  static Widget _paint(
    BuildContext context, {
    required PrestigeMarkSpec spec,
    required double size,
    required Color? color,
    required double sheen,
  }) {
    final dark = context.gpDark;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PrestigeMarkPainter(
          spec: spec,
          // An explicit [color] means "paint me in this one ink" — the
          // greyscale check and any surface that wants the local text colour.
          // It also switches the metal off, because a one-colour metal is a
          // contradiction.
          flat: color,
          base: color ?? spec.color(dark),
          highlight: spec.highlight(dark),
          shadow: spec.shadow(dark),
          sheen: sheen,
        ),
      ),
    );
  }
}

/// The sheen's own clock.
///
/// One pass, then a long wait: the band crosses in the first 22% of a cycle
/// and the remaining 3.6 seconds are empty. That ratio is the whole design.
/// A continuous shimmer on a rank you earned once reads as a loading state,
/// and something that moves every frame in the corner of the eye is a thing
/// you end up wanting to turn off. Rare enough to be a reward.
///
/// THREE passes, then it stops for good, and that is not only taste. A
/// controller on `repeat()` never settles, so `pumpAndSettle` on any test
/// that renders this hangs until it times out — which is exactly what
/// happened the first time this ran, in the two summit tests. A finite
/// animation ends, the tree settles, and the tests are testing the real
/// widget rather than a stubbed one.
class _AnimatedPrestigeMark extends StatefulWidget {
  final PrestigeMarkSpec spec;
  final double size;

  const _AnimatedPrestigeMark({required this.spec, required this.size});

  @override
  State<_AnimatedPrestigeMark> createState() => _AnimatedPrestigeMarkState();
}

class _AnimatedPrestigeMarkState extends State<_AnimatedPrestigeMark>
    with SingleTickerProviderStateMixin {
  static const Duration _cycle = Duration(milliseconds: 4600);
  static const double _sweepFraction = 0.22;
  static const int _passes = 3;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _cycle * _passes,
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        // Position within the current pass, then within that pass's sweep.
        final withinCycle = (_c.value * _passes) % 1.0;
        final raw = withinCycle / _sweepFraction;
        // Parked at 1 for the rest of the cycle, which the painter reads as
        // "draw nothing" rather than "draw the band at the bottom".
        final sheen = raw >= 1 ? 1.0 : Curves.easeInOutCubic.transform(raw);
        return PrestigeMark._paint(
          context,
          spec: widget.spec,
          size: widget.size,
          color: null,
          sheen: sheen,
        );
      },
    );
  }
}

/// Local, so this file does not depend on the theme extension's private
/// palette type just to read one bool.
extension on BuildContext {
  bool get gpDark => Theme.of(this).brightness == Brightness.dark;
}

/// Below this the apex stays the plain disc it has always been.
///
/// The ladder orders itself by ink mass, and 12pt in a scrolling leaderboard
/// is where that ordering has to survive; an engraved figure at that size is
/// mud, and mud that costs a save layer per row. So the summit's identity is
/// gated to the sizes that can hold it, which is the same rule this file
/// already states for the tier icons: identity at large sizes only, never the
/// thing that carries rank. Delete the engraving and every ordering test
/// gives the same answer, because [prestigeMarkInkCoverage] is computed from
/// the silhouette and the engraving never leaves it.
const double _kApexEngravingMinSize = 48.0;

/// The apex engraving: thirteen squares in a diamond, being this app's own
/// grid with every cell filled.
///
/// Chosen over a crown, a star or a laurel because those are trophies
/// borrowed from other games, and this one can afford to be a RECORD instead:
/// the thing a hundred levels actually consisted of was filling squares. It
/// is also subtractive — struck INTO the disc rather than piled on top — which
/// keeps the summit the simplest silhouette on the ladder, the property the
/// class doc argues for at length.
///
/// Explicitly NOT light imagery. This tier was renamed off 'Eternal Light'
/// because An-Nur is one of the 99 Names (see PrestigeCatalog's own comment);
/// rays, a halo or a burst would walk the visual straight back to the name
/// that was rejected.
///
/// Rows of 1/3/5/3/1 on a 13-unit pitch, 9.6-unit squares, so the figure is
/// mirror-symmetric about BOTH axes and spans 61.6 of the 84-unit inner face,
/// its furthest corner sitting at radius 31.2 against a rim at 42.
/// Symmetry about the vertical is not decoration: a [CustomPainter] is not
/// mirrored under `Directionality.rtl` while the row around it is, so a figure
/// with a side would end up on the wrong one in Arabic.
const double _kApexPitch = 13.0;
const double _kApexSquare = 9.6;
const List<List<int>> _kApexRows = [
  [2],
  [1, 2, 3],
  [0, 1, 2, 3, 4],
  [1, 2, 3],
  [2],
];

/// The engraved figure, as top-left corners in the 100-unit design box.
///
/// Exposed for the same reason [prestigeMarkInkCoverage] is: so a test can
/// assert the design property EXACTLY rather than squinting at pixels. The
/// property that matters is mirror symmetry about the vertical axis, and the
/// engraving is deliberately low-contrast, so a pixel diff of a shifted
/// square lands inside antialiasing noise and proves nothing. The
/// coordinates do not.
List<Offset> prestigeApexEngravingCells() => [
      for (var row = 0; row < _kApexRows.length; row++)
        for (final col in _kApexRows[row])
          Offset(
            50 + (col - 2) * _kApexPitch - _kApexSquare / 2,
            50 + (row - 2) * _kApexPitch - _kApexSquare / 2,
          ),
    ];

/// The side of one engraved square, in the same 100-unit box.
const double kApexEngravingSquare = _kApexSquare;

/// Below this the gradient is skipped entirely: three stops across a 12pt
/// ring average out to roughly the base colour anyway, and the shader costs a
/// save layer on every one of six marks in a scrolling list.
const double _kMetalMinSize = 16.0;

class _PrestigeMarkPainter extends CustomPainter {
  final PrestigeMarkSpec spec;
  final Color? flat;
  final Color base;
  final Color highlight;
  final Color shadow;

  /// Where the apex sheen has got to, 0..1. Exactly 0 or 1 means "parked",
  /// and nothing is drawn, so a still mark costs no extra paint at all.
  final double sheen;

  const _PrestigeMarkPainter({
    required this.spec,
    required this.flat,
    required this.base,
    required this.highlight,
    required this.shadow,
    this.sheen = 0,
  });

  /// The metal itself: light catching the top, base through the middle, a
  /// shadowed bottom edge, which is what reads as a struck object rather than
  /// a coloured outline.
  ///
  /// VERTICAL, never diagonal, and that is not an aesthetic preference. This
  /// painter is not mirrored under `Directionality.rtl` while the Row around
  /// it is, so a diagonal highlight would be lit from the upper-left in
  /// English and from the upper-right in Arabic with nothing to catch it. A
  /// top-centre light source is the only one that survives both.
  Shader? _metal(Size size) {
    if (flat != null || size.shortestSide < _kMetalMinSize) return null;
    return ui.Gradient.linear(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      [highlight, base, shadow],
      const [0.0, 0.46, 1.0],
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 100.0;
    final centre = Offset(50 * s, 50 * s);
    final shader = _metal(size);

    if (spec.solid) {
      final r = (_kOuterRadius + spec.outerStroke / 2) * s;
      canvas.drawCircle(
        centre,
        r,
        Paint()
          ..color = base
          ..shader = shader
          ..style = PaintingStyle.fill
          ..isAntiAlias = true,
      );
      if (flat == null && size.shortestSide >= _kApexEngravingMinSize) {
        _engrave(canvas, size, s, centre, r);
      }
      return;
    }

    void ring(double rCl, double stroke, double sweepDeg) {
      final paint = Paint()
        ..color = base
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * s
        ..strokeCap = StrokeCap.butt
        ..isAntiAlias = true;
      final r = rCl * s;
      if (sweepDeg >= 360) {
        canvas.drawCircle(centre, r, paint);
        return;
      }
      // Centred on 12 o'clock so the gap lands at 6 o'clock and the figure is
      // symmetric about x — see the class doc for why that is not optional.
      final start = _rad(-90 - sweepDeg / 2);
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: r),
        start,
        _rad(sweepDeg),
        false,
        paint,
      );
    }

    ring(_kOuterRadius, spec.outerStroke, spec.outerSweep);
    if (spec.innerSweep > 0) {
      ring(_kInnerRadius, spec.innerStroke, spec.innerSweep);
    }
  }

  /// Strikes the rim, the grid and the travelling sheen into the apex disc.
  ///
  /// Everything here is clipped to the disc and drawn in the metal's OWN
  /// shadow and highlight rather than a new colour, so the medal still reads
  /// as one struck object instead of a disc with a sticker on it.
  void _engrave(Canvas canvas, Size size, double s, Offset centre, double r) {
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: centre, radius: r)));

    // The raised edge. An inset ring, not an outline: an outline on the
    // silhouette would change the ink the ladder is measured by.
    canvas.drawCircle(
      centre,
      _kOuterRadius * s,
      Paint()
        ..color = shadow.withOpacity(0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * s
        ..isAntiAlias = true,
    );

    final side = _kApexSquare * s;
    final radius = Radius.circular(1.6 * s);
    for (var row = 0; row < _kApexRows.length; row++) {
      for (final col in _kApexRows[row]) {
        final left = centre.dx + (col - 2) * _kApexPitch * s - side / 2;
        final top = centre.dy + (row - 2) * _kApexPitch * s - side / 2;
        final cell = RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, side, side),
          radius,
        );
        canvas.drawRRect(
          cell,
          Paint()
            ..color = shadow.withOpacity(0.70)
            ..isAntiAlias = true,
        );
        // A light lip along the BOTTOM edge only, which is what turns a flat
        // square into a pressed one. Bottom-only rather than bottom-right,
        // because a horizontal offset would have a side and this painter does
        // not get mirrored in Arabic.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(left, top + side - 1.1 * s, side, 1.1 * s),
            Radius.circular(0.5 * s),
          ),
          Paint()
            ..color = highlight.withOpacity(0.30)
            ..isAntiAlias = true,
        );
      }
    }

    // The sheen. A band of light crossing top to bottom, its position given
    // by [sheen] in 0..1; at rest it parks off the top edge and nothing is
    // drawn. Vertical for the same reason the metal gradient is vertical, and
    // the class doc explains that one at length.
    final t = sheen;
    if (t > 0 && t < 1) {
      final bandHeight = 26 * s;
      final travel = size.height + bandHeight * 2;
      final y = -bandHeight + travel * t;
      final band = Rect.fromLTWH(0, y, size.width, bandHeight);
      canvas.drawRect(
        band,
        Paint()
          ..isAntiAlias = true
          ..shader = ui.Gradient.linear(
            Offset(size.width / 2, band.top),
            Offset(size.width / 2, band.bottom),
            [
              highlight.withOpacity(0),
              highlight.withOpacity(0.55),
              highlight.withOpacity(0),
            ],
            const [0.0, 0.5, 1.0],
          ),
      );
    }
    canvas.restore();
  }

  static double _rad(double deg) => deg * math.pi / 180;

  @override
  bool shouldRepaint(_PrestigeMarkPainter old) =>
      old.spec != spec ||
      old.flat != flat ||
      old.base != base ||
      old.highlight != highlight ||
      old.shadow != shadow ||
      old.sheen != sheen;
}
