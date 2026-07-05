import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/analytics_service.dart';
import '../../../core/services/local_store_service.dart';
import '../../auth/notifiers/auth_notifier.dart';

/// Free-tier limits. Guests keep their existing 3-habit trial; signed-in
/// free accounts get a generous cap that most users won't hit for weeks —
/// the paywall should feel like an invitation, not a wall.
const int kFreeHabitLimit = 10;

const String _kGuestPremiumKey = 'premium_active_v1';

/// Whether the account has GrowDaily Premium.
///
/// This is the single entitlement seam for the whole app: UI gates read
/// this provider, and the store SDK (in_app_purchase / RevenueCat) only has
/// to call [PremiumNotifier.activate] on a verified purchase and
/// [PremiumNotifier.deactivate] on expiry. Until the store is wired, the
/// paywall's purchase button reports "not yet available" and nothing here
/// grants access — no fake unlocks.
class PremiumNotifier extends StateNotifier<bool> {
  final String? _uid;

  PremiumNotifier(this._uid) : super(false) {
    _load();
  }

  DocumentReference<Map<String, dynamic>> get _userRef =>
      FirebaseFirestore.instance.collection('users').doc(_uid);

  Future<void> _load() async {
    try {
      if (_uid == null) {
        final saved = await LocalStoreService.getSettingsMap(_kGuestPremiumKey);
        if (mounted) state = (saved['active'] as bool?) ?? false;
        return;
      }
      final snap = await _userRef.get();
      if (mounted) {
        state = (snap.data()?['premiumActive'] as bool?) ?? false;
      }
    } catch (_) {}
  }

  /// Grant premium — call ONLY after the store SDK verifies a purchase.
  Future<void> activate() async {
    state = true;
    AnalyticsService.instance.track('premium_activated');
    await _persist(true);
  }

  /// Revoke premium — expiry, refund, or verified downgrade.
  Future<void> deactivate() async {
    state = false;
    await _persist(false);
  }

  Future<void> _persist(bool active) async {
    if (_uid == null) {
      final saved = await LocalStoreService.getSettingsMap(_kGuestPremiumKey);
      await LocalStoreService.putSettingsMap(
        _kGuestPremiumKey,
        {...saved, 'active': active},
      );
      return;
    }
    try {
      await _userRef.set(
        {'premiumActive': active},
        SetOptions(merge: true),
      );
    } catch (_) {}
  }
}

final premiumProvider = StateNotifierProvider<PremiumNotifier, bool>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  return PremiumNotifier(uid);
});
