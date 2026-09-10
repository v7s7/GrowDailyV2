import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/features/auth/screens/auth_screen.dart';

import '../../helpers/landing_harness.dart';

/// Where the email form's message lands.
///
/// It used to render below the "other ways in" link, four elements past the
/// field it was about and with the submit button in between, so on a phone
/// the answer to a failed sign-in was off the bottom of the keyboard's
/// window and the form read as if it had done nothing. These tests pin the
/// ORDER rather than any pixel value: password field, then the message,
/// then the forgot-password link, then the button that was pressed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LandingHarness harness;
  final en = const S(Locale('en'));
  final ar = const S(Locale('ar'));

  setUp(() async {
    harness = LandingHarness();
    await harness.prepare();
  });

  tearDown(() => harness.dispose());

  /// Opens the email form and submits it empty, which is the one failure a
  /// widget test can raise on its own: it is caught in _submit before any
  /// Firebase call, so nothing here needs a network or a fake auth backend.
  /// A phone-sized window, because the default 800x600 test surface puts the
  /// submit button past the bottom edge and the tap silently misses.
  Future<void> openForm(WidgetTester tester, S s, {Locale? locale}) async {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(390, 844) * 3.0;
    addTearDown(tester.view.reset);
    await tester
        .pumpWidget(harness.app(home: const AuthScreen(), locale: locale));
    await harness.settle(tester);
    await tester.tap(find.text(s.continueWithEmail));
    await harness.settle(tester);
  }

  Future<void> failEmptySubmit(WidgetTester tester, S s,
      {Locale? locale}) async {
    await openForm(tester, s, locale: locale);
    final submit = find.widgetWithText(FilledButton, s.signInAction);
    await tester.ensureVisible(submit);
    await harness.settle(tester);
    await tester.tap(submit);
    await harness.settle(tester);
  }

  testWidgets('the message sits under the password field, above the link',
      (tester) async {
    await failEmptySubmit(tester, en);

    expect(find.text(en.errFillAll), findsOneWidget);

    // The second TextField is the password one (email, password; the confirm
    // field only exists on the register tab).
    final password = tester.getRect(find.byType(TextField).at(1));
    final message = tester.getRect(find.text(en.errFillAll));
    final forgot = tester.getRect(find.text(en.authForgotPassword));
    final submit = tester.getRect(find.widgetWithText(FilledButton, en.signInAction));

    expect(message.top, greaterThan(password.bottom),
        reason: 'the message must clear the password field');
    expect(message.bottom, lessThan(forgot.top),
        reason: 'and land above the forgot-password link, which is the next '
            'thing to reach for once it appears');
    expect(message.bottom, lessThan(submit.top),
        reason: 'and above the button that was just pressed, not below it');
  });

  testWidgets('the same order in Arabic, where the screen is RTL',
      (tester) async {
    await failEmptySubmit(tester, ar, locale: const Locale('ar'));

    final password = tester.getRect(find.byType(TextField).at(1));
    final message = tester.getRect(find.text(ar.errFillAll));
    final forgot = tester.getRect(find.text(ar.authForgotPassword));

    expect(message.top, greaterThan(password.bottom));
    expect(message.bottom, lessThan(forgot.top));
    // Direction is the screen's, not the message's: the row is built with a
    // Row, so the icon leads on the right and the text runs from there.
    expect(Directionality.of(tester.element(find.text(ar.errFillAll))),
        TextDirection.rtl);
  });

  testWidgets('no message before anything is submitted', (tester) async {
    await openForm(tester, en);

    expect(find.text(en.errFillAll), findsNothing);
    // Both slots are in the tree from the first frame - they are the two
    // collapsed AnimatedSize boxes - so an empty one must not hold height
    // between the password field and the link.
    final password = tester.getRect(find.byType(TextField).at(1));
    final forgot = tester.getRect(find.text(en.authForgotPassword));
    expect(forgot.top - password.bottom, lessThan(24),
        reason: 'an empty slot collapses to nothing');
  });

  testWidgets('the button that was pressed is still reachable after it',
      (tester) async {
    // The small phone, where the height a message costs actually decides
    // something: on 375x667 the submit button sits at the bottom edge, so a
    // message opening above it pushes it off unless the screen follows.
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(375, 667) * 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.app(home: const AuthScreen()));
    await harness.settle(tester);
    await tester.tap(find.text(en.continueWithEmail));
    await harness.settle(tester);

    // NOT scrolled first: at rest the button's bottom sits at 655 of 667,
    // which is what makes this the interesting size. The message then costs
    // more than the 12pt left under it.
    final submit = find.widgetWithText(FilledButton, en.signInAction);
    expect(tester.getRect(submit).bottom, lessThanOrEqualTo(667.0),
        reason: 'the premise of this test: it starts on screen');
    await tester.tap(submit);
    // No extra pumping: the reveal polls with scheduled frames rather than a
    // timer, so settle() waits for the whole sequence on its own.
    await harness.settle(tester);

    expect(find.text(en.errFillAll), findsOneWidget);
    final rect = tester.getRect(submit);
    // 1pt of slack for the tail of the easing curve, not for the fix: the
    // regression this pins put the button 20pt below the edge.
    expect(rect.bottom, lessThanOrEqualTo(668.0),
        reason: 'an answer you can read next to a button you cannot reach is '
            'only half a fix');
    expect(tester.getRect(find.text(en.errFillAll)).bottom,
        lessThanOrEqualTo(668.0),
        reason: 'and the message came along with it');
  });

  testWidgets('and it never leaves the screen on the way there',
      (tester) async {
    // The end state alone would also be satisfied by letting the button fall
    // off the bottom and yanking it back afterwards, which is what the first
    // version of this did: two events with a pause between them. Sampling
    // every frame of the growth is what tells the two apart.
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(375, 667) * 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.app(home: const AuthScreen()));
    await harness.settle(tester);
    await tester.tap(find.text(en.continueWithEmail));
    await harness.settle(tester);

    final submit = find.widgetWithText(FilledButton, en.signInAction);
    final password = find.byType(TextField).at(1);
    final startedAt = tester.getRect(password).top;

    await tester.tap(submit);
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 30));
      expect(tester.getRect(submit).bottom, lessThanOrEqualTo(668.0),
          reason: 'the button dipped below the edge at frame $frame');
    }
    await harness.settle(tester);

    // The other half of "one motion": the screen above is what moved, and it
    // moved by the height the message took.
    expect(tester.getRect(password).top, lessThan(startedAt - 15));
  });

  testWidgets('closing the form clears the message', (tester) async {
    await failEmptySubmit(tester, en);
    expect(find.text(en.errFillAll), findsOneWidget);

    await tester.tap(find.text(en.authOtherWays));
    await harness.settle(tester);

    // Neither slot may keep it: a message about the form would read as if it
    // belonged to Apple or Google once the form is gone.
    expect(find.text(en.errFillAll), findsNothing);
  });
}
