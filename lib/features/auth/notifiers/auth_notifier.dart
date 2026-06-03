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

  // ── Helpers ─────────────────────────────────────────────────

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
