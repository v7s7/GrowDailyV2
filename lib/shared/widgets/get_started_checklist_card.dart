import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/app_guide_provider.dart';
import '../../core/providers/first_run_offer_provider.dart';
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
/// Now it shows the whole guide: a progress bar, a quiet "2 of 4", and all
/// four steps at once, with the finished ones ticked and the next one picked
/// out. Tapping the card arms the very same coach-mark the Settings guide
/// would (see [startGuideLesson]): the real button on the real screen,
/// circled, for them to press themselves. Everything is still dismissible,
/// and it retires itself once the guide is finished.
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
    final steps = ref.watch(guideStepsProvider);
    final gp = context.gp;
    final s = S.of(context);
    final isAr = s.isAr;

    final card = Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: GameColors.gold.withOpacity(0.35)),
      ),
      // No InkWell around the whole card any more.
      //
      // The card renders four rows, ticks the done ones, and puts a chevron on
      // the next one, so it reads as a four item menu. It was not one: a
      // single tap handler wrapped everything and always armed whatever step
      // happened to be next, so tapping «انضم لغرفة» did not go to Rooms. It
      // went wherever the card had already decided. Four rows that look
      // tappable and are not is the kind of thing a person only notices as
      // "this app is a bit odd" and never reports.
      //
      // Each row now carries its own tap and goes where it says. Done rows
      // stay tappable on purpose: the guide is replayable everywhere else,
      // and a finished step is exactly the one somebody wants to see again.
      child: Material(
        color: Colors.transparent,
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
                        // Undo, because this X is a permanent, silent delete
                        // of the only thing teaching a first-time user what
                        // to do, and it sits in the corner where every app
                        // puts "close this notice". See
                        // undoGetStartedDismissed for why not a confirmation
                        // dialog. Six seconds and swipe-down to dismiss,
                        // matching the pause and delete snackbars on this
                        // same screen.
                        ScaffoldMessenger.of(context)
                          ..clearSnackBars()
                          ..showSnackBar(SnackBar(
                            content: Text(s.guideHiddenUndoHint),
                            duration: const Duration(seconds: 6),
                            behavior: SnackBarBehavior.floating,
                            dismissDirection: DismissDirection.down,
                            margin:
                                const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            action: SnackBarAction(
                              label: s.undo,
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                undoGetStartedDismissed(ref);
                              },
                            ),
                          ));
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
                // A thin bar for the shape of the whole thing at a glance.
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  // Tweened, not set. Finishing a step used to move this bar
                  // between two frames, which is the same as not moving it:
                  // the one moment the bar exists for is the moment it grows,
                  // and it was the only moment it never showed.
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                      begin: 0,
                      end: progress.total == 0
                          ? 0
                          : progress.done / progress.total,
                    ),
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : GameMotion.slow,
                    curve: Curves.easeOutCubic,
                    builder: (_, value, __) => LinearProgressIndicator(
                      value: value,
                      minHeight: 4,
                      backgroundColor: gp.surfaceHL,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(GameColors.gold),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // ALL four steps, not just the next one.
                //
                // This card used to render a single row — whichever step was
                // next — so a new user could see "step 2 of 4" without ever
                // seeing what steps 3 and 4 were, or what step 1 had been.
                // A guide that hides its own contents is a prompt, not a
                // guide: you cannot tell how long it is, what you already
                // did, or whether it is worth starting. Four short rows cost
                // about sixty points of height and answer all three.
                for (var i = 0; i < steps.length; i++) ...[
                  if (i > 0) const SizedBox(height: 2),
                  _GuideStepRow(
                    lesson: steps[i].lesson,
                    done: steps[i].done,
                    isNext: steps[i].lesson == next.lesson,
                    isAr: isAr,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      startGuideLesson(
                        context,
                        ref,
                        steps[i].lesson,
                        habitsEmpty: ref.read(habitListProvider).isEmpty,
                        // Not a route, nothing to pop.
                        popFirst: false,
                      );
                    },
                  ),
                ],
              ],
            ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.08, end: 0);

    // Somebody who answered «بعدين» to the first-run question is landing on a
    // Grid that is byte for byte the one everybody else gets: nothing is
    // dimmed, nothing is blocking, and nothing new was added to this card.
    //
    // What they get instead is three breaths and then stillness, once, on the
    // card that already IS the offer they deferred. This card carries every
    // emphasis the Grid has (the only gold border, the gold flag, the gold
    // progress bar, all four steps), so a badge or a dot on top of it would be
    // a second announcement of the same fact, which is the mistake the app
    // guide's own "new" dot comment warns about. What was missing was not
    // emphasis, it was the connection between the question they just declined
    // and the thing on screen that answers it. Three breaths draw that line
    // and then get out of the way; a permanent pulse would be trained away
    // inside two sessions and take the offer with it.
    return _DeferredOfferPulse(child: card);
  }
}


/// One line of the Get Started checklist.
///
/// Three states, deliberately distinguished by more than colour: a done step
/// gets a filled tick and drops its subtitle (it has nothing left to teach),
/// the next step keeps its subtitle and a chevron (it is the one that acts),
/// and a later step is dimmed with no subtitle so the eye skips it without
/// having to read it.
class _GuideStepRow extends StatelessWidget {
  final AppGuideLesson lesson;
  final bool done;
  final bool isNext;
  final bool isAr;
  final VoidCallback onTap;

  const _GuideStepRow({
    required this.lesson,
    required this.done,
    required this.isNext,
    required this.isAr,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      // 12 of vertical padding around a 19pt icon is 43 to 44 points, which
      // is Apple's minimum and was measured, not guessed: at the 4 this
      // started with, a row came out at 28. The gap BETWEEN rows drops from 9
      // to 2 to pay for most of it, since the padding now does the separating,
      // so the card grows by about 20 points rather than 36.
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Keyed on `done`, so the tick REPLACES the empty ring rather than
        // recolouring it, and gets its own entrance. Without the key the two
        // icons are the same widget to Flutter and the change is a repaint,
        // which is how a step could complete with no acknowledgement at all.
        Icon(
          done ? Icons.check_circle_rounded : Icons.circle_outlined,
          key: ValueKey(done),
          size: 19,
          color: done
              ? GameColors.emerald
              : (isNext ? GameColors.gold : gp.textTert.withOpacity(0.55)),
        )
            .animate(key: ValueKey('tick-$lesson-$done'))
            .scale(
              begin: const Offset(0.55, 0.55),
              end: const Offset(1, 1),
              // elasticOut, matching the achievement medal's own entrance in
              // reaction_overlays.dart, because this is the same event at a
              // smaller size: a thing that was open is now closed.
              curve: Curves.elasticOut,
              duration: done ? 520.ms : 1.ms,
            ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                appGuideLessonTitle(lesson, isAr),
                style: TextStyle(
                  fontSize: isNext ? 14.5 : 13.5,
                  fontWeight: isNext ? FontWeight.w800 : FontWeight.w600,
                  color: done
                      ? gp.textTert
                      : (isNext ? gp.textPrimary : gp.textSec),
                ),
              ),
              if (isNext) ...[
                const SizedBox(height: 2),
                Text(
                  appGuideLessonSubtitle(lesson, isAr),
                  style: TextStyle(fontSize: 12.5, color: gp.textSec),
                ),
              ],
            ],
          ),
        ),
        // A chevron on every row now, not just the next one. It was the only
        // thing marking a row as tappable, and while that was honest when one
        // row was the tap target, it now says the opposite of the truth about
        // the other three. Dimmed on the rows that are not next, so the
        // hierarchy the card had is kept.
        Icon(
          Icons.chevron_right_rounded,
          size: 18,
          color: isNext ? gp.textTert : gp.textTert.withOpacity(0.45),
        ),
      ],
        ),
      ),
    );
  }
}


/// Three slow breaths, once, and only for somebody who answered «بعدين» to the
/// first-run question during this launch.
///
/// It reads [firstRunAnswerProvider], which is memory-only and never seeded at
/// boot (see that file), and clears it on the first frame. So this can only
/// ever play in the same launch as the tap that caused it: a cold start has
/// nothing to replay, and the second time this card builds it is inert.
class _DeferredOfferPulse extends ConsumerStatefulWidget {
  final Widget child;
  const _DeferredOfferPulse({required this.child});

  @override
  ConsumerState<_DeferredOfferPulse> createState() =>
      _DeferredOfferPulseState();
}

class _DeferredOfferPulseState extends ConsumerState<_DeferredOfferPulse>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;
  Animation<double>? _scale;

  @override
  void initState() {
    super.initState();
    // Read, do not watch: this is a one-shot, and watching would restart the
    // breathing every time anything else on the Grid rebuilt.
    if (ref.read(firstRunAnswerProvider) != FirstRunAnswer.later) return;
    // Consume it here rather than in build. Writing provider state during a
    // build is forbidden, and post-frame is late enough that the gate has
    // already swapped in HomeShell.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(firstRunAnswerProvider.notifier).state = null;
    });

    // 350ms per half breath, three full breaths, then still. A TweenSequence
    // played once rather than repeat(reverse: true) with a counter: the
    // animation ends at rest by construction, with nothing to stop and no
    // status listener to leak.
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2100),
    );
    _scale = TweenSequence<double>([
      for (var i = 0; i < 3; i++) ...[
        TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 1.018)
              .chain(CurveTween(curve: Curves.easeInOut)),
          weight: 1,
        ),
        TweenSequenceItem(
          tween: Tween(begin: 1.018, end: 1.0)
              .chain(CurveTween(curve: Curves.easeInOut)),
          weight: 1,
        ),
      ],
    ]).animate(_c!);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read once, here, rather than in build: the controller's whole existence
    // is decided at this point, so a mid-flight toggle cannot leave a half
    // configured animation. Reduce Motion means no breathing at all, not a
    // faster one: the whole point of the effect is movement.
    if (_c != null && !_c!.isAnimating && _c!.value == 0) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _c!.dispose();
        _c = null;
        _scale = null;
      } else {
        _c!.forward();
      }
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = _scale;
    if (scale == null) return widget.child;
    return AnimatedBuilder(
      animation: scale,
      builder: (_, child) => Transform.scale(scale: scale.value, child: child),
      child: widget.child,
    );
  }
}
