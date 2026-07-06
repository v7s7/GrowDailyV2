import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/game_theme.dart';
import '../../features/habits/catalog/islamic_habit_catalog.dart';
import '../../features/habits/models/habit_model.dart';
import 'category_icon.dart';

class HabitCard extends StatefulWidget {
  final IslamicHabitTemplate template;
  final int completions;
  final bool isDone;
  final VoidCallback? onComplete;

  const HabitCard({
    super.key,
    required this.template,
    required this.completions,
    required this.isDone,
    this.onComplete,
  });

  @override
  State<HabitCard> createState() => _HabitCardState();
}

class _HabitCardState extends State<HabitCard> {
  bool _pressed = false;
  bool _justCompleted = false;

  @override
  void didUpdateWidget(HabitCard old) {
    super.didUpdateWidget(old);
    if (!old.isDone && widget.isDone) {
      setState(() => _justCompleted = true);
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) setState(() => _justCompleted = false);
      });
    }
  }

  String _subtitle(BuildContext context) {
    final s = S.of(context);
    final freq = widget.template.frequencyType == HabitFrequencyType.daily
        ? s.habitDaily
        : s.habitWeeklyTimes(widget.template.frequencyTarget);
    final cue = widget.template.cueAfter;
    final cueText = cue == null || cue.isEmpty ? '' : s.habitAfterCue(cue);
    if (widget.template.hasTimer) {
      final mins = (widget.template.timerDurationSeconds ?? 0) ~/ 60;
      return '$freq  ·  ${mins}min$cueText';
    }
    return '$freq$cueText';
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(
          color: widget.isDone ? GameColors.gold.withOpacity(0.4) : gp.border,
          width: widget.isDone ? 1.0 : 0.5,
        ),
        boxShadow: widget.isDone
            ? [
                BoxShadow(
                  color: GameColors.gold.withOpacity(0.07),
                  blurRadius: 16,
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: widget.isDone
                        ? GameColors.gold.withOpacity(0.12)
                        : gp.surfaceHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: CategoryIcon(
                    category: widget.template.category,
                    size: 20,
                    color: widget.isDone ? GameColors.gold : gp.textSec,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.template.name.toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: widget.isDone ? GameColors.gold : gp.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitle(context),
                        style: TextStyle(
                          fontSize: 11,
                          color: gp.textSec,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.template.frequencyTarget > 1)
                  _CompletionDots(
                    total: widget.template.frequencyTarget,
                    filled: widget.completions,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Container(height: 0.5, color: gp.border),
            const SizedBox(height: 14),
            Row(
              children: [
                _RewardTag(
                  icon: Icons.bolt_rounded,
                  text: '+${widget.template.xpReward} XP',
                  color: GameColors.xpBlue,
                ),
                const SizedBox(width: 8),
                _RewardTag(
                  icon: Icons.circle_rounded,
                  text: '+${widget.template.goldReward} G',
                  color: GameColors.gold,
                ),
                const Spacer(),
                GestureDetector(
                  onTapDown: widget.isDone
                      ? null
                      : (_) => setState(() => _pressed = true),
                  onTapUp: widget.isDone
                      ? null
                      : (_) {
                          setState(() => _pressed = false);
                          widget.onComplete?.call();
                        },
                  onTapCancel: widget.isDone
                      ? null
                      : () => setState(() => _pressed = false),
                  child: AnimatedScale(
                    scale: _pressed ? 0.92 : 1.0,
                    duration: const Duration(milliseconds: 100),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: widget.isDone
                            ? GameColors.gold.withOpacity(0.1)
                            : GameColors.gold,
                        borderRadius: BorderRadius.circular(8),
                        border: widget.isDone
                            ? Border.all(
                                color: GameColors.gold.withOpacity(0.35),
                                width: 0.5)
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.isDone
                                ? Icons.check_rounded
                                : Icons.add_rounded,
                            size: 13,
                            color: widget.isDone
                                ? GameColors.gold
                                : Colors.black,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            widget.isDone ? s.habitDone : s.habitComplete,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              color: widget.isDone
                                  ? GameColors.gold
                                  : Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    )
        .animate(target: _justCompleted ? 1 : 0)
        .scaleXY(begin: 1, end: 1.015, duration: 120.ms)
        .then()
        .scaleXY(begin: 1.015, end: 1, duration: 200.ms);
  }
}

class _CompletionDots extends StatelessWidget {
  final int total;
  final int filled;
  const _CompletionDots({required this.total, required this.filled});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Row(
      children: List.generate(total > 7 ? 7 : total, (i) {
        final active = i < filled;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 7,
          height: 7,
          margin: const EdgeInsets.only(left: 5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? GameColors.gold : Colors.transparent,
            border: Border.all(
              color: active ? GameColors.gold : gp.surfaceHL,
              width: 1,
            ),
          ),
        );
      }),
    );
  }
}

class _RewardTag extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _RewardTag(
      {required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}
