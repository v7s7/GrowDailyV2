import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/get_started_checklist_provider.dart';
import '../../core/theme/game_theme.dart';
import '../../features/habits/notifiers/custom_habits_notifier.dart'
    show habitListProvider, habitsStillLoadingProvider;
import '../../features/matrix/notifiers/matrix_notifier.dart';

/// The actual "get someone to their first real action" moment — replaces
/// relying on the one-time nav spotlight (see homeSpotlightSeenProvider) or
/// the 5-slide OnboardingScreen tour to teach this. Neither of those was
/// enough on its own: the slide tour is a feature-tour-before-you've-used-
/// anything shape, and the spotlight is one generic "here's your nav bar"
/// popup that only ever mentions habits in passing, never tasks, and is
/// gone forever after one dismiss regardless of whether either thing ever
/// actually got done.
///
/// Two steps, watched against real data rather than a one-shot flag:
///  - "Add your first habit" - done the moment [habitListProvider] is
///    non-empty.
///  - "Add your first task" - done the moment [matrixProvider]'s task list
///    is non-empty.
/// Shows on both Grid and Matrix (each screen supplies its own
/// [onAddHabit]/[onAddTask] - see grid_screen.dart/matrix_screen.dart for
/// how the "other domain" row jumps tabs instead of trying to reach across
/// screens), disappears the instant both are true - no persisted flag
/// needed for that path, it's just live state - and can also be dismissed
/// early via the corner button, which *does* persist (see
/// markGetStartedDismissed) since that one really is "never show this
/// again," not "temporarily satisfied."
class GetStartedChecklistCard extends ConsumerWidget {
  final VoidCallback onAddHabit;
  final VoidCallback onAddTask;
  const GetStartedChecklistCard({
    super.key,
    required this.onAddHabit,
    required this.onAddTask,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dismissed = ref.watch(getStartedDismissedProvider);
    // Guard against the same flash-before-real-data problem
    // habitsStillLoadingProvider's own doc comment describes for the Grid
    // empty state: a returning user with real habits/tasks would otherwise
    // see "add your first..." for one frame before their actual data pops
    // in.
    final habitsLoading = ref.watch(habitsStillLoadingProvider);
    final matrixState = ref.watch(matrixProvider);
    if (dismissed || habitsLoading || matrixState.isLoading) {
      return const SizedBox.shrink();
    }

    final habitDone = ref.watch(habitListProvider).isNotEmpty;
    final taskDone = matrixState.tasks.isNotEmpty;
    if (habitDone && taskDone) return const SizedBox.shrink();

    final gp = context.gp;
    final s = S.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: GameColors.gold.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flag_rounded, size: 17, color: GameColors.gold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.getStartedTitle,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: gp.textPrimary,
                  ),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(100),
                onTap: () {
                  HapticFeedback.selectionClick();
                  markGetStartedDismissed(ref);
                },
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(Icons.close_rounded, size: 16, color: gp.textTert),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _ChecklistRow(
            done: habitDone,
            label: s.getStartedAddHabit,
            onTap: habitDone ? null : onAddHabit,
          ),
          _ChecklistRow(
            done: taskDone,
            label: s.getStartedAddTask,
            onTap: taskDone ? null : onAddTask,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.08, end: 0);
  }
}

class _ChecklistRow extends StatelessWidget {
  final bool done;
  final String label;
  final VoidCallback? onTap;
  const _ChecklistRow({required this.done, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.lightImpact();
                onTap!();
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              Icon(
                done ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 19,
                color: done ? GameColors.emerald : gp.textTert,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: done ? gp.textTert : gp.textPrimary,
                    decoration: done ? TextDecoration.lineThrough : null,
                    decorationColor: gp.textTert,
                  ),
                ),
              ),
              if (!done)
                Icon(Icons.chevron_right_rounded, size: 18, color: gp.textTert),
            ],
          ),
        ),
      ),
    );
  }
}
