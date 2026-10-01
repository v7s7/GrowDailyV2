// PaintOnlyScaleEffect draws what flutter_animate's ScaleEffect draws, on
// every frame: the same paint matrix, bit for bit, and the same pixels.
//
// The Grid's 2x flame moved to it so a pulse frame stops rebuilding and
// re-laying out the board (see paint_only_scale_effect.dart). Here the two
// run side by side from the same kind of Animate, exactly as _BoostBadge
// builds the flame, through uneven frame steps, a parent rebuild mid-pulse
// (flutter_animate hands the effect a new animation on every build), and the
// whole thing taken away and brought back.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/shared/widgets/paint_only_scale_effect.dart';

final _libraryKey = GlobalKey();
final _paintOnlyKey = GlobalKey();

/// The flame as _BoostBadge built it, and as it builds it now.
Widget _flame({required bool paintOnly}) {
  final icon = const Icon(
    Icons.local_fire_department_rounded,
    size: 9,
    color: Colors.black,
  ).animate(onPlay: (c) => c.repeat(reverse: true));
  if (!paintOnly) {
    return icon.scaleXY(
      begin: 0.8,
      end: 1.2,
      duration: 650.ms,
      curve: Curves.easeInOut,
    );
  }
  return RepaintBoundary(
    child: icon.addEffect(const PaintOnlyScaleEffect(
      begin: Offset(0.8, 0.8),
      end: Offset(1.2, 1.2),
      duration: Duration(milliseconds: 650),
      curve: Curves.easeInOut,
    )),
  );
}

class _Host extends StatefulWidget {
  const _Host({super.key});
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool shown = true;
  int builds = 0;
  void rebuild() => setState(() => builds++);
  void show(bool value) => setState(() => shown = value);

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (shown) ...[
                RepaintBoundary(
                  key: _libraryKey,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: _flame(paintOnly: false),
                  ),
                ),
                RepaintBoundary(
                  key: _paintOnlyKey,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: _flame(paintOnly: true),
                  ),
                ),
              ],
              // Changes on every rebuild, so the flames' Animates rebuild.
              Text('$builds'),
            ],
          ),
        ),
      );
}

/// The paint matrix from [boundary]'s child down to the icon.
List<double> _matrix(WidgetTester tester, GlobalKey boundary) {
  final icon = tester.renderObject(find.descendant(
    of: find.byKey(boundary),
    matching: find.byType(Icon),
  ));
  final top = tester.renderObject(find.byKey(boundary));
  return icon.getTransformTo(top).storage.toList();
}

Future<Uint8List> _pixels(WidgetTester tester, GlobalKey boundary) async {
  final box =
      tester.renderObject(find.byKey(boundary)) as RenderRepaintBoundary;
  late Uint8List bytes;
  await tester.runAsync(() async {
    final image = await box.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    bytes = data!.buffer.asUint8List();
  });
  return bytes;
}

void main() {
  testWidgets('the same matrix on every frame, and the same pixels',
      (tester) async {
    final host = GlobalKey<_HostState>();
    await tester.pumpWidget(_Host(key: host));
    final scales = <double>{};
    var pixelChecks = 0;
    final pictures = <String>{};
    for (var i = 0; i < 200; i++) {
      if (i == 60 || i == 61 || i == 130) host.currentState!.rebuild();
      if (i == 150) host.currentState!.show(false);
      if (i == 155) host.currentState!.show(true);
      await tester.pump(Duration(milliseconds: 7 + (i * 7) % 11));
      if (!host.currentState!.shown) continue;
      final library = _matrix(tester, _libraryKey);
      final paintOnly = _matrix(tester, _paintOnlyKey);
      expect(paintOnly, library, reason: 'frame $i');
      scales.add(library.first);
      if (i % 17 == 3) {
        final drawn = await _pixels(tester, _libraryKey);
        expect(
          await _pixels(tester, _paintOnlyKey),
          drawn,
          reason: 'pixels on frame $i',
        );
        pictures.add(drawn.join(','));
        pixelChecks++;
      }
    }
    expect(scales.length, greaterThan(100), reason: 'the flame still moves');
    expect(pixelChecks, greaterThanOrEqualTo(12));
    // The pixels compared are a flame, drawn at more than one size.
    expect(pictures.length, greaterThan(1));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tick changes paint only', (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: _PaintOnlyFlame()),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    var builds = 0;
    var layouts = 0;
    final printBefore = debugPrint;
    debugOnRebuildDirtyWidget = (_, __) => builds++;
    debugPrint = (String? message, {int? wrapWidth}) {
      if ((message ?? '').startsWith('Laying out')) layouts++;
    };
    debugPrintLayouts = true;
    try {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    } finally {
      debugPrintLayouts = false;
      debugPrint = printBefore;
      debugOnRebuildDirtyWidget = null;
    }
    expect(builds, 0);
    expect(layouts, 0);
    await tester.pumpWidget(const SizedBox());
  });
}

class _PaintOnlyFlame extends StatelessWidget {
  const _PaintOnlyFlame();
  @override
  Widget build(BuildContext context) => _flame(paintOnly: true);
}
