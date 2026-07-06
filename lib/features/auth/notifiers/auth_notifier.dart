import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/analytics_service.dart';
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
      // Ensure user document exists (handles v1 migrations)
      await _ensureUserDoc(cred.user!.uid, email);
      AnalyticsService.instance.track('auth_signed_in');
    });
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
        await _createUserDoc(cred.user!.uid, email);
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

  /// Best-effort recursive delete of everything under `users/{uid}`. Client
  /// SDKs can't delete a document's subcollections automatically, so each
  /// known subcollection is fetched and batch-deleted before the parent doc.
  /// If this ever needs to run unattended (e.g. from a support request
  /// instead of the signed-in user themselves), move it into a Cloud
  /// Function using the Admin SDK instead.
  static Future<void> _deleteAllUserData(String uid) async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    const subcollections = [
      'daily',
      'custom_habits',
      'focus_plans',
      'matrix_tasks',
      'weekly_challenges',
    ];
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

  static Future<void> _createUserDoc(String uid, String email) async {
    final ref =
        FirebaseFirestore.instance.collection('users').doc(uid);
    await ref.set({
      'uid': uid,
      'displayName': email.split('@')[0],
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
    if (!snap.exists) await _createUserDoc(uid, email);
  }
}

final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AsyncValue<void>>(
        (ref) => AuthNotifier());
