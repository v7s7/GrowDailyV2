// Sprout.cutSwap: a pose change as a cut, for a sprout moved as a whole at
// the swap (the launch curtain's afternoon scenes). The old pose leaves in
// the frame the new one arrives, and the new one is whole at once with the
// swap's squash kept. Without it the house crossfade holds the old pose
// under the new one for a moment, as it always has.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/features/mascot/sprout.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    SproutPose pose, {
    bool cut = true,
    bool reduced = false,
  }) =>
      tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: Center(
                child: Sprout(
                  pose: pose,
                  height: 150,
                  entrance: SproutEntrance.none,
                  idleBreaths: 0,
                  cutSwap: cut,
                ),
              ),
            ),
          ),
        ),
      );

  Finder picture(SproutPose pose) => find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is ResizeImage &&
            ((w.image as ResizeImage).imageProvider as AssetImage).assetName ==
                pose.asset,
      );

  /// How much of [f] shows through the opacities above it.
  double shown(WidgetTester tester, Finder f) {
    var o = 1.0;
    tester.element(f).visitAncestorElements((e) {
      final w = e.widget;
      if (w is Opacity) o *= w.opacity;
      if (w is FadeTransition) o *= w.opacity.value;
      return true;
    });
    return o;
  }

  final full = Sprout.sizeOf(SproutPose.winkJump, 150).height;

  testWidgets('a cut: the old pose goes in the swap frame, the new one is '
      'whole, the squash kept', (tester) async {
    await pump(tester, SproutPose.treadmill);
    expect(shown(tester, picture(SproutPose.treadmill)), 1);
    await pump(tester, SproutPose.winkJump);
    expect(picture(SproutPose.treadmill), findsNothing);
    expect(shown(tester, picture(SproutPose.winkJump)), 1);
    expect(
      tester.getRect(picture(SproutPose.winkJump)).height,
      closeTo(.88 * full, .5),
      reason: 'the swap\'s squash, from the feet',
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(picture(SproutPose.treadmill), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.getRect(picture(SproutPose.winkJump)).height,
      closeTo(full, .01),
    );
  });

  testWidgets('Reduce Motion: the same cut, and no squash', (tester) async {
    await pump(tester, SproutPose.treadmill, reduced: true);
    await pump(tester, SproutPose.winkJump, reduced: true);
    expect(picture(SproutPose.treadmill), findsNothing);
    expect(shown(tester, picture(SproutPose.winkJump)), 1);
    expect(
      tester.getRect(picture(SproutPose.winkJump)).height,
      closeTo(full, .01),
    );
  });

  testWidgets('without it the old pose is held under the new one a moment',
      (tester) async {
    await pump(tester, SproutPose.treadmill, cut: false);
    await pump(tester, SproutPose.winkJump, cut: false);
    expect(shown(tester, picture(SproutPose.treadmill)), 1);
    expect(shown(tester, picture(SproutPose.winkJump)), 0);
    await tester.pump(const Duration(milliseconds: 400));
    expect(picture(SproutPose.treadmill), findsNothing);
    expect(shown(tester, picture(SproutPose.winkJump)), 1);
  });
}
