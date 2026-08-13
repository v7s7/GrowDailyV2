import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/local_store_service.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../models/prestige_tier.dart';

/// Which [PrestigeTier] to show off, plus loading state — deliberately the
/// *only* thing persisted for the whole Level Prestige System. Unlike
/// [CharacterState.ownedAccessoryIds] (a gold purchase is a one-time grant
/// that has to be remembered forever, independent of future gold spending),
/// prestige "ownership" needs no storage at all: a tier is unlocked exactly
/// when `DashboardState.level >= tier.minLevel`, which is already loaded
/// and re-evaluated live every time — see [PrestigeCatalog.unlockedFor].
/// The only genuine per-user choice is *which* unlocked tier to display,
/// since reaching Level 50 doesn't retire the Level 10 title someone might
/// still prefer the look of.
class PrestigeState {
  /// Explicit pick, or null to mean "always show my highest unlocked tier
  /// automatically" — the default for every account, including one that's
  /// never opened the picker. Set only by [PrestigeNotifier.equipTier].
  final String? equippedTierId;
  final bool isLoading;

  const PrestigeState({this.equippedTierId, this.isLoading = true});

  /// The tier actually shown right now for [level] — the explicit pick if
  /// one is set and still valid, else the highest unlocked. Never null:
  /// see [PrestigeCatalog.highestFor].
  PrestigeTier displayedTier(int level) {
    final picked = PrestigeCatalog.findById(equippedTierId);
    if (picked != null && picked.minLevel <= level) return picked;
    return PrestigeCatalog.highestFor(level);
  }

  PrestigeState copyWith({
    String? equippedTierId,
    bool clearEquipped = false,
    bool? isLoading,
  }) =>
      PrestigeState(
        equippedTierId:
            clearEquipped ? null : (equippedTierId ?? this.equippedTierId),
        isLoading: isLoading ?? this.isLoading,
      );
}

/// Owns the single equipped-tier choice — a small, separate module from
/// both [DashboardNotifier] (which owns level itself; this only ever reads
/// it, passed in by the caller, same arm's-length relationship
/// CharacterNotifier has with gold) and [CharacterNotifier] (a parallel
/// prestige *lane*, not a parallel *character/accessory* system — nothing
/// here writes characterId/equippedAccessoryId/ownedAccessoryIds, and
/// nothing in CharacterNotifier writes equippedPrestigeTierId). Mirrors
/// CharacterNotifier's load/persist/guest shape closely (same
/// _mutatedBeforeLoad race guard, same "merge onto the shared user doc for
/// signed-in, a dedicated Hive settings key for guest" split) so this reads
/// as the established pattern for "small per-account cosmetic choice"
/// rather than a new one.
class PrestigeNotifier extends StateNotifier<PrestigeState> {
  final String? _uid;

  // Same race this guards against in CharacterNotifier: a tap on the
  // picker sheet right after this screen opens could land before _load()/
  // _loadGuest() resolves — see that class's identical field for the full
  // reasoning.
  bool _mutatedBeforeLoad = false;

  PrestigeNotifier(this._uid) : super(const PrestigeState()) {
    if (_uid != null) {
      _load();
    } else {
      _loadGuest();
    }
  }

  DocumentReference<Map<String, dynamic>> get _userRef =>
      FirebaseFirestore.instance.collection('users').doc(_uid);

  Future<void> _load() async {
    if (_uid == null) return;
    try {
      final snap = await _userRef.get();
      if (!mounted) return;
      if (_mutatedBeforeLoad) {
        state = state.copyWith(isLoading: false);
        return;
      }
      final data = snap.data();
      state = PrestigeState(
        equippedTierId: data?['equippedPrestigeTierId'] as String?,
        isLoading: false,
      );
    } catch (_) {
      if (mounted) state = state.copyWith(isLoading: false);
    }
  }

  Future<void> _loadGuest() async {
    try {
      final saved =
          await LocalStoreService.getSettingsMap(LocalStoreService.guestPrestigeKey);
      if (!mounted) return;
      if (_mutatedBeforeLoad) {
        state = state.copyWith(isLoading: false);
        return;
      }
      state = PrestigeState(
        equippedTierId: saved['equippedPrestigeTierId'] as String?,
        isLoading: false,
      );
    } catch (_) {
      if (mounted) state = state.copyWith(isLoading: false);
    }
  }

  // Fire-and-forget, same as CharacterNotifier._persist — the optimistic
  // state update already happened by the time callers reach this.
  void _persist() {
    final data = {'equippedPrestigeTierId': state.equippedTierId};
    if (_uid == null) {
      LocalStoreService.putSettingsMap(LocalStoreService.guestPrestigeKey, data)
          .ignore();
    } else {
      _userRef.set(data, SetOptions(merge: true)).ignore();
    }
  }

  /// Sets which unlocked tier to display; pass null to go back to "always
  /// show my highest, automatically" (the default). [currentLevel] is the
  /// caller's already-loaded DashboardState.level — passed in rather than
  /// read from a ref here so this notifier never needs to watch
  /// dashboardProvider itself, the same arm's-length relationship
  /// CharacterNotifier.buyAccessory has with gold (via DashboardNotifier.
  /// spendGold rather than reading the field directly).
  ///
  /// No-ops silently on a tier not yet unlocked at [currentLevel] — mirrors
  /// CharacterNotifier.equipAccessory's "no-op on unowned rather than
  /// throw" rule, so a stale UI tap (e.g. the picker sheet was still open
  /// from before a level-down-impossible-but-hypothetical edge case) can
  /// never equip something that isn't actually earned.
  void equipTier(String? tierId, int currentLevel) {
    if (tierId != null) {
      final tier = PrestigeCatalog.findById(tierId);
      if (tier == null || tier.minLevel > currentLevel) return;
    }
    _mutatedBeforeLoad = true;
    state = tierId == null
        ? state.copyWith(clearEquipped: true)
        : state.copyWith(equippedTierId: tierId);
    _persist();
  }
}

final prestigeProvider =
    StateNotifierProvider<PrestigeNotifier, PrestigeState>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  return PrestigeNotifier(uid);
});
