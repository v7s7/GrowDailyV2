import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/analytics_service.dart';

final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

final guestModeProvider = StateProvider<bool>((ref) => false);

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
      // Create Firestore profile on first registration
      await _createUserDoc(cred.user!.uid, email);
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
