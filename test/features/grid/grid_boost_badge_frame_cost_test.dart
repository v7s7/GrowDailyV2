// The 2x flame on a room-boosted habit pulses exactly as it did, and a pulse
// frame no longer rebuilds, re-lays out and repaints the Grid around it.
//
// The flame repeats a scale pulse for as long as the boost lasts, so it asks
// for a frame at every vsync (up to 120 a second on a ProMotion iPhone). As
// flutter_animate's ScaleEffect, each tick rebuilt an AnimatedBuilder under
// the board's LayoutBuilder, and a dirty element under a LayoutBuilder lays
// that LayoutBuilder out again: 9 layouts up one chain to the page's
// viewport and about 290 render objects repainted per frame, for a 9pt icon.
// PaintOnlyScaleEffect sets the same matrix on the same RenderTransform from
// the animation's own listener, and a RepaintBoundary keeps the repaint to
// the flame.
//
// The first test's trace was recorded from the board before the change and
// frozen: the flame's paint matrix and the badge's place on every frame of a
// run with uneven frame steps, the badge taken away and brought back, and a
// board rebuild. The second pins the saving.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/features/habits/notifiers/newly_added_habit_provider.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';

import '../../helpers/landing_harness.dart';

/// The trace's digest, frozen from the board before the change and never
/// regenerated.
const String _frozenTrace =
    '4bb73c83e9aff5cdc8d3940739fac8cdee52fbdf77ba8160b34e2aca7b5782f5';

final _boosted =
    StateProvider<Set<String>>((ref) => const {'quran_daily_page'});

Finder _badge() => find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_BoostBadge',
      skipOffstage: false,
    );

/// The RenderTransform that scales the flame, and its child.
(RenderTransform, RenderBox) _flameTransform(WidgetTester tester) {
  final icon = tester.renderObject(find.descendant(
    of: _badge(),
    matching:
        find.byIcon(Icons.local_fire_department_rounded, skipOffstage: false),
  ));
  RenderObject child = icon;
  var node = icon.parent;
  while (node is! RenderTransform) {
    child = node!;
    node = node.parent;
  }
  return (node, child as RenderBox);
}

/// The flame's paint matrix and where the badge sits on its board: '-' with
/// no badge. On the board, not the screen: what is above the board (the
/// day's line, say) changes from day to day.
String _flame(WidgetTester tester) {
  if (_badge().evaluate().isEmpty) return '-';
  final (transform, child) = _flameTransform(tester);
  final m = Matrix4.identity();
  transform.applyPaintTransform(child, m);
  final box = tester.renderObject<RenderBox>(_badge());
  final board = tester.renderObject<RenderBox>(find.ancestor(
    of: _badge(),
    matching: find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_GridTable',
      skipOffstage: false,
    ),
  ));
  return '${m.storage.join(',')}|'
      '${box.localToGlobal(Offset.zero, ancestor: board)}|${box.size}';
}

void main() {
  late LandingHarness h;

  setUp(() async {
    h = LandingHarness();
    await h.prepare(
      activeCatalogIds: const [
        'inbox_zero',
        'sunnah_fasting',
        'quran_daily_page',
        'sleep_schedule',
        'cold_shower',
      ],
      extraOverrides: [
        // As in grid_square_alignment_test.dart's boosted case: the badge
        // only reads membership.
        myLinkedRoomHabitsProvider
            .overrideWithValue({'quran_daily_page': <RoomModel>[]}),
        roomBoostedHabitsProvider.overrideWith((ref) => ref.watch(_boosted)),
      ],
    );
  });
  tearDown(() => h.dispose());

  testWidgets('the flame pulses exactly as flutter_animate\'s did',
      (tester) async {
    await tester.pumpWidget(h.app());
    final frames = <String>[_flame(tester)];
    final scales = <double>{};
    for (var i = 0; i < 240; i++) {
      if (i == 90) h.container.read(_boosted.notifier).state = const {};
      if (i == 110) {
        h.container.read(_boosted.notifier).state = const {'quran_daily_page'};
      }
      if (i == 160) {
        h.container.read(newlyAddedHabitIdProvider.notifier).state = 'nobody';
      }
      // Uneven steps, 7 to 17ms, so the pulse is sampled all over its curve.
      await tester.pump(Duration(milliseconds: 7 + (i * 7) % 11));
      final frame = _flame(tester);
      frames.add(frame);
      if (frame != '-') scales.add(double.parse(frame.split(',').first));
    }
    expect(scales.length, greaterThan(100), reason: 'the flame still moves');
    expect(scales.reduce((a, b) => a < b ? a : b),
        greaterThanOrEqualTo(0.8 - 1e-9));
    expect(scales.reduce((a, b) => a > b ? a : b),
        lessThanOrEqualTo(1.2 + 1e-9));
    expect(frames.where((f) => f == '-'), isNotEmpty);

    final digest = sha256.convert(utf8.encode(frames.join('\n'))).toString();
    // ignore: avoid_print
    if (digest != _frozenTrace) print('flame trace: $digest');
    expect(digest, _frozenTrace);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 20));
  });

  testWidgets('a pulse frame rebuilds nothing, lays out nothing and paints '
      'only the flame', semanticsEnabled: false, (tester) async {
    await tester.pumpWidget(h.app());
    // Past Doum's three counted breaths (3.2s each, 4.2s asleep) and every
    // entrance: at 1.5s he is still breathing.
    for (var i = 0; i < 150; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(SchedulerBinding.instance.transientCallbackCount, 1,
        reason: 'only the flame is still running');

    var builds = 0, layouts = 0, paints = 0;
    final printBefore = debugPrint;
    addTearDown(() {
      debugPrintLayouts = false;
      debugPrint = printBefore;
      debugProfilePaintsEnabled = false;
      debugOnProfilePaint = null;
      debugOnRebuildDirtyWidget = null;
    });
    debugOnRebuildDirtyWidget = (_, __) => builds++;
    debugOnProfilePaint = (_) => paints++;
    debugProfilePaintsEnabled = true;
    debugPrint = (String? message, {int? wrapWidth}) {
      if ((message ?? '').startsWith('Laying out')) layouts++;
    };
    debugPrintLayouts = true;
    final matrices = <String>{};
    const frameCount = 20;
    try {
      for (var i = 0; i < frameCount; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final (transform, child) = _flameTransform(tester);
        final m = Matrix4.identity();
        transform.applyPaintTransform(child, m);
        matrices.add(m.storage.join(','));
      }
    } finally {
      debugPrintLayouts = false;
      debugPrint = printBefore;
      debugProfilePaintsEnabled = false;
      debugOnProfilePaint = null;
      debugOnRebuildDirtyWidget = null;
    }
    // ignore: avoid_print
    print('per pulse frame: ${builds / frameCount} rebuilds, '
        '${layouts / frameCount} layouts, ${paints / frameCount} paints');
    expect(matrices.length, greaterThan(frameCount ~/ 2),
        reason: 'the flame moves between frames');
    // Before: 1 rebuild, 9 layouts and 290 paints a frame. After: 0, 0 and
    // 6 (the flame's own layer), with a little room over the 6.
    expect(builds, 0);
    expect(layouts, 0);
    expect(paints, lessThanOrEqualTo(8 * frameCount));

    // An opaque route over the Grid still mutes it.
    final navigator =
        tester.state<NavigatorState>(find.byType(Navigator).first);
    navigator.push(PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) => const SizedBox.expand(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(SchedulerBinding.instance.transientCallbackCount, 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 20));
  });
}
