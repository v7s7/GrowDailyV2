import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/features/auth/screens/auth_screen.dart';
import 'package:grow_daily_v2/features/auth/services/social_auth_service.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Which banner a failed sign-in shows, and what gets logged about it.
///
/// App Review's screenshot of build 70 shows "Invalid email or password"
/// under the three buttons after a tap on Continue with Apple: Firebase had
/// refused the Apple token with `invalid-credential`, and the screen mapped
/// that code the same way for every path. A person who never typed a password
/// was told their password was wrong.
void main() {
  const en = S(Locale('en'));
  const ar = S(Locale('ar'));

  FirebaseAuthException auth(String code) => FirebaseAuthException(code: code);
  String social(S s, String code) =>
      AuthScreen.errorMessageFor(s, auth(code), fromSocial: true);

  group('AuthScreen.errorMessageFor', () {
    test('a refused Google or Apple token does not mention a password', () {
      for (final s in [en, ar]) {
        expect(
          social(s, 'invalid-credential'),
          s.errGeneric,
        );
        expect(
          social(s, 'invalid-credential'),
          isNot(s.errInvalidCredential),
        );
      }
    });

    test('the email form keeps its wrong email or password message', () {
      for (final code in [
        'invalid-credential',
        'wrong-password',
        'user-not-found',
      ]) {
        expect(
          AuthScreen.errorMessageFor(en, auth(code), fromSocial: false),
          en.errInvalidCredential,
        );
      }
    });

    test('the social-specific codes keep their own messages', () {
      expect(
        social(en, 'account-exists-with-different-credential'),
        en.errAccountExistsWithEmail,
      );
      expect(
        social(en, 'operation-not-allowed'),
        en.errSignInMethodUnavailable,
      );
      expect(
        social(en, 'apple-account-required'),
        en.errAppleAccountRequired,
      );
      expect(
        social(en, 'network-request-failed'),
        en.errNetwork,
      );
    });

    test('anything that is not a Firebase auth error is generic', () {
      expect(
        AuthScreen.errorMessageFor(en, StateError('x'), fromSocial: true),
        en.errGeneric,
      );
    });
  });

  group('SocialAuthService.failureCode', () {
    test('names the vendor code, never the message', () {
      expect(
        SocialAuthService.failureCode(
          const SignInWithAppleAuthorizationException(
            code: AuthorizationErrorCode.failed,
            message: 'someone@example.com',
          ),
        ),
        'apple/failed',
      );
      expect(
        SocialAuthService.failureCode(
          const GoogleSignInException(
            code: GoogleSignInExceptionCode.clientConfigurationError,
            description: 'someone@example.com',
          ),
        ),
        'google/clientConfigurationError',
      );
      expect(
        SocialAuthService.failureCode(
          FirebaseAuthException(
            code: 'invalid-credential',
            message: 'Invalid OAuth response from apple.com',
          ),
        ),
        'invalid-credential',
      );
      expect(SocialAuthService.failureCode(StateError('x')), 'StateError');
    });

    test('an Apple error shown as "needs an Apple Account" keeps its code', () {
      final e = AppleAccountRequiredException(AuthorizationErrorCode.unknown);
      // The screen still maps it by its Firebase-style code...
      expect(
        AuthScreen.errorMessageFor(en, e, fromSocial: true),
        en.errAppleAccountRequired,
      );
      // ...and the failure event records what Apple actually said.
      expect(SocialAuthService.failureCode(e), 'apple/unknown');
    });
  });
}
