import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/auth/screens/set_new_password_screen.dart';

import '../../helpers/landing_harness.dart';

/// The screen offered after a Google or Apple sign-in has silently removed
/// an account's password.
///
/// It is an OFFER, not a gate: the account works either way, so "later" has
/// to be there and has to close it. And it must not verify anything, because
/// there is no code to verify - the session in hand is the proof.
class _FakeAuth extends AuthNotifier {
  _FakeAuth(super.ref);

  String? added;

  @override
  Future<void> addPassword(String password) async {
    added = password;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LandingHarness harness;
  late _FakeAuth auth;
  final en = const S(Locale('en'));
  final ar = const S(Locale('ar'));

  setUp(() async {
    harness = LandingHarness();
    await harness.prepare(extraOverrides: [
      authNotifierProvider.overrideWith((ref) => auth = _FakeAuth(ref)),
    ]);
  });

  tearDown(() => harness.dispose());

  Future<void> pump(WidgetTester tester, {Locale? locale}) async {
    // The override only builds the fake when the provider is first read, and
    // the "too short" case never gets that far on its own.
    harness.container.read(authNotifierProvider.notifier);
    await tester.pumpWidget(harness.app(
      home: const SetNewPasswordScreen.addToAccount(email: 'someone@example.com'),
      locale: locale,
    ));
    await harness.settle(tester);
  }

  testWidgets('it explains what happened, and to which address',
      (tester) async {
    await pump(tester);

    expect(find.text(en.addPasswordTitle), findsOneWidget);
    expect(find.text(en.addPasswordBody), findsOneWidget);
    expect(find.textContaining('someone@example.com'), findsOneWidget);
    // No code to check, so no waiting state on the way in.
    expect(find.text(en.setPasswordChecking), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('too short is caught before Firebase is asked', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.tap(find.widgetWithText(FilledButton, en.setPasswordSave));
    await harness.settle(tester);

    expect(find.text(en.errPasswordTooShort), findsOneWidget);
    expect(auth.added, isNull);
  });

  testWidgets('a real password is linked onto the account', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'longenough');
    await tester.tap(find.widgetWithText(FilledButton, en.setPasswordSave));
    await harness.settle(tester);

    expect(auth.added, 'longenough');
  });

  testWidgets('"later" closes it, because the account works either way',
      (tester) async {
    await pump(tester);

    expect(find.text(en.addPasswordLater), findsOneWidget);
    // The one-time-link warning belongs to the reset flow, not to this one.
    expect(find.text(en.setPasswordNote), findsNothing);
  });

  testWidgets('Arabic keeps the address left-to-right inside an RTL screen',
      (tester) async {
    await pump(tester, locale: const Locale('ar'));

    expect(find.text(ar.addPasswordTitle), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.textDirection, TextDirection.ltr);
  });
}
