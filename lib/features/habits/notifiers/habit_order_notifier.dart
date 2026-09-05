import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/local_store_service.dart';
import '../../auth/notifiers/auth_notifier.dart';

/// Manual sort rank for the Today's Habits list, keyed by habit id — works
/// uniformly for both catalog and custom habits (see [habitListProvider] in
/// custom_habits_notifier.dart), since catalog templates are `const` and
/// can't carry mutable per-user state themselves.
///
/// Same fractional-order trick as `MatrixTask.order`: dragging a habit
/// between two others only ever rewrites the dragged habit's own value (the
/// midpoint of its new neighbors), so a single drag never has to rewrite
/// every other habit's rank.
class HabitOrderNotifier extends StateNotifier<Map<String, double>> {
  final String? _uid;

  HabitOrderNotifier(this._uid) : super(const {}) {
    if (_uid != null) {
      _load();
    } else {
      _loadGuest();
    }
  }

  static const String _kGuestKey = LocalStoreService.habitOrderKey;

  DocumentReference<Map<String, dynamic>> get _userRef =>
      FirebaseFirestore.instance.collection('users').doc(_uid);

  Future<void> _load() async {
    if (_uid == null) return;
    try {
      final snap = await _userRef.get();
      if (!mounted) return;
      final raw =
          (snap.data()?['habitOrder'] as Map?)?.cast<String, dynamic>() ??
              {};
      // Merged UNDER whatever is already in memory, not assigned over it:
      // a reorder() that ran while this load was still in flight has
      // already produced a rank the person watched land, and a plain
      // `state = loaded` here silently threw it away — after which
      // _persist wrote the emptied map back over the stored one, losing
      // the order on disk too (caught by habit_reorder_test's reload
      // case, where the write always races the constructor's load).
      state = {
        for (final e in raw.entries) e.key: (e.value as num).toDouble(),
        ...state,
      };
    } catch (_) {}
  }

  Future<void> _loadGuest() async {
    final box = await LocalStoreService.settingsBox();
    final raw = (box.get(_kGuestKey) as Map?)?.cast<String, dynamic>() ?? {};
    if (!mounted) return;
    // Same merge-under as _load above, same clobber race.
    state = {
      for (final e in raw.entries) e.key: (e.value as num).toDouble(),
      ...state,
    };
  }

  /// Moves [id] so it sorts immediately before [beforeId] within
  /// [orderedIds] — the currently-displayed, already-sorted habit id list —
  /// or to the end if [beforeId] is null (dropped past the last row).
  ///
  /// A habit with no entry in [state] yet (never manually dragged) falls
  /// back to its position within [orderedIds] as its rank, so mixing
  /// touched and untouched habits still sorts correctly instead of shoving
  /// every untouched habit to the same value.
  void reorder(String id, List<String> orderedIds, {String? beforeId}) {
    if (id == beforeId) return;
    final siblings = orderedIds.where((h) => h != id).toList();
    if (siblings.isEmpty) return;

    double rankOf(String habitId) {
      final idx = siblings.indexOf(habitId);
      return state[habitId] ?? idx.toDouble();
    }

    double newOrder;
    final beforeIdx = beforeId == null ? -1 : siblings.indexOf(beforeId);
    if (beforeIdx == -1) {
      // Dropped past the last row (or an unrecognized target) — append.
      newOrder = rankOf(siblings.last) + 1000;
    } else {
      final beforeRank = rankOf(siblings[beforeIdx]);
      final prevRank = beforeIdx > 0 ? rankOf(siblings[beforeIdx - 1]) : null;
      newOrder =
          prevRank == null ? beforeRank - 1000 : (prevRank + beforeRank) / 2;
    }

    state = {...state, id: newOrder};
    _persist();
  }

  Future<void> _persist() async {
    // Snapshot before any await: the guest path suspends on settingsBox(),
    // and `state` read after that suspension is whatever it has become by
    // then, not what this call was asked to save.
    final snapshot = state;
    if (_uid != null) {
      _userRef.set({'habitOrder': snapshot}, SetOptions(merge: true)).ignore();
      return;
    }
    final box = await LocalStoreService.settingsBox();
    await box.put(_kGuestKey, snapshot);
  }
}

final habitOrderProvider =
    StateNotifierProvider<HabitOrderNotifier, Map<String, double>>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  return HabitOrderNotifier(uid);
});
