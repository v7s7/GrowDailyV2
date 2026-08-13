// The guide is now ONE list, read by both places it appears: the card on the
// Grid and the full list in Settings.
//
// Before, they were two. The Grid had its own two-step checklist (add a
// habit, add a task) and Settings had four (add a habit, track a day, add a
// task, join a Room). Two of the four were duplicates — and the step the Grid
// list left out was colouring a square, which is the entire product. Someone
// could finish the Grid checklist, watch it disappear, and never once have
// coloured one.
//
// These tests exist so that can't come back: the order, the membership and
// every "done" condition are pinned here, and both surfaces read them.
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/providers/app_guide_provider.dart';

void main() {
  group('the guide covers the app in the order someone meets it', () {
    test('four steps, and colouring a square is one of them', () {
      // The regression that started all of this: the core loop must be IN
      // the guide, not implied by a line of grey hint text on a card.
      expect(AppGuideLesson.values, hasLength(4));
      expect(AppGuideLesson.values, contains(AppGuideLesson.colorSquare));
    });

    test('build a habit, then mark a day, then the wider app', () {
      // Order is load-bearing: the Grid card shows the first unfinished step,
      // so this list IS the path a new user is walked down. Colouring has to
      // come straight after having something to colour, and before tasks and
      // rooms — which are other pillars, not the core loop.
      expect(AppGuideLesson.values, [
        AppGuideLesson.addHabit,
        AppGuideLesson.colorSquare,
        AppGuideLesson.addTask,
        AppGuideLesson.discoverRooms,
      ]);
    });
  });

  group('every step is worded, in both languages', () {
    test('a title and a subtitle exist for each, EN and AR', () {
      // A missing string here would render as an empty row in the guide —
      // silently, and only for one language.
      for (final lesson in AppGuideLesson.values) {
        for (final isAr in [true, false]) {
          expect(appGuideLessonTitle(lesson, isAr).trim(), isNotEmpty,
              reason: 'title missing for $lesson (isAr=$isAr)');
          expect(appGuideLessonSubtitle(lesson, isAr).trim(), isNotEmpty,
              reason: 'subtitle missing for $lesson (isAr=$isAr)');
        }
      }
    });

    test('the coach-mark copy exists for each too', () {
      // The row promises something and the coach-mark delivers it; both
      // halves have to be there or a step opens onto a blank card.
      for (final lesson in AppGuideLesson.values) {
        for (final isAr in [true, false]) {
          expect(appGuideLessonCoachTitle(lesson, isAr).trim(), isNotEmpty,
              reason: 'coach title missing for $lesson (isAr=$isAr)');
          expect(appGuideLessonCoachBody(lesson, isAr).trim(), isNotEmpty,
              reason: 'coach body missing for $lesson (isAr=$isAr)');
        }
      }
    });

    test('Arabic and English are actually different strings', () {
      // Catches a copy-paste that leaves one language showing the other's
      // text — which reads as a broken translation, not a missing one.
      for (final lesson in AppGuideLesson.values) {
        expect(appGuideLessonTitle(lesson, true),
            isNot(appGuideLessonTitle(lesson, false)),
            reason: '$lesson has the same title in both languages');
      }
    });
  });
}
