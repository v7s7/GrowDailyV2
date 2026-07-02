import 'dart:async';
import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/game_theme.dart';
import '../../../features/dashboard/notifiers/dashboard_notifier.dart';
import '../../../shared/widgets/game_nav_bar.dart';

enum FocusDuration {
  short(25, 30),
  medium(50, 60),
  long(90, 100);

  const FocusDuration(this.minutes, this.xpReward);
  final int minutes;
  final int xpReward;
  int get seconds => minutes * 60;
  String get label => '$minutes min';
}

class FocusTimerScreen extends ConsumerStatefulWidget {
  const FocusTimerScreen({super.key});

  @override
  ConsumerState<FocusTimerScreen> createState() => _FocusTimerScreenState();
}

class _FocusTimerScreenState extends ConsumerState<FocusTimerScreen> {
  FocusDuration _selected = FocusDuration.short;
  late int _remaining = _selected.seconds;
  bool _running = false;
  bool _done = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    if (_done) return;
    HapticFeedback.mediumImpact();
    setState(() => _running = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remaining <= 1) {
        _timer?.cancel();
        setState(() {
          _remaining = 0;
          _running = false;
          _done = true;
        });
        _onComplete();
        return;
      }
      setState(() => _remaining--);
    });
  }

  void _pause() {
    HapticFeedback.lightImpact();
    _timer?.cancel();
    setState(() => _running = false);
  }

  void _reset() {
    HapticFeedback.lightImpact();
    _timer?.cancel();
    setState(() {
      _running = false;
      _done = false;
      _remaining = _selected.seconds;
    });
  }

  void _selectDuration(FocusDuration d) {
    if (_running) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selected = d;
      _remaining = d.seconds;
      _done = false;
    });
  }

  void _onComplete() {
    HapticFeedback.heavyImpact();
    ref.read(dashboardProvider.notifier).awardBonus(xp: _selected.xpReward, gold: 0);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FocusCompleteSheet(duration: _selected),
    );
  }

  String get _timeDisplay {
    final m = _remaining ~/ 60;
    final s = _remaining % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  double get _progress => 1.0 - (_remaining / _selected.seconds);

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Scaffold(
      backgroundColor: gp.bg,
      bottomNavigationBar: const GameNavBar(currentIndex: 1),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: gp.bg,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            title: Text(
              'Focus Timer',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: gp.surface,
                      borderRadius: BorderRadius.circular(GameSpacing.chipRadius),
                      border: Border.all(color: gp.border, width: 0.5),
                    ),
                    child: Row(
                      children: FocusDuration.values.map((d) {
                        final sel = d == _selected;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => _selectDuration(d),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: sel ? GameColors.gold : Colors.transparent,
                                borderRadius:
                                    BorderRadius.circular(GameSpacing.chipRadius - 2),
                              ),
                              child: Text(
                                d.label,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: sel ? Colors.black : gp.textSec,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ).animate().fadeIn(duration: 400.ms),
                  const SizedBox(height: 56),
                  SizedBox(
                    width: 240,
                    height: 240,
                    child: CustomPaint(
                      painter: _TimerRingPainter(
                        progress: _progress,
                        trackColor: gp.border,
                        arcColor: _done
                            ? GameColors.success
                            : _running
                                ? GameColors.xpBlue
                                : GameColors.gold,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _timeDisplay,
                              style: TextStyle(
                                fontSize: 52,
                                fontWeight: FontWeight.w900,
                                color: gp.textPrimary,
                                letterSpacing: -2,
                                height: 1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _done ? 'COMPLETE' : (_running ? 'FOCUSING' : 'READY'),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _done
                                    ? GameColors.success
                                    : (_running ? GameColors.xpBlue : gp.textTert),
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ).animate().fadeIn(duration: 600.ms, delay: 100.ms),
                  const SizedBox(height: 56),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _RoundIconButton(
                        icon: Icons.refresh_rounded,
                        onTap: _reset,
                        bg: gp.surface,
                        fg: gp.textSec,
                        size: 52,
                        iconSize: 22,
                      ),
                      const SizedBox(width: 20),
                      _RoundIconButton(
                        icon: _running
                            ? Icons.pause_rounded
                            : (_done ? Icons.check_rounded : Icons.play_arrow_rounded),
                        onTap: _running ? _pause : (_done ? () {} : _start),
                        bg: _done ? GameColors.success.withOpacity(0.15) : GameColors.gold,
                        fg: _done ? GameColors.success : Colors.black,
                        size: 80,
                        iconSize: 36,
                      ),
                      const SizedBox(width: 20),
                      const SizedBox(width: 52, height: 52),
                    ],
                  ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
                  const SizedBox(height: 32),
                  if (!_done)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.bolt_rounded, size: 14, color: GameColors.xpBlue),
                        const SizedBox(width: 4),
                        Text(
                          '+${_selected.xpReward} XP on completion',
                          style: TextStyle(
                            fontSize: 13,
                            color: gp.textTert,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ).animate(delay: 300.ms).fadeIn(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimerRingPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color arcColor;
  const _TimerRingPainter({
    required this.progress,
    required this.trackColor,
    required this.arcColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    final arc = Paint()
      ..color = arcColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        progress.clamp(0.0, 1.0) * 2 * pi,
        false,
        arc,
      );
    }
  }

  @override
  bool shouldRepaint(_TimerRingPainter old) =>
      old.progress != progress || old.arcColor != arcColor;
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color bg;
  final Color fg;
  final double size;
  final double iconSize;
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    required this.bg,
    required this.fg,
    required this.size,
    required this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(icon, color: fg, size: iconSize),
      ),
    );
  }
}

class _FocusCompleteSheet extends StatelessWidget {
  final FocusDuration duration;
  const _FocusCompleteSheet({required this.duration});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          border: Border.all(color: GameColors.success.withOpacity(0.4), width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: gp.border,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            const SizedBox(height: 28),
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: GameColors.success.withOpacity(0.14),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: GameColors.success.withOpacity(0.28),
                    blurRadius: 28,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Icon(Icons.check_rounded, size: 34, color: GameColors.success),
            )
                .animate()
                .scale(
                    begin: const Offset(0.4, 0.4),
                    curve: Curves.elasticOut,
                    duration: 700.ms)
                .fadeIn(duration: 300.ms),
            const SizedBox(height: 18),
            const Text(
              'FOCUS SESSION COMPLETE',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: GameColors.success,
                letterSpacing: 2,
              ),
            ).animate(delay: 200.ms).fadeIn(),
            const SizedBox(height: 8),
            Text(
              'Deep Work Done',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
                letterSpacing: -0.3,
              ),
            ).animate(delay: 280.ms).fadeIn().slideY(begin: 0.2),
            const SizedBox(height: 6),
            Text(
              'You stayed focused for ${duration.label}. Small sessions build a strong mind.',
              style: TextStyle(fontSize: 14, color: gp.textSec),
              textAlign: TextAlign.center,
            ).animate(delay: 320.ms).fadeIn(),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: GameColors.xpBlue.withOpacity(0.12),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: GameColors.xpBlue.withOpacity(0.3), width: 0.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.bolt_rounded, size: 14, color: GameColors.xpBlue),
                  const SizedBox(width: 5),
                  Text(
                    '+${duration.xpReward} XP',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: GameColors.xpBlue,
                    ),
                  ),
                ],
              ),
            ).animate(delay: 380.ms).fadeIn(),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(context);
                },
                child: const Text('GREAT WORK'),
              ),
            ).animate(delay: 460.ms).fadeIn().slideY(begin: 0.2),
          ],
        ),
      ),
    );
  }
}
