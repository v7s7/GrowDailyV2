import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/features/auth/screens/auth_screen.dart';

import '../../helpers/landing_harness.dart';

/// The email form is closed at first paint and opens in place.
///
/// The point of the change is what someone sees BEFORE deciding anything:
/// the tabs, both fields, the confirm field, the forgot link and the submit
/// button used to be on screen immediately, eleven controls deep, which
/// pushed the guest button off the bottom of a 390x844 phone. Guest is how
/// most people meet this app, so these tests pin the two facts that matter:
/// the form starts hidden, and the guest action is reachable without it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LandingHarness harness;
  final en = const S(Locale('en'));

  setUp(() async {
    harness = LandingHarness();
    await harness.prepare();
  });

  tearDown(() => harness.dispose());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(harness.app(home: const AuthScreen()));
    await harness.settle(tester);
  }

  group('the email form starts closed', () {
    testWidgets('no fields, tabs or submit button at first paint',
        (tester) async {
      await pump(tester);

      expect(find.byType(TextField), findsNothing);
      expect(find.text(en.signIn), findsNothing);
      expect(find.text(en.createAccount), findsNothing);
      expect(find.text(en.authForgotPassword), findsNothing);
      expect(find.text(en.signInAction), findsNothing);
    });

    testWidgets('the email button and the guest button are both there',
        (tester) async {
      await pump(tester);

      expect(find.text(en.continueWithEmail), findsOneWidget);
      expect(find.text(en.tryAsGuest), findsOneWidget);
      // The whole reason for the change: the pair of lines explaining what
      // each path does with your progress is on screen rather than below the
      // fold. textContaining, because each line is a Text.rich whose lead is
      // a separate span.
      expect(find.textContaining(en.authAccountLead), findsOneWidget);
      expect(find.textContaining(en.authGuestLead), findsOneWidget);
    });
  });

  group('opening and closing', () {
    testWidgets('tapping the email button reveals the form', (tester) async {
      await pump(tester);

      await tester.tap(find.text(en.continueWithEmail));
      await harness.settle(tester);

      expect(find.byType(TextField), findsNWidgets(2));
      // Two of each, not one, and that is correct rather than a bug: since
      // the English went to sentence case the mode TAB and the submit BUTTON
      // read the same words ("Sign in"). The tab picks the mode, the button
      // performs it, which is what most apps do.
      expect(find.text(en.signIn), findsNWidgets(2));
      expect(find.text(en.createAccount), findsOneWidget);
      expect(find.text(en.signInAction), findsNWidgets(2));
      // The button that opened it is gone, replaced by what it opened.
      expect(find.text(en.continueWithEmail), findsNothing);
    });

    testWidgets('the way back out closes it again', (tester) async {
      await pump(tester);
      await tester.tap(find.text(en.continueWithEmail));
      await harness.settle(tester);

      expect(find.text(en.authOtherWays), findsOneWidget);
      // With the form open the column is taller than the 800x600 test
      // surface, so the link exists in the tree but sits outside the
      // viewport. Tapping it without scrolling first taps empty space and
      // silently does nothing.
      await tester.ensureVisible(find.text(en.authOtherWays));
      await harness.settle(tester);
      await tester.tap(find.text(en.authOtherWays));
      await harness.settle(tester);

      expect(find.byType(TextField), findsNothing);
      expect(find.text(en.continueWithEmail), findsOneWidget);
    });

    testWidgets('the guest action survives opening the form', (tester) async {
      // Opening the form must not bury the path the product depends on.
      await pump(tester);
      await tester.tap(find.text(en.continueWithEmail));
      await harness.settle(tester);

      expect(find.text(en.tryAsGuest), findsOneWidget);
    });

    testWidgets('creating an account reveals the confirm field',
        (tester) async {
      await pump(tester);
      await tester.tap(find.text(en.continueWithEmail));
      await harness.settle(tester);

      expect(find.byType(TextField), findsNWidgets(2));
      await tester.tap(find.text(en.createAccount));
      await harness.settle(tester);

      expect(find.byType(TextField), findsNWidgets(3));
      // Same collision as above, the other way round: in register mode the
      // active tab and the submit button both read "Create account".
      expect(find.text(en.createAccountAction), findsNWidgets(2));
    });
  });

  group('credential fields are pinned left-to-right', () {
    testWidgets('even inside an Arabic RTL screen', (tester) async {
      // An email address is never Arabic. Inheriting the ambient RTL
      // direction puts the caret on the wrong side and resolves the @ and
      // the dots to the wrong end as the address is typed.
      await tester.pumpWidget(
        harness.app(
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: AuthScreen(),
          ),
        ),
      );
      await harness.settle(tester);

      await tester.tap(find.text(en.continueWithEmail));
      await harness.settle(tester);

      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(fields, isNotEmpty);
      for (final f in fields) {
        expect(f.textDirection, TextDirection.ltr);
      }
    });
  });
}
