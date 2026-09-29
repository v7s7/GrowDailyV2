// Pins sightSnackBar (lib/shared/widgets/snack_bar_watch.dart) to the SDK the
// app builds with. It reads a SnackBar out of the root Scaffold's own tree:
// the 'snackBar' layout slot, the SnackBar's animation, the transition's
// RenderClipRect and the Material's RenderPhysicalShape. None of that is
// public API, so if a Flutter upgrade moves any of it, this file is what
// fails, instead of Doum quietly standing behind a pop-up.
//
// Nested Scaffolds on purpose: in the app the Grid's Scaffold sits inside
// HomeShell's, and only the ROOT one paints the bar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/shared/widgets/app_snackbar.dart';
import 'package:grow_daily_v2/shared/widgets/snack_bar_watch.dart';

const _barKey = Key('bar');
const _pageKey = Key('page');

Widget _app({ThemeData? theme}) => MaterialApp(
      theme: theme ?? ThemeData(useMaterial3: true),
      home: Scaffold(
        bottomNavigationBar: const SizedBox(key: _barKey, height: 80),
        body: Scaffold(
          body: Builder(
            builder: (context) => const SizedBox.expand(key: _pageKey),
          ),
        ),
      ),
    );

BuildContext _page(WidgetTester tester) => tester.element(find.byKey(_pageKey));

/// The visible top of the bar as a person sees it: the lower of the
/// growing clip's top and the surface's top.
double _visibleTop(WidgetTester tester) {
  final surface = find.descendant(
    of: find.byType(SnackBar),
    matching: find.byType(Material),
  );
  final clip = find.descendant(
    of: find.byType(SnackBar),
    matching: find.byType(ClipRect),
  );
  final top = tester.getRect(surface.first).top;
  final clipTop = tester.getRect(clip.first).top;
  return top > clipTop ? top : clipTop;
}

void main() {
  testWidgets('no bar: nothing sighted', (tester) async {
    await tester.pumpWidget(_app());
    expect(sightSnackBar(_page(tester)), isNull);
  });

  testWidgets('a bar on the root Scaffold is sighted from the inner page, '
      'its top on the surface, above the bottom bar', (tester) async {
    await tester.pumpWidget(_app());
    ScaffoldMessenger.of(_page(tester)).showOne(
      const SnackBar(
        content: Text('one line'),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: Duration(seconds: 3),
      ),
    );
    await tester.pumpAndSettle();
    final seen = sightSnackBar(_page(tester));
    expect(seen, isNotNull);
    expect(seen!.offstage, isFalse);
    expect(seen.status, AnimationStatus.completed);
    expect(seen.showing, isTrue);
    final surface = tester.getRect(
      find.descendant(of: find.byType(SnackBar), matching: find.byType(Material))
          .first,
    );
    expect(seen.top, moreOrLessEquals(surface.top, epsilon: 0.01));
    // 16pt of margin between the surface and the bar.
    final bar = tester.getRect(find.byKey(_barKey));
    expect(surface.bottom, moreOrLessEquals(bar.top - 16, epsilon: 0.01));
    await tester.pumpAndSettle(const Duration(seconds: 4));
  });

  testWidgets('the entrance: the edge rises with the growing clip, status '
      'forward, then completed', (tester) async {
    await tester.pumpWidget(_app());
    ScaffoldMessenger.of(_page(tester)).showOne(
      const SnackBar(
        content: Text('growing'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
      ),
    );
    await tester.pump();
    final tops = <double>[];
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final seen = sightSnackBar(_page(tester));
      expect(seen, isNotNull);
      if (seen!.status == AnimationStatus.forward) {
        expect(seen.showing, isTrue);
        expect(seen.top, moreOrLessEquals(_visibleTop(tester), epsilon: 0.01));
        tops.add(seen.top);
      }
    }
    expect(tops.length, greaterThan(4));
    // It only ever rises (y shrinks) while it grows in.
    for (var i = 1; i < tops.length; i++) {
      expect(tops[i], lessThanOrEqualTo(tops[i - 1] + 0.01));
    }
    await tester.pumpAndSettle();
    expect(sightSnackBar(_page(tester))!.status, AnimationStatus.completed);
    await tester.pumpAndSettle(const Duration(seconds: 4));
  });

  testWidgets('leaving: reverse (not showing), then gone', (tester) async {
    await tester.pumpWidget(_app());
    final messenger = ScaffoldMessenger.of(_page(tester));
    messenger.showOne(
      const SnackBar(
        content: Text('leaving'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
      ),
    );
    await tester.pumpAndSettle();
    messenger.hideCurrentSnackBar();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final leaving = sightSnackBar(_page(tester));
    expect(leaving, isNotNull);
    expect(leaving!.status, AnimationStatus.reverse);
    expect(leaving.showing, isFalse);
    await tester.pumpAndSettle();
    expect(sightSnackBar(_page(tester)), isNull);
  });

  testWidgets('a swipe down moves the sighted edge down with the surface',
      (tester) async {
    await tester.pumpWidget(_app());
    ScaffoldMessenger.of(_page(tester)).showOne(
      const SnackBar(
        content: Text('swipe me'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
      ),
    );
    await tester.pumpAndSettle();
    final before = sightSnackBar(_page(tester))!.top;
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('swipe me')),
    );
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    final during = sightSnackBar(_page(tester))!;
    expect(during.top, greaterThan(before + 10));
    await gesture.up();
    await tester.pumpAndSettle(const Duration(seconds: 4));
  });

  testWidgets('a two-line bar and a default-margin bar are measured, not '
      'assumed', (tester) async {
    await tester.pumpWidget(_app());
    final messenger = ScaffoldMessenger.of(_page(tester));
    messenger.showOne(
      const SnackBar(
        content: Text('one\ntwo'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
      ),
    );
    await tester.pumpAndSettle();
    final twoLines = sightSnackBar(_page(tester))!;
    expect(twoLines.top, moreOrLessEquals(_visibleTop(tester), epsilon: 0.01));
    final bar = tester.getRect(find.byKey(_barKey));
    // Taller than a one-line bar's 48 plus its 16 margin.
    expect(bar.top - twoLines.top, greaterThan(64));
    await tester.pumpAndSettle(const Duration(seconds: 4));
  });

  testWidgets('the app theme (floating by default, rounded) is read the same',
      (tester) async {
    await tester.pumpWidget(_app(
      theme: ThemeData(
        useMaterial3: true,
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      ),
    ));
    ScaffoldMessenger.of(_page(tester)).showOne(
      const SnackBar(content: Text('themed'), duration: Duration(seconds: 3)),
    );
    await tester.pumpAndSettle();
    final seen = sightSnackBar(_page(tester));
    expect(seen, isNotNull);
    expect(seen!.showing, isTrue);
    expect(seen.top, moreOrLessEquals(_visibleTop(tester), epsilon: 0.01));
    await tester.pumpAndSettle(const Duration(seconds: 4));
  });

  testWidgets('FrameWatch calls a watcher after frames, and stops',
      (tester) async {
    await tester.pumpWidget(_app());
    var calls = 0;
    void watcher() => calls++;
    FrameWatch.add(watcher);
    await tester.pump();
    expect(calls, greaterThan(0));
    final seen = calls;
    FrameWatch.remove(watcher);
    await tester.pump();
    await tester.pump();
    expect(calls, seen);
  });
}
