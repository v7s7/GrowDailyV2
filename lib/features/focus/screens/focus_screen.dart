import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/game_nav_bar.dart';
import '../models/daily_focus_plan.dart';
import '../models/focus_duration.dart';
import '../notifiers/focus_plan_notifier.dart';
import '../notifiers/focus_timer_notifier.dart';

class FocusScreen extends ConsumerStatefulWidget {
  const FocusScreen({super.key});

  @override
  ConsumerState<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends ConsumerState<FocusScreen> {
  late final TextEditingController _topTaskController;
  late final TextEditingController _cueController;
  late final TextEditingController _actionController;

  @override
  void initState() {
    super.initState();
    final plan = ref.read(focusPlanProvider).plan;
    _topTaskController = TextEditingController(text: plan.topTask);
    _cueController = TextEditingController(text: plan.cue);
    _actionController = TextEditingController(text: plan.action);
  }

  @override
  void dispose() {
    _topTaskController.dispose();
    _cueController.dispose();
    _actionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final state = ref.watch(focusPlanProvider);
    final timer = ref.watch(focusTimerProvider);

    ref.listen<FocusPlanState>(focusPlanProvider, (prev, next) {
      final shouldSyncFields = prev == null ||
          (prev.isLoading && !next.isLoading) ||
          prev.plan.dateKey != next.plan.dateKey ||
          _allFieldsWereReset(prev.plan, next.plan);
      if (!shouldSyncFields) return;
      _topTaskController.text = next.plan.topTask;
      _cueController.text = next.plan.cue;
      _actionController.text = next.plan.action;
    });

    // The XP/gold award and the session log happen inside FocusTimerNotifier
    // itself (so they land even if this screen isn't open when a sprint
    // finishes). This listener only handles the celebratory bottom sheet,
    // shown when the transition to "done" happens while the user is here.
    ref.listen<FocusTimerState>(focusTimerProvider, (prev, next) {
      if (prev != null && !prev.isDone && next.isDone) {
        HapticFeedback.heavyImpact();
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _FocusCompleteSheet(duration: next.duration),
        );
      }
    });

    return Scaffold(
      backgroundColor: gp.bg,
      bottomNavigationBar: const GameNavBar(currentIndex: 2),
      body: SafeArea(
        child: state.isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color: GameColors.gold,
                  strokeWidth: 2,
                ),
              )
            : CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                      child: _Header(plan: state.plan)
                          .animate()
                          .fadeIn(duration: 420.ms)
                          .slideY(begin: -0.06),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                      child: _FocusCaptureCard(
                        plan: state.plan,
                        topTaskController: _topTaskController,
                        cueController: _cueController,
                        actionController: _actionController,
                        onSave: _saveFocus,
                      )
                          .animate(delay: 80.ms)
                          .fadeIn(duration: 420.ms)
                          .slideY(begin: 0.08),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                      child: _FocusTimerCard(
                        duration: timer.duration,
                        remainingSeconds: timer.remainingSeconds(),
                        isRunning: timer.isRunning,
                        isDone: timer.isDone,
                        onSelectDuration: _selectDuration,
                        onStartPause:
                            timer.isRunning ? _pauseTimer : _startTimer,
                        onReset: _resetTimer,
                      )
                          .animate(delay: 120.ms)
                          .fadeIn(duration: 420.ms)
                          .slideY(begin: 0.08),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                      child: _DailyRitualCard(plan: state.plan)
                          .animate(delay: 150.ms)
                          .fadeIn(duration: 420.ms)
                          .slideY(begin: 0.08),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                      child: _EvidenceCard()
                          .animate(delay: 220.ms)
                          .fadeIn(duration: 420.ms)
                          .slideY(begin: 0.08),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 96)),
                ],
              ),
      ),
    );
  }

  void _selectDuration(FocusDuration d) {
    HapticFeedback.selectionClick();
    ref.read(focusTimerProvider.notifier).selectDuration(d);
  }

  void _startTimer() {
    HapticFeedback.mediumImpact();
    ref.read(focusTimerProvider.notifier).start();
  }

  void _pauseTimer() {
    HapticFeedback.lightImpact();
    ref.read(focusTimerProvider.notifier).pause();
  }

  void _resetTimer() {
    HapticFeedback.lightImpact();
    ref.read(focusTimerProvider.notifier).reset();
  }

  bool _allFieldsWereReset(DailyFocusPlan prev, DailyFocusPlan next) =>
      (prev.topTask.isNotEmpty || prev.cue.isNotEmpty || prev.action.isNotEmpty) &&
      next.topTask.isEmpty &&
      next.cue.isEmpty &&
      next.action.isEmpty;

  void _saveFocus() {
    HapticFeedback.lightImpact();
    ref.read(focusPlanProvider.notifier).saveFocus(
          topTask: _topTaskController.text,
          cue: _cueController.text,
          action: _actionController.text,
        );
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.of(context).focusPlanSaved),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final DailyFocusPlan plan;
  const _Header({required this.plan});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: GameColors.xpBlue.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.center_focus_strong_rounded,
                  color: GameColors.xpBlue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S.of(context).focusDailyTitle,
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      color: gp.textPrimary,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    S.of(context).focusTagline,
                    style: TextStyle(fontSize: 12, color: gp.textSec),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pushNamed(context, '/matrix'),
              tooltip: S.of(context).navGoals,
              icon: Icon(Icons.checklist_rounded, color: gp.textSec),
            ),
          ],
        ),
        const SizedBox(height: 18),
        ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: LinearProgressIndicator(
            minHeight: 7,
            value: plan.progress,
            backgroundColor: gp.surface,
            color: GameColors.gold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          S.of(context).focusRitualProgress(plan.completedSteps),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: gp.textTert,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

class _FocusCaptureCard extends StatelessWidget {
  final DailyFocusPlan plan;
  final TextEditingController topTaskController;
  final TextEditingController cueController;
  final TextEditingController actionController;
  final VoidCallback onSave;

  const _FocusCaptureCard({
    required this.plan,
    required this.topTaskController,
    required this.cueController,
    required this.actionController,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            icon: Icons.flag_rounded,
            title: s.focusMostImportantTask,
            subtitle: s.focusMitSubtitle,
            color: GameColors.gold,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: topTaskController,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              hintText: s.focusTopTaskHint,
              labelText: s.focusTopTaskLabel,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            s.focusIfThenPlan,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: gp.textTert,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: cueController,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              prefixText: s.focusCuePrefix,
              hintText: s.focusCueHint,
              labelText: s.focusCueLabel,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: actionController,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSave(),
            decoration: InputDecoration(
              prefixText: s.focusActionPrefix,
              hintText: s.focusActionHint,
              labelText: s.focusActionLabel,
            ),
          ),
          if (plan.hasImplementationIntention) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: GameColors.xpBlue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: GameColors.xpBlue.withOpacity(0.18)),
              ),
              child: Text(
                '${s.focusCuePrefix}${plan.cue}, ${s.focusActionPrefix}${plan.action}.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: gp.textPrimary,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onSave,
            icon: const Icon(Icons.check_rounded, size: 18),
            label: Text(s.focusSavePlan),
          ),
        ],
      ),
    );
  }
}

class _FocusTimerCard extends StatelessWidget {
  final FocusDuration duration;
  final int remainingSeconds;
  final bool isRunning;
  final bool isDone;
  final ValueChanged<FocusDuration> onSelectDuration;
  final VoidCallback onStartPause;
  final VoidCallback onReset;

  const _FocusTimerCard({
    required this.duration,
    required this.remainingSeconds,
    required this.isRunning,
    required this.isDone,
    required this.onSelectDuration,
    required this.onStartPause,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final mm = (remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final ss = (remainingSeconds % 60).toString().padLeft(2, '0');
    final progress = 1.0 - (remainingSeconds / duration.seconds);
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            icon: Icons.timer_rounded,
            title: s.focusTimerTitle,
            subtitle: s.focusTimerSubtitle,
            color: GameColors.xpBlue,
          ),
          const SizedBox(height: 16),
          Row(
            children: FocusDuration.values.map((d) {
              final selected = d == duration;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: OutlinedButton(
                    onPressed: isRunning ? null : () => onSelectDuration(d),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 38),
                      foregroundColor: selected ? Colors.black : GameColors.gold,
                      backgroundColor: selected ? GameColors.gold : Colors.transparent,
                    ),
                    child: Text(s.focusMinutesLabel(d.minutes)),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          Center(
            child: SizedBox(
              width: 180,
              height: 180,
              child: CustomPaint(
                painter: _TimerRingPainter(
                  progress: progress,
                  trackColor: gp.border,
                  arcColor: isDone
                      ? GameColors.success
                      : isRunning
                          ? GameColors.xpBlue
                          : GameColors.gold,
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$mm:$ss',
                        style: TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w900,
                          color: gp.textPrimary,
                          letterSpacing: -1.5,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isDone
                            ? s.focusComplete
                            : (isRunning ? s.focusFocusing : s.focusReady),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isDone
                              ? GameColors.success
                              : (isRunning ? GameColors.xpBlue : gp.textTert),
                          letterSpacing: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: isDone ? null : onStartPause,
                  icon: Icon(isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  label: Text(isRunning ? s.focusPauseSprint : s.focusStartSprint),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                onPressed: onReset,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: s.focusResetTimer,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.bolt_rounded, size: 14, color: GameColors.xpBlue),
              const SizedBox(width: 4),
              Text(
                s.focusXpOnCompletion(duration.xpReward),
                style: TextStyle(
                  fontSize: 12,
                  color: gp.textTert,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
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
    final radius = size.width / 2 - 8;
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    final arc = Paint()
      ..color = arcColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
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

class _FocusCompleteSheet extends StatelessWidget {
  final FocusDuration duration;
  const _FocusCompleteSheet({required this.duration});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
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
            Text(
              s.focusSessionCompleteTitle,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: GameColors.success,
                letterSpacing: 2,
              ),
            ).animate(delay: 200.ms).fadeIn(),
            const SizedBox(height: 8),
            Text(
              s.focusDeepWorkDone,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
                letterSpacing: -0.3,
              ),
            ).animate(delay: 280.ms).fadeIn().slideY(begin: 0.2),
            const SizedBox(height: 6),
            Text(
              s.focusStayedFocused(s.focusMinutesLabel(duration.minutes)),
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
                child: Text(s.focusGreatWork),
              ),
            ).animate(delay: 460.ms).fadeIn().slideY(begin: 0.2),
          ],
        ),
      ),
    );
  }
}

class _DailyRitualCard extends ConsumerWidget {
  final DailyFocusPlan plan;
  const _DailyRitualCard({required this.plan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            icon: Icons.auto_awesome_rounded,
            title: s.focusRitualTitle,
            subtitle: s.focusRitualSubtitle,
            color: GameColors.success,
          ),
          const SizedBox(height: 14),
          _RitualTile(
            title: s.focusRitualPlanWin,
            subtitle: plan.topTask.isEmpty ? s.focusRitualChooseTask : plan.topTask,
            isDone: plan.planDone,
            onTap: () => ref.read(focusPlanProvider.notifier).togglePlan(),
          ),
          _RitualTile(
            title: s.focusRitualRunSprint,
            subtitle: s.focusRitualSprintsLogged(plan.focusSessions),
            isDone: plan.sprintDone,
            onTap: () => ref.read(focusPlanProvider.notifier).toggleSprint(),
          ),
          _RitualTile(
            title: s.focusRitualReview,
            subtitle: s.focusRitualReviewSubtitle,
            isDone: plan.reviewDone,
            onTap: () => ref.read(focusPlanProvider.notifier).toggleReview(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    ref.read(focusPlanProvider.notifier).addFocusSession();
                  },
                  icon: const Icon(Icons.timer_rounded, size: 18),
                  label: Text(s.focusLogSprint),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  ref.read(focusPlanProvider.notifier).resetToday();
                },
                icon: const Icon(Icons.refresh_rounded),
                tooltip: s.focusResetToday,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EvidenceCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            icon: Icons.psychology_rounded,
            title: s.focusWhyTitle,
            subtitle: s.focusWhySubtitle,
            color: GameColors.xpBlue,
          ),
          const SizedBox(height: 14),
          _EvidenceChip(
            icon: Icons.place_rounded,
            title: s.focusIfThenCueTitle,
            body: s.focusIfThenCueBody,
          ),
          _EvidenceChip(
            icon: Icons.looks_one_rounded,
            title: s.focusOneTaskTitle,
            body: s.focusOneTaskBody,
          ),
          _EvidenceChip(
            icon: Icons.timer_rounded,
            title: s.focusSprintTitle,
            body: s.focusSprintBody,
          ),
        ],
      ),
    );
  }
}

class _RitualTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isDone;
  final VoidCallback onTap;

  const _RitualTile({
    required this.title,
    required this.subtitle,
    required this.isDone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDone
                ? GameColors.success.withOpacity(0.10)
                : gp.surfaceHL.withOpacity(0.45),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDone
                  ? GameColors.success.withOpacity(0.24)
                  : gp.border.withOpacity(0.55),
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: isDone ? GameColors.success : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDone ? GameColors.success : gp.textTert,
                    width: 1.4,
                  ),
                ),
                child: isDone
                    ? const Icon(Icons.check_rounded,
                        size: 16, color: Colors.black)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: gp.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: gp.textSec),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EvidenceChip extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _EvidenceChip({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: GameColors.xpBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: gp.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: TextStyle(fontSize: 12, color: gp.textSec, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: gp.textPrimary,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: gp.textSec, height: 1.3),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CardShell extends StatelessWidget {
  final Widget child;
  const _CardShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: child,
    );
  }
}
