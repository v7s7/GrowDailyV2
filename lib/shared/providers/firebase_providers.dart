import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Singleton service providers ───────────────────────────────────────────────

final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
  name: 'firebaseAuth',
);

final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
  name: 'firestore',
);

// ── Auth state ────────────────────────────────────────────────────────────────

/// Emits the current [User] on sign-in/sign-out; null when unauthenticated.
final authStateProvider = StreamProvider<User?>(
  (ref) => ref.watch(firebaseAuthProvider).authStateChanges(),
  name: 'authState',
);

/// Convenience: current UID or null.
final currentUidProvider = Provider<String?>(
  (ref) => ref.watch(authStateProvider).valueOrNull?.uid,
  name: 'currentUid',
);
