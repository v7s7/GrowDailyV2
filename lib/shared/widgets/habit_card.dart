import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/game_theme.dart';
import '../../features/habits/catalog/islamic_habit_catalog.dart';
import '../../features/habits/models/habit_cue.dart';
import '../../features/habits/models/habit_model.dart';
import 'category_icon.dart';

class HabitCard extends StatefulWidget {
  final IslamicHabitTemplate template;
  final int completions;
  final bool isDone;
  final VoidCallback? onComplete;

  /// Whether *today* is already marked as a slip (avoid-completely) or an
  /// over-limit day (set-a-limit) for this quit habit — derived by the
  /// caller from today's Grid square (`SquareState.failed`), not a new
  /// piece of state of its own. Ignored for [GoalType.build] habits.
  final bool isFailedToday;

  /// Logs today as a slip/over-limit day for a quit habit — the
  /// deliberately-quieter secondary action next to the primary affirm
  /// button. Null (and the control hidden) for build habits.
  final VoidCallback? onSlip;

  /// Reverses a mis-tapped [onSlip] for today. Only ever shown while
  /// [isFailedToday] is true.
  final VoidCallback? onUndoSlip;

  /// Current per-habit streak (already gap-corrected — see
  /// `DashboardState.habitStreak`). 0 hides the streak chip entirely, so a
  /// brand-new habit's card isn't cluttered with a "0" before it's ever
  /// been completed.
  final int streak;

  /// Optional drag handle rendered in the header row — supplied by the
  /// caller (see `_SwipeableHabitRow` in dashboard_screen.dart) rather than
  /// built here, so this card stays decoupled from any particular
  /// drag-and-drop implementation.
  final Widget? trailingHandle;

  const HabitCard({
    super.key,
    required this.template,
    required this.completions,
    required this.isDone,
    this.onComplete,
    this.isFailedToday = false,
    this.onSlip,
    this.onUndoSlip,
    this.streak = 0,
    this.trailingHandle,
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

  bool get _isQuit => widget.template.goalType == GoalType.quit;

  /// The "this is done today" accent for the card chrome (border, glow,
  /// icon tile, title) — emerald for quit habits, gold for build, matching
  /// whichever color [_quitActionPill]/[_buildActionPill] uses so the whole
  /// card agrees with its own action button instead of the button being the
  /// only part that looks different.
  Color get _doneAccent => _isQuit ? GameColors.emerald : GameColors.gold;

  /// The icon's own color, stable across done/not-done — a habit with a
  /// user-picked color (see IslamicHabitTemplate.customColor) keeps that
  /// identity color instead of the icon getting swapped to the generic
  /// gold/emerald done-accent, the same way its category icon would
  /// otherwise be fixed to whatever the category (not the habit itself)
  /// says. Only the icon and its background tile read this — the card's
  /// border/glow/title stay on [_doneAccent], so "done" still has one
  /// consistent visual meaning across every card in the list.
  Color get _iconAccent => widget.template.customColor ?? _doneAccent;

  String _actionLabel(BuildContext context) {
    final s = S.of(context);
    if (_isQuit) {
      return widget.template.reductionType == ReductionType.limit
          ? s.habitWithinLimit
          : s.habitStayedOnTrack;
    }
    return s.habitComplete;
  }

  String _subtitle(BuildContext context) {
    final s = S.of(context);
    final freq = widget.template.frequencyType == HabitFrequencyType.daily
        ? s.habitDaily
        : s.habitWeeklyTimes(widget.template.frequencyTarget);
    final cue = widget.template.cueAfter;
    // cueAfter is stored as a stable key/value (see HabitCue) — this covers
    // both custom habits and the hardcoded catalog templates ('Fajr',
    // 'Asr', ...), so either one displays in whatever language the app is
    // in right now, not whichever language it was written/created in.
    final cueText = cue == null || cue.isEmpty
        ? ''
        : s.habitAfterCue(HabitCue.fromStoredValue(cue).labelFor(context));
    // A set-a-limit quit habit's number is otherwise invisible on the card
    // itself — "within limit" means nothing without the limit — so it's
    // worth the subtitle space the way a timer's minutes already get.
    final amount = widget.template.limitAmount;
    final limitText = _isQuit &&
            widget.template.reductionType == ReductionType.limit &&
            amount != null
        ? '  ·  ≤$amount ${widget.template.unitLabel(s.limitUnitLabel(widget.template.limitUnit?.name ?? 'times'))}'
        : '';
    if (widget.template.hasTimer) {
      final mins = (widget.template.timerDurationSeconds ?? 0) ~/ 60;
      return '$freq  ·  ${mins}min$cueText$limitText';
    }
    return '$freq$cueText$limitText';
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
          color: widget.isDone ? _doneAccent.withOpacity(0.4) : gp.border,
          width: widget.isDone ? 1.0 : 0.5,
        ),
        boxShadow: widget.isDone
            ? [
                BoxShadow(
                  color: _doneAccent.withOpacity(0.07),
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
                        ? _iconAccent.withOpacity(0.12)
                        : (widget.template.customColor?.withOpacity(0.12) ??
                            gp.surfaceHigh),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: CategoryIcon(
                    category: widget.template.category,
                    size: 20,
                    color: widget.isDone
                        ? _iconAccent
                        : (widget.template.customColor ?? gp.textSec),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.template.localName(s.isAr).toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: s.isAr ? 0 : 0.5,
                          color: widget.isDone ? _doneAccent : gp.textPrimary,
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
                if (widget.trailingHandle != null) ...[
                  const SizedBox(width: 8),
                  widget.trailingHandle!,
                ],
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
                  color: GameColors.iconXp,
                ),
                const SizedBox(width: 8),
                _RewardTag(
                  icon: Icons.circle_rounded,
                  text: '+${widget.template.goldReward} G',
                  color: GameColors.gold,
                ),
                if (widget.streak > 0) ...[
                  const SizedBox(width: 8),
                  _RewardTag(
                    icon: Icons.local_fire_department_rounded,
                    text: '${widget.streak}',
                    color: GameColors.iconStreak,
                  ),
                ],
                const Spacer(),
                _isQuit ? _quitActionPill(context, s) : _buildActionPill(s),
              ],
            ),
            // Quit habits get a second, deliberately quiet control under
            // the primary pill: logging a slip should never look as
            // rewarding to tap as staying clean/within-limit does, so this
            // is plain text, not another filled button. Stays available
            // even after the primary pill is tapped — "said clean, actually
            // slipped later" needs the same fix as "never tapped anything
            // today" (onSlip/_slipHabit already reverses a same-day
            // completion first via uncompleteHabit) — and swaps to a small
            // "Undo" once today is already marked failed, for a mis-tap.
            // The onSlip != null guard hides this for a weekly-target quit
            // habit (frequencyTarget > 1) — dashboard_screen.dart
            // deliberately leaves onSlip/isFailedToday unwired for those,
            // matching completeHabit's own single-tap-only Grid sync rule,
            // so there'd be nothing for a tap here to actually do.
            if (_isQuit && !widget.isFailedToday && widget.onSlip != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: _SlipLink(
                  label: widget.template.reductionType == ReductionType.limit
                      ? s.habitLogOverLimit
                      : s.habitLogSlip,
                  icon: Icons.close_rounded,
                  onTap: widget.onSlip,
                ),
              ),
            ] else if (_isQuit && widget.isFailedToday) ...[
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: _SlipLink(
                  label: s.matrixUndo,
                  icon: Icons.undo_rounded,
                  onTap: widget.onUndoSlip,
                ),
              ),
            ],
          ],
        ),
      ),
    )
        .animate(target: _justCompleted ? 1 : 0)
        .scaleXY(begin: 1, end: 1.015, duration: 120.ms)
        .then()
        .scaleXY(begin: 1.015, end: 1, duration: 200.ms);
  }

  /// Build habits' primary action pill — gold, unchanged from before quit
  /// habits got their own visual language (see [_quitActionPill]).
  Widget _buildActionPill(S s) => GestureDetector(
        onTapDown:
            widget.isDone ? null : (_) => setState(() => _pressed = true),
        onTapUp: widget.isDone
            ? null
            : (_) {
                setState(() => _pressed = false);
                widget.onComplete?.call();
              },
        onTapCancel:
            widget.isDone ? null : () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.92 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: widget.isDone
                  ? GameColors.gold.withOpacity(0.1)
                  : GameColors.gold,
              borderRadius: BorderRadius.circular(8),
              border: widget.isDone
                  ? Border.all(
                      color: GameColors.gold.withOpacity(0.35), width: 0.5)
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.isDone ? Icons.check_rounded : Icons.add_rounded,
                  size: 13,
                  color: widget.isDone ? GameColors.gold : Colors.black,
                ),
                const SizedBox(width: 5),
                Text(
                  widget.isDone ? s.habitDone : _actionLabel(context),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: s.isAr ? 0 : 0.8,
                    color: widget.isDone ? GameColors.gold : Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  /// Quit habits' primary action pill — emerald (this app's other core
  /// accent, already what a completed Grid square means — see
  /// ThemePreset's doc comment) rather than gold, and a shield glyph
  /// rather than a checklist "+", so a clean/within-limit
  /// day doesn't visually read as "ticking off a task" the way a build
  /// habit does. A third, locked state (red, matching Grid's `failed`
  /// square) takes over once [HabitCard.isFailedToday] is true — see
  /// [_SlipLink] for how a slip is logged/undone.
  Widget _quitActionPill(BuildContext context, S s) {
    if (widget.isFailedToday) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: GameColors.error.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: GameColors.error.withOpacity(0.35), width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.close_rounded, size: 13, color: GameColors.error),
            const SizedBox(width: 5),
            Text(
              widget.template.reductionType == ReductionType.limit
                  ? s.habitOverLimitToday
                  : s.habitSlippedToday,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: s.isAr ? 0 : 0.8,
                color: GameColors.error,
              ),
            ),
          ],
        ),
      );
    }
    return GestureDetector(
      onTapDown:
          widget.isDone ? null : (_) => setState(() => _pressed = true),
      onTapUp: widget.isDone
          ? null
          : (_) {
              setState(() => _pressed = false);
              widget.onComplete?.call();
            },
      onTapCancel:
          widget.isDone ? null : () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isDone
                ? GameColors.emerald.withOpacity(0.1)
                : GameColors.emerald,
            borderRadius: BorderRadius.circular(8),
            border: widget.isDone
                ? Border.all(
                    color: GameColors.emerald.withOpacity(0.35), width: 0.5)
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.isDone ? Icons.check_rounded : Icons.shield_rounded,
                size: 13,
                // !isDone sits on a *solid* emerald fill (see decoration
                // above), not a tint — needs a contrast-checked color, not
                // emerald-on-emerald like the isDone branch. See
                // GameColors.onEmerald's doc comment.
                color: widget.isDone
                    ? GameColors.emerald
                    : GameColors.onEmerald,
              ),
              const SizedBox(width: 5),
              Text(
                _actionLabel(context),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: s.isAr ? 0 : 0.8,
                  color: widget.isDone
                      ? GameColors.emerald
                      : GameColors.onEmerald,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The quiet secondary control under a quit habit's action pill — plain
/// text + small icon, deliberately less visually rewarding to tap than the
/// primary pill (see [HabitCard._quitActionPill]'s doc comment for why).
class _SlipLink extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  const _SlipLink({required this.label, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!.call();
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: gp.textTert),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: gp.textTert,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
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
