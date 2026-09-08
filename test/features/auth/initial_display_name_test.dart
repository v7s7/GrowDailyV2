import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';

/// The rule that names a brand-new account.
///
/// It used to be one expression inside _createUserDoc, and it only had to
/// cope with email registration. Google and Apple both break its assumptions:
/// Google hands over a real full name, and Apple hands over an address like
/// `a1b2c3d4e5@privaterelay.appleid.com` whose local part is random hex. The
/// name this returns is written to the user document once and then shown on
/// the profile AND on every Rooms leaderboard the account joins, so getting
/// it wrong is both permanent and public.
void main() {
  group('initialDisplayName', () {
    test('uses the name the provider gave, when there is one', () {
      expect(
        AuthNotifier.initialDisplayName(
          'someone@gmail.com',
          providerName: 'Aziz Alhaddad',
        ),
        'Aziz Alhaddad',
      );
    });

    test('falls back to the email local part with no provider name', () {
      expect(AuthNotifier.initialDisplayName('aziz@gmail.com'), 'aziz');
    });

    test('never names an Apple relay account after its random local part', () {
      // The exact shape Apple issues when someone chooses "Hide My Email".
      expect(
        AuthNotifier.initialDisplayName('a1b2c3d4e5@privaterelay.appleid.com'),
        'Warrior',
      );
    });

    test('the relay check is case insensitive', () {
      expect(
        AuthNotifier.initialDisplayName('A1B2C3@PrivateRelay.AppleID.com'),
        'Warrior',
      );
    });

    test('a relay address still yields the real name Apple sent with it', () {
      // First authorization: Apple withholds the address but not the name.
      expect(
        AuthNotifier.initialDisplayName(
          'a1b2c3d4e5@privaterelay.appleid.com',
          providerName: 'Sara Ahmed',
        ),
        'Sara Ahmed',
      );
    });

    test('screens an objectionable provider name', () {
      // A provider name reaches public leaderboards without ever passing
      // through setDisplayName's guard, so this is the only place it is
      // checked.
      expect(
        AuthNotifier.initialDisplayName(
          'ok@gmail.com',
          providerName: 'hitler',
        ),
        // Falls through to the email local part, which is clean.
        'ok',
      );
    });

    test('screens an objectionable email local part', () {
      expect(AuthNotifier.initialDisplayName('hitler@gmail.com'), 'Warrior');
    });

    test('handles an email Apple withheld entirely', () {
      // user.email is null on a second device for a relay account, and the
      // notifier passes an empty string rather than a hole.
      expect(AuthNotifier.initialDisplayName(''), 'Warrior');
    });

    test('handles a value with no @ at all', () {
      expect(AuthNotifier.initialDisplayName('not-an-email'), 'Warrior');
    });

    test('ignores an all-whitespace provider name', () {
      expect(
        AuthNotifier.initialDisplayName('aziz@gmail.com', providerName: '   '),
        'aziz',
      );
    });

    test('trims a provider name rather than storing the padding', () {
      expect(
        AuthNotifier.initialDisplayName(
          'aziz@gmail.com',
          providerName: '  Aziz  ',
        ),
        'Aziz',
      );
    });
  });
}
