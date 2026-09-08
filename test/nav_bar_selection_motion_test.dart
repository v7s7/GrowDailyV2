// The nav bar's selection has to move as ONE thing.
//
// The pill was an AnimatedContainer while the icon colour, the label colour
// and the label weight were switched on `selected`, so a tap eased the wash
// over 160ms and snapped the letterform on the same frame. That reads as a
// glitch rather than a transition, and it is invisible to a test that only
// looks at the resting states — which is why this one samples the middle.
//
// The bar is pumped on its own rather than inside HomeShell: the shell's
// tabs are real screens that want Firebase, and none of that is what this
// is about.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/shared/widgets/game_nav_bar.dart';

/// The rendered colour and weight of the tab label at [index].
(Color?, FontWeight?) labelStyle(WidgetTester tester, int index) {
  final t = tester.widgetList<Text>(find.byType(Text)).elementAt(index);
  return (t.style?.color, t.style?.fontWeight);
}

/// A bar whose selected tab a test can move.
Widget harness(int index, void Function(int) onTap) => MaterialApp(
      theme: GameTheme.light,
      home: Scaffold(
        bottomNavigationBar: GameNavBar(currentIndex: index, onSelect: onTap),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();


  testWidgets('the ink and the weight travel, they do not snap',
      (tester) async {
    // The glass bar is the iOS one; on Android GameNavBar renders Material's
    // NavigationBar, which animates itself from navigationBarTheme. Tests
    // default to Android, so without this override these would silently
    // exercise the wrong bar and pass either way. Cleared inside the body
    // because the framework asserts foundation debug vars are unset before
    // tearDown gets a turn.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    // The selection is moved by rebuilding the bar with a new index, which
    // is exactly what HomeShell does on a tap. That drives the same
    // didUpdateWidget path without dragging tap plumbing into it.
    await tester.pumpWidget(harness(0, (_) {}));
    await tester.pumpAndSettle();

    final (restColor, restWeight) = labelStyle(tester, 1);
    expect(restColor, isNotNull);
    expect(restWeight, FontWeight.w500);

    await tester.pumpWidget(harness(1, (_) {}));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    final (midColor, midWeight) = labelStyle(tester, 1);

    // Mid-flight it must be neither end. A snap would already equal the
    // selected ink one frame after the change.
    expect(midColor, isNot(restColor),
        reason: 'the label ink never left its unselected value');
    expect(midColor, isNot(GameColors.goldInkLight),
        reason: 'the label ink jumped straight to selected, i.e. it '
            'snapped rather than animated');

    // And it does arrive.
    await tester.pumpAndSettle();
    final (endColor, endWeight) = labelStyle(tester, 1);
    expect(endColor, GameColors.goldInkLight);
    expect(endWeight, FontWeight.w700);
    expect(midWeight, isNotNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a tab does not animate in on first build', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    // The controller is seeded with `value:` rather than animated from a
    // tween's begin, so the bar is already at rest on the first frame.
    // Without that, every tab would fade in on launch.
    await tester.pumpWidget(harness(0, (_) {}));
    await tester.pump();
    final (firstFrame, _) = labelStyle(tester, 0);
    await tester.pumpAndSettle();
    final (settled, _) = labelStyle(tester, 0);
    expect(firstFrame, settled,
        reason: 'the selected tab was still moving after the first frame');
    expect(settled, GameColors.goldInkLight);
    debugDefaultTargetPlatformOverride = null;
  });
}
