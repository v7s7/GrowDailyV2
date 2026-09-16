import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/habit_mirror.dart';
import '../../../core/services/local_store_service.dart';
import '../../../core/services/user_doc.dart';
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

  /// The order as hydrated from the device's copy, so [_load] can tell a
  /// rank the person just dragged from one that was merely mirrored. Empty
  /// when nothing was hydrated, which makes the merge below collapse to its
  /// original "everything in memory wins" behaviour.
  Map<String, double> _hydratedOrder = const {};

  /// Whether the server's ranks have arrived. Until they have, [_persist]
  /// may only send what this session produced — see there.
  bool _serverSettled = false;

  HabitOrderNotifier(this._uid) : super(const {}) {
    if (_uid != null) {
      // Hydrated so the rows do not paint in catalog order and then visibly
      // re-sort a moment later when the real ranks arrive.
      final mirror = HabitMirror.snapshot;
      if (mirror != null && mirror.uid == _uid) {
        state = Map.of(mirror.habitOrder);
        _hydratedOrder = Map.of(mirror.habitOrder);
      }
      _load();
    } else {
      _loadGuest();
    }
  }

  /// Ranks that differ from what was hydrated, i.e. the ones this session
  /// actually produced. Everything else is the mirror's copy of the server's
  /// own answer, and must not outrank the answer itself — otherwise a
  /// reorder done on another phone would never take effect here.
  Map<String, double> get _reorderedSinceHydrate => {
        for (final e in state.entries)
          if (_hydratedOrder[e.key] != e.value) e.key: e.value,
      };

  static const String _kGuestKey = LocalStoreService.habitOrderKey;

  DocumentReference<Map<String, dynamic>> get _userRef =>
      FirebaseFirestore.instance.collection('users').doc(_uid);

  Future<void> _load() async {
    if (_uid == null) return;
    try {
      // Shared with the three other notifiers that want a field from this
      // same document on the same launch — see [UserDoc].
      final data = await UserDoc.read(_uid);
      if (!mounted) return;
      final raw =
          (data?['habitOrder'] as Map?)?.cast<String, dynamic>() ?? {};
      // Merged UNDER whatever is already in memory, not assigned over it:
      // a reorder() that ran while this load was still in flight has
      // already produced a rank the person watched land, and a plain
      // `state = loaded` here silently threw it away — after which
      // _persist wrote the emptied map back over the stored one, losing
      // the order on disk too (caught by habit_reorder_test's reload
      // case, where the write always races the constructor's load).
      state = {
        for (final e in raw.entries) e.key: (e.value as num).toDouble(),
        ..._reorderedSinceHydrate,
      };
      // Inside the try, and only here: a read that threw has not settled, and
      // must not license sending the mirrored map back as authoritative.
      _serverSettled = true;
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
      // Before the read has landed, `state` is largely the device's mirrored
      // copy, and sending it whole would write those stale ranks back as
      // authoritative — overwriting any rank another device produced since.
      // Only what this session actually dragged goes up; merge:true leaves
      // every other id's rank on the server untouched. Not HELD until the
      // read settles, because a read that throws would then drop the drag
      // forever, and a thrown read is exactly when this is reachable.
      final toSend = _serverSettled ? snapshot : _reorderedSinceHydrate;
      if (toSend.isEmpty) return;
      _userRef.set({'habitOrder': toSend}, SetOptions(merge: true)).ignore();
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
