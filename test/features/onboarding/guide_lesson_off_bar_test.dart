// An App Guide lesson for a page the bar does not hold.
//
// startGuideLesson asked HomeShell for the lesson's tab and THEN popped back
// to the shell. Riverpod calls listeners at once, so the shell had already
// pushed the page (it is not in the bar), and the pop right after closed it
// again: the lesson opened nothing. True for Tasks since Tasks could leave
// the bar, and for Habits since 2026-09-30.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/providers/app_guide_provider.dart';
import 'package:grow_daily_v2/core/providers/nav_layout_provider.dart';
import 'package:grow_daily_v2/features/grid/screens/grid_screen.dart';
import 'package:grow_daily_v2/features/matrix/screens/matrix_screen.dart';
import 'package:grow_daily_v2/features/onboarding/screens/app_guide_screen.dart';
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
            onPressed: () =>
                startGuideLesson(context, ref, lesson, habitsEmpty: true),
            child: const Text('START LESSON'),
          ),
        ),
      );
}

void main() {
  late LandingHarness h;
  tearDown(() => h.dispose());

  /// Fixed frames, not pumpAndSettle: an empty quadrant's "+" and the
  /// lesson's coach-mark both animate for as long as they are up.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> runLesson(WidgetTester tester, AppGuideLesson lesson) async {
    await tester.binding.setSurfaceSize(const Size(402, 874));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(h.app(home: const HomeShell()));
    await pumpFrames(tester);
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute<void>(builder: (_) => _GuideStandIn(lesson)));
    await pumpFrames(tester);
    await tester.tap(find.text('START LESSON'));
    await pumpFrames(tester);
    expect(find.text('START LESSON'), findsNothing,
        reason: 'the guide pops back to the shell');
    expect(h.container.read(activeAppGuideLessonProvider), lesson);
  }

  group('a bar without Habits', () {
    setUp(() async {
      h = LandingHarness();
      await h.prepare(extraOverrides: [
        navLayoutProvider.overrideWith(
            (ref) => NavLayoutNotifier(const [NavTab.matrix, NavTab.tasbih, NavTab.profile])),
      ]);
    });

    testWidgets('"add a habit" opens the Habits page', (tester) async {
      await runLesson(tester, AppGuideLesson.addHabit);
      expect(find.byType(GridScreen), findsOneWidget);
    });
  });

  group('a bar without Tasks', () {
    setUp(() async {
      h = LandingHarness();
      await h.prepare(extraOverrides: [
        navLayoutProvider.overrideWith(
            (ref) => NavLayoutNotifier(const [NavTab.grid, NavTab.tasbih, NavTab.profile])),
      ]);
    });

    testWidgets('"add a task" opens the Tasks page', (tester) async {
      await runLesson(tester, AppGuideLesson.addTask);
      expect(find.byType(MatrixScreen), findsOneWidget);
    });
  });
}
