import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/local_store_service.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../models/accessory.dart';
import '../models/character_option.dart';

class CharacterState {
  final String characterId;

  /// At most one accessory is worn at a time (matches the source project
  /// this was ported from) — not one per category. Switching category just
  /// swaps which single accessory is shown.
  final String? equippedAccessoryId;

  /// Every accessory the account has ever bought, plus
  /// [AccessoryCatalog.defaultOwnedId] which every account starts with.
  final Set<String> ownedAccessoryIds;

  final bool isLoading;

  const CharacterState({
    this.characterId = 'male_ghutra_blue',
    this.equippedAccessoryId = 'misbah_amber',
    this.ownedAccessoryIds = const {'misbah_amber'},
    this.isLoading = true,
  });

  CharacterOption get character => CharacterCatalog.findByIdOrDefault(characterId);
  Accessory? get equippedAccessory => AccessoryCatalog.findById(equippedAccessoryId);
  bool owns(String accessoryId) => ownedAccessoryIds.contains(accessoryId);

  CharacterState copyWith({
    String? characterId,
    String? equippedAccessoryId,
    bool clearEquipped = false,
    Set<String>? ownedAccessoryIds,
    bool? isLoading,
  }) =>
      CharacterState(
        characterId: characterId ?? this.characterId,
        equippedAccessoryId:
            clearEquipped ? null : (equippedAccessoryId ?? this.equippedAccessoryId),
        ownedAccessoryIds: ownedAccessoryIds ?? this.ownedAccessoryIds,
        isLoading: isLoading ?? this.isLoading,
      );
}

/// Owns character/accessory selection — a small, separate module from
/// [DashboardNotifier] (which owns gold itself) the same way MatrixNotifier
/// is separate from it: this reads dashboard gold to pay for purchases via
/// [DashboardNotifier.spendGold], but never touches the 'gold' field
/// directly itself.
class CharacterNotifier extends StateNotifier<CharacterState> {
  final Ref _ref;
  final String? _uid;

  CharacterNotifier(this._ref, this._uid) : super(const CharacterState()) {
    if (_uid != null) {
      _load();
    } else {
      _loadGuest();
    }
  }

  DocumentReference<Map<String, dynamic>> get _userRef =>
      FirebaseFirestore.instance.collection('users').doc(_uid);

  Set<String> _readOwned(dynamic raw) {
    final owned = <String>{};
    if (raw is List) {
      owned.addAll(raw.map((e) => e.toString()));
    }
    owned.add(AccessoryCatalog.defaultOwnedId);
    return owned;
  }

  Future<void> _load() async {
    if (_uid == null) return;
    try {
      final snap = await _userRef.get();
      if (!mounted) return;
      final data = snap.data();
      if (data == null) {
        state = state.copyWith(isLoading: false);
        return;
      }
      state = CharacterState(
        characterId: (data['characterId'] as String?) ?? state.characterId,
        equippedAccessoryId:
            (data['equippedAccessoryId'] as String?) ?? AccessoryCatalog.defaultOwnedId,
        ownedAccessoryIds: _readOwned(data['ownedAccessoryIds']),
        isLoading: false,
      );
    } catch (_) {
      if (mounted) state = state.copyWith(isLoading: false);
    }
  }

  Future<void> _loadGuest() async {
    try {
      final saved = await LocalStoreService.getSettingsMap(
        LocalStoreService.guestCharacterKey,
      );
      if (!mounted) return;
      if (saved.isEmpty) {
        state = state.copyWith(isLoading: false);
        return;
      }
      state = CharacterState(
        characterId: (saved['characterId'] as String?) ?? state.characterId,
        equippedAccessoryId:
            (saved['equippedAccessoryId'] as String?) ?? AccessoryCatalog.defaultOwnedId,
        ownedAccessoryIds: _readOwned(saved['ownedAccessoryIds']),
        isLoading: false,
      );
    } catch (_) {
      if (mounted) state = state.copyWith(isLoading: false);
    }
  }

  // Fire-and-forget, same as MatrixNotifier._persist — `.ignore()` returns
  // void (that's the point: it silences the "unawaited future" lint
  // deliberately), so it can never be `await`ed. The optimistic state
  // update already happened by the time callers reach this.
  void _persist() {
    final data = {
      'characterId': state.characterId,
      'equippedAccessoryId': state.equippedAccessoryId,
      'ownedAccessoryIds': state.ownedAccessoryIds.toList(),
    };
    if (_uid == null) {
      LocalStoreService.putSettingsMap(
        LocalStoreService.guestCharacterKey,
        data,
      ).ignore();
    } else {
      _userRef.set(data, SetOptions(merge: true)).ignore();
    }
  }

  /// Free and instant — characters are never gold-gated.
  void selectCharacter(String id) {
    if (CharacterCatalog.findByIdOrDefault(id).id != id) return;
    state = state.copyWith(characterId: id);
    _persist();
  }

  /// Equips an already-owned accessory, or pass null to go bare-handed.
  /// No-ops silently on an unowned id rather than throwing — a stale UI
  /// tap (e.g. a double-tap racing a revoke) should never crash.
  void equipAccessory(String? id) {
    if (id != null && !state.owns(id)) return;
    state = id == null
        ? state.copyWith(clearEquipped: true)
        : state.copyWith(equippedAccessoryId: id);
    _persist();
  }

  /// Spends gold (via DashboardNotifier, the sole owner of that field) to
  /// permanently unlock [id]. Returns false without spending anything if
  /// already owned, unknown, or unaffordable; returns false without
  /// unlocking if the gold spend itself fails to persist (matches
  /// DashboardNotifier.buyStreakFreeze's "don't grant on a failed write"
  /// rule). On success, also equips the new accessory immediately — buying
  /// something in the shop and then having to go tap "equip" separately
  /// would be a needless extra step.
  Future<bool> buyAccessory(String id) async {
    if (state.owns(id)) return false;
    final accessory = AccessoryCatalog.findById(id);
    if (accessory == null) return false;

    final spent =
        await _ref.read(dashboardProvider.notifier).spendGold(accessory.goldCost);
    if (!spent) return false;

    state = state.copyWith(
      ownedAccessoryIds: {...state.ownedAccessoryIds, id},
      equippedAccessoryId: id,
    );
    _persist();
    return true;
  }
}

final characterProvider =
    StateNotifierProvider<CharacterNotifier, CharacterState>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  return CharacterNotifier(ref, uid);
});
