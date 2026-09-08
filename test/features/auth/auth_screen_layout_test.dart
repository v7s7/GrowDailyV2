import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/features/auth/screens/auth_screen.dart';

import '../../helpers/landing_harness.dart';

/// The auth screen is the one screen every single person sees, on whatever
/// phone and whatever text size they already had set before they met this
/// app. It is also the screen with the most stacked controls, so it is the
/// first place a column runs out of room.
///
/// These pump it at the two extremes that actually exist in the wild: the
/// smallest phone still supported (iPhone SE, 375x667) and 200% text, which
/// is a normal setting for anyone over about fifty. A RenderFlex overflow
/// throws in a test, so a failure here is unambiguous.
///
/// The [openEmail] flag is load-bearing rather than a convenience. Once the
/// email form was collapsed behind a button, every case in this file was
/// silently testing the SHORT version of the screen, which is exactly the
/// version that was never at risk. The tall one, eleven controls deep, is
/// the reason the file exists, and it is only reachable through that tap.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LandingHarness harness;
  const en = S(Locale('en'));

  setUp(() async {
    harness = LandingHarness();
    await harness.prepare();
  });

  tearDown(() => harness.dispose());

  Future<void> pumpAt(
    WidgetTester tester, {
    required Size size,
    required double textScale,
    TextDirection direction = TextDirection.ltr,
    bool openEmail = false,
    bool register = false,
  }) async {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = size * 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      harness.app(
        home: Directionality(
          textDirection: direction,
          child: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(textScale),
            ),
            child: const AuthScreen(),
          ),
        ),
      ),
    );
    await harness.settle(tester);

    if (openEmail) {
      await tester.tap(find.text(en.continueWithEmail));
      await harness.settle(tester);
      if (register) {
        // The tallest state of all: register mode adds the confirm field.
        await tester.ensureVisible(find.text(en.createAccount));
        await harness.settle(tester);
        await tester.tap(find.text(en.createAccount));
        await harness.settle(tester);
      }
    }
  }

  group('collapsed, which is what first paint shows', () {
    testWidgets('iPhone SE, default text', (tester) async {
      await pumpAt(tester, size: const Size(375, 667), textScale: 1.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('iPhone SE at 200% text', (tester) async {
      await pumpAt(tester, size: const Size(375, 667), textScale: 2.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('iPhone 17 at 200% text', (tester) async {
      await pumpAt(tester, size: const Size(402, 874), textScale: 2.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Arabic RTL, 200% text, small screen', (tester) async {
      await pumpAt(
        tester,
        size: const Size(375, 667),
        textScale: 2.0,
        direction: TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('email form open, which is the tall state', () {
    testWidgets('iPhone SE, default text', (tester) async {
      await pumpAt(
        tester,
        size: const Size(375, 667),
        textScale: 1.0,
        openEmail: true,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('iPhone SE at 200% text', (tester) async {
      await pumpAt(
        tester,
        size: const Size(375, 667),
        textScale: 2.0,
        openEmail: true,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('iPhone SE at 200% text, register mode, the tallest of all',
        (tester) async {
      await pumpAt(
        tester,
        size: const Size(375, 667),
        textScale: 2.0,
        openEmail: true,
        register: true,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Arabic RTL, 200% text, small screen', (tester) async {
      await pumpAt(
        tester,
        size: const Size(375, 667),
        textScale: 2.0,
        direction: TextDirection.rtl,
        openEmail: true,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('opening the form is visible to the person who tapped', () {
    testWidgets('the email field takes focus, which scrolls it into view',
        (tester) async {
      // On a 375x667 phone the form opens below the fold. Without the
      // focus request in _setEmailOpen the screen does not move, so the tap
      // reads as broken. Focus is what drags it into view.
      await pumpAt(
        tester,
        size: const Size(375, 667),
        textScale: 1.0,
        openEmail: true,
      );

      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.focusNode?.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}
