import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/app_guide_provider.dart';
import '../../core/providers/get_started_checklist_provider.dart';
import '../../core/theme/game_theme.dart';
import '../../features/habits/notifiers/custom_habits_notifier.dart'
    show habitListProvider, habitsStillLoadingProvider;
import '../../features/matrix/notifiers/matrix_notifier.dart';
import '../../features/onboarding/notifiers/guide_steps_provider.dart';
import '../../features/onboarding/screens/app_guide_screen.dart';

/// The guide, on the Grid — the same steps Settings' App Guide lists, in the
/// same order, from the same source ([guideStepsProvider]).
///
/// It used to be a separate two-item checklist of its own: "add your first
/// habit", "add your first task". Two problems came out of that, and both are
/// why the app felt harder to start than it is.
///
/// It never taught the thing the app IS. Colouring a square — "Color your
/// life, one square at a time" — was in the Settings guide and nowhere in
/// first run, so someone could tick both boxes, watch the card disappear, and
/// never once have coloured one.
///
/// And its second step pointed away. Tapping "add your first task" switched to
/// the Tasks tab, so a brand-new user's second instruction was to leave the
/// screen the app is named after before they had used it once.
///
/// Now it shows one step at a time — the next unfinished one — with a quiet
/// "2 of 4" so there's a sense of an end. Tapping it arms the very same
/// coach-mark the Settings guide would (see [startGuideLesson]): the real
/// button on the real screen, circled, for them to press themselves.
/// Everything is still dismissible, and it retires itself once the guide is
/// finished.
class GetStartedChecklistCard extends ConsumerWidget {
  /// Kept for callers that pass them, but the card no longer routes anything
  /// itself — every step goes through [startGuideLesson] so the Grid and
  /// Settings can never teach the same step two different ways.
  final VoidCallback? onAddHabit;
  final VoidCallback? onAddTask;
  const GetStartedChecklistCard({super.key, this.onAddHabit, this.onAddTask});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dismissed = ref.watch(getStartedDismissedProvider);
    // Guard against the flash-before-real-data problem
    // habitsStillLoadingProvider's own doc comment describes: a returning
    // user with real habits would otherwise see step one for a frame before
    // their data lands.
    final habitsLoading = ref.watch(habitsStillLoadingProvider);
    final matrixState = ref.watch(matrixProvider);
    if (dismissed || habitsLoading || matrixState.isLoading) {
      return const SizedBox.shrink();
    }

    final next = ref.watch(nextGuideStepProvider);
    // Guide finished — nothing left to say, and no flag needed to remember
    // that: it's true from real data every launch.
    if (next == null) return const SizedBox.shrink();

    final progress = ref.watch(guideProgressProvider);
    final gp = context.gp;
    final s = S.of(context);
    final isAr = s.isAr;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: GameColors.gold.withOpacity(0.35)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          onTap: () {
            HapticFeedback.lightImpact();
            startGuideLesson(
              context,
              ref,
              next.lesson,
              habitsEmpty: ref.read(habitListProvider).isEmpty,
              // Not a route — nothing to pop.
              popFirst: false,
            );
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
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
                    // Quiet, tabular, and honest about how much is left —
                    // an unbounded checklist reads as a chore.
                    Text(
                      s.guideStepCount(progress.done + 1, progress.total),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: gp.textTert,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    InkWell(
                      borderRadius:
                          BorderRadius.circular(GameSpacing.pillRadius),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        markGetStartedDismissed(ref);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(Icons.close_rounded,
                            size: 16, color: gp.textTert),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.circle_outlined, size: 19, color: gp.textTert),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            appGuideLessonTitle(next.lesson, isAr),
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: gp.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            appGuideLessonSubtitle(next.lesson, isAr),
                            style:
                                TextStyle(fontSize: 12.5, color: gp.textSec),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        size: 18, color: gp.textTert),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.08, end: 0);
  }
}
