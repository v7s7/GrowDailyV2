import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/features/auth/models/sign_in_methods.dart';
import 'package:grow_daily_v2/features/profile/screens/sign_in_methods_screen.dart';

import '../../helpers/landing_harness.dart';

/// Profile, Settings, Account, "How you sign in".
///
/// The page exists because Firebase can take a way in away without saying so
/// (the password of an unverified address disappears the moment Google or
/// Apple signs in with it), and because Apple's Hide My Email opens a second,
/// empty account that only a link from inside the real one can undo. What is
/// tested here is the part a person's access depends on: which action each
/// row offers, and the two cases where it must offer none.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LandingHarness harness;
  const en = S(Locale('en'));
  const ar = S(Locale('ar'));

  // Set by each test BEFORE it pumps. The override is read lazily, on the
  // screen's first build, and the harness has to be prepared outside the
  // test body: awaiting Hive inside testWidgets never completes.
  late SignInMethods methods;

  setUp(() async {
    harness = LandingHarness();
    await harness.prepare(extraOverrides: [
      signInMethodsProvider.overrideWith((ref) => methods),
    ]);
  });

  tearDown(() => harness.dispose());

  /// The rows follow what the device can actually run: Google needs iOS or
  /// Android, Apple needs iOS or macOS, and the auth screen gates its own
  /// buttons the same way. Tests run on the host, where both read false, so
  /// the platform is set for the build and cleared again straight after:
  /// the test framework fails any test that leaves a debug flag set.
  Future<void> pump(
    WidgetTester tester,
    SignInMethods forAccount, {
    Locale? locale,
    TargetPlatform platform = TargetPlatform.iOS,
  }) async {
    methods = forAccount;
    debugDefaultTargetPlatformOverride = platform;
    await tester.pumpWidget(harness.app(
      home: const SignInMethodsScreen(),
      locale: locale,
    ));
    await harness.settle(tester);
    debugDefaultTargetPlatformOverride = null;
  }

  testWidgets('an account with a password and Google can remove either',
      (tester) async {
    await pump(
      tester,
      const SignInMethods(
        hasPassword: true,
        hasGoogle: true,
        hasApple: false,
        accountEmail: 'aziz@example.com',
        googleEmail: 'aziz@gmail.com',
      ),
    );

    expect(find.text(en.signInMethodPassword), findsOneWidget);
    expect(find.text('Google'), findsOneWidget);
    expect(find.text('Apple'), findsOneWidget);
    // Two ways in, so both can go, and Apple is there to connect.
    expect(find.text(en.signInMethodRemove), findsNWidgets(2));
    expect(find.text(en.signInMethodConnect), findsOneWidget);
    expect(find.text(en.signInMethodOnlyWayIn), findsNothing);
  });

  testWidgets('the only way in cannot be removed, and says so',
      (tester) async {
    await pump(
      tester,
      const SignInMethods(
        hasPassword: false,
        hasGoogle: true,
        hasApple: false,
        accountEmail: 'aziz@gmail.com',
        googleEmail: 'aziz@gmail.com',
      ),
    );

    expect(find.text(en.signInMethodOnlyWayIn), findsOneWidget);
    expect(find.text(en.signInMethodRemove), findsNothing);
    // The way back for a password Firebase deleted, standing rather than
    // offered once on the sign-in where it happened.
    expect(find.text(en.signInMethodSetPassword), findsOneWidget);
    expect(find.text(en.signInMethodPasswordHint), findsOneWidget);
  });

  testWidgets('a hidden Apple address is told why, and offered no password',
      (tester) async {
    await pump(
      tester,
      const SignInMethods(
        hasPassword: false,
        hasGoogle: false,
        hasApple: true,
        accountEmail: 'abc123@privaterelay.appleid.com',
        appleEmail: 'abc123@privaterelay.appleid.com',
      ),
    );

    expect(find.text(en.signInMethodPasswordHidden), findsOneWidget);
    expect(find.text(en.signInMethodSetPassword), findsNothing);
    // Google is the way to a second way in for this account.
    expect(find.text(en.signInMethodConnect), findsOneWidget);
    expect(find.text(en.signInMethodOnlyWayIn), findsOneWidget);
  });

  testWidgets('a platform that cannot offer Apple does not list it',
      (tester) async {
    await pump(
      tester,
      const SignInMethods(
        hasPassword: true,
        hasGoogle: false,
        hasApple: false,
        accountEmail: 'aziz@example.com',
      ),
      platform: TargetPlatform.android,
    );

    expect(find.text('Apple'), findsNothing);
    expect(find.text('Google'), findsOneWidget);
  });

  testWidgets('a method already connected is listed even where it cannot be '
      'offered', (tester) async {
    // Someone who signed up with Apple on their iPhone and opened the app on
    // an Android phone still has to see, and be able to remove, that method.
    await pump(
      tester,
      const SignInMethods(
        hasPassword: true,
        hasGoogle: false,
        hasApple: true,
        accountEmail: 'aziz@example.com',
        appleEmail: 'aziz@example.com',
      ),
      platform: TargetPlatform.android,
    );

    expect(find.text('Apple'), findsOneWidget);
    expect(find.text(en.signInMethodRemove), findsNWidgets(2));
  });

  testWidgets('with no account behind it, the page offers nothing',
      (tester) async {
    // A guest, or the frame after a sign-out. Connect would only produce
    // "no current user" from Firebase, so no row offers an action.
    await pump(
      tester,
      const SignInMethods(
        hasPassword: false,
        hasGoogle: false,
        hasApple: false,
        accountEmail: '',
      ),
    );

    expect(find.text(en.signInMethodConnect), findsNothing);
    expect(find.text(en.signInMethodSetPassword), findsNothing);
    expect(find.text(en.signInMethodRemove), findsNothing);
  });

  testWidgets('Arabic says the same things', (tester) async {
    await pump(
      tester,
      const SignInMethods(
        hasPassword: true,
        hasGoogle: false,
        hasApple: false,
        accountEmail: 'aziz@example.com',
      ),
      locale: const Locale('ar'),
    );

    expect(find.text(ar.signInMethodsTitle), findsOneWidget);
    expect(find.text(ar.signInMethodsIntro), findsOneWidget);
    expect(find.text(ar.signInMethodOnlyWayIn), findsOneWidget);
    expect(find.text(ar.signInMethodsFooter), findsOneWidget);
    // Two providers left to connect, none to remove.
    expect(find.text(ar.signInMethodConnect), findsNWidgets(2));
    expect(find.text(ar.signInMethodRemove), findsNothing);
  });
}
