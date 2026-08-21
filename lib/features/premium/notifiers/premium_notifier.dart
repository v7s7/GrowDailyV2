import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show CustomerInfo;

import '../../../core/services/analytics_service.dart';
import '../../../core/services/local_store_service.dart';
import '../../../core/services/purchase_service.dart';

/// Free-tier limits. Guests keep their existing 3-habit trial; signed-in
/// free accounts get a generous cap that most users won't hit for weeks —
/// the paywall should feel like an invitation, not a wall.
const int kFreeHabitLimit = 10;

/// How many reminders the free tier can attach to a single Matrix task.
/// One is the whole free offering here, and deliberately so: a single
/// reminder is what a task app is expected to do at all, while *stacking*
/// them — nudged at 3:00, 3:30 and 4:00 for a 5pm meeting — is the alarm-
/// clock behaviour worth paying for. Premium is uncapped rather than
/// merely a bigger number, so the upgrade reads as "this limit goes away"
/// instead of trading one ceiling for another.
///
/// Note this gates *adding*, not keeping: [canAddReminder] is only ever
/// asked before a new reminder is created, so a task that already carries
/// several keeps firing all of them if an entitlement lapses. Silently
/// dropping reminders someone had set would be the worst possible way to
/// find out a subscription expired.
///
/// Separately from this product cap, NotificationService.
/// kMaxTaskReminderSlots bounds how many of a task's reminders can be
/// armed with the OS at once — that one is an iOS platform limit, not a
/// tier limit, and applies to Premium too.
const int kFreeTaskReminders = 1;

/// Whether another reminder may be added to a task that currently has
/// [current] of them. Pure so it's unit-testable without Riverpod or
/// RevenueCat, same shape and reasoning as [canBrowseHistoryMonth].
bool canAddReminder({required int current, required bool isPremium}) =>
    isPremium || current < kFreeTaskReminders;

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
/// Hive key for the last known entitlement, with the account it belonged to.
/// See [loadPersistedPremium] for why this exists at all.
const _kPremiumCacheKey = 'premium_entitlement_v1';

/// The entitlement this device last saw, for seeding [premiumProvider]
/// before the first frame.
///
/// ── Why a cache, when RevenueCat is the source of truth ────────────────
/// It used to start at `false` every single launch and only become true
/// after [PurchaseService.logIn] finished a NETWORK ROUND TRIP. Three things
/// followed from that, all of them reported as "the app does not know I am
/// Premium until I open the Premium page":
///
///  1. Every cold start flashed the free UI at a paying customer: locked
///     history, muted year strips, a blurred recap card, an upgrade banner.
///  2. Offline, it never recovered. A paying customer on a plane was simply
///     a free customer, because the only thing that could correct the guess
///     was a request that could not complete.
///  3. If that one request failed, nothing retried until the app was
///     resumed or the paywall screen was opened by hand, which is exactly
///     the "open the page and then it notices" behaviour.
///
/// So the entitlement is now persisted like every other boot-time setting
/// this app already restores before its first frame (theme mode, preset,
/// font, locale, guest mode). RevenueCat stays the ONLY authority: this is
/// a warm start, not a second source of truth, and the first authoritative
/// answer that arrives overwrites it in both directions, including a lapse
/// or a refund flipping it back off.
///
/// It is deliberately NOT a Firestore field. One used to exist and was
/// removed on purpose (see firestore.rules' premiumFieldOk() comment):
/// anything the client can write, the client can grant itself. A local
/// cache carries no such risk, because it can only ever make THIS device
/// briefly optimistic about an account that already had the entitlement,
/// and the SDK corrects it within seconds. Cross-device is already solved
/// by RevenueCat itself, which keys entitlement to the App User ID that
/// [PurchaseService.logIn] binds to the account.
Future<bool> loadPersistedPremium() async {
  // A read that throws would take main.dart's boot sequence with it, so a
  // broken box answers "free" and lets RevenueCat correct it, exactly as it
  // would for a device that had never cached anything.
  try {
    final box = await LocalStoreService.settingsBox();
    final raw = box.get(_kPremiumCacheKey);
    if (raw is! Map) return false;
    return raw['entitled'] == true;
  } catch (_) {
    return false;
  }
}

/// The account the cached entitlement belonged to, so a DIFFERENT account
/// signing in on this device can never inherit it.
Future<String?> loadPersistedPremiumUid() async {
  try {
    final box = await LocalStoreService.settingsBox();
    final raw = box.get(_kPremiumCacheKey);
    if (raw is! Map) return null;
    final uid = raw['uid'];
    return uid is String && uid.isNotEmpty ? uid : null;
  } catch (_) {
    return null;
  }
}

class PremiumNotifier extends StateNotifier<bool> {
  StreamSubscription<CustomerInfo>? _sub;

  /// The account this device's cached entitlement was written for, read from
  /// disk at boot. Compared against the account that actually signs in, in
  /// [bindAccount].
  String? _cachedUid;

  /// The signed-in account, once known. Null for a guest.
  String? _uid;

  PremiumNotifier({bool initial = false, String? cachedUid})
      : _cachedUid = cachedUid,
        _uid = cachedUid,
        super(initial) {
    // Live updates for anything that happens *after* construction — a
    // purchase completing, a renewal or refund picked up on next launch,
    // a restore. See PurchaseService.customerInfoUpdates' doc comment.
    _sub = PurchaseService.instance.customerInfoUpdates.listen(applyCustomerInfo);
    // Plus an immediate one-time look so state isn't just the cached guess
    // until the first update happens to arrive — mirrors every other
    // notifier here that seeds itself at construction.
    refresh();
  }

  /// Ties the cached entitlement to the account that actually signed in.
  ///
  /// Called from main.dart's auth listener, alongside [PurchaseService.logIn].
  /// If this device's cache belonged to a DIFFERENT account, the seeded guess
  /// is wrong and is dropped immediately rather than left standing until
  /// RevenueCat answers: a shared or resold device must never show one
  /// person's subscription to the next person who signs in.
  void bindAccount(String uid) {
    _uid = uid;
    final stale = _cachedUid != null && _cachedUid != uid;
    _cachedUid = uid;
    if (stale && state) {
      // Deferred by a microtask, and that is not a detail.
      //
      // main.dart's auth listener is registered with fireImmediately, so on
      // a cold start this runs SYNCHRONOUSLY inside initState, while the
      // widget tree is still building. Dropping `state` right here would
      // notify every widget watching premiumProvider mid-build, which
      // Flutter asserts on ('!_dirty': markNeedsBuild during build) and
      // which takes the whole app to a red screen rather than to the free
      // tier. A microtask runs the moment that synchronous work finishes,
      // so the wrong entitlement is never painted, and never mutated from
      // inside a build either.
      Future.microtask(() => _set(false));
      return;
    }
    // Re-stamp the cache under this uid so a guest who signs up keeps the
    // entitlement they just bought.
    if (state) _persist();
  }

  /// Signed out. Drops the entitlement and the cache together, so the next
  /// account on this device starts from nothing rather than from whatever
  /// the last one had.
  void detachAccount() {
    _uid = null;
    _cachedUid = null;
    _set(false);
  }

  void _set(bool entitled) {
    if (!mounted) return;
    if (entitled && !state) {
      AnalyticsService.instance.track('premium_activated');
    }
    final changed = entitled != state;
    state = entitled;
    if (changed || entitled) _persist();
  }

  void _persist() {
    // Fire and forget: a failed write costs one cold start's worth of
    // optimism, never correctness, since RevenueCat still answers.
    //
    // try/catch AND catchError, which is not belt and braces. Opening the
    // box can fail SYNCHRONOUSLY (LocalStoreService.settingsBox throws a
    // HiveError outright when Hive has not been initialised), and a
    // synchronous throw walks straight past .catchError, which only ever
    // sees a failed Future. This is called from bindAccount during app
    // start, so an escaping throw there would land mid-mount and take the
    // first frame with it. Caching the entitlement must never be able to
    // stop the app opening.
    unawaited(_write());
  }

  /// The actual write, `await`ed inside a try so BOTH failure shapes land in
  /// the same catch.
  ///
  /// Opening a Hive box can fail synchronously (no path configured) and can
  /// also complete its future with an error, and a `.then(...).catchError(...)`
  /// chain does not reliably contain both: the synchronous throw escapes to
  /// the caller, which here is bindAccount, which main.dart calls during app
  /// start. An escaping throw there lands mid-mount and takes the first frame
  /// with it, turning a best-effort cache write into a launch failure.
  ///
  /// Not unit-testable, and worth saying why so nobody tries again: Hive
  /// completes its own internal opening-box completer with the same error, so
  /// in a test zone the failure is reported as unhandled no matter how
  /// completely the CALLER handles it. A test asserting "this does not throw"
  /// fails even when the code under test is perfect, which is how the first
  /// attempt at one fooled itself. In the app there is no such zone, and this
  /// catch is what keeps the throw off bindAccount's caller.
  Future<void> _write() async {
    try {
      final box = await LocalStoreService.settingsBox();
      await box.put(_kPremiumCacheKey, {'uid': _uid, 'entitled': state});
    } catch (_) {
      // Nothing to do: the next authoritative answer rewrites this anyway.
    }
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
    _set(PurchaseService.instance.isEntitled(info));
  }

  /// Forces a fresh look at RevenueCat's cached entitlement. Cheap and
  /// safe to call often (see PurchaseService.getCustomerInfo's doc
  /// comment) — kept for main.dart's app-resume hook, same as every other
  /// notifier's refresh() here.
  Future<void> refresh() async {
    final info = await PurchaseService.instance.getCustomerInfo();
    if (info != null && mounted) {
      // Through _set, not a bare assignment: a refresh that finds a lapsed
      // subscription has to clear the cache too, or the next cold start
      // would seed the entitlement straight back.
      _set(PurchaseService.instance.isEntitled(info));
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
