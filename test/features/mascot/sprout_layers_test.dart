// Sprout.underlay and Sprout.overlay: what the launch curtain paints round a
// pose (the winter fire glows, the hourglass sand, the treadmill belt) sits
// in the pose's own box, under and over its picture, and leaves with the
// pose. Without them the picture is the bare Image it always was.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/features/mascot/sprout.dart';

void main() {
  const under = ValueKey('under');
  const over = ValueKey('over');

  Future<void> pump(WidgetTester tester, SproutPose pose, {bool layers = true}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: Sprout(
              pose: pose,
              height: 150,
              entrance: SproutEntrance.none,
              idleBreaths: 0,
              underlay: layers ? const ColoredBox(key: under, color: Colors.red) : null,
              overlay: layers ? const ColoredBox(key: over, color: Colors.blue) : null,
            ),
          ),
        ),
      );

  testWidgets('fill the pose\'s box, one under and one over its picture',
      (tester) async {
    await pump(tester, SproutPose.winterHourglass);
    final box = tester.getRect(find.byType(Sprout));
    final size = Sprout.sizeOf(SproutPose.winterHourglass, 150);
    expect(box.width, closeTo(size.width, .01));
    expect(box.height, closeTo(size.height, .01));
    for (final layer in [under, over]) {
      final r = tester.getRect(find.byKey(layer));
      expect(
        [r.left, r.top, r.right, r.bottom],
        [
          for (final v in [box.left, box.top, box.right, box.bottom])
            closeTo(v, .01),
        ],
      );
    }
    // In paint order: the tree's own order.
    final order = [
      for (final e in find
          .byWidgetPredicate(
            (w) => w.key == under || w.key == over || w is Image,
          )
          .evaluate())
        e.widget.key == under
            ? 'under'
            : e.widget.key == over
                ? 'over'
                : 'picture',
    ];
    expect(order, ['under', 'picture', 'over']);
  });

  testWidgets('leave with the pose', (tester) async {
    await pump(tester, SproutPose.winterHourglass);
    await pump(tester, SproutPose.winterHappyHeart, layers: false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(under), findsNothing);
    expect(find.byKey(over), findsNothing);
  });

  testWidgets('without them the picture is the bare Image, keyed by the pose',
      (tester) async {
    await pump(tester, SproutPose.frontWave, layers: false);
    expect(find.byKey(const ValueKey(SproutPose.frontWave)), findsOneWidget);
    expect(
      tester.widget(find.byKey(const ValueKey(SproutPose.frontWave))),
      isA<Image>(),
    );
  });
}
