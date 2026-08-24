import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_guide_provider.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../../habits/notifiers/custom_habits_notifier.dart'
    show habitListProvider;
import '../../matrix/notifiers/matrix_notifier.dart';

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
  return [
    GuideStep(AppGuideLesson.addHabit, habits.isNotEmpty),
    // cumulativeXp, not a green-square count: any coloured square earns XP,
    // and the lesson is "a square responds to you", not "get it green".
    GuideStep(AppGuideLesson.colorSquare, dash.cumulativeXp > 0),
    GuideStep(AppGuideLesson.addTask, matrixState.tasks.isNotEmpty),
    // Rooms can't derive "done" from data the way the others can - a guest
    // can't join at all, and a signed-in person may look without joining - so
    // this one remembers that the guide took them there. See
    // appGuideRoomsSeenProvider.
    GuideStep(AppGuideLesson.discoverRooms, roomsSeen),
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

/// Which tab a lesson's target lives on: 0 Grid, 1 Profile, 2 Tasks.
///
/// Duplicated deliberately from startGuideLesson's own switch rather than
/// shared, because that one also has side effects (it WRITES the tab). This
/// is a pure question, and the chain needs to ask it without answering it.
int guideLessonTab(AppGuideLesson lesson) => switch (lesson) {
      AppGuideLesson.addHabit || AppGuideLesson.colorSquare => 0,
      AppGuideLesson.discoverRooms => 1,
      AppGuideLesson.addTask => 2,
    };
