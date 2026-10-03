// An App Guide lesson has to END: when its action is done, and when its page
// is left. Both used to leave it armed.
//
// Done: each host screen asked "was the list empty and is it not now" (or "was
// XP zero"), which is true once per account. The guide is replayable from
// Settings, so the person most likely to open a lesson already has habits and
// tasks, and for them the dim stayed up after they had done exactly what it
// asked.
//
// Left: the dim lives inside the page and the bar stays live under it. A tab
// tap away was a way out but not an end, so the next visit to that page dimmed
// it again with a card nobody had asked for that time.
import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/providers/app_guide_provider.dart';
import 'package:grow_daily_v2/core/providers/nav_layout_provider.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/matrix/models/matrix_task.dart';
import 'package:grow_daily_v2/features/matrix/notifiers/matrix_notifier.dart';
import 'package:grow_daily_v2/features/matrix/screens/matrix_screen.dart';
import 'package:grow_daily_v2/features/onboarding/notifiers/guide_steps_provider.dart';
import 'package:grow_daily_v2/features/onboarding/screens/app_guide_screen.dart';
import 'package:grow_daily_v2/shared/widgets/coach_mark_overlay.dart';
import 'package:grow_daily_v2/shared/widgets/home_shell.dart';

import '../../helpers/landing_harness.dart';

/// Stands in for the App Guide screen: a route over the shell whose one
/// button starts [lesson] the way a guide row does.
class _GuideStandIn extends ConsumerWidget {
  final AppGuideLesson lesson;
  const _GuideStandIn(this.lesson);

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => startGuideLesson(
              context,
              ref,
              lesson,
              habitsEmpty: ref.read(habitListProvider).isEmpty,
            ),
            child: const Text('START LESSON'),
          ),
        ),
      );
}

/// Habits and Tasks side by side: a page-turn or jump between them never
/// builds Profile, which reaches for Firebase, and a widget test has none.
final _sideBySide = [
  navLayoutProvider.overrideWith((ref) =>
      NavLayoutNotifier(const [NavTab.grid, NavTab.matrix, NavTab.profile])),
];

/// A harness for a new install. LandingHarness opens the same named boxes in
/// every test, and Hive hands back a box still open from the test before,
/// saved squares and all, so they are emptied first.
Future<LandingHarness> _freshHarness({
  List<String> activeCatalogIds = const [],
  List<Override> extraOverrides = const [],
}) async {
  for (final name in ['box_settings', 'box_daily_logs', 'box_habits']) {
    if (Hive.isBoxOpen(name)) await Hive.box<dynamic>(name).clear();
  }
  final h = LandingHarness();
  await h.prepare(
    activeCatalogIds: activeCatalogIds,
    extraOverrides: extraOverrides,
  );
  return h;
}

void main() {
  late LandingHarness h;
  tearDown(() => h.dispose());

  /// Fixed frames, not pumpAndSettle: the coach-mark's ring breathes for as
  /// long as it is up.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  AppGuideLesson? lesson() => h.container.read(activeAppGuideLessonProvider);

  /// Runs [change] in the real async zone and lets its save land. A save
  /// left in flight inside fake async hangs the NEXT test's box (see
  /// LandingHarness's golden rule), which is how this file first stalled.
  Future<void> saved(WidgetTester tester, Future<void> Function() change) =>
      tester.runAsync(() async {
        await change();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

  Future<void> startLesson(WidgetTester tester, AppGuideLesson asked) async {
    await tester.binding.setSurfaceSize(const Size(402, 874));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(h.app(home: const HomeShell()));
    await pumpFrames(tester);
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    unawaited(
      nav.push(MaterialPageRoute<void>(builder: (_) => _GuideStandIn(asked))),
    );
    await pumpFrames(tester);
    await tester.tap(find.text('START LESSON'));
    await pumpFrames(tester);
    expect(lesson(), asked);
    expect(find.byType(CoachMarkOverlay), findsOneWidget,
        reason: 'the lesson is up before anything is asked of it');
  }

  group('leaving the page ends the lesson', () {
    setUp(() async {
      h = await _freshHarness(extraOverrides: _sideBySide);
    });

    testWidgets('a tab tap away from Tasks, then back, does not dim again',
        (tester) async {
      await startLesson(tester, AppGuideLesson.addTask);

      await tester.tap(find.text('Habits'));
      await pumpFrames(tester);
      expect(lesson(), isNull,
          reason: 'walking away through the bar is a Skip');

      await tester.tap(find.text('Tasks'));
      await pumpFrames(tester);
      expect(find.byType(MatrixScreen), findsOneWidget);
      expect(find.byType(CoachMarkOverlay), findsNothing,
          reason: 'coming back later must not bring an unasked dim');
    });

    testWidgets('the jump that starts a lesson does not end it',
        (tester) async {
      // The ask itself is a page change, from wherever the guide was opened
      // to the lesson's own page. It must survive that.
      await startLesson(tester, AppGuideLesson.addTask);
      await pumpFrames(tester);
      expect(lesson(), AppGuideLesson.addTask);
    });
  });

  group('closing an off-bar page ends its lesson', () {
    setUp(() async {
      h = await _freshHarness(extraOverrides: [
        navLayoutProvider.overrideWith((ref) => NavLayoutNotifier(
            const [NavTab.grid, NavTab.tasbih, NavTab.profile])),
      ]);
    });

    testWidgets('Tasks pushed for the lesson, then closed', (tester) async {
      await startLesson(tester, AppGuideLesson.addTask);
      expect(find.byType(MatrixScreen), findsOneWidget);

      await tester.pageBack();
      await pumpFrames(tester);
      expect(find.byType(MatrixScreen), findsNothing);
      expect(lesson(), isNull);
    });
  });

  // prepare() opens Hive for real, so it runs in setUp, never in a test
  // body: real IO inside the fake-async zone never completes.
  group('a replayed "add a task" ends when a task is added', () {
    setUp(() async {
      h = await _freshHarness(extraOverrides: _sideBySide);
    });

    testWidgets('with tasks already on the board', (tester) async {
      // Somebody who already uses Tasks, replaying the lesson from Settings.
      await saved(tester, () async {
        h.container
            .read(matrixProvider.notifier)
            .add('Already here', MatrixQuadrant.doFirst);
      });

      await startLesson(tester, AppGuideLesson.addTask);
      await saved(tester, () async {
        h.container
            .read(matrixProvider.notifier)
            .add('Added during the lesson', MatrixQuadrant.doFirst);
      });
      await pumpFrames(tester);

      expect(lesson(), isNull,
          reason: 'the task they were asked to add is there, so the dim goes');
      expect(find.byType(CoachMarkOverlay), findsNothing);
    });
  });

  group('a replayed "add a habit" ends when a habit is added', () {
    setUp(() async {
      h = await _freshHarness(
          activeCatalogIds: ['morning_athkar'], extraOverrides: _sideBySide);
    });

    testWidgets('with habits already on the board', (tester) async {
      await startLesson(tester, AppGuideLesson.addHabit);
      await saved(tester, () async {
        h.container.read(customHabitsProvider.notifier).add(
              name: 'Read 10 pages',
              category: HabitCategory.quran,
              frequencyType: HabitFrequencyType.daily,
              frequencyTarget: 1,
            );
      });
      await pumpFrames(tester);

      // Not null: this guest has never coloured a square, so the run carries
      // on to that step on the same screen, exactly as a first habit does.
      expect(lesson(), AppGuideLesson.colorSquare);
    });
  });

  group('a replayed "colour a square" ends when a square is coloured', () {
    setUp(() async {
      h = await _freshHarness(
        activeCatalogIds: ['morning_athkar', 'quran_daily_page'],
        extraOverrides: _sideBySide,
      );
    });

    testWidgets('with squares already coloured', (tester) async {
      await tester.pumpWidget(h.app(home: const HomeShell()));
      await pumpFrames(tester);

      Future<void> mark(String habitId) async {
        await saved(
          tester,
          () => h.container.read(dashboardProvider.notifier).completeHabit(
                habitId: habitId,
                xpReward: 10,
                goldReward: 1,
                frequencyTarget: 1,
                allHabitsDoneAfter: false,
              ),
        );
        await pumpFrames(tester);
      }

      // A square already coloured before the lesson: XP is not zero, which
      // is the state the old "XP left zero" test could never see change.
      await mark('quran_daily_page');
      expect(h.container.read(dashboardProvider).cumulativeXp, greaterThan(0));

      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      unawaited(nav.push(MaterialPageRoute<void>(
          builder: (_) => const _GuideStandIn(AppGuideLesson.colorSquare))));
      await pumpFrames(tester);
      await tester.tap(find.text('START LESSON'));
      await pumpFrames(tester);
      expect(lesson(), AppGuideLesson.colorSquare);

      await mark('morning_athkar');
      expect(lesson(), isNull,
          reason: 'a square was coloured during the lesson, so it is over');
    });
  });

  group('colouring a square is a habit mark, not XP', () {
    setUp(() async {
      h = await _freshHarness(extraOverrides: _sideBySide);
    });

    testWidgets('XP from a finished task does not tick the step',
        (tester) async {
      await tester.pumpWidget(h.app(home: const HomeShell()));
      await pumpFrames(tester);

      await saved(
        tester,
        () => h.container
            .read(dashboardProvider.notifier)
            .awardBonus(xp: 25, gold: 5),
      );
      await pumpFrames(tester);
      expect(h.container.read(dashboardProvider).cumulativeXp, greaterThan(0));

      final colour = h.container
          .read(guideStepsProvider)
          .firstWhere((st) => st.lesson == AppGuideLesson.colorSquare);
      expect(colour.done, isFalse,
          reason: 'nobody has touched a square; a task paid this XP');
    });
  });
}
