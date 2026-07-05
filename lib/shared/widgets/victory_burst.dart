import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/game_theme.dart';

/// The celebration language of the app: a physics-based confetti burst fired
/// from the exact point of interaction, the pattern the best trackers on the
/// market (Streaks, Confetti Habits, Duolingo) use for completion moments.
///
/// Implementation follows Flutter particle best practice: a single
/// [CustomPainter] driven by one [AnimationController], a modest particle
/// count, rendered on the root [Overlay] above everything, and removed the
/// frame the animation completes. No dependencies, fully theme-colored.
void showVictoryBurst(
  BuildContext context,
  Offset globalCenter, {
  int particleCount = 16,
  double spread = 72,
  Duration duration = const Duration(milliseconds: 650),
  List<Color>? colors,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => IgnorePointer(
      child: _VictoryBurst(
        center: globalCenter,
        particleCount: particleCount,
        spread: spread,
        duration: duration,
        colors: colors ??
            const [
              GameColors.emerald,
              GameColors.gold,
              GameColors.xpBlue,
              Colors.white,
            ],
        onCompleted: () => entry.remove(),
      ),
    ),
  );
  overlay.insert(entry);
}

/// Convenience for celebrating a widget: fires a burst at the widget's own
/// center right after it mounts. Used by the achievement unlock sheet.
class VictoryBurstOnMount extends StatefulWidget {
  final Widget child;
  final int particleCount;
  final double spread;
  final List<Color>? colors;

  const VictoryBurstOnMount({
    super.key,
    required this.child,
    this.particleCount = 26,
    this.spread = 110,
    this.colors,
  });

  @override
  State<VictoryBurstOnMount> createState() => _VictoryBurstOnMountState();
}

class _VictoryBurstOnMountState extends State<VictoryBurstOnMount> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) return;
      showVictoryBurst(
        context,
        box.localToGlobal(box.size.center(Offset.zero)),
        particleCount: widget.particleCount,
        spread: widget.spread,
        duration: const Duration(milliseconds: 900),
        colors: widget.colors,
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ─── Internals ────────────────────────────────────────────────────────────

class _VictoryBurst extends StatefulWidget {
  final Offset center;
  final int particleCount;
  final double spread;
  final Duration duration;
  final List<Color> colors;
  final VoidCallback onCompleted;

  const _VictoryBurst({
    required this.center,
    required this.particleCount,
    required this.spread,
    required this.duration,
    required this.colors,
    required this.onCompleted,
  });

  @override
  State<_VictoryBurst> createState() => _VictoryBurstState();
}

class _VictoryBurstState extends State<_VictoryBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    final rnd = math.Random();
    _particles = List.generate(widget.particleCount, (i) {
      // Even angular distribution with jitter reads as a clean radial pop
      // rather than random noise, with a slight upward bias so the confetti
      // "jumps" before gravity takes over.
      final angle = (i / widget.particleCount) * 2 * math.pi +
          (rnd.nextDouble() - 0.5) * 0.7;
      return _Particle(
        direction: Offset(math.cos(angle), math.sin(angle) - 0.35),
        distance: widget.spread * (0.55 + rnd.nextDouble() * 0.45),
        size: 2.5 + rnd.nextDouble() * 3.5,
        color: widget.colors[i % widget.colors.length],
        isRect: rnd.nextBool(),
        spin: (rnd.nextDouble() - 0.5) * 10,
      );
    });
    _ctrl = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onCompleted();
      })
      ..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: CustomPaint(
        painter: _BurstPainter(
          progress: _ctrl,
          center: widget.center,
          particles: _particles,
          spread: widget.spread,
        ),
      ),
    );
  }
}

class _Particle {
  final Offset direction;
  final double distance;
  final double size;
  final Color color;
  final bool isRect;
  final double spin;

  const _Particle({
    required this.direction,
    required this.distance,
    required this.size,
    required this.color,
    required this.isRect,
    required this.spin,
  });
}

class _BurstPainter extends CustomPainter {
  final Animation<double> progress;
  final Offset center;
  final List<_Particle> particles;
  final double spread;

  _BurstPainter({
    required this.progress,
    required this.center,
    required this.particles,
    required this.spread,
  }) : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t <= 0 || t >= 1) return;

    // Particles decelerate outward (easeOutCubic) while gravity pulls the
    // tail of the flight down; they fade over the final 45%.
    final radial = Curves.easeOutCubic.transform(t);
    final gravity = 60.0 * t * t;
    final fade = t < 0.55 ? 1.0 : 1.0 - (t - 0.55) / 0.45;

    // Expanding ring ripple under the confetti grounds the burst.
    final ringT = Curves.easeOut.transform(math.min(1, t * 1.6));
    if (ringT < 1) {
      canvas.drawCircle(
        center,
        spread * 0.55 * ringT,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2 * (1 - ringT)
          ..color = GameColors.emerald.withOpacity(0.5 * (1 - ringT)),
      );
    }

    final paint = Paint();
    for (final p in particles) {
      final pos = center +
          p.direction * (p.distance * radial) +
          Offset(0, gravity);
      paint.color = p.color.withOpacity(fade.clamp(0.0, 1.0));
      if (p.isRect) {
        canvas.save();
        canvas.translate(pos.dx, pos.dy);
        canvas.rotate(p.spin * t);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: p.size * 2,
              height: p.size * 1.2,
            ),
            const Radius.circular(1.5),
          ),
          paint,
        );
        canvas.restore();
      } else {
        canvas.drawCircle(pos, p.size * (1 - 0.3 * t), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => false;
}
