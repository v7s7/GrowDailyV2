import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/features/auth/screens/auth_screen.dart';

import '../../helpers/landing_harness.dart';

/// Not an assertion, a ruler.
///
/// Prints where every element of the signed-out screen actually lands on the
/// two phones that matter, so decisions about vertical balance are made
/// against measurements rather than against a screenshot someone squinted at.
/// Run with: flutter test test/features/auth/auth_layout_measure_test.dart
///
/// ONE CAVEAT that makes the printed numbers optimistic: the Google button is
/// absent here. SocialAuthService.googleAvailable is `Platform.isIOS ||
/// Platform.isAndroid`, and a widget test runs on macOS, so it returns false.
/// Every "content ends at" figure below is therefore missing one 52pt button
/// plus its 10pt gap. Add 62pt to get the real device number.
///
/// That correction is what makes the small phone tight rather than roomy: at
/// 1.6x text on a 375x667 screen the real content ends around 656 of 667.
/// Anything added to this screen has to shrink on small phones rather than
/// push, or the guest button goes back below the fold, which is the exact
/// problem the collapse was built to fix.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LandingHarness harness;
  const en = S(Locale('en'));

  setUp(() async {
    harness = LandingHarness();
    await harness.prepare();
  });
  tearDown(() => harness.dispose());

  Future<void> measure(
    WidgetTester tester,
    String label,
    Size size,
    double scale,
  ) async {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = size * 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      harness.app(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
          ),
          child: const AuthScreen(),
        ),
      ),
    );
    await harness.settle(tester);

    // ignore: avoid_print
    print('\n=== $label  ${size.width.toInt()}x${size.height.toInt()} '
        '@ ${scale}x ===');
    void rect(String name, Finder f) {
      if (f.evaluate().isEmpty) {
        // ignore: avoid_print
        print('  ${name.padRight(26)} (absent)');
        return;
      }
      final r = tester.getRect(f.first);
      // ignore: avoid_print
      print('  ${name.padRight(26)} top ${r.top.toStringAsFixed(0).padLeft(4)}'
          '  bottom ${r.bottom.toStringAsFixed(0).padLeft(4)}'
          '  h ${r.height.toStringAsFixed(0).padLeft(3)}');
    }

    rect('logo', find.byType(Image));
    rect('wordmark', find.text('Grow Daily'));
    rect('tagline', find.text(en.tagline));
    rect('apple', find.text(en.continueWithApple));
    rect('google', find.text(en.continueWithGoogle));
    rect('email', find.text(en.continueWithEmail));
    rect('guest', find.text(en.tryAsGuest));
    rect('fact: account', find.textContaining(en.authAccountLead));
    rect('fact: guest', find.textContaining(en.authGuestLead));

    final last = find.textContaining(en.authGuestLead);
    if (last.evaluate().isNotEmpty) {
      final bottom = tester.getRect(last.first).bottom;
      final pct = bottom / size.height * 100;
      // ignore: avoid_print
      print('  content ends at ${bottom.toStringAsFixed(0)} of '
          '${size.height.toInt()}  = ${pct.toStringAsFixed(1)}% down, '
          '${(size.height - bottom).toStringAsFixed(0)}pt of slack below');
    }
  }

  testWidgets('measure the signed-out screen', (tester) async {
    await measure(tester, 'iPhone 17', const Size(402, 874), 1.0);
  });

  testWidgets('measure on the small phone', (tester) async {
    await measure(tester, 'iPhone SE', const Size(375, 667), 1.0);
  });

  testWidgets('measure at large text', (tester) async {
    await measure(tester, 'iPhone SE big text', const Size(375, 667), 1.6);
  });
}
