// What SafeWrapText's kept measurement buys, and what it must never cost.
// The rendered answers themselves are pinned by
// safe_wrap_text_parity_test.dart; these tests pin the work done to reach
// them, counted as TextPainters through FlutterMemoryAllocations:
//  * a rebuild with nothing changed measures nothing, on iOS and Android;
//  * a font change forgets the kept answer, so the next rebuild measures;
//  * every painter the label or its helpers create is disposed by the
//    time the label leaves the tree;
//  * the web path keeps nothing and measures on every rebuild, exactly as
//    many painters as the code before the change did (frozen below).
//
// Rebuilds come from a StatefulBuilder under a bare Directionality,
// MediaQuery and DefaultTextStyle, never from re-pumping a MaterialApp,
// so no framework painter (the debug banner's, say) lands in the counts.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/shared/widgets/safe_wrap_text.dart';

const _plex = 'SafeWrapReusePlex';

const _gridStyle = TextStyle(
  fontFamily: _plex,
  fontSize: 11.5,
  fontWeight: FontWeight.w600,
  height: 1.15,
);

/// One label to rebuild, and the TextPainters the code before the change
/// created on every rebuild of it (frozen 2026-09-30, never regenerate).
class _Case {
  const _Case(
    this.name,
    this.text, {
    this.style,
    required this.width,
    this.maxLines = 2,
    this.tap = false,
    required this.paintersPerRebuildBefore,
  });

  final String name;
  final String text;
  final TextStyle? style;
  final double width;
  final int maxLines;
  final bool tap;
  final int paintersPerRebuildBefore;
}

const _cases = <_Case>[
  // Five words, each measured on its own.
  _Case(
    'an English name in the Grid style',
    'Read one page of Quran',
    style: _gridStyle,
    width: 90,
    paintersPerRebuildBefore: 5,
  ),
  // Six words.
  _Case(
    'an Arabic name in the Grid style',
    'قراءة صفحة من القرآن الكريم يوميًا',
    style: _gridStyle,
    width: 90,
    paintersPerRebuildBefore: 6,
  ),
  // Two words, then the reveal check's whole-text layout: the
  // textOverflowsAt path, on a name that fits so no Tooltip is built.
  _Case(
    'a name that fits, reveal on',
    'Morning walk',
    width: 300,
    tap: true,
    paintersPerRebuildBefore: 3,
  ),
  // maxLines 1: only the reveal check.
  _Case(
    'one line, reveal on',
    'Morning walk',
    width: 300,
    maxLines: 1,
    tap: true,
    paintersPerRebuildBefore: 1,
  ),
  // The fourth word is too wide, which answers alone: four painters and
  // the Tooltip branch.
  _Case(
    'a truncated name, reveal on',
    'This is a genuinely long habit name that will not fit on two lines',
    width: 90,
    tap: true,
    paintersPerRebuildBefore: 4,
  ),
];

/// TextPainters created and disposed while it listens, by identity.
class _PainterCount {
  _PainterCount() {
    FlutterMemoryAllocations.instance.addListener(_listen);
  }

  final created = <Object>{};
  final disposed = <Object>{};

  void _listen(ObjectEvent event) {
    if (event.object is! TextPainter) return;
    if (event is ObjectCreated) created.add(event.object);
    if (event is ObjectDisposed) disposed.add(event.object);
  }

  void stop() => FlutterMemoryAllocations.instance.removeListener(_listen);
}

/// Mounts [c] under a StatefulBuilder and returns its setState.
Future<StateSetter> _mount(WidgetTester tester, _Case c) async {
  late StateSetter rebuild;
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Overlay(
        initialEntries: [
          OverlayEntry(
            builder: (_) => MediaQuery(
              data: const MediaQueryData(),
              child: DefaultTextStyle(
                style: const TextStyle(fontSize: 14),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: StatefulBuilder(
                    builder: (context, setState) {
                      rebuild = setState;
                      return SizedBox(
                        width: c.width,
                        child: SafeWrapText(
                          c.text,
                          style: c.style,
                          maxLines: c.maxLines,
                          tapToRevealWhenTruncated: c.tap,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
  return rebuild;
}

/// The painters each of ten same-input rebuilds created.
Future<List<int>> _tenRebuilds(
  WidgetTester tester,
  StateSetter rebuild,
  _PainterCount count,
) async {
  final perRebuild = <int>[];
  for (var i = 0; i < 10; i++) {
    final before = count.created.length;
    rebuild(() {});
    await tester.pump();
    perRebuild.add(count.created.length - before);
  }
  return perRebuild;
}

/// What the label renders: its Text's line cap, and whether it is wrapped
/// in the reveal Tooltip.
(int?, bool) _rendered(WidgetTester tester) {
  final label = find.byType(SafeWrapText);
  return (
    tester
        .widget<Text>(find.descendant(of: label, matching: find.byType(Text)))
        .maxLines,
    find.descendant(of: label, matching: find.byType(Tooltip))
        .evaluate()
        .isNotEmpty,
  );
}

void main() {
  setUpAll(() async {
    await ui.loadFontFromList(
      File('google_fonts/IBMPlexSansArabic-SemiBold.ttf').readAsBytesSync(),
      fontFamily: _plex,
    );
  });

  tearDown(() => SafeWrapText.debugMeasureEveryBuild = null);

  group('on iOS and Android', () {
    for (final c in _cases) {
      testWidgets('${c.name}: ten same-input rebuilds measure nothing and '
          'render the same', (tester) async {
        final count = _PainterCount();
        addTearDown(count.stop);
        final rebuild = await _mount(tester, c);
        final first = _rendered(tester);

        expect(await _tenRebuilds(tester, rebuild, count), List.filled(10, 0));
        expect(_rendered(tester), first);
      });
    }

    testWidgets('a fontsChange message makes the next rebuild measure '
        'again, and only that one', (tester) async {
      final c = _cases.first;
      final count = _PainterCount();
      addTearDown(count.stop);
      final rebuild = await _mount(tester, c);
      final first = _rendered(tester);

      // Awaited: PaintingBinding tells its listeners only after an await of
      // its own.
      await PaintingBinding.instance
          .handleSystemMessage(<String, dynamic>{'type': 'fontsChange'});

      final perRebuild = await _tenRebuilds(tester, rebuild, count);
      expect(perRebuild, [
        c.paintersPerRebuildBefore,
        ...List.filled(9, 0),
      ]);
      expect(_rendered(tester), first);
    });

    testWidgets('a font change on its own rebuilds nothing', (tester) async {
      final c = _cases.first;
      final count = _PainterCount();
      addTearDown(count.stop);
      await _mount(tester, c);
      final before = count.created.length;

      await PaintingBinding.instance
          .handleSystemMessage(<String, dynamic>{'type': 'fontsChange'});
      await tester.pump();

      // The label's own RenderParagraph relays out on a font change, as it
      // always did, but the label is not rebuilt and so measures nothing.
      expect(count.created.length, before);
    });

    testWidgets('a changed input measures again', (tester) async {
      final count = _PainterCount();
      addTearDown(count.stop);
      var width = 90.0;
      var text = 'Read one page of Quran';
      late StateSetter rebuild;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: DefaultTextStyle(
              style: const TextStyle(fontSize: 14),
              child: Align(
                alignment: Alignment.topLeft,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    rebuild = setState;
                    return SizedBox(
                      width: width,
                      child: SafeWrapText(text, style: _gridStyle),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );

      Future<int> step(void Function() change) async {
        final before = count.created.length;
        rebuild(change);
        await tester.pump();
        return count.created.length - before;
      }

      expect(await step(() => width = 60), 5);
      expect(await step(() {}), 0);
      expect(await step(() => text = 'Morning walk'), 2);
      expect(await step(() {}), 0);
    });

    testWidgets('every painter created is disposed once the label leaves '
        'the tree', (tester) async {
      for (final c in _cases) {
        final count = _PainterCount();
        addTearDown(count.stop);
        final rebuild = await _mount(tester, c);
        await _tenRebuilds(tester, rebuild, count);
        await tester.pumpWidget(const SizedBox());
        count.stop();
        expect(count.created, isNotEmpty, reason: c.name);
        expect(
          count.created.difference(count.disposed),
          isEmpty,
          reason: c.name,
        );
      }
    });
  });

  group('on the web, measured on every build', () {
    for (final c in _cases) {
      testWidgets('${c.name}: every rebuild measures as many painters as '
          'before, renders the same, and disposes them all', (tester) async {
        SafeWrapText.debugMeasureEveryBuild = true;
        final count = _PainterCount();
        addTearDown(count.stop);
        final rebuild = await _mount(tester, c);
        final first = _rendered(tester);

        expect(
          await _tenRebuilds(tester, rebuild, count),
          List.filled(10, c.paintersPerRebuildBefore),
        );
        expect(_rendered(tester), first);

        await tester.pumpWidget(const SizedBox());
        expect(count.created.difference(count.disposed), isEmpty);
      });
    }
  });
}
