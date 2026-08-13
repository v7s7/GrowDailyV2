import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/app_guide_provider.dart';
import '../notifiers/guide_steps_provider.dart';
import '../../../core/providers/home_tab_provider.dart';
import '../../../core/theme/game_theme.dart';
import '../../grid/notifiers/weekly_grid_notifier.dart';
import '../../habits/notifiers/custom_habits_notifier.dart' show habitListProvider;

/// One lesson row's content — icon/color plus the enticing "why" copy shown
/// here, kept separate from [appGuideLessonCoachTitle]/[appGuideLessonCoachBody]
/// (the direct "tap here" copy shown once you're actually looking at the
/// real button on Grid/Matrix/Profile), since the two serve different jobs:
/// this row has to make someone want to tap it, the coach-mark just has to
/// tell them what to do once they're there.
class _Lesson {
  final AppGuideLesson id;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool done;
  const _Lesson({
    required this.id,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.done,
  });
}

/// A hands-on, replayable reference for the app's four core actions — add a
/// habit, track a day, add a task, find a Room — reachable any time from
/// Settings (see profile_screen_settings.dart's Support group) rather than
/// a one-shot tour you either catch on day one or never see again.
///
/// Each row doesn't explain in place; tapping it jumps to the real tab and
/// circles the real, live button with [CoachMarkOverlay] (see
/// grid_screen.dart/matrix_screen.dart/profile_screen.dart, which each
/// render one keyed off [activeAppGuideLessonProvider]) — the person does
/// the actual thing themselves, this screen just points the way. That's
/// the whole design brief: teach, don't do it for them.
///
/// Every row is always tappable, done or not — a done lesson just swaps its
/// circle for a checkmark and its chevron for a replay icon, since
/// "done once" and "never worth seeing again" aren't the same thing for a
/// reference screen someone opens specifically to be reminded how
/// something works.
class AppGuideScreen extends ConsumerWidget {
  const AppGuideScreen({super.key});


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final isAr = s.isAr;

    // Only for startGuideLesson's habitsEmpty redirect — every "is this step
    // done" question is answered by guideStepsProvider below.
    final habits = ref.watch(habitListProvider);

    // One source of truth, shared with the Grid's guide card — see
    // guideStepsProvider. This screen used to build its own list with its own
    // copy and its own done-conditions, which is exactly how it drifted out
    // of step with the Grid's checklist in the first place.
    final steps = ref.watch(guideStepsProvider);
    final lessons = [
      for (final step in steps)
        _Lesson(
          id: step.lesson,
          icon: _iconFor(step.lesson),
          color: _colorFor(step.lesson),
          title: appGuideLessonTitle(step.lesson, isAr),
          subtitle: appGuideLessonSubtitle(step.lesson, isAr),
          done: step.done,
        ),
    ];

    return Scaffold(
      backgroundColor: gp.bg,
      appBar: AppBar(
        backgroundColor: gp.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(
          isAr ? 'دليل التطبيق' : 'App Guide',
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800, color: gp.textPrimary),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            isAr
                ? 'دروس سريعة وعملية — كل درس يدلّك على الزر الحقيقي لتجرّبه بنفسك.'
                : 'Quick, hands-on lessons — each one points you to the real button so you can try it yourself.',
            style: TextStyle(fontSize: 13, height: 1.5, color: gp.textSec),
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: gp.surface,
              borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
              border: Border.all(color: gp.border, width: 0.5),
            ),
            child: Column(
              children: [
                for (var i = 0; i < lessons.length; i++) ...[
                  if (i != 0) Container(height: 0.5, color: gp.divider),
                  _LessonRow(
                    lesson: lessons[i],
                    isFirst: i == 0,
                    isLast: i == lessons.length - 1,
                    onTap: () => startGuideLesson(
                      context,
                      ref,
                      lessons[i].id,
                      habitsEmpty: habits.isEmpty,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LessonRow extends StatelessWidget {
  final _Lesson lesson;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;
  const _LessonRow({
    required this.lesson,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.only(
        topLeft: isFirst ? const Radius.circular(GameSpacing.cardRadius) : Radius.zero,
        topRight: isFirst ? const Radius.circular(GameSpacing.cardRadius) : Radius.zero,
        bottomLeft: isLast ? const Radius.circular(GameSpacing.cardRadius) : Radius.zero,
        bottomRight: isLast ? const Radius.circular(GameSpacing.cardRadius) : Radius.zero,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: lesson.color.withOpacity(0.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(lesson.icon, size: 18, color: lesson.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lesson.title,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: gp.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    lesson.subtitle,
                    style: TextStyle(fontSize: 11.5, color: gp.textSec),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              lesson.done ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 18,
              color: lesson.done ? GameColors.emerald : gp.textTert,
            ),
            const SizedBox(width: 6),
            Icon(
              lesson.done ? Icons.replay_rounded : Icons.chevron_right_rounded,
              size: 17,
              color: gp.textTert,
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 280.ms);
  }
}

/// Jumps to the tab that owns [lesson] and arms its coach-mark, so the
/// person does the real thing on the real button.
///
/// Shared by both places the guide appears — AppGuideScreen's full list and
/// the Grid's guide card — so a step behaves identically whichever one
/// launched it. [popFirst] is false for the Grid card, which isn't a route
/// and has nothing to pop.
void startGuideLesson(
  BuildContext context,
  WidgetRef ref,
  AppGuideLesson lesson, {
  required bool habitsEmpty,
  bool popFirst = true,
}) {
    HapticFeedback.selectionClick();
    final isAr = S.of(context).isAr;
    var target = lesson;

    // Coloring a square needs a habit row to color in the first place — if
    // there isn't one yet, redirect to that lesson instead of spotlighting
    // an empty Grid with nothing to circle.
    if (lesson == AppGuideLesson.colorSquare && habitsEmpty) {
      target = AppGuideLesson.addHabit;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(isAr
              ? 'أضف عادة أولاً — لنفعل ذلك الآن.'
              : "Add a habit first — let's do that now."),
        ),
      );
    }

    if (target == AppGuideLesson.discoverRooms) {
      markAppGuideRoomsSeen(ref);
    }

    // The coach-mark for this lesson circles *today's* square specifically
    // (see grid_screen_table.dart's todayCellKey) — if Grid was left
    // scrolled to a past or future week, today's square isn't even in the
    // tree to find, so the spotlight would silently never appear. Jumping
    // back to the current week first guarantees it's always there.
    if (target == AppGuideLesson.colorSquare) {
      ref.read(weeklyGridProvider.notifier).goToCurrentWeek();
    }

    final tabIndex = switch (target) {
      AppGuideLesson.addHabit || AppGuideLesson.colorSquare => 0,
      AppGuideLesson.discoverRooms => 1,
      AppGuideLesson.addTask => 2,
    };
    // Instant, not animated — this screen is about to pop, and HomeShell's
    // PageView sits directly underneath it, so an animated page-turn here
    // would run at the same time as the pop transition and look like a
    // glitchy double-shift instead of one clean motion. See
    // requestedHomeTabInstantProvider's doc comment.
    ref.read(requestedHomeTabInstantProvider.notifier).state = true;
    ref.read(requestedHomeTabProvider.notifier).state = tabIndex;
    ref.read(activeAppGuideLessonProvider.notifier).state = target;
    if (popFirst) Navigator.of(context).pop();
  }

IconData _iconFor(AppGuideLesson lesson) => switch (lesson) {
      AppGuideLesson.addHabit => Icons.add_circle_rounded,
      AppGuideLesson.colorSquare => Icons.grid_view_rounded,
      AppGuideLesson.addTask => Icons.bolt_rounded,
      AppGuideLesson.discoverRooms => Icons.groups_rounded,
    };

Color _colorFor(AppGuideLesson lesson) => switch (lesson) {
      AppGuideLesson.addHabit => GameColors.emerald,
      AppGuideLesson.colorSquare => GameColors.gold,
      AppGuideLesson.addTask => GameColors.error,
      AppGuideLesson.discoverRooms => GameColors.iconStreak,
    };
