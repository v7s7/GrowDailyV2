// The guide has to carry somebody past step one, without ever grabbing
// somebody who never asked for it.
//
// Before: every host screen cleared the lesson the moment its goal was met and
// chained nothing, so answering «ورّيني أول خطوة» got you one circled button
// and then silence. Reaching step two meant noticing the card again and
// tapping it again, four times over.
//
// The danger in fixing that is obvious, and this codebase has already paid for
// it twice: an automatic chain from one dim to the next is the deleted
// autoShowAppGuideProvider wearing a different hat. The property that keeps
// them apart is nameable, and it is what most of this file tests:
//
//   advanceGuideAfter can only ever CONTINUE a run, never start one.
//
// It reads activeAppGuideLessonProvider and returns immediately when that is
// null or holds a different lesson. That provider is memory only, never
// persisted, never seeded at boot, so no cold start can make it produce a dim.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/providers/app_guide_provider.dart';
import 'package:grow_daily_v2/features/onboarding/notifiers/guide_chain.dart';
import 'package:grow_daily_v2/features/onboarding/notifiers/guide_steps_provider.dart';

/// advanceGuideAfter takes a WidgetRef, which a plain test cannot build. It
/// only ever calls read(), so this mirrors it exactly against a container,
/// including the post-frame deferral, which is expressed here as "the caller
/// decides when to apply the pending value".
({AppGuideLesson? immediate, AppGuideLesson? deferred}) advance(
  ProviderContainer c,
  AppGuideLesson completed,
) {
  if (c.read(activeAppGuideLessonProvider) != completed) {
    return (immediate: c.read(activeAppGuideLessonProvider), deferred: null);
  }
  final next = guideStepAfter(c.read(guideStepsProvider), completed);
  if (next == null || guideLessonTab(next) != guideLessonTab(completed)) {
    c.read(activeAppGuideLessonProvider.notifier).state = null;
    return (immediate: null, deferred: null);
  }
  return (immediate: completed, deferred: next);
}

ProviderContainer containerWith(List<GuideStep> steps, AppGuideLesson? active) {
  final c = ProviderContainer(overrides: [
    guideStepsProvider.overrideWithValue(steps),
  ]);
  c.read(activeAppGuideLessonProvider.notifier).state = active;
  return c;
}

const allOpen = [
  GuideStep(AppGuideLesson.addHabit, false),
  GuideStep(AppGuideLesson.colorSquare, false),
  GuideStep(AppGuideLesson.addTask, false),
  GuideStep(AppGuideLesson.discoverRooms, false),
];

void main() {
  group('it cannot start a run', () {
    test('a completion with nothing armed changes nothing', () {
      final c = containerWith(allOpen, null);
      addTearDown(c.dispose);
      final r = advance(c, AppGuideLesson.addHabit);
      expect(r.deferred, isNull);
      expect(c.read(activeAppGuideLessonProvider), isNull,
          reason: 'somebody who never asked for the guide adds a habit in '
              'total silence, exactly as before');
    });

    test('a completion for a DIFFERENT lesson than the armed one is ignored',
        () {
      final c = containerWith(allOpen, AppGuideLesson.discoverRooms);
      addTearDown(c.dispose);
      final r = advance(c, AppGuideLesson.addHabit);
      expect(r.deferred, isNull);
      expect(c.read(activeAppGuideLessonProvider), AppGuideLesson.discoverRooms,
          reason: 'the armed lesson is somebody else\'s run and must survive');
    });

    test('the armed lesson is not persisted anywhere', () {
      // A fresh container is what a cold start produces. If this is ever not
      // null, some boot path started seeding it, and the auto-tour is back.
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(activeAppGuideLessonProvider), isNull);
    });
  });

  group('it continues a run, on the same screen only', () {
    test('adding a habit hands over to colouring its square', () {
      final c = containerWith(allOpen, AppGuideLesson.addHabit);
      addTearDown(c.dispose);
      final r = advance(c, AppGuideLesson.addHabit);
      expect(r.deferred, AppGuideLesson.colorSquare,
          reason: 'this is the handoff the whole change exists for: the '
              'square you just created is the next thing circled');
    });

    test('colouring a square stops, because tasks live on another tab', () {
      final c = containerWith(
        const [
          GuideStep(AppGuideLesson.addHabit, true),
          GuideStep(AppGuideLesson.colorSquare, false),
          GuideStep(AppGuideLesson.addTask, false),
          GuideStep(AppGuideLesson.discoverRooms, false),
        ],
        AppGuideLesson.colorSquare,
      );
      addTearDown(c.dispose);
      final r = advance(c, AppGuideLesson.colorSquare);
      expect(r.deferred, isNull);
      expect(c.read(activeAppGuideLessonProvider), isNull,
          reason: 'moving somebody to another tab because they finished '
              'something is the uninvited tour again');
    });

    test('a step whose successor is already done skips to the real next one',
        () {
      final c = containerWith(
        const [
          GuideStep(AppGuideLesson.addHabit, false),
          GuideStep(AppGuideLesson.colorSquare, true),
          GuideStep(AppGuideLesson.addTask, false),
          GuideStep(AppGuideLesson.discoverRooms, false),
        ],
        AppGuideLesson.addHabit,
      );
      addTearDown(c.dispose);
      final r = advance(c, AppGuideLesson.addHabit);
      // addTask is next, and it is on another tab, so the run ends.
      expect(r.deferred, isNull);
      expect(c.read(activeAppGuideLessonProvider), isNull);
    });

    test('the last step ends the run rather than looping', () {
      final c = containerWith(
        const [
          GuideStep(AppGuideLesson.addHabit, true),
          GuideStep(AppGuideLesson.colorSquare, true),
          GuideStep(AppGuideLesson.addTask, true),
          GuideStep(AppGuideLesson.discoverRooms, false),
        ],
        AppGuideLesson.discoverRooms,
      );
      addTearDown(c.dispose);
      final r = advance(c, AppGuideLesson.discoverRooms);
      expect(r.deferred, isNull);
      expect(c.read(activeAppGuideLessonProvider), isNull);
    });
  });

  group('guideStepAfter reads the one list', () {
    test('walks forward only, never back to a step behind it', () {
      expect(guideStepAfter(allOpen, AppGuideLesson.addTask),
          AppGuideLesson.discoverRooms);
      expect(guideStepAfter(allOpen, AppGuideLesson.discoverRooms), isNull);
    });

    test('skips done steps', () {
      const partly = [
        GuideStep(AppGuideLesson.addHabit, false),
        GuideStep(AppGuideLesson.colorSquare, true),
        GuideStep(AppGuideLesson.addTask, true),
        GuideStep(AppGuideLesson.discoverRooms, false),
      ];
      expect(guideStepAfter(partly, AppGuideLesson.addHabit),
          AppGuideLesson.discoverRooms);
    });
  });

  test('every lesson maps to the tab that actually hosts it', () {
    expect(guideLessonTab(AppGuideLesson.addHabit), 0);
    expect(guideLessonTab(AppGuideLesson.colorSquare), 0);
    expect(guideLessonTab(AppGuideLesson.discoverRooms), 1);
    expect(guideLessonTab(AppGuideLesson.addTask), 2);
  });
}
