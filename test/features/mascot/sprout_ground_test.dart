// Doum standing on something on a page with nothing else under him: the
// empty Habits page and the empty Rooms page (Aziz, 2026-10-03: he floated
// mid-screen there). A short line and a soft shadow at his feet
// (GroundedSprout), drawn under him.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/mascot/sprout.dart';
import 'package:grow_daily_v2/features/mascot/sprout_ground.dart';

void main() {
  Future<void> pump(WidgetTester tester, SproutPose pose, double height,
      {ThemeData? theme}) async {
    await tester.pumpWidget(MaterialApp(
      theme: theme ?? GameTheme.light,
      home: Scaffold(
        body: Center(child: GroundedSprout(pose: pose, height: height)),
      ),
    ));
    await tester.pumpAndSettle();
  }

  for (final (pose, height) in [
    (SproutPose.pencil, 170.0),
    (SproutPose.frontWave, 120.0),
  ]) {
    testWidgets('$pose at $height: his feet on the line, the shadow under them',
        (tester) async {
      await pump(tester, pose, height);
      final doum = tester.getRect(find.byType(Sprout));
      final line = tester.getRect(find.byKey(const ValueKey('sprout-ground-line')));
      final shadow =
          tester.getRect(find.byKey(const ValueKey('sprout-ground-shadow')));
      final box = tester.getRect(find.byType(GroundedSprout));

      // The line meets his feet: each picture keeps 1.6% of its height
      // clear under them.
      expect(line.top - doum.top,
          moreOrLessEquals(GroundedSprout.groundYFor(pose, height), epsilon: 0.01));
      expect(doum.bottom - line.top, moreOrLessEquals(doum.height * 0.016, epsilon: 0.01));
      // Centred under him, the shadow straddling the line, the line wider
      // than he is.
      expect(shadow.center.dx, moreOrLessEquals(doum.center.dx, epsilon: 0.5));
      expect(line.center.dx, moreOrLessEquals(doum.center.dx, epsilon: 0.5));
      expect(shadow.center.dy, moreOrLessEquals(line.top, epsilon: 0.5));
      expect(line.width, greaterThan(doum.width * 2));
      expect(shadow.width, lessThan(doum.width));
      // The box ends with the shadow: nothing hangs below it.
      expect(box.bottom, moreOrLessEquals(shadow.bottom, epsilon: 0.5));

      // Painted line, shadow, Doum: he stands over both.
      final stack = tester.widget<Stack>(find.descendant(
        of: find.byType(GroundedSprout),
        matching: find.byType(Stack),
      ).first);
      expect((stack.children[0].key), const ValueKey('sprout-ground-line'));
      expect((stack.children[1].key), const ValueKey('sprout-ground-shadow'));
      expect(
        find.descendant(
          of: find.byWidget(stack.children[2]),
          matching: find.byType(Sprout),
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets('dark mode: the same ground, in the dark theme\'s colours',
      (tester) async {
    await pump(tester, SproutPose.frontWave, 120, theme: GameTheme.dark);
    expect(find.byKey(const ValueKey('sprout-ground-line')), findsOneWidget);
    expect(find.byKey(const ValueKey('sprout-ground-shadow')), findsOneWidget);
  });

  testWidgets(
      'in a slot narrower than the line it wants, the line fits the slot and '
      'he stays centred', (tester) async {
    // The empty Habits page: a 170pt Doum asks for a 341pt line between
    // margins that leave less on a small phone.
    await tester.pumpWidget(MaterialApp(
      theme: GameTheme.light,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 296,
            child: Column(mainAxisSize: MainAxisSize.min, children: const [
              GroundedSprout(pose: SproutPose.pencil, height: 170),
            ]),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final slot = tester.getRect(find.byType(Column));
    final line = tester.getRect(find.byKey(const ValueKey('sprout-ground-line')));
    final doum = tester.getRect(find.byType(Sprout));
    expect(line.width, moreOrLessEquals(296, epsilon: 0.5));
    expect(line.left, greaterThanOrEqualTo(slot.left - 0.5));
    expect(line.right, lessThanOrEqualTo(slot.right + 0.5));
    expect(doum.center.dx, moreOrLessEquals(slot.center.dx, epsilon: 0.5));
  });

  testWidgets(
      'answers its natural height: the empty Habits page measures it '
      '(SliverFillRemaining)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: GameTheme.light,
      home: Scaffold(
        body: CustomScrollView(slivers: const [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: GroundedSprout(pose: SproutPose.pencil, height: 170),
            ),
          ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(Sprout), findsOneWidget);
  });
}
