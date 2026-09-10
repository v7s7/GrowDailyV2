import 'dart:convert';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Which button a social sign-in came from. The caller needs this after the
/// fact: the two providers fail differently, and the profile screen shows a
/// different line for each.
enum SocialProvider { google, apple }

/// Firebase's own provider ids, as they appear in `User.providerData`.
/// Spelled out here so the notifier and the profile screen compare against
/// one definition rather than repeating the string literals.
const String googleProviderId = 'google.com';
const String appleProviderId = 'apple.com';
const String passwordProviderId = 'password';

/// Thrown when the user backs out of the provider's own sheet.
///
/// Its own type rather than a code on a shared error because it is not an
/// error at all: dismissing Apple's sheet or Google's account chooser is a
/// decision, and the one thing the UI must NOT do is answer it with a red
/// banner. Every call site catches this and returns to the idle state.
class SocialSignInCancelled implements Exception {
  const SocialSignInCancelled();
}

/// A provider credential plus the profile details that come with it, before
/// any of it reaches Firebase.
///
/// [displayName] is carried separately from the Firebase user because of
/// Apple: the full name is handed over ONLY on the very first authorization
/// for a given Apple ID, and never again on any later sign-in, no matter how
/// many times the app asks. Firebase does not persist it either, so a name
/// not written to our own user document during that first call is gone
/// permanently, and the account is stuck with a fallback name forever.
class SocialCredential {
  const SocialCredential({
    required this.provider,
    required this.credential,
    this.displayName,
    this.photoUrl,
    this.appleAuthorizationCode,
  });

  final SocialProvider provider;
  final AuthCredential credential;

  /// Apple only. The single-use authorization code from this authorization,
  /// which is the ONLY thing that can revoke the app's Apple token.
  ///
  /// Deliberately not folded into [credential] as an accessToken: Firebase's
  /// apple.com provider wants an idToken and a rawNonce and nothing else,
  /// and revocation is a separate call
  /// ([FirebaseAuth.revokeTokenWithAuthorizationCode]) that happens at
  /// deletion time. Apple has required apps offering Sign in with Apple to
  /// revoke on account deletion since June 2022, so this is a review
  /// requirement rather than tidiness.
  final String? appleAuthorizationCode;

  /// Best available human name from the provider, already trimmed. Null when
  /// the provider withheld it (Apple on every sign-in after the first).
  final String? displayName;

  /// Google only. Apple never returns a photo.
  final String? photoUrl;
}

/// The Google and Apple halves of sign-in, kept away from [AuthNotifier] so
/// that class stays about Firebase and Firestore rather than about two
/// vendor SDKs with very different shapes.
///
/// Everything here stops at "here is a credential". Signing in, creating the
/// user document and the guest-data handover all stay in AuthNotifier, so
/// there is exactly one place where a new account comes into existence
/// regardless of how the person proved who they are.
class SocialAuthService {
  SocialAuthService._();
  static final SocialAuthService instance = SocialAuthService._();

  /// The OAuth 2.0 **web** client of the Firebase project, taken from
  /// android/app/google-services.json (`client_type: 3`).
  ///
  /// Android needs this and iOS does not, and the asymmetry is not cosmetic.
  /// google_sign_in 7.x on Android goes through Credential Manager, which
  /// mints an ID token for the *server* client rather than for the app, so
  /// with no serverClientId the sign-in succeeds and hands back an account
  /// with a null idToken, which Firebase then refuses. On iOS the plugin
  /// reads CLIENT_ID straight out of the bundled GoogleService-Info.plist,
  /// so passing anything from Dart there is redundant.
  static const String _webClientId =
      '508215311979-56pq3q1h9l3s9fbgfegomud8o0mi734o.apps.googleusercontent.com';

  Future<void>? _googleInit;

  /// Runs `initialize` exactly once per process and remembers the future, so
  /// concurrent taps (double-tap on the button, or the button plus a retry)
  /// share one initialization instead of racing two.
  Future<void> _ensureGoogleReady() {
    return _googleInit ??= GoogleSignIn.instance.initialize(
      serverClientId: _isAndroid ? _webClientId : null,
    );
  }

  /// Whether the Sign in with Apple button should be shown at all.
  ///
  /// iOS only, deliberately. The plugin does support Android, but only
  /// through a web flow that needs an Apple *Services ID* and a hosted
  /// HTTPS redirect endpoint that forwards the POST back into the app.
  /// This project has neither, and a button that opens a browser and fails
  /// is worse than no button. It is also not required there: guideline 4.8
  /// binds on Apple's own platforms, and Android users have Google.
  // defaultTargetPlatform, never dart:io's Platform: the auth screen asks
  // these on its first frame, and Platform throws on the web (Unsupported
  // operation: Platform._operatingSystem), which painted the whole web app
  // as a grey error box before anything else could draw. On the web neither
  // provider is configured (no OAuth client id, no Apple services id), so
  // both read false and the screen offers email and guest.
  static bool get _isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get _isMacOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  bool get appleAvailable => _isIOS || _isMacOS;

  /// Whether Google sign-in can be offered on this platform.
  bool get googleAvailable => _isIOS || _isAndroid;

  /// Opens Google's account chooser and returns the resulting credential.
  ///
  /// Throws [SocialSignInCancelled] if the user dismisses the sheet.
  Future<SocialCredential> google() async {
    await _ensureGoogleReady();
    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      // 7.x reports a dismissal as a thrown exception rather than 6.x's null
      // return. `interrupted` covers the case where the system tears the
      // sheet down without the user choosing anything, which is a
      // dismissal from where they are standing.
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        throw const SocialSignInCancelled();
      }
      rethrow;
    }

    final idToken = account.authentication.idToken;
    if (idToken == null) {
      // Reached when the Android build has no serverClientId that matches a
      // registered SHA-1, which is a configuration fault rather than
      // anything the person tapping the button did. Surfaced as a Firebase
      // code the screen already knows how to render generically.
      throw FirebaseAuthException(
        code: 'missing-google-id-token',
        message: 'Google returned no ID token. Check that the app signing '
            'certificate SHA-1 is registered on the Firebase Android app and '
            'that serverClientId matches the web OAuth client.',
      );
    }

    final name = account.displayName?.trim();
    return SocialCredential(
      provider: SocialProvider.google,
      credential: GoogleAuthProvider.credential(idToken: idToken),
      displayName: (name == null || name.isEmpty) ? null : name,
      photoUrl: account.photoUrl,
    );
  }

  /// Opens Apple's sheet and returns the resulting credential.
  ///
  /// Throws [SocialSignInCancelled] if the user dismisses the sheet.
  Future<SocialCredential> apple() async {
    // The nonce is what stops a stolen identity token being replayed at
    // Firebase by someone else. Apple is given the SHA-256 and embeds it in
    // the token it signs; Firebase is given the raw string and checks that
    // it hashes to what the token carries. Sending the same value to both,
    // or skipping it, removes the check entirely.
    final rawNonce = _randomNonce();
    final AuthorizationCredentialAppleID apple;
    try {
      apple = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: _sha256Hex(rawNonce),
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const SocialSignInCancelled();
      }
      // A device with no Apple Account signed in cannot run the flow at all.
      // iOS puts up its own "sign in to your Apple Account in Settings"
      // prompt first, and reports whatever the person does with it as
      // `unknown` or `notHandled` rather than as a cancellation.
      //
      // Worth separating from the generic error because the generic one says
      // "try again", and trying again is the one thing that cannot work:
      // every retry re-opens the same prompt until an account exists. Caught
      // on a fresh simulator, which is also what a first-time reviewer or
      // anyone with a newly wiped phone would be holding.
      if (e.code == AuthorizationErrorCode.unknown ||
          e.code == AuthorizationErrorCode.notHandled) {
        throw FirebaseAuthException(
          code: 'apple-account-required',
          message: 'Sign in with Apple needs an Apple Account on the device.',
        );
      }
      rethrow;
    }

    final identityToken = apple.identityToken;
    if (identityToken == null) {
      throw FirebaseAuthException(
        code: 'missing-apple-id-token',
        message: 'Apple returned no identity token.',
      );
    }

    return SocialCredential(
      provider: SocialProvider.apple,
      credential: OAuthProvider(appleProviderId).credential(
        idToken: identityToken,
        rawNonce: rawNonce,
      ),
      displayName: _appleFullName(apple),
      appleAuthorizationCode: apple.authorizationCode,
    );
  }

  /// Clears the Google session so the next sign-in shows the account chooser
  /// again instead of silently reusing the last account.
  ///
  /// Best-effort: a device that never signed in with Google has nothing to
  /// sign out of, and that must not turn a normal sign-out into an error.
  Future<void> signOutProviders() async {
    try {
      await _ensureGoogleReady();
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Nothing to disconnect, or Google is unavailable on this device.
    }
  }

  /// Apple's given/family name pair joined, or null if it withheld both.
  ///
  /// Both halves are optional independently: someone can be handed back a
  /// given name with no family name, and on every authorization after the
  /// first both are null.
  static String? _appleFullName(AuthorizationCredentialAppleID apple) {
    final parts = [apple.givenName, apple.familyName]
        .whereType<String>()
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    return parts.isEmpty ? null : parts.join(' ');
  }

  /// A cryptographically random string for the Apple nonce.
  ///
  /// [Random.secure] rather than [Random]: a predictable nonce is the same
  /// as no nonce, and the whole point of the value is unguessability.
  static String _randomNonce([int length = 32]) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._';
    final rand = Random.secure();
    return List.generate(length, (_) => chars[rand.nextInt(chars.length)])
        .join();
  }

  static String _sha256Hex(String input) =>
      sha256.convert(utf8.encode(input)).toString();
}
