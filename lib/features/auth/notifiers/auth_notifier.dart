import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/analytics_service.dart';
import '../../../core/services/push_notification_service.dart';
import '../../../core/utils/text_moderation.dart';
import '../../../core/services/local_store_service.dart';

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
}

/// Reads the persisted guest-mode flag. Called once at app boot (see
/// main.dart) to seed [guestModeProvider]'s initial value.
Future<bool> loadPersistedGuestMode() async {
  final box = await LocalStoreService.settingsBox();
  return (box.get(_kGuestModeKey) as bool?) ?? false;
}

class AuthNotifier extends StateNotifier<AsyncValue<void>> {
  AuthNotifier() : super(const AsyncData(null));

  Future<void> signIn(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard<void>(() async {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      // Ensure user document exists (handles v1 migrations) and carries an
      // `email` field (handles v2 migrations - see _ensureUserDoc).
      await _ensureUserDoc(cred.user!.uid, cred.user?.email ?? email.trim());
      AnalyticsService.instance.track('auth_signed_in');
    });
  }

  /// Sends Firebase's password-reset email.
  ///
  /// Deliberately NOT routed through [state]: the screen's error listener
  /// maps AsyncError into sign-in wording ("invalid credentials"), which is
  /// nonsense for a reset. Returns false only on a delivery-level failure
  /// (offline); user-not-found returns TRUE on purpose, so the caller shows
  /// the same confirmation either way and this can't be used to probe which
  /// emails have accounts.
  Future<bool> sendPasswordReset(String email) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
      return true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'invalid-email') return true;
      return false;
    } catch (_) {
      return false;
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
        await _createUserDoc(cred.user!.uid, cred.user?.email ?? email.trim());
      } catch (_) {
        // The Auth account exists but has no profile doc. _AuthGate routes
        // on authStateChanges() alone, so leaving this account signed in
        // would drop the user into a blank/broken GridScreen with no way
        // to recover. Roll the Auth account back so registration is
        // all-or-nothing and they can just try again.
        await cred.user?.delete();
        rethrow;
      }
      AnalyticsService.instance.track('auth_registered');
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
    await FirebaseAuth.instance.signOut();
    AnalyticsService.instance.track('auth_signed_out');
    state = const AsyncData(null);
  }

  /// Permanently deletes the signed-in account: re-authenticates with the
  /// given password (Firebase requires a recent sign-in before it will let
  /// you delete a user), wipes every document under `users/{uid}` — the
  /// profile doc plus the daily/custom_habits/focus_plans/matrix_tasks/
  /// weekly_challenges subcollections — then deletes the Firebase Auth
  /// account itself. Required by App Store review guideline 5.1.1(v): any
  /// app that supports account creation must support in-app account
  /// deletion, not just sign-out/deactivation.
  Future<void> deleteAccount(String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard<void>(() async {
      final user = FirebaseAuth.instance.currentUser;
      final email = user?.email;
      if (user == null || email == null) {
        throw FirebaseAuthException(
          code: 'no-current-user',
          message: 'No signed-in account to delete.',
        );
      }
      final credential =
          EmailAuthProvider.credential(email: email, password: password);
      await user.reauthenticateWithCredential(credential);
      await _deleteAllUserData(user.uid);
      await user.delete();
      AnalyticsService.instance.track('account_deleted');
    });
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
  /// 5.1.1(v). firestore.rules already lets a participant delete their own
  /// entry (`allow delete: if isOwner(uid)`), so no rules change is needed.
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
          await FirebaseFirestore.instance
              .collection('rooms')
              .doc(code)
              .collection('participants')
              .doc(uid)
              .delete();
        } catch (_) {
          // One unreachable room must not strand the whole deletion.
        }
      }
    } catch (_) {
      // Same reasoning one level up.
    }
  }

  static Future<void> _createUserDoc(String uid, String email) async {
    final ref =
        FirebaseFirestore.instance.collection('users').doc(uid);
    await ref.set({
      'uid': uid,
      // Kept alongside `createdAt` specifically so an admin can open the
      // Firebase console's Firestore Data tab and filter/sort the `users`
      // collection by email or signup date directly - Firebase Auth's own
      // user list supports neither, and doesn't join with this collection.
      'email': email.trim(),
      // The email local-part is a convenient default name, and it is also
      // the one path a display name could reach Rooms leaderboards without
      // ever meeting isObjectionable — setDisplayName guards every EDIT,
      // but nobody types this value, so nothing else screens it. A neutral
      // fallback beats seeding a slur@-address straight onto a public row.
      'displayName':
          isObjectionable(email.split('@')[0]) ? 'Warrior' : email.split('@')[0],
      'level': 1,
      'currentLevelXp': 0,
      'cumulativeXp': 0,
      'gold': 0,
      'currentStreak': 0,
      'longestStreak': 0,
      'streakFreezes': 1,
      'unlockedAchievements': <String>[],
      'equippedHabitIds': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> _ensureUserDoc(String uid, String email) async {
    final ref =
        FirebaseFirestore.instance.collection('users').doc(uid);
    final snap = await ref.get();
    if (!snap.exists) {
      await _createUserDoc(uid, email);
      return;
    }
    // Backfill accounts created before `email` was stored on this doc (see
    // _createUserDoc's doc comment) - merge-write only touches this one
    // field, so createdAt and everything else already on the doc is left
    // exactly as-is. Runs at most once per account: every sign-in after
    // this either finds the field already set, or just set it.
    if ((snap.data()?['email'] as String?)?.isNotEmpty != true) {
      await ref.set({'email': email.trim()}, SetOptions(merge: true));
    }
  }
}

final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AsyncValue<void>>(
        (ref) => AuthNotifier());
