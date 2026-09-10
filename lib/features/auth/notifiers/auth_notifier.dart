import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/deep_links.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/services/local_store_service.dart';
import '../../../core/services/push_notification_service.dart';
import '../../../core/utils/text_moderation.dart';
import '../services/social_auth_service.dart';
import 'guest_reconnect_provider.dart';

final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

const _kGuestModeKey = 'guest_mode_active_v1';

/// Whether the app is being used in guest mode. Deliberately a bare
/// [StateProvider] so every existing call site can keep doing
/// `ref.read(guestModeProvider.notifier).state = value` — but reads its
/// initial value from Hive at boot (seeded in main.dart) and every write
/// should go through [setGuestMode] below so the flag survives a cold
/// start. Before this, a returning guest with fully intact local data was
/// bounced back to the auth screen on every relaunch, because this flag
/// reset to `false` in memory while the underlying Hive data stayed put.
final guestModeProvider = StateProvider<bool>((ref) => false);

/// Sets guest mode and persists it. Use this instead of writing
/// `guestModeProvider.notifier.state` directly.
Future<void> setGuestMode(WidgetRef ref, bool value) async {
  ref.read(guestModeProvider.notifier).state = value;
  final box = await LocalStoreService.settingsBox();
  await box.put(_kGuestModeKey, value);
  // Re-entering guest mode cancels any pending deletion of the guest data.
  // Someone who signed out and came back to guest is plainly still using
  // it, and a countdown started by an earlier account's answer must not
  // delete it out from under them mid-session.
  if (value) await LocalStoreService.clearGuestDiscardMark();
}

/// Reads the persisted guest-mode flag. Called once at app boot (see
/// main.dart) to seed [guestModeProvider]'s initial value.
Future<bool> loadPersistedGuestMode() async {
  final box = await LocalStoreService.settingsBox();
  return (box.get(_kGuestModeKey) as bool?) ?? false;
}

/// How the signed-in account authenticates, as far as anything that needs to
/// re-verify it is concerned.
///
/// Deliberately coarser than Firebase's provider list: the only question the
/// delete sheet asks is "what do I have to put in front of this person to
/// prove it is them", and that has exactly these answers.
enum AuthMethod {
  /// Email and password. Re-verified by typing the password.
  password,

  /// Google. Re-verified by running the account chooser again.
  google,

  /// Apple. Re-verified by running Apple's sheet again, which also produces
  /// the authorization code needed to revoke the token.
  apple,

  /// Nobody is signed in, or the account carries a provider this app does
  /// not offer.
  none,
}

/// What came back from a password-reset request.
///
/// [sent] also covers an address with no account at all: answering that
/// differently would let anyone test which addresses are registered, and
/// Firebase's own email-enumeration protection reports success either way
/// regardless.
enum ResetOutcome { sent, network, tooMany, failed }

class AuthNotifier extends StateNotifier<AsyncValue<void>> {
  AuthNotifier(this._ref) : super(const AsyncData(null));

  /// Held so the social sign-in path can arm [justRegisteredProvider]
  /// itself.
  ///
  /// Email registration arms that flag from the screen, before its await,
  /// because the screen is the only place that knows a registration is
  /// about to happen. Social sign-in cannot copy that: whether the account
  /// is new is only knowable AFTER the credential comes back, by which time
  /// authStateChanges has already fired and torn the auth screen down, so
  /// there is no widget left to do it. This notifier outlives the screen,
  /// and [GuestReconnectPrompt] *watches* the flag rather than listening to
  /// it, so a value written this late is still picked up.
  final Ref _ref;

  Future<void> signIn(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard<void>(() async {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      // Ensure user document exists (handles v1 migrations) and carries an
      // `email` field (handles v2 migrations - see _ensureUserDoc).
      await _ensureUserDoc(
        cred.user!.uid,
        cred.user?.email ?? email.trim(),
        // This sign-in IS the proof: they just used it.
        hasPassword: true,
      );
      AnalyticsService.instance.track('auth_signed_in');
    });
  }

  /// Sends Firebase's password-reset email.
  ///
  /// Deliberately NOT routed through [state]: the screen's error listener
  /// maps AsyncError into sign-in wording ("invalid credentials"), which is
  /// nonsense for a reset. user-not-found reports SENT on purpose, so the
  /// caller shows the same confirmation either way and this cannot be used to
  /// probe which addresses have accounts.
  ///
  /// It returns an outcome rather than a bool because the bool was a lie by
  /// omission: the screen printed "check your internet connection" for every
  /// false, so a rate limit, a disabled provider and a genuinely broken
  /// request all told the person to go and look at their wifi. The code is
  /// logged in debug for the same reason, since a swallowed exception is
  /// exactly what made this hard to see.
  Future<ResetOutcome> sendPasswordReset(String email) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: email.trim(),
        // Where Firebase's own page sends them AFTER the reset. It cannot be
        // stopped from being the page that takes the password (the action URL
        // is a template setting, and template editing is switched off for this
        // project), but it can be made to hand back afterwards: /reset is an
        // App Link, so on a phone this opens Grow Daily rather than a browser,
        // and in a browser it is our page saying the password is changed.
        //
        // Deliberately no iOS/Android parameters: those route through Dynamic
        // Links, which Google shut down, and the App Link already does the
        // opening.
        actionCodeSettings: ActionCodeSettings(
          url: 'https://$linkHost$resetPath',
          handleCodeInApp: false,
        ),
      );
      return ResetOutcome.sent;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'invalid-email') {
        return ResetOutcome.sent;
      }
      debugPrint('[auth] password reset failed: ${e.code} / ${e.message}');
      return switch (e.code) {
        'network-request-failed' => ResetOutcome.network,
        'too-many-requests' => ResetOutcome.tooMany,
        _ => ResetOutcome.failed,
      };
    } catch (e) {
      debugPrint('[auth] password reset threw: $e');
      return ResetOutcome.failed;
    }
  }

  Future<void> register(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard<void>(() async {
      final cred =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      try {
        // Create Firestore profile on first registration
        await _createUserDoc(
          cred.user!.uid,
          cred.user?.email ?? email.trim(),
          freshRegistration: true,
          hasPassword: true,
        );
      } catch (_) {
        // The Auth account exists but has no profile doc. _AuthGate routes
        // on authStateChanges() alone, so leaving this account signed in
        // would drop the user into a blank/broken GridScreen with no way
        // to recover. Roll the Auth account back so registration is
        // all-or-nothing and they can just try again.
        await cred.user?.delete();
        rethrow;
      }
      // Only a registration that fully landed (profile doc written, no
      // rollback) makes this uid eligible for the guest-data offer — see
      // LocalStoreService.guestReconnectCandidateKey. Recording it before
      // the doc write would leave a rolled-back registration eligible.
      await LocalStoreService.markReconnectCandidate(cred.user!.uid);
      AnalyticsService.instance.track('auth_registered');
    });
  }

  /// Signs in with Google or Apple, creating the account on first use.
  ///
  /// One method for both providers and for both "sign in" and "sign up",
  /// because with an OAuth provider those are not separate acts: the person
  /// taps one button and Firebase decides whether a uid already exists. The
  /// tab the auth screen happens to be showing is irrelevant here, which is
  /// why neither the caller nor this method reads it.
  ///
  /// Cancelling the provider's sheet returns quietly to the idle state
  /// rather than surfacing an error, so the screen shows no red banner for
  /// something the person deliberately did. That is why the provider call
  /// sits OUTSIDE [AsyncValue.guard]: guard turns every throw into an
  /// AsyncError, and the screen's listener renders any AsyncError as a
  /// failure message.
  Future<void> signInWithSocial(SocialProvider provider) async {
    state = const AsyncLoading();

    final SocialCredential social;
    try {
      social = provider == SocialProvider.google
          ? await SocialAuthService.instance.google()
          : await SocialAuthService.instance.apple();
    } on SocialSignInCancelled {
      state = const AsyncData(null);
      return;
    } catch (e, st) {
      state = AsyncError<void>(e, st);
      return;
    }

    state = await AsyncValue.guard<void>(() async {
      final cred =
          await FirebaseAuth.instance.signInWithCredential(social.credential);
      final user = cred.user!;
      // Apple can withhold the address entirely on a second device, and a
      // relay address is still an address; either way the user doc's `email`
      // field is descriptive only (see _createUserDoc), so an empty string
      // is a truthful value rather than a hole.
      final email = user.email ?? '';
      final isNewAccount = cred.additionalUserInfo?.isNewUser ?? false;

      if (!isNewAccount) {
        await _ensureUserDoc(user.uid, email);
        // Never allowed to fail the sign-in it is riding on: this is an
        // extra read of one field, and a Firestore hiccup must not turn a
        // sign-in that worked into an error banner.
        try {
          await _repairDroppedPassword(user, email);
        } catch (_) {
          // The flag stays as it was, so the next provider sign-in tries
          // again. Nothing is lost by being late.
        }
        // A returning Apple account has no name to re-learn (Apple hands the
        // full name over once and never again), but a returning Google
        // account can have had its Google name or photo changed since, and
        // this is the only moment we see them.
        await _refreshSocialProfile(user.uid, social);
        AnalyticsService.instance.track(
          'auth_signed_in',
          props: {'method': provider.name},
        );
        return;
      }

      try {
        await _createUserDoc(
          user.uid,
          email,
          freshRegistration: true,
          providerName: social.displayName,
          photoUrl: social.photoUrl,
        );
      } catch (_) {
        // Same all-or-nothing rollback as register(): an Auth account with
        // no profile doc drops the user into a broken Grid with no way back.
        await user.delete();
        rethrow;
      }
      await LocalStoreService.markReconnectCandidate(user.uid);

      // The guest-data offer, armed here rather than on the auth screen.
      // See [_ref]: by this line the screen has already been disposed by
      // authStateChanges, so it could not do this for itself, and only now
      // is it known that this sign-in created an account at all.
      if (await LocalStoreService.hasGuestProgress()) {
        _ref.read(justRegisteredProvider.notifier).state = true;
      }
      AnalyticsService.instance.track(
        'auth_registered',
        props: {'method': provider.name},
      );
    });
  }

  Future<void> signOut() async {
    // The FCM token doc has to go while this account is still signed in:
    // users/{uid}/fcmTokens/* is owner-only in firestore.rules, so the
    // delete main.dart's auth listener attempts AFTER authStateChanges
    // emits null runs unauthenticated, is rejected, and was silently
    // swallowed — a shared or handed-over device kept receiving the old
    // account's room pushes. The listener's call stays as a harmless no-op
    // backstop.
    await PushNotificationService.instance.clearForSignOut();
    // Google keeps its own session alongside Firebase's. Left signed in, the
    // next tap of the Google button silently reuses the account that just
    // signed out instead of showing the chooser, so a shared or handed-over
    // device could not switch accounts at all.
    await SocialAuthService.instance.signOutProviders();
    await FirebaseAuth.instance.signOut();
    AnalyticsService.instance.track('auth_signed_out');
    state = const AsyncData(null);
  }

  /// Puts a password onto the signed-in account, so it has two ways in
  /// again: the provider it just used, and an email/password pair.
  ///
  /// linkWithCredential rather than any kind of "reset": there is nothing to
  /// reset, the credential was deleted, and this account is already proven
  /// by the provider sign-in that is holding it open right now. Writing the
  /// flag back is what stops [_repairDroppedPassword] from ever offering
  /// this again.
  Future<void> addPassword(String password) async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? '';
    if (user == null || email.isEmpty) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No signed-in account with an address to attach a password to.',
      );
    }
    await user.linkWithCredential(
      EmailAuthProvider.credential(email: email, password: password),
    );
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .set({'hasPassword': true}, SetOptions(merge: true));
    AnalyticsService.instance.track('auth_password_added');
  }

  /// Notices when Firebase has just DELETED this account's password, and
  /// arms the offer to put a new one back.
  ///
  /// This is not a hypothetical. Firebase treats an email/password account
  /// whose address was never verified as unproven: anyone can type a
  /// stranger's address and set a password on it. So the moment that same
  /// address signs in with a provider that proves ownership (Google always,
  /// Apple usually), Firebase DELETES the password credential and links the
  /// provider in its place. Same uid, same data, same everything, except
  /// that the password no longer exists. Nothing is said to the person, and
  /// the next email sign-in fails as "wrong password" because from the
  /// client's side there is nothing left to compare against.
  ///
  /// It cannot be prevented from here (the swap happens server-side, inside
  /// the sign-in that just succeeded), and the password cannot be restored,
  /// because it was never readable. What CAN be done is notice and say so:
  /// `hasPassword` on the user doc is what we last knew, `providerData` is
  /// what is true now, and the two disagreeing means exactly this happened.
  ///
  /// Fires at most once per account. The flag is cleared here, so the offer
  /// is made on the sign-in where the loss is discovered and never again,
  /// and setting a password later writes it back to true.
  Future<void> _repairDroppedPassword(User user, String email) async {
    final hasPasswordNow =
        user.providerData.any((p) => p.providerId == passwordProviderId);
    if (hasPasswordNow || email.isEmpty) return;

    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final snap = await ref.get();
    if (snap.data()?['hasPassword'] != true) return;

    await ref.set({'hasPassword': false}, SetOptions(merge: true));
    AnalyticsService.instance.track('auth_password_dropped');
    _ref.read(passwordDroppedProvider.notifier).state = email;
  }

  /// How the signed-in account proves who it is, which decides what the
  /// delete sheet has to ask for.
  ///
  /// Reads `providerData` rather than assuming: an account can carry more
  /// than one, and the sheet must not ask a Google-only user for a password
  /// they were never given the chance to set.
  static AuthMethod currentAuthMethod() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return AuthMethod.none;
    final ids = user.providerData.map((p) => p.providerId).toSet();
    // Password first: an account that has one can always re-authenticate
    // with it, and typing it is a better "are you sure" gate for an
    // irreversible action than a one-tap provider sheet.
    if (ids.contains(passwordProviderId)) return AuthMethod.password;
    if (ids.contains(appleProviderId)) return AuthMethod.apple;
    if (ids.contains(googleProviderId)) return AuthMethod.google;
    return AuthMethod.none;
  }

  /// Permanently deletes the signed-in account: re-authenticates (Firebase
  /// requires a recent sign-in before it will let you delete a user), wipes
  /// every document under `users/{uid}` — the profile doc plus the
  /// daily/custom_habits/focus_plans/matrix_tasks/weekly_challenges
  /// subcollections — then deletes the Firebase Auth account itself.
  /// Required by App Store review guideline 5.1.1(v): any app that supports
  /// account creation must support in-app account deletion, not just
  /// sign-out/deactivation.
  ///
  /// [password] is required for, and only used by, a password account. A
  /// Google or Apple account re-authenticates by running its provider's
  /// sheet again, which is the only credential it has. Before this took
  /// providers into account, a social account could not be deleted at all:
  /// reauthentication was hard-wired to EmailAuthProvider, so it failed with
  /// invalid-credential no matter what was typed, and 5.1.1(v) was not
  /// actually satisfied for those users.
  ///
  /// An Apple account additionally has its token REVOKED before deletion.
  /// Apple has required that of every app offering Sign in with Apple since
  /// June 2022: without it the app stays listed under the person's Apple ID
  /// settings after they deleted their account here.
  ///
  /// Returns false when the person dismissed the provider sheet, so the
  /// caller can go back to idle instead of reporting a failure.
  Future<bool> deleteAccount({String? password}) async {
    state = const AsyncLoading();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      state = AsyncError<void>(
        FirebaseAuthException(
          code: 'no-current-user',
          message: 'No signed-in account to delete.',
        ),
        StackTrace.current,
      );
      return true;
    }

    // Re-authentication runs outside AsyncValue.guard for the same reason as
    // signInWithSocial: a dismissed provider sheet is a decision, not an
    // error, and guard would turn it into one.
    String? appleAuthorizationCode;
    try {
      switch (currentAuthMethod()) {
        case AuthMethod.password:
          final email = user.email;
          if (email == null || password == null || password.isEmpty) {
            throw FirebaseAuthException(
              code: 'invalid-credential',
              message: 'A password is required to delete this account.',
            );
          }
          await user.reauthenticateWithCredential(
            EmailAuthProvider.credential(email: email, password: password),
          );
        case AuthMethod.google:
          final social = await SocialAuthService.instance.google();
          await user.reauthenticateWithCredential(social.credential);
        case AuthMethod.apple:
          final social = await SocialAuthService.instance.apple();
          await user.reauthenticateWithCredential(social.credential);
          // Captured from THIS authorization: the code is single-use and
          // only ever handed out at the moment Apple's sheet completes.
          appleAuthorizationCode = social.appleAuthorizationCode;
        case AuthMethod.none:
          throw FirebaseAuthException(
            code: 'no-current-user',
            message: 'This account has no sign-in method to verify.',
          );
      }
    } on SocialSignInCancelled {
      state = const AsyncData(null);
      return false;
    } catch (e, st) {
      state = AsyncError<void>(e, st);
      return true;
    }

    state = await AsyncValue.guard<void>(() async {
      if (appleAuthorizationCode != null) {
        try {
          await FirebaseAuth.instance
              .revokeTokenWithAuthorizationCode(appleAuthorizationCode);
        } catch (_) {
          // Best-effort, and deliberately not fatal. Someone who asked to be
          // deleted and got an error instead is the worse outcome, and the
          // same reasoning already governs _leaveAllRooms below. The Apple
          // ID keeps a stale entry in its settings list; the account here
          // still goes.
        }
      }
      await _deleteAllUserData(user.uid);
      await user.delete();
      AnalyticsService.instance.track('account_deleted');
    });
    return true;
  }

  // ── Helpers ─────────────────────────────────────────────────

  /// Best-effort recursive delete of everything under `users/{uid}`, plus
  /// this account's membership of any Room. Client SDKs can't delete a
  /// document's subcollections automatically, so each known subcollection is
  /// fetched and batch-deleted before the parent doc. If this ever needs to
  /// run unattended (e.g. from a support request instead of the signed-in
  /// user themselves), move it into a Cloud Function using the Admin SDK
  /// instead.
  ///
  /// The list below is load-bearing: privacy_policy.html tells people
  /// deletion "permanently removes your account and all associated data",
  /// and anything missing from this list makes that sentence false. It is
  /// also what App Review checks under guideline 5.1.1(v). `milestones` and
  /// `fcmTokens` were both missing — the first is a full history of what
  /// this person achieved and when, the second an active push token, so a
  /// deleted account could still have been sent a notification.
  ///
  /// Room participant docs are deleted too, and separately, because they do
  /// not live under `users/{uid}` at all: they sit at
  /// `rooms/{code}/participants/{uid}` and carry a display name and a
  /// progress history that other members can read. Leaving them behind
  /// meant a deleted account stayed visible on other people's leaderboards.
  static Future<void> _deleteAllUserData(String uid) async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    const subcollections = [
      'daily',
      'custom_habits',
      'custom_rewards',
      'focus_plans',
      'matrix_tasks',
      'weekly_challenges',
      'milestones',
      'fcmTokens',
      'habit_history',
    ];
    // Before the user doc goes, since that is where the room codes live.
    await _leaveAllRooms(uid, userRef);
    for (final name in subcollections) {
      final snap = await userRef.collection(name).get();
      const chunkSize = 400; // stay under Firestore's 500-write batch limit
      for (var i = 0; i < snap.docs.length; i += chunkSize) {
        final batch = FirebaseFirestore.instance.batch();
        for (final doc in snap.docs.skip(i).take(chunkSize)) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    }
    await userRef.delete();
  }

  /// Removes this account from every Room it is a member of.
  ///
  /// Best-effort by design, and failures are swallowed: a room whose
  /// participant doc cannot be removed must not block the account deletion
  /// itself, because a user who asked to be deleted and got an error
  /// instead is the worse outcome — both for them and under guideline
  /// 5.1.1(v). This no longer deletes the entry: firestore.rules stopped
  /// allowing a member to delete their own participant doc once leaving
  /// became a soft departure (RoomParticipant.leftAt), because that delete
  /// was the leave-and-rejoin score reset. The entry is stamped as left and
  /// stripped of every identifying field instead, which is an owner UPDATE
  /// the rules do allow, and nothing ever draws a departed member again.
  static Future<void> _leaveAllRooms(
    String uid,
    DocumentReference<Map<String, dynamic>> userRef,
  ) async {
    try {
      final snap = await userRef.get();
      final codes = (snap.data()?['roomCodes'] as List?)
              ?.whereType<String>()
              .toList() ??
          const <String>[];
      for (final code in codes) {
        try {
          // A departure, not a delete. Deleting a participant doc is what
          // the leave-and-rejoin reset was made of, so firestore.rules no
          // longer allows a member to delete their own entry (only the
          // room's creator can, for a full teardown). The entry is stamped
          // as left instead, exactly as RoomsController.leaveRoom does, and
          // stripped of everything that named the person: every roster read
          // skips a departed member, so nothing of theirs is drawn anywhere
          // again, and what remains is an anonymous record of days.
          await FirebaseFirestore.instance
              .collection('rooms')
              .doc(code)
              .collection('participants')
              .doc(uid)
              .set(
            {
              'leftAt': Timestamp.now(),
              'displayName': '',
              'characterId': '',
              'accessoryId': FieldValue.delete(),
              'prestigeTierId': FieldValue.delete(),
              'linkedHabitNames': FieldValue.delete(),
            },
            SetOptions(merge: true),
          );
          // Out of the headcount too, as RoomsController.leaveRoom does.
          await FirebaseFirestore.instance
              .collection('rooms')
              .doc(code)
              .set(
                {'memberCount': FieldValue.increment(-1)},
                SetOptions(merge: true),
              )
              .catchError((_) {});
        } catch (_) {
          // One unreachable room must not strand the whole deletion.
        }
      }
    } catch (_) {
      // Same reasoning one level up.
    }
  }

  /// Creates the profile doc for [uid].
  ///
  /// [freshRegistration] separates the two callers, and it is load-bearing.
  /// A genuine new registration also gets an empty `activeCatalogIds`,
  /// which reads like a no-op and is not: ActiveCatalogNotifier._load()
  /// (habit_plans.dart) treats a MISSING field as "this account predates
  /// catalog syncing" and seeds itself from this device's own Hive box
  /// instead. That fallback is right for the account it was written for
  /// and wrong for a guest who just signed up: it handed the new account
  /// the guest's catalog picks while their activation dates - already
  /// parsed from the absent Firestore field into an empty map, and never
  /// re-read from Hive on that path - stayed lost, then wrote that
  /// emptiness back. A catalog habit with no birth date reports itself as
  /// scheduled on every past day (IslamicHabitTemplate.isScheduledFor
  /// skips the guard when createdAt is null), and with none of the guest's
  /// completions carried over, every one of those days graded as a miss:
  /// Grid squares, the heatmap, insights, the weekly recap, room credit.
  /// Writing the field, even empty, says "this account HAS an answer and
  /// it is none", so the fallback stays out of it.
  ///
  /// [_ensureUserDoc] deliberately does NOT pass it. Its caller is a
  /// sign-in that found no profile doc at all, which is the exact legacy
  /// case the fallback exists to rescue.
  ///
  /// See test/features/habits/guest_signup_catalog_carryover_test.dart.
  ///
  /// [providerName] and [photoUrl] are what Google or Apple handed over.
  /// Both are absent for an email registration, and [providerName] is absent
  /// for every Apple sign-in after the very first, which is precisely why it
  /// has to be written here and now: Apple releases the full name once per
  /// Apple ID and Firebase does not keep it, so a name not persisted during
  /// that first authorization is gone for good.
  static Future<void> _createUserDoc(
    String uid,
    String email, {
    bool freshRegistration = false,
    bool hasPassword = false,
    String? providerName,
    String? photoUrl,
  }) async {
    final ref =
        FirebaseFirestore.instance.collection('users').doc(uid);
    await ref.set({
      'uid': uid,
      // Kept alongside `createdAt` specifically so an admin can open the
      // Firebase console's Firestore Data tab and filter/sort the `users`
      // collection by email or signup date directly - Firebase Auth's own
      // user list supports neither, and doesn't join with this collection.
      'email': email.trim(),
      'displayName': initialDisplayName(email, providerName: providerName),
      if (photoUrl != null && photoUrl.isNotEmpty) 'photoUrl': photoUrl,
      'level': 1,
      'currentLevelXp': 0,
      'cumulativeXp': 0,
      'gold': 0,
      'currentStreak': 0,
      'longestStreak': 0,
      'streakFreezes': 1,
      'unlockedAchievements': <String>[],
      'equippedHabitIds': <String>[],
      if (freshRegistration) 'activeCatalogIds': <String>[],
      // What we believe about this account's PASSWORD, which is the only
      // way to notice that Firebase has taken it away. See
      // [_repairDroppedPassword] for the whole story.
      if (hasPassword) 'hasPassword': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// The name a brand-new account starts life with.
  ///
  /// Order matters. A real name from Google or Apple is always the best
  /// answer and is used when there is one. Failing that the email local-part
  /// is a convenient default, and it is also the one path a display name
  /// could reach Rooms leaderboards without ever meeting isObjectionable:
  /// setDisplayName guards every EDIT, but nobody types this value, so
  /// nothing else screens it. A neutral fallback beats seeding a
  /// slur@-address, or a provider-supplied name someone set to a slur,
  /// straight onto a public row.
  ///
  /// The private-relay clause is what stops Apple accounts being named after
  /// a random hex string. Someone who hides their address gets an email like
  /// `a1b2c3d4e5@privaterelay.appleid.com`, and the old local-part rule
  /// would have put `a1b2c3d4e5` on their profile and on every leaderboard
  /// they joined.
  ///
  /// Public because the Profile screen needs the identical rule for its own
  /// fallback when the user document has not loaded yet. Two copies of it
  /// would drift, and the private-relay clause is exactly the sort of clause
  /// that gets fixed in one copy only.
  static String initialDisplayName(String email, {String? providerName}) {
    final fromProvider = providerName?.trim();
    if (fromProvider != null &&
        fromProvider.isNotEmpty &&
        !isObjectionable(fromProvider)) {
      return fromProvider;
    }
    final local = email.contains('@') ? email.split('@')[0] : '';
    if (local.isEmpty ||
        email.toLowerCase().endsWith('@privaterelay.appleid.com') ||
        isObjectionable(local)) {
      return 'Warrior';
    }
    return local;
  }

  /// Writes back a Google name or photo that changed since last time.
  ///
  /// Only ever fills gaps or updates the photo; it never overwrites a
  /// display name the person has since set for themselves in this app, which
  /// is why it reads the doc first and compares against what registration
  /// would have written. Apple contributes nothing here, since it withholds
  /// the name on every sign-in after the first.
  static Future<void> _refreshSocialProfile(
    String uid,
    SocialCredential social,
  ) async {
    final photoUrl = social.photoUrl;
    final name = social.displayName?.trim();
    if ((photoUrl == null || photoUrl.isEmpty) &&
        (name == null || name.isEmpty)) {
      return;
    }
    final ref = FirebaseFirestore.instance.collection('users').doc(uid);
    final snap = await ref.get();
    if (!snap.exists) return;
    final data = snap.data() ?? const <String, dynamic>{};
    final update = <String, Object?>{};

    if (photoUrl != null &&
        photoUrl.isNotEmpty &&
        data['photoUrl'] != photoUrl) {
      update['photoUrl'] = photoUrl;
    }
    // Only when there is no usable name on the doc at all. Someone who
    // renamed themselves here must not be silently renamed back to whatever
    // their Google account says every time they sign in.
    final existing = (data['displayName'] as String?)?.trim();
    if ((existing == null || existing.isEmpty || existing == 'Warrior') &&
        name != null &&
        name.isNotEmpty &&
        !isObjectionable(name)) {
      update['displayName'] = name;
    }
    if (update.isEmpty) return;
    await ref.set(update, SetOptions(merge: true));
  }

  static Future<void> _ensureUserDoc(
    String uid,
    String email, {
    bool hasPassword = false,
  }) async {
    final ref =
        FirebaseFirestore.instance.collection('users').doc(uid);
    final snap = await ref.get();
    if (!snap.exists) {
      await _createUserDoc(uid, email, hasPassword: hasPassword);
      return;
    }
    // Written on every password sign-in, not only at registration, so the
    // accounts that already existed before this field did get marked the
    // first time their owner uses a password. Cheap: a merge of one boolean
    // that is already true on every sign-in after the first.
    if (hasPassword && snap.data()?['hasPassword'] != true) {
      await ref.set({'hasPassword': true}, SetOptions(merge: true));
    }
    // Backfill accounts created before `email` was stored on this doc (see
    // _createUserDoc's doc comment) - merge-write only touches this one
    // field, so createdAt and everything else already on the doc is left
    // exactly as-is. Runs at most once per account: every sign-in after
    // this either finds the field already set, or just set it.
    //
    // The empty-[email] guard is for Apple: it can withhold the address on a
    // second device, and without this the backfill would write an empty
    // string over and over on every sign-in, once per launch forever,
    // without ever setting the field it is trying to set.
    if (email.trim().isNotEmpty &&
        (snap.data()?['email'] as String?)?.isNotEmpty != true) {
      await ref.set({'email': email.trim()}, SetOptions(merge: true));
    }
  }
}

final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AsyncValue<void>>(
  (ref) => AuthNotifier(ref),
);

/// The address of an account that just lost its password to a Google or
/// Apple sign-in, set once by [AuthNotifier._repairDroppedPassword] and
/// consumed by main.dart, which puts up the screen offering to set a new
/// one. Null the rest of the time.
final passwordDroppedProvider = StateProvider<String?>((ref) => null);
