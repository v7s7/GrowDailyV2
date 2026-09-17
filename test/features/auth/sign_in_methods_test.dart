import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/auth/models/sign_in_methods.dart';

/// What the "How you sign in" page is allowed to conclude from Firebase's
/// own provider list.
///
/// The rules here are the ones that keep a person from being locked out:
/// never offer to remove the last way in, never offer a password to an
/// address no mail can reach, and read the ways in from `providerData`
/// rather than from anything the app remembered earlier, because Firebase
/// changes that list without telling the app (it deletes the password of an
/// unverified address the moment that address signs in with Google or
/// Apple).
class _FakeUserInfo implements UserInfo {
  _FakeUserInfo(this.providerId, this.email);

  @override
  final String providerId;
  @override
  final String? email;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUser implements User {
  _FakeUser({required this.email, required this.providerData});

  @override
  final String? email;
  @override
  final List<UserInfo> providerData;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  UserInfo password(String email) => _FakeUserInfo('password', email);
  UserInfo google(String email) => _FakeUserInfo('google.com', email);
  UserInfo apple(String? email) => _FakeUserInfo('apple.com', email);

  group('SignInMethods.of', () {
    test('reads every way in, and the address each one uses', () {
      final m = SignInMethods.of(_FakeUser(
        email: 'aziz@example.com',
        providerData: [password('aziz@example.com'), google('aziz@gmail.com')],
      ));

      expect(m.hasPassword, isTrue);
      expect(m.hasGoogle, isTrue);
      expect(m.hasApple, isFalse);
      expect(m.accountEmail, 'aziz@example.com');
      expect(m.googleEmail, 'aziz@gmail.com');
      expect(m.appleEmail, isNull);
      expect(m.count, 2);
      expect(m.isLastWayIn, isFalse);
    });

    test('nobody signed in has no ways in, and does not throw', () {
      final m = SignInMethods.of(null);

      expect(m.count, 0);
      expect(m.hasPassword, isFalse);
      expect(m.accountEmail, '');
      expect(m.isLastWayIn, isTrue);
      expect(m.canAddPassword, isFalse);
    });

    test('the password Firebase deleted is simply not in the list', () {
      // The account was made with an email and a password, then Google
      // signed in with the same address. Same uid, same data, no password.
      final m = SignInMethods.of(_FakeUser(
        email: 'aziz@gmail.com',
        providerData: [google('aziz@gmail.com')],
      ));

      expect(m.hasPassword, isFalse);
      expect(m.hasGoogle, isTrue);
      expect(m.isLastWayIn, isTrue);
      // The offer this page exists to keep standing.
      expect(m.canAddPassword, isTrue);
      expect(m.droppedPassword(docSaysHadPassword: true), isTrue);
      expect(m.droppedPassword(docSaysHadPassword: false), isFalse);
    });
  });

  group('the rules that stop a lockout', () {
    test('one way in is the last way in, whichever one it is', () {
      for (final only in [
        [password('a@b.com')],
        [google('a@b.com')],
        [apple('a@b.com')],
      ]) {
        final m = SignInMethods.of(_FakeUser(email: 'a@b.com', providerData: only));
        expect(m.isLastWayIn, isTrue, reason: only.first.providerId);
      }

      final two = SignInMethods.of(_FakeUser(
        email: 'a@b.com',
        providerData: [apple('a@b.com'), google('a@b.com')],
      ));
      expect(two.isLastWayIn, isFalse);
    });

    test('a hidden Apple address is never offered a password', () {
      final m = SignInMethods.of(_FakeUser(
        email: 'abc123@privaterelay.appleid.com',
        providerData: [apple('abc123@privaterelay.appleid.com')],
      ));

      expect(m.emailIsHidden, isTrue);
      // A password needs an inbox a reset link can reach, and Apple's relay
      // rejects mail from a sender it does not know.
      expect(m.canAddPassword, isFalse);
    });

    test('an address Apple withheld entirely is not offered one either', () {
      final m = SignInMethods.of(_FakeUser(
        email: null,
        providerData: [apple(null)],
      ));

      expect(m.accountEmail, '');
      expect(m.emailIsHidden, isFalse);
      expect(m.canAddPassword, isFalse);
    });

    test('an ordinary address with no password is offered one', () {
      final m = SignInMethods.of(_FakeUser(
        email: 'aziz@example.com',
        providerData: [apple('aziz@example.com')],
      ));

      expect(m.canAddPassword, isTrue);
    });

    test('an account that already has a password is not offered another', () {
      final m = SignInMethods.of(_FakeUser(
        email: 'aziz@example.com',
        providerData: [password('aziz@example.com')],
      ));

      expect(m.canAddPassword, isFalse);
    });
  });
}
