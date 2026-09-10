import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/constants/deep_links.dart';

/// What the app accepts as a password-reset link.
///
/// The shape matters more than it looks: Firebase puts EVERY kind of email
/// action through one URL with a `mode`, so a parser that only checks the
/// path would open the new-password screen for an email-verification link.
void main() {
  group('parsePasswordResetLink', () {
    test('the App Link out of the email', () {
      expect(
        parsePasswordResetLink(Uri.parse(
            'https://grow-daily-339ef.web.app/reset?mode=resetPassword&oobCode=ABC123&apiKey=k&lang=ar')),
        'ABC123',
      );
    });

    test('the custom scheme the web page falls back to, where "reset" is the host', () {
      expect(
        parsePasswordResetLink(Uri.parse('growdaily://reset?oobCode=ABC123')),
        'ABC123',
      );
    });

    test('a trailing slash is still the same page', () {
      expect(
        parsePasswordResetLink(
            Uri.parse('https://grow-daily-339ef.web.app/reset/?oobCode=ABC123')),
        'ABC123',
      );
    });

    test('no mode at all is accepted: our own page builds the link that way', () {
      expect(
        parsePasswordResetLink(
            Uri.parse('https://grow-daily-339ef.web.app/reset?oobCode=ABC123')),
        'ABC123',
      );
    });

    test('another mode on the same path is NOT a password reset', () {
      expect(
        parsePasswordResetLink(Uri.parse(
            'https://grow-daily-339ef.web.app/reset?mode=verifyEmail&oobCode=ABC123')),
        isNull,
      );
    });

    test('no code, no screen', () {
      expect(
        parsePasswordResetLink(
            Uri.parse('https://grow-daily-339ef.web.app/reset?mode=resetPassword')),
        isNull,
      );
      expect(
        parsePasswordResetLink(
            Uri.parse('https://grow-daily-339ef.web.app/reset?oobCode=')),
        isNull,
      );
    });

    test('a room invite is left to the room parser', () {
      expect(
        parsePasswordResetLink(
            Uri.parse('https://grow-daily-339ef.web.app/join/ABCD')),
        isNull,
      );
      expect(parsePasswordResetLink(Uri.parse('growdaily://join/ABCD')), isNull);
    });

    test('an unrelated scheme is ignored', () {
      expect(
        parsePasswordResetLink(Uri.parse('someotherapp://reset?oobCode=ABC123')),
        isNull,
      );
    });

    test('the code keeps its case, since Firebase codes are case-sensitive', () {
      expect(
        parsePasswordResetLink(
            Uri.parse('growdaily://reset?oobCode=aB-_cD9')),
        'aB-_cD9',
      );
    });
  });
}
