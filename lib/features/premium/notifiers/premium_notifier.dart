import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show CustomerInfo;

import '../../../core/services/analytics_service.dart';
import '../../../core/services/purchase_service.dart';

/// Free-tier limits. Guests keep their existing 3-habit trial; signed-in
/// free accounts get a generous cap that most users won't hit for weeks —
/// the paywall should feel like an invitation, not a wall.
const int kFreeHabitLimit = 10;

/// How many months of any history surface the free tier can browse — the
/// current month plus two before it, matching the Monthly Heatmap's free
/// window exactly so the whole app tells one consistent story: free sees
/// the recent past, Premium owns its whole history.
const int kFreeHistoryMonths = 3;

/// Whether a history screen (Night Review calendar, Habit Notes journal)
/// may browse to the month starting at [monthStart]. Pure so it's
/// unit-testable — see test/features/premium/history_gate_test.dart.
/// [now] is any date inside the current month (callers pass
/// `DateTime.now().effectiveDay`).
bool canBrowseHistoryMonth({
  required DateTime monthStart,
  required DateTime now,
  required bool isPremium,
}) {
  if (isPremium) return true;
  final monthsBack =
      (now.year - monthStart.year) * 12 + (now.month - monthStart.month);
  return monthsBack < kFreeHistoryMonths;
}

/// Whether the account has GrowDaily Premium.
///
/// This is the single entitlement seam for the whole app: every UI gate
/// (habit cap, voice notes, heatmap history, ...) reads this provider, and
/// it's driven entirely by [PurchaseService] — RevenueCat's verified
/// CustomerInfo, never a value this client could set on its own. There's
/// deliberately no Firestore field behind this anymore (see
/// firestore.rules' premiumFieldOk() comment, now historical): RevenueCat
/// tracks entitlement per App User ID and [PurchaseService.logIn]/[logOut]
/// (wired to authStateProvider — see main.dart) ties that id to this
/// account, so the same purchase already follows the account across
/// devices/reinstalls without this notifier needing to sync anything
/// itself.
class PremiumNotifier extends StateNotifier<bool> {
  StreamSubscription<CustomerInfo>? _sub;

  PremiumNotifier() : super(false) {
    // Live updates for anything that happens *after* construction — a
    // purchase completing, a renewal or refund picked up on next launch,
    // a restore. See PurchaseService.customerInfoUpdates' doc comment.
    _sub = PurchaseService.instance.customerInfoUpdates.listen(applyCustomerInfo);
    // Plus an immediate one-time look so state isn't just `false` until the
    // first update happens to arrive — mirrors every other notifier here
    // that seeds itself at construction.
    refresh();
  }

  /// Applies [info] to [state] right now, synchronously - no waiting on
  /// the async stream above. PremiumScreen calls this immediately after a
  /// successful purchase/restore with the CustomerInfo RevenueCat already
  /// handed back in that same call, rather than trusting that
  /// [PurchaseService.customerInfoUpdates] has delivered the same update
  /// yet. Both paths carry the same already-verified CustomerInfo -
  /// calling this early is just removing a race between "the purchase
  /// call resolved" and "the separate listener happened to fire", not a
  /// second source of truth. Safe to call redundantly (idempotent): if
  /// the stream listener above also reports the same info moments later,
  /// `entitled == state` and nothing changes.
  void applyCustomerInfo(CustomerInfo info) {
    if (!mounted) return;
    final entitled = PurchaseService.instance.isEntitled(info);
    if (entitled && !state) {
      AnalyticsService.instance.track('premium_activated');
    }
    state = entitled;
  }

  /// Forces a fresh look at RevenueCat's cached entitlement. Cheap and
  /// safe to call often (see PurchaseService.getCustomerInfo's doc
  /// comment) — kept for main.dart's app-resume hook, same as every other
  /// notifier's refresh() here.
  Future<void> refresh() async {
    final info = await PurchaseService.instance.getCustomerInfo();
    if (info != null && mounted) {
      state = PurchaseService.instance.isEntitled(info);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final premiumProvider =
    StateNotifierProvider<PremiumNotifier, bool>((ref) => PremiumNotifier());
