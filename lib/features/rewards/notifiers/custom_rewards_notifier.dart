import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/local_store_service.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../models/custom_reward.dart';

class CustomRewardsState {
  final List<CustomReward> rewards;
  final bool isLoading;

  /// The list could not be read. Adding and editing are refused while this
  /// is set, because every write here rewrites the whole guest blob: saving
  /// on top of a failed read would persist an empty list over a real one.
  /// Claiming is refused too, but for a different reason, see [loadFailed]'s
  /// use in the notifier.
  final bool loadFailed;

  /// The reward currently being paid for, if any.
  ///
  /// Exists because [DashboardNotifier.spendGold] rolls back by restoring an
  /// ABSOLUTE snapshot of the balance it saw. Two overlapping spends
  /// therefore lose an update: A for 60 hangs, B for 30 succeeds, A fails
  /// and restores the balance it snapshotted before B ran, which refunds B's
  /// deduction and hands B over free. One spend at a time makes that
  /// unreachable.
  final String? claimingId;

  const CustomRewardsState({
    this.rewards = const [],
    this.isLoading = true,
    this.loadFailed = false,
    this.claimingId,
  });

  CustomRewardsState copyWith({
    List<CustomReward>? rewards,
    bool? isLoading,
    bool? loadFailed,
    String? claimingId,
    bool clearClaiming = false,
  }) =>
      CustomRewardsState(
        rewards: rewards ?? this.rewards,
        isLoading: isLoading ?? this.isLoading,
        loadFailed: loadFailed ?? this.loadFailed,
        claimingId: clearClaiming ? null : (claimingId ?? this.claimingId),
      );

  CustomReward? byId(String id) {
    for (final r in rewards) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// How many are affordable right now, for the closet card's subtitle.
  int affordableCount(int gold) =>
      rewards.where((r) => r.priceGold <= gold).length;

  /// Gold still needed for the nearest unaffordable one, or null when they
  /// are all affordable or the list is empty.
  int? closestShortfall(int gold) {
    int? best;
    for (final r in rewards) {
      final short = r.priceGold - gold;
      if (short > 0 && (best == null || short < best)) best = short;
    }
    return best;
  }
}

/// The user's own reward list: what they buy with gold, in their own words.
///
/// Copies MatrixNotifier's two-path shape (a per-item Firestore document
/// under the account, a whole-list blob in Hive for guests) because a small
/// list of user-authored records is exactly the problem that solves. It does
/// NOT copy MatrixNotifier's fire-and-forget persistence for the one
/// operation where money moves, see [claim].
class CustomRewardsNotifier extends StateNotifier<CustomRewardsState> {
  final Ref _ref;
  final String? _uid;

  /// A guest can add a reward before the disk read resolves: both fire in
  /// the same tick after construction. Without this the read wins and wipes
  /// the just-added record. Same guard, same reason, as MatrixNotifier's.
  bool _mutatedBeforeLoad = false;

  CustomRewardsNotifier(this._ref, this._uid)
      : super(const CustomRewardsState()) {
    if (_uid != null) {
      _load();
    } else {
      _loadGuest();
    }
  }

  CollectionReference<Map<String, dynamic>> get _col => FirebaseFirestore
      .instance
      .collection('users')
      .doc(_uid)
      .collection('custom_rewards');

  static List<CustomReward> _sorted(List<CustomReward> raw) {
    final out = [...raw]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return out;
  }

  Future<void> _load() async {
    try {
      final snap = await _col.get();
      if (!mounted) return;
      final parsed = <CustomReward>[];
      for (final d in snap.docs) {
        // Per document, so one unreadable record costs only itself. The
        // alternative, a single parse over the whole list, loses everybody's
        // rewards to one bad field.
        final r = CustomReward.fromMap(d.data(), id: d.id);
        if (r != null) parsed.add(r);
      }
      state = state.copyWith(
        rewards: _mutatedBeforeLoad ? _merge(parsed) : _sorted(parsed),
        isLoading: false,
        loadFailed: false,
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, loadFailed: true);
    }
  }

  Future<void> _loadGuest() async {
    try {
      final box = await LocalStoreService.settingsBox();
      final raw = box.get(LocalStoreService.guestCustomRewardsKey);
      final parsed = <CustomReward>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) {
            final r = CustomReward.fromMap(e.cast<String, dynamic>());
            if (r != null) parsed.add(r);
          }
        }
      }
      if (!mounted) return;
      state = state.copyWith(
        rewards: _mutatedBeforeLoad ? _merge(parsed) : _sorted(parsed),
        isLoading: false,
        loadFailed: false,
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, loadFailed: true);
    }
  }

  /// Keeps anything added during the load and drops stored copies of it.
  /// Only reachable through [_mutatedBeforeLoad], so the common path is a
  /// plain sort.
  List<CustomReward> _merge(List<CustomReward> stored) {
    final live = {for (final r in state.rewards) r.id};
    return _sorted([
      ...state.rewards,
      ...stored.where((r) => !live.contains(r.id)),
    ]);
  }

  Future<void> _saveGuest() async {
    final box = await LocalStoreService.settingsBox();
    await box.put(
      LocalStoreService.guestCustomRewardsKey,
      state.rewards.map((r) => r.toMap()).toList(),
    );
  }

  void _persist(CustomReward reward) {
    if (_uid == null) {
      _saveGuest().ignore();
    } else {
      _col
          .doc(reward.id)
          .set(reward.toFirestore(), SetOptions(merge: true))
          .ignore();
    }
  }

  void _persistDelete(String id) {
    if (_uid == null) {
      _saveGuest().ignore();
    } else {
      _col.doc(id).delete().ignore();
    }
  }

  /// Returns the created reward so a caller can undo by id, or null when the
  /// list is full or the input is unusable.
  CustomReward? add({required String name, required int priceGold}) {
    if (state.loadFailed) return null;
    if (name.trim().isEmpty) return null;
    if (state.rewards.length >= kCustomRewardListMax) return null;

    _mutatedBeforeLoad = true;
    final reward = CustomReward.create(name: name, priceGold: priceGold);
    state = state.copyWith(rewards: [...state.rewards, reward]);
    _persist(reward);
    return reward;
  }

  void update(String id, {String? name, int? priceGold}) {
    if (state.loadFailed) return;
    if (name != null && name.trim().isEmpty) return;
    final idx = state.rewards.indexWhere((r) => r.id == id);
    if (idx < 0) return;

    _mutatedBeforeLoad = true;
    final updated = state.rewards[idx].copyWith(
      name: name?.trim(),
      priceGold: priceGold?.clamp(kCustomRewardMinPrice, kCustomRewardMaxPrice),
    );
    final next = [...state.rewards]..[idx] = updated;
    state = state.copyWith(rewards: next);
    _persist(updated);
  }

  void remove(String id) {
    if (state.loadFailed) return;
    _mutatedBeforeLoad = true;
    state = state.copyWith(
      rewards: state.rewards.where((r) => r.id != id).toList(),
    );
    _persistDelete(id);
  }

  /// Puts back an exact record a delete removed, for the undo action.
  /// Guarded against a stale snackbar tapped twice.
  void restore(CustomReward reward) {
    if (state.loadFailed) return;
    if (state.rewards.any((r) => r.id == reward.id)) return;
    if (state.rewards.length >= kCustomRewardListMax) return;

    _mutatedBeforeLoad = true;
    state = state.copyWith(rewards: _sorted([...state.rewards, reward]));
    _persist(reward);
  }

  /// Buys [id] with gold. Returns whether the gold actually left.
  ///
  /// Deliberately writes NOTHING to the rewards store. A claim does not
  /// change the reward: same name, same price, still there tomorrow, because
  /// the point of this sink is that a reward repeats. That makes
  /// [DashboardNotifier.spendGold] the ENTIRE transaction, and it already
  /// checks affordability, deducts optimistically, persists on the right
  /// backend for guest and signed-in alike, and restores the previous
  /// balance itself on a failed write. There is no second write to half-land
  /// and so no rollback owed here: a caller that also tried to repair the
  /// balance would double-credit.
  ///
  /// If a claim count or a claim log is ever added, this stops being true
  /// and this method has to become CharacterNotifier.buyAccessory's shape:
  /// snapshot, await the delivery write, and on a throw restore and refund
  /// in the same method.
  Future<bool> claim(String id) async {
    if (state.claimingId != null) return false;
    if (state.loadFailed) return false;
    final reward = state.byId(id);
    if (reward == null) return false;

    state = state.copyWith(claimingId: id);
    try {
      return await _ref
          .read(dashboardProvider.notifier)
          .spendGold(reward.priceGold);
    } finally {
      if (mounted) state = state.copyWith(clearClaiming: true);
    }
  }
}

final customRewardsProvider =
    StateNotifierProvider<CustomRewardsNotifier, CustomRewardsState>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  return CustomRewardsNotifier(ref, uid);
});
