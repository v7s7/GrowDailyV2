import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notifiers/auth_notifier.dart';
import '../services/social_auth_service.dart';

/// Apple's relay domain. An address that ends in it forwards to the person's
/// real inbox and is unique to this app, so it can never match an account
/// made with their own address, and no mail we send from Firebase (a reset
/// link) reaches it unless the sender is registered with Apple.
const String appleRelaySuffix = '@privaterelay.appleid.com';

/// Every way into the account that is signed in right now, read off
/// Firebase's own `providerData` rather than remembered anywhere.
///
/// Why this exists. Firebase silently DELETES the password of an account
/// whose address was never verified the moment that same address signs in
/// with Google or Apple (see AuthNotifier._repairDroppedPassword). The app
/// offers a new password on the sign-in where it notices, but that offer is
/// made once, and accounts that lost a password before the detector shipped
/// never got one at all. A person in that state can still get in, with the
/// provider button, but nothing on screen tells them so, and typing the
/// password they remember fails as "invalid".
///
/// The other half is Apple's Hide My Email: the address is a relay string
/// that matches no existing account, so Apple makes a SECOND, empty account
/// and the person's habits look gone. Connecting Apple to the real account
/// from here is what makes "Continue with Apple" land on their own data
/// from then on.
class SignInMethods {
  const SignInMethods({
    required this.hasPassword,
    required this.hasGoogle,
    required this.hasApple,
    required this.accountEmail,
    this.googleEmail,
    this.appleEmail,
  });

  /// Reads the signed-in account. A null user (signed out, or the screen
  /// rebuilding one frame after a sign-out) has no ways in at all, which is
  /// the honest answer rather than a crash.
  factory SignInMethods.of(User? user) {
    if (user == null) {
      return const SignInMethods(
        hasPassword: false,
        hasGoogle: false,
        hasApple: false,
        accountEmail: '',
      );
    }
    String? emailFor(String providerId) {
      for (final p in user.providerData) {
        if (p.providerId == providerId) return p.email;
      }
      return null;
    }

    final ids = user.providerData.map((p) => p.providerId).toSet();
    return SignInMethods(
      hasPassword: ids.contains(passwordProviderId),
      hasGoogle: ids.contains(googleProviderId),
      hasApple: ids.contains(appleProviderId),
      accountEmail: user.email ?? '',
      googleEmail: emailFor(googleProviderId),
      appleEmail: emailFor(appleProviderId),
    );
  }

  final bool hasPassword;
  final bool hasGoogle;
  final bool hasApple;

  /// The account's own address, which is empty when Apple withheld it.
  final String accountEmail;
  final String? googleEmail;
  final String? appleEmail;

  int get count =>
      (hasPassword ? 1 : 0) + (hasGoogle ? 1 : 0) + (hasApple ? 1 : 0);

  /// True while removing anything would lock the account. Firebase refuses
  /// to unlink the last provider anyway; asking first is friendlier than
  /// letting it fail.
  bool get isLastWayIn => count <= 1;

  /// Apple hid the address behind its relay, so this account has no inbox we
  /// can reach and a password could never be recovered by email.
  bool get emailIsHidden => accountEmail.toLowerCase().endsWith(appleRelaySuffix);

  /// A password needs an address to belong to, and a reset mail needs one
  /// that reaches a real inbox.
  bool get canAddPassword => !hasPassword && accountEmail.isNotEmpty && !emailIsHidden;

  /// What Firebase did without telling anyone: a password that was there
  /// before is gone, and a provider stands in its place.
  bool droppedPassword({required bool docSaysHadPassword}) =>
      docSaysHadPassword && !hasPassword && (hasGoogle || hasApple);
}

/// Bumped by anything that changes the account's providers. Linking and
/// unlinking do NOT emit an auth state change, so without this the rows
/// would keep showing what was true when the screen opened.
final signInMethodsRefreshProvider = StateProvider<int>((ref) => 0);

/// The ways in, rebuilt whenever the signed-in user changes or something
/// connects or removes a provider. Overridden wholesale in widget tests, so
/// no test needs a live FirebaseAuth.
final signInMethodsProvider = Provider<SignInMethods>((ref) {
  ref.watch(signInMethodsRefreshProvider);
  try {
    // The STREAM is only a rebuild trigger. Its User is pinned to the
    // delegate that existed at sign-in, and linking, unlinking and reload
    // each build a new delegate without emitting an auth state change, so
    // reading its providerData would show what was true when the session
    // started: an already-removed method would still look connected, and
    // the last-way-in guard would be computed from a count that is too
    // high. currentUser wraps the live delegate, so it is always current.
    ref.watch(authStateProvider);
    return SignInMethods.of(FirebaseAuth.instance.currentUser);
  } catch (_) {
    // No Firebase app, which only happens in a test that never initialised
    // one. Answering "no ways in" is honest there and keeps a screen that
    // merely reads this from throwing.
    return SignInMethods.of(null);
  }
});
