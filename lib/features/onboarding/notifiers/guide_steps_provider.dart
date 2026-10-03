import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_guide_provider.dart';
import '../../../core/providers/nav_layout_provider.dart' show NavTab;
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../../habits/notifiers/custom_habits_notifier.dart'
    show habitListProvider;
import '../../matrix/notifiers/matrix_notifier.dart';
import '../../rooms/notifiers/rooms_notifier.dart' show myRoomCodesProvider;

/// One step of the guide, and whether this person has already done it.
class GuideStep {
  final AppGuideLesson lesson;
  final bool done;
  const GuideStep(this.lesson, this.done);
}

/// THE guide — one ordered list, one definition of "done", read by both
/// places the guide appears.
///
/// There used to be two lists. The Grid showed a "Get Started" checklist with
/// its own two steps (add a habit, add a task) and Settings showed an App
/// Guide with four (add a habit, track a day, add a task, join a Room). Two of
/// the four were duplicates, so the same instruction existed twice in two
/// different places — and the one the Grid list left out was
/// [AppGuideLesson.colorSquare], which is the entire product. Someone could
/// finish the Grid checklist, watch it disappear, and never once have coloured
/// a square.
///
/// Worse, the Grid list's second step pointed *away*: tapping "add your first
/// task" switched to the Tasks tab, so a brand-new user's second instruction
/// was to leave the screen the app is named after before they had used it
/// once.
///
/// Now there is one list. The order is the order someone actually meets these
/// things: build a habit, mark a day, then the wider app.
///
/// "Done" is always read from real data rather than a remembered flag — a
/// person who added a habit before ever opening the guide has already done
/// step one, and being told to do it again would be the guide arguing with
/// what it can plainly see.
final guideStepsProvider = Provider<List<GuideStep>>((ref) {
  final habits = ref.watch(habitListProvider);
  final dash = ref.watch(dashboardProvider);
  final matrixState = ref.watch(matrixProvider);
  final roomsSeen = ref.watch(appGuideRoomsSeenProvider);
  // Being IN a room settles the step on its own, whatever the flag says.
  // asData, so a stream that has not answered yet leaves the flag to decide
  // rather than briefly un-ticking a step that is done.
  final inARoom =
      ref.watch(myRoomCodesProvider).asData?.value.isNotEmpty ?? false;
  return [
    GuideStep(AppGuideLesson.addHabit, habits.isNotEmpty),
    // A habit mark, not XP. This read cumulativeXp > 0, on the reasoning
    // that any coloured square earns XP, which is true, but XP is not only
    // earned on squares: a finished task pays it, and so do the tasbih and a
    // room's bonus. So somebody who added a task and ticked it off before
    // ever touching the board saw «لوّن مربّع اليوم» ticked, and the one step
    // that teaches what the app IS was skipped for them. See habitMarkCount.
    GuideStep(AppGuideLesson.colorSquare, habitMarkCount(dash) > 0),
    GuideStep(AppGuideLesson.addTask, matrixState.tasks.isNotEmpty),
    // Rooms is the one step with no single source of truth. A guest cannot
    // join at all and a signed-in person may look without joining, so the
    // flag remembers that the guide took them there — but the flag is LOCAL
    // and membership is not, so on a new device (or a reinstall) somebody
    // sitting in three rooms was told to go and join one. That is the guide
    // arguing with what it can plainly see, which the doc comment above
    // gives as the reason this list derives from real data wherever it can.
    // Either signal completes it: visited, or actually in one.
    GuideStep(AppGuideLesson.discoverRooms, roomsSeen || inARoom),
  ];
});

/// The next thing to do, or null once the whole guide is finished.
final nextGuideStepProvider = Provider<GuideStep?>((ref) {
  for (final step in ref.watch(guideStepsProvider)) {
    if (!step.done) return step;
  }
  return null;
});

/// How many steps are done, for the "2 of 4" the Grid card shows.
final guideProgressProvider = Provider<({int done, int total})>((ref) {
  final steps = ref.watch(guideStepsProvider);
  return (done: steps.where((s) => s.done).length, total: steps.length);
});

/// The step after [lesson], or null when [lesson] was the last unfinished one.
///
/// Reads the same single list everything else does, so "what is next" can
/// never disagree between the card, Settings and the chain.
AppGuideLesson? guideStepAfter(List<GuideStep> steps, AppGuideLesson lesson) {
  var passed = false;
  for (final step in steps) {
    if (step.lesson == lesson) {
      passed = true;
      continue;
    }
    if (passed && !step.done) return step.lesson;
  }
  return null;
}

/// Every mark this account has put on a habit: finished habit-days, green
/// squares (a past day's square counts here and nowhere else), and today's
/// and the still-open yesterday's taps, which is where a habit counted
/// several times a day shows its first tap before the day is finished.
///
/// What «لوّن مربّع اليوم» means by done, and what the Grid listens to for
/// the lesson's own end. Habit-only on purpose: XP, which this used to be,
/// also comes from tasks, the tasbih and rooms.
///
/// [withYesterday] false for that listener. Yesterday's counts are read in
/// AFTER a load says it has finished (readGraceDay runs once the loaded
/// state is set), so between midnight and the 10:00 cutoff a reload would
/// look like a tap and end a lesson nobody had finished. The lesson circles
/// today's square anyway; a tap on yesterday's is outside its ring.
int habitMarkCount(DashboardState d, {bool withYesterday = true}) =>
    d.totalCompletions +
    d.totalGreenSquares +
    d.completions.values.fold<int>(0, (a, b) => a + b) +
    (withYesterday
        ? d.graceCompletions.values.fold<int>(0, (a, b) => a + b)
        : 0);

/// The page a lesson's target lives on.
///
/// By [NavTab], not by position: the bar is customisable, so a position
/// says nothing about which page is showing. startGuideLesson asks for
/// this page, the chain compares two lessons' pages, and HomeShell ends a
/// lesson whose page has been left (see [guideLessonLivesOn]). One answer
/// for all three, so they cannot disagree about where a lesson is.
NavTab guideLessonTab(AppGuideLesson lesson) => switch (lesson) {
      AppGuideLesson.addHabit || AppGuideLesson.colorSquare => NavTab.grid,
      AppGuideLesson.discoverRooms => NavTab.profile,
      AppGuideLesson.addTask => NavTab.matrix,
    };

/// Whether [tab] showing keeps [lesson] going.
///
/// Its own page, and for the Rooms lesson the Rooms page too: that lesson
/// starts on Profile's Rooms row and finishes on the Rooms page's Create
/// and Join buttons, and somebody with Rooms in their bar who answers it by
/// tapping that tab has done exactly what it asked.
bool guideLessonLivesOn(AppGuideLesson lesson, NavTab tab) =>
    guideLessonTab(lesson) == tab ||
    (lesson == AppGuideLesson.discoverRooms && tab == NavTab.rooms);
