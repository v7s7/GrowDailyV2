import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/auth/services/social_auth_service.dart';

/// The shape of the credential Sign in with Apple hands to Firebase.
///
/// Build 70 was rejected under 2.1(a) because every Apple sign-in failed
/// with the wrong email or password banner. The credential was built with the
/// generic `OAuthProvider('apple.com').credential(...)`, which is tagged
/// sign-in method `oauth`; firebase_auth 5.7.0's iOS plugin sends that down
/// its generic OAuth branch, a nil accessToken becomes "" in FirebaseAuth 11,
/// and Firebase refuses any request carrying `access_token=` for apple.com
/// ("Invalid OAuth response from apple.com", measured against this project on
/// 2026-09-16). Nothing on a simulator without an Apple Account reaches this
/// code, so these map checks are the only automated guard on it.
void main() {
  group('SocialAuthService.appleFirebaseCredential', () {
    test('is tagged apple.com, so the plugin takes its Apple branch', () {
      final map = SocialAuthService.appleFirebaseCredential(
        identityToken: 'header.payload.signature',
        rawNonce: 'raw-nonce',
      ).asMap();

      // FLTFirebaseAuthPlugin.m dispatches on signInMethod: 'apple.com'
      // reaches appleCredentialWithIDToken:rawNonce:fullName:, 'oauth'
      // reaches credentialWithProviderID:IDToken:rawNonce:accessToken:.
      expect(map['signInMethod'], 'apple.com');
      expect(map['providerId'], appleProviderId);
    });

    test('carries no access token at all, not even an empty one', () {
      final map = SocialAuthService.appleFirebaseCredential(
        identityToken: 'header.payload.signature',
        rawNonce: 'raw-nonce',
      ).asMap();

      expect(map['accessToken'], isNull);
      expect(map['idToken'], 'header.payload.signature');
      // The RAW nonce: Apple was given its SHA-256, Firebase checks the pair.
      expect(map['rawNonce'], 'raw-nonce');
    });

    test('passes the first-authorization name through to Firebase', () {
      final map = SocialAuthService.appleFirebaseCredential(
        identityToken: 't',
        rawNonce: 'n',
        givenName: 'Aziz',
        familyName: 'Alkubaisi',
      ).asMap();

      expect(map['givenName'], 'Aziz');
      expect(map['familyName'], 'Alkubaisi');
    });

    test('blank name halves go as null, real ones trimmed', () {
      // The SDK sends ANY non-nil half, "" included, as a `user` item.
      final map = SocialAuthService.appleFirebaseCredential(
        identityToken: 't',
        rawNonce: 'n',
        givenName: '  Aziz ',
        familyName: '   ',
      ).asMap();

      expect(map['givenName'], 'Aziz');
      expect(map['familyName'], isNull);
    });

    test('a returning Apple account (no name) still builds', () {
      final map = SocialAuthService.appleFirebaseCredential(
        identityToken: 't',
        rawNonce: 'n',
      ).asMap();

      expect(map['givenName'], isNull);
      expect(map['familyName'], isNull);
      expect(map['signInMethod'], 'apple.com');
    });

    test('the generic OAuth form is the one that routes to the broken branch',
        () {
      // Pins the reason, so a future "simplify back to OAuthProvider" edit
      // fails here rather than in App Review.
      final generic = OAuthProvider(appleProviderId)
          .credential(idToken: 't', rawNonce: 'n')
          .asMap();
      expect(generic['signInMethod'], 'oauth');
    });
  });
}
