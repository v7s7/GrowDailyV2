import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/utils/reduced_motion.dart';
import 'sprout.dart';

/// The sprout turning to face you: side, three-quarter, front, then a hop.
/// A first meeting, for the first-run screen.
///
/// Each step is a pose change, so each one gets [Sprout]'s squash-and-spring
/// swap and the turn reads as a character moving rather than three pictures.
/// Reduce Motion skips straight to the front pose.
class SproutTurnaround extends StatefulWidget {
  const SproutTurnaround({super.key, required this.height});

  final double height;

  @override
  State<SproutTurnaround> createState() => _SproutTurnaroundState();
}

class _SproutTurnaroundState extends State<SproutTurnaround> {
  static const _steps = [
    SproutPose.sideRightLeafUp,
    SproutPose.threeQuarterWave,
    SproutPose.frontWave,
  ];

  final _moves = SproutController();
  final _timers = <Timer>[];
  int _step = 0;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (prefersReducedMotion(context)) {
      _step = _steps.length - 1;
      return;
    }
    // After the entrance pop (420 ms): turn, turn, then say hello.
    _timers
      ..add(Timer(const Duration(milliseconds: 750), () => _to(1)))
      ..add(Timer(const Duration(milliseconds: 1150), () => _to(2)))
      ..add(Timer(const Duration(milliseconds: 1500), _moves.hop));
  }

  void _to(int step) {
    if (mounted) setState(() => _step = step);
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _moves.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // One box for every step, the tallest one's, feet on its floor: the side
    // view stands 4pt taller than the front at 160, and a box that followed
    // each pose would nudge the text under it on every turn.
    final tallest = _steps
        .map((p) => Sprout.sizeOf(p, widget.height).height)
        .reduce((a, b) => a > b ? a : b);
    return SizedBox(
      height: tallest,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Sprout(
          pose: _steps[_step],
          height: widget.height,
          controller: _moves,
        ),
      ),
    );
  }
}
