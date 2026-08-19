// showOverlayNotice exists for one reason: confirmations posted from
// inside a modal bottom sheet must actually be seen. A SnackBar posted
// there draws on the Scaffold BEHIND the sheet, so the app was telling
// people "resumed" and "deleted" into a layer nobody could see.
//
// These tests pin the properties a finder can actually see: the notice
// appears when posted from inside a sheet, survives that sheet closing,
// and removes its own OverlayEntry afterwards.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/shared/widgets/overlay_notice.dart';

void main() {
  /// A screen whose only button opens a modal sheet; the sheet's own
  /// button posts a notice, exactly like the paused-habits list does.
  Widget harness() => MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (sheetContext) => ElevatedButton(
                    onPressed: () =>
                        showOverlayNotice(sheetContext, 'رجعت إلى لوحتك'),
                    child: const Text('post'),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

  testWidgets('a notice posted from inside a modal sheet is shown',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('post'), findsOneWidget, reason: 'sheet is open');

    await tester.tap(find.text('post'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('رجعت إلى لوحتك'), findsOneWidget);
  });

  testWidgets('the notice outlives the sheet it was posted from',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('post'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    // Dismiss the sheet. Anything built inside the sheet's own subtree
    // goes with it, which is why the three matrix widgets that grew
    // inline notice slots could never confirm an action that also closed
    // the sheet. An overlay entry survives, so "resumed" is still on
    // screen after the sheet is gone.
    //
    // Note this does NOT prove the rootOverlay: true part of the
    // implementation: this harness has a single Navigator, so the root
    // overlay and the nearest one are the same object, and the test still
    // passes with rootOverlay: false. That flag only starts to matter
    // under a nested Navigator, and it is a paint-order property, which
    // no finder can see.
    Navigator.of(tester.element(find.text('post'))).pop();
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    expect(find.text('post'), findsNothing, reason: 'sheet really is gone');
    expect(find.text('رجعت إلى لوحتك'), findsOneWidget);
  });

  testWidgets('the notice removes itself and leaves nothing behind',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('post'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('رجعت إلى لوحتك'), findsOneWidget);

    // 3.2s visible + the reverse animation. A leaked OverlayEntry here
    // would sit on top of the app forever.
    await tester.pump(const Duration(milliseconds: 3300));
    await tester.pumpAndSettle();
    expect(find.text('رجعت إلى لوحتك'), findsNothing);
  });
}
