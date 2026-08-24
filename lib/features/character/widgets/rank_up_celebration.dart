import 'dart:ui' as ui show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/victory_burst.dart';
import '../models/prestige_tier.dart';
import 'prestige_mark.dart';

/// The moment a rank is crossed: the mark you already had, closing further.
///
/// ── Why this shape ────────────────────────────────────────────────────────
///
/// The static ladder orders itself by INK MASS, not by colour: the outer arc
/// opens 90, 180, 270, 360 degrees across the first four ranks, then a second
/// ring opens inside it across the next three, then the whole figure floods
/// solid at the summit, with the strokes thickening under all of it (see
/// [kPrestigeMarks] and the invariants in prestige_mark_test.dart). Colour is
/// nominal and can only ever be a name.
///
/// So the celebration animates exactly those channels and invents nothing.
/// The mark is on screen from the first frame at the OLD rank, holds still,
/// then opens to the new one. Nothing appears out of nowhere, which is what
/// makes it read as earned rather than as a reward screen bolted on: the thing
/// being celebrated is visibly the thing the person already had.
///
/// ── The settle is a compression, and that is deliberate ───────────────────
///
/// The landing beat scales the mark DOWN and springs back, like a stamp
/// seating into wax, rather than scaling up. Scaling up on an easeOut from a
/// small centre is the visual grammar of light bursting outward, which is the
/// grammar of النور. This ladder has already renamed three tiers to move away
/// from that association (see the notes on 'radiant', 'luminous' and
/// 'eternal_light' in prestige_tier.dart). Nothing here glows, radiates, or
/// sits on a halo, and the mark is deliberately painted on the bare barrier
/// with no plate behind it: at 96pt it already has mass of its own, so the
/// emphasis is that it is the only object in the frame.
///
/// ── One dial, and it is the ladder's own ──────────────────────────────────
///
/// Every duration, the particle count and the compression depth are a lerp on
/// [_weight], which is [prestigeMarkInkCoverage] normalised across the ladder.
/// There is no per-tier branch anywhere except the one that adds the flood at
/// the summit. Reorder the spec table and this reorders with it for free,
/// which is why the celebration can never disagree with the mark it is about.

/// Normalised ink coverage of [spec], 0 at Bronze and 1 at Champion.
///
/// Bounds computed from the ladder ends rather than hardcoded, so a change to
/// either end moves this with it.
double _weight(PrestigeMarkSpec spec) {
  final all = kPrestigeMarks.values.toList()
    ..sort((a, b) => a.rank.compareTo(b.rank));
  final lo = prestigeMarkInkCoverage(all.first);
  final hi = prestigeMarkInkCoverage(all.last);
  if (hi <= lo) return 0;
  return ((prestigeMarkInkCoverage(spec) - lo) / (hi - lo)).clamp(0.0, 1.0);
}

/// Shows the unlock moment for crossing from [from] into [to].
///
/// Returns as soon as the sheet is closed. Callers do not need to guard on
/// tiers without a mark: the two catalogs are keyed by the same ids, but if
/// one ever drifts this returns without showing anything rather than throwing
/// in the middle of a celebration.
Future<void> showRankUpCelebration(
  BuildContext context, {
  required PrestigeTier from,
  required PrestigeTier to,
}) {
  final fromSpec = prestigeMarkFor(from);
  final toSpec = prestigeMarkFor(to);
  if (fromSpec == null || toSpec == null) return Future<void>.value();

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    // Same barrier as MilestoneCelebration, the app's current biggest moment,
    // so this arrives in the app's own grammar rather than announcing itself
    // with a new one.
    barrierColor: Colors.black.withOpacity(0.85),
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, __, ___) =>
        RankUpCelebration(from: fromSpec, to: toSpec, tier: to),
    transitionBuilder: (ctx, anim, __, child) => FadeTransition(
      opacity: anim,
      child: MediaQuery.disableAnimationsOf(ctx)
          ? child
          : ScaleTransition(
              scale: Tween<double>(begin: 0.90, end: 1.0).animate(
                  CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
              child: child,
            ),
    ),
  );
}

class RankUpCelebration extends StatefulWidget {
  final PrestigeMarkSpec from;
  final PrestigeMarkSpec to;
  final PrestigeTier tier;

  const RankUpCelebration({
    super.key,
    required this.from,
    required this.to,
    required this.tier,
  });

  @override
  State<RankUpCelebration> createState() => _RankUpCelebrationState();
}

class _RankUpCelebrationState extends State<RankUpCelebration>
    with SingleTickerProviderStateMixin {
  static const double _markSize = 96;

  late final double _u = _weight(widget.to);

  // Every scalar in the moment, as a lerp on _u. Champion is the only break
  // in an otherwise smooth ramp, and that is correct: its coverage jumps by a
  // factor of 1.75, the largest step on the whole ladder.
  late final int _holdMs = (220 + 160 * _u).round();
  late final int _travelMs = (400 + 460 * _u).round();
  late final int _settleMs = (240 + 220 * _u).round();
  late final double _depth = 1 - (0.030 + 0.055 * _u);
  late final int _particles = (10 + 20 * _u).round();
  late final double _spread = 84 + 56 * _u;

  late final int _landMs = _holdMs + _travelMs;
  late final int _totalMs = _landMs + _settleMs;

  AnimationController? _c;
  final GlobalKey _markKey = GlobalKey();
  bool _calm = false;
  bool _configured = false;
  bool _landed = false;
  int _hapticQuarters = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_configured) return;
    _configured = true;
    // Read the flag once, here, not in build: the controller's whole layout is
    // decided at construction, so a mid-flight toggle would otherwise leave a
    // half configured animation running.
    _calm = MediaQuery.disableAnimationsOf(context);
    if (_calm) {
      // Reduce Motion means the new mark, at rest, immediately. Not a faster
      // version of the same thing: the sweep IS the content, and a rushed
      // sweep is worse than none.
      HapticFeedback.heavyImpact();
      _landed = true;
      return;
    }
    _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _totalMs),
    )..addListener(_tick);
    _c!.forward();
  }

  /// Haptics are driven off degrees travelled rather than off time, so a
  /// single rung crossing gets one tick and a two rung jump gets two, with no
  /// threshold constant anywhere.
  void _tick() {
    final t = _travelProgress;
    final total = _degreesToTravel;
    final quarters = total <= 0 ? 0 : (t * total / 90).floor();
    if (quarters > _hapticQuarters) {
      _hapticQuarters = quarters;
      HapticFeedback.lightImpact();
    }
    if (!_landed && _c!.value >= _landMs / _totalMs) {
      _landed = true;
      HapticFeedback.heavyImpact();
      final box = _markKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && mounted) {
        showVictoryBurst(
          context,
          box.localToGlobal(box.size.center(Offset.zero)),
          particleCount: _particles,
          spread: _spread,
          duration: const Duration(milliseconds: 900),
          // The moment's own metal, so the burst belongs to this rank rather
          // than to the app's generic celebration palette.
          colors: [
            widget.to.color(_isDark),
            widget.to.highlight(_isDark),
            Colors.white,
          ],
        );
      }
    }
  }

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  double get _degreesToTravel =>
      (widget.to.outerSweep - widget.from.outerSweep).abs() +
      (widget.to.innerSweep - widget.from.innerSweep).abs();

  /// 0 before the hold ends, 1 once the travel window is over.
  double get _rawTravel {
    if (_c == null) return 1;
    final ms = _c!.value * _totalMs;
    if (ms <= _holdMs) return 0;
    return ((ms - _holdMs) / _travelMs).clamp(0.0, 1.0);
  }

  /// At the summit the travel window is shared: the rings close over the first
  /// 60 percent of it and the flood fills the last 40. The flood has to finish
  /// BY the landing frame, because until the figure is solid it is not yet the
  /// new rank, and landing on a rank that has not arrived would be a lie the
  /// haptic tells before the pixels do.
  static const double _sweepShare = 0.6;

  double get _travelProgress => widget.to.solid
      ? (_rawTravel / _sweepShare).clamp(0.0, 1.0)
      : _rawTravel;

  double get _floodProgress => widget.to.solid
      ? ((_rawTravel - _sweepShare) / (1 - _sweepShare)).clamp(0.0, 1.0)
      : 0;

  /// 0 until the mark lands, 1 once it has settled.
  double get _settleProgress {
    if (_c == null) return 1;
    final ms = _c!.value * _totalMs;
    if (ms <= _landMs) return 0;
    return ((ms - _landMs) / _settleMs).clamp(0.0, 1.0);
  }

  /// The two sweeps run in sequence, never in parallel.
  ///
  /// A naive parallel lerp across a two rung jump passes through states no
  /// rung on the ladder actually has (an outer ring at 315 degrees with an
  /// inner ring already at 45), which reads as a glitch rather than as a
  /// promotion. Stage lengths are proportional to how far each channel has to
  /// travel, so a crossing that only moves the inner ring spends the whole
  /// window on it.
  PrestigeMarkSpec get _currentSpec {
    final a = widget.from, b = widget.to;
    final t = Curves.easeInOutCubic.transform(_travelProgress);
    final dOuter = (b.outerSweep - a.outerSweep).abs();
    final dInner = (b.innerSweep - a.innerSweep).abs();
    final total = dOuter + dInner;

    double outerT, innerT;
    if (total <= 0) {
      outerT = innerT = t;
    } else {
      final split = dOuter / total;
      outerT = split <= 0 ? 1 : (t / split).clamp(0.0, 1.0);
      innerT = split >= 1 ? 0 : ((t - split) / (1 - split)).clamp(0.0, 1.0);
    }

    // Strokes run across the WHOLE travel window, underneath both sweep
    // stages. They are the third ordering channel and the only one that
    // separates ranks 4 and 5, where both outer rings are already closed.
    final strokeT = Curves.easeOutCubic.transform(_travelProgress);
    // Colour resolves last, across the settle, so the geometry finishes
    // arguing before the identity is named.
    final colourT = Curves.easeOutCubic.transform(_settleProgress);

    Color mix(Color x, Color y) => Color.lerp(x, y, colourT)!;

    return PrestigeMarkSpec(
      rank: b.rank,
      metal: b.metal,
      outerSweep: ui.lerpDouble(a.outerSweep, b.outerSweep, outerT)!,
      outerStroke: ui.lerpDouble(a.outerStroke, b.outerStroke, strokeT)!,
      innerSweep: ui.lerpDouble(a.innerSweep, b.innerSweep, innerT)!,
      innerStroke: ui.lerpDouble(a.innerStroke, b.innerStroke, strokeT)!,
      // The summit's flood is a clip over the top rather than a spec flag, so
      // the rings underneath keep animating normally right up to the moment
      // they are swallowed.
      solid: false,
      onDark: mix(a.onDark, b.onDark),
      highlightDark: mix(a.highlightDark, b.highlightDark),
      shadowDark: mix(a.shadowDark, b.shadowDark),
      onLight: mix(a.onLight, b.onLight),
      highlightLight: mix(a.highlightLight, b.highlightLight),
      shadowLight: mix(a.shadowLight, b.shadowLight),
    );
  }

  /// The compression. See this file's header for why it is not an expansion.
  double get _settleScale {
    final p = _settleProgress;
    if (p <= 0 || p >= 1) return 1;
    // Down fast, back slow: 35 percent of the window falling, 65 rising.
    if (p < 0.35) {
      return ui.lerpDouble(
          1, _depth, Curves.easeOutQuint.transform(p / 0.35))!;
    }
    return ui.lerpDouble(
        _depth, 1, Curves.easeOutBack.transform((p - 0.35) / 0.65))!;
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isAr = s.isAr;
    final spec = _calm ? widget.to : _currentSpec;
    final ink = widget.to.color(_isDark);
    final total = kPrestigeMarks.length;
    // Text delays are measured from the landing frame, not from mount, so
    // they stay in step with a moment whose own length changes by rank.
    final base = _calm ? 0 : _landMs;

    return Semantics(
      liveRegion: true,
      label: s.rankUpSemantic(widget.tier.title(isAr), widget.to.rank, total),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              s.rankUpEyebrow,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: ink,
                letterSpacing: isAr ? 0 : 3,
              ),
            ).animate(delay: 320.ms).fadeIn(duration: 200.ms),
            const SizedBox(height: 22),
            // No plate, no ring, no shadow. See the header.
            //
            // AnimatedBuilder rather than setState on the whole sheet: the
            // five text lines below run their own staggered flutter_animate
            // entrances, and rebuilding them sixty times a second is both
            // wasted work and a way to make those entrances stutter.
            _c == null
                ? _mark(spec)
                : AnimatedBuilder(
                    animation: _c!,
                    builder: (_, __) => _mark(_currentSpec),
                  ),
            const SizedBox(height: 24),
            // The bare title carries the identity. The eyebrow above already
            // said "new rank" and the line below already says which rung, so
            // wrapping the name in a third sentence about ranks would make one
            // short column say the same noun three times.
            Text(
              widget.tier.title(isAr),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            )
                .animate(delay: (base + 60).ms)
                .fadeIn(duration: 260.ms)
                // slideY and not slideX: horizontal motion has a side, and
                // this app is RTL.
                .slideY(begin: 0.16, end: 0, curve: Curves.easeOutCubic),
            const SizedBox(height: 8),
            Text(
              s.rankUpLadderPosition(widget.to.rank, total),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ).animate(delay: (base + 130).ms).fadeIn(duration: 220.ms),
            const SizedBox(height: 14),
            Text(
              widget.to.solid
                  ? s.rankUpSummitLine
                  : '${s.rankUpMarkGrew}\n${s.rankUpNextAtLevel(_nextLevel)}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Colors.white.withOpacity(0.55),
              ),
            ).animate(delay: (base + 200).ms).fadeIn(duration: 220.ms),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  backgroundColor: GameColors.gold,
                  foregroundColor: GameColors.onGold,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(GameSpacing.cardRadius),
                  ),
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(context);
                },
                child: Text(
                  s.keepGrowing,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
            )
                .animate(delay: (base + 280).ms)
                .fadeIn(duration: 260.ms)
                .slideY(begin: 0.2, end: 0, curve: Curves.easeOutCubic),
          ],
        ),
      ),
    );
  }

  Widget _mark(PrestigeMarkSpec spec) => Transform.scale(
        scale: _settleScale,
        child: _FloodedMark(
          key: _markKey,
          spec: spec,
          solidTarget: widget.to.solid ? widget.to : null,
          size: _markSize,
          floodProgress: _floodProgress,
          calm: _calm,
        ),
      );

  /// The level that opens the next rung, or this one's own when there is no
  /// next. Only ever read on the non summit branch.
  int get _nextLevel {
    for (final t in PrestigeCatalog.tiers) {
      if (t.minLevel > widget.tier.minLevel) return t.minLevel;
    }
    return widget.tier.minLevel;
  }
}

/// The mark, plus the summit's flood on top of it.
///
/// Champion is the one rung where the figure stops being a diagram and becomes
/// an object: coverage jumps by a factor of 1.75, the biggest step after the
/// very first one. It is drawn as a filled disc growing over the two closed
/// rings rather than as a spec change, so the rings keep animating normally
/// right up to the frame they are swallowed.
class _FloodedMark extends StatelessWidget {
  final PrestigeMarkSpec spec;
  final PrestigeMarkSpec? solidTarget;
  final double size;
  final double floodProgress;
  final bool calm;

  const _FloodedMark({
    super.key,
    required this.spec,
    required this.solidTarget,
    required this.size,
    required this.floodProgress,
    required this.calm,
  });

  @override
  Widget build(BuildContext context) {
    final mark = PrestigeMark(spec: spec, size: size);
    final solid = solidTarget;
    if (solid == null) return mark;
    // The sheen runs only once the flood has actually finished arriving. Two
    // things moving over each other during the flood would just read as
    // noise, and the medal has not been struck yet at that point.
    final settled = floodProgress >= 1;
    // calm IS MediaQuery.disableAnimations (see _calm above), so the sheen
    // is exactly the thing it is asking not to happen.
    if (calm) return PrestigeMark(spec: solid, size: size);
    return Stack(
      alignment: Alignment.center,
      children: [
        mark,
        ClipOval(
          clipper: _GrowingCircle(
            Curves.easeInOutCubic.transform(floodProgress.clamp(0.0, 1.0)),
          ),
          child: PrestigeMark(spec: solid, size: size, animate: settled),
        ),
      ],
    );
  }
}

class _GrowingCircle extends CustomClipper<Rect> {
  final double t;
  const _GrowingCircle(this.t);

  @override
  Rect getClip(Size size) => Rect.fromCircle(
        center: size.center(Offset.zero),
        radius: size.shortestSide / 2 * t,
      );

  @override
  bool shouldReclip(_GrowingCircle old) => old.t != t;
}
