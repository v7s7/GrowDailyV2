import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/local_store_service.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../models/mood.dart';

class NightReviewState {
  final Mood? mood;
  final String reflection;
  final bool saved;
  final bool isLoading;

  const NightReviewState({
    this.mood,
    this.reflection = '',
    this.saved = false,
    this.isLoading = true,
  });

  NightReviewState copyWith({
    Mood? mood,
    String? reflection,
    bool? saved,
    bool? isLoading,
  }) =>
      NightReviewState(
        mood: mood ?? this.mood,
        reflection: reflection ?? this.reflection,
        saved: saved ?? this.saved,
        isLoading: isLoading ?? this.isLoading,
      );
}

/// Tonight's mood + reflection check-in. Scoped only to *today* — there is
/// no history browsing here, just "how was today", mirroring the simplicity
/// of the morning IntentionScreen this pairs with.
class NightReviewNotifier extends StateNotifier<NightReviewState> {
  final String? _uid;

  NightReviewNotifier(this._uid) : super(const NightReviewState()) {
    _load();
  }

  static String get _todayKey {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  DocumentReference<Map<String, dynamic>> get _dailyRef => FirebaseFirestore
      .instance
      .collection('users')
      .doc(_uid)
      .collection('daily')
      .doc(_todayKey);

  Future<void> _load() async {
    try {
      final Map<String, dynamic> d;
      if (_uid != null) {
        final snap = await _dailyRef.get();
        d = snap.data() ?? {};
      } else {
        d = await LocalStoreService.getDailyMap(_todayKey);
      }
      if (!mounted) return;
      state = NightReviewState(
        mood: Mood.fromJsonOrNull(d['mood'] as String?),
        reflection: d['dailyReflection'] as String? ?? '',
        saved: d['nightReviewDone'] as bool? ?? false,
        isLoading: false,
      );
    } catch (_) {
      if (mounted) state = state.copyWith(isLoading: false);
    }
  }

  void setMood(Mood mood) {
    state = state.copyWith(mood: mood, saved: false);
  }

  void setReflection(String text) {
    state = state.copyWith(reflection: text, saved: false);
  }

  /// Persists tonight's mood + reflection. Returns whether it actually
  /// saved — this used to flip `state.saved` to `true` (driving a "Saved!"
  /// checkmark in the UI) before the write below ran, and swallowed any
  /// failure, so a dropped connection meant the user saw confirmation for a
  /// reflection that was never written anywhere. Now a failed write rolls
  /// `saved` back to `false` and reports failure so the screen can tell the
  /// user to try again instead of lying to them.
  Future<bool> save() async {
    if (state.mood == null) return false;
    final data = {
      'mood': state.mood!.toJson(),
      'dailyReflection': state.reflection.trim(),
      'nightReviewDone': true,
    };
    state = state.copyWith(saved: true);
    if (_uid == null) {
      try {
        final existing = await LocalStoreService.getDailyMap(_todayKey);
        await LocalStoreService.putDailyMap(_todayKey, {
          ...existing,
          ...data,
          'date': DateTime.now().toIso8601String(),
        });
        return true;
      } catch (_) {
        if (mounted) state = state.copyWith(saved: false);
        return false;
      }
    }
    try {
      await _dailyRef.set(data, SetOptions(merge: true));
      return true;
    } catch (_) {
      if (mounted) state = state.copyWith(saved: false);
      return false;
    }
  }
}

final nightReviewProvider =
    StateNotifierProvider<NightReviewNotifier, NightReviewState>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  return NightReviewNotifier(uid);
});
